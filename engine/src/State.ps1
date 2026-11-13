# GitHub reads: the context check and the current settings. The State.*.ps1 files and Apply.ps1 are the only other files that call GitHub.

# One command for both scopes: gh auth login requests neither, and an operator missing one usually misses both.
$script:ScopeCommand = 'gh auth refresh -h github.com -s admin:org,admin:org_hook'
# The admin scopes give the token nearly owner rights, so they are granted for a run and removed after it.
$script:ScopeRemoveCommand = 'gh auth refresh -h github.com -r admin:org,admin:org_hook'

function Write-ScopeRemoveRecommendation {
    # Printed on every exit once the token holds an admin scope: after a run, an error or an abort.
    Write-BootstrapRecommendation -Message 'remove the admin scopes from gh until the next run:' -Command $script:ScopeRemoveCommand
}

function Assert-GitHubOrgContext {
    <#
    .SYNOPSIS
    Ensures the gh account is an active owner of the organization with the admin:org and admin:org_hook scopes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Organization
    )

    try {
        $membership = Invoke-GhApi -Endpoint "user/memberships/orgs/$Organization"
    }
    catch {
        throw "Cannot read your membership in the GitHub organization '$Organization'; check that it exists and that gh is signed in (gh auth login). $($_.Exception.Message)"
    }
    if ($membership.state -ne 'active') {
        throw "Your membership in '$Organization' is '$($membership.state)'; accept the invitation first."
    }
    if ($membership.role -ne 'admin') {
        throw "The gh account must be an owner of '$Organization', but its role is '$($membership.role)'."
    }

    # Organization settings need the admin:org scope, which gh auth login does not request.
    try {
        Invoke-GhApi -Endpoint "orgs/$Organization/actions/permissions" | Out-Null
    }
    catch {
        throw "Cannot read the Actions settings of '$Organization': gh needs the admin:org scope. Run: $script:ScopeCommand. $($_.Exception.Message)"
    }

    # Organization webhooks need admin:org_hook; GitHub has no read-only scope for them.
    try {
        Invoke-GhApi -Endpoint "orgs/$Organization/hooks" | Out-Null
    }
    catch {
        # admin:org passed the probe above, so the token already holds it.
        Write-ScopeRemoveRecommendation
        throw "Cannot read the webhooks of '$Organization': gh needs the admin:org_hook scope. Run: $script:ScopeCommand. $($_.Exception.Message)"
    }

    Write-Host "Organization: $Organization"
    Write-Host "Account:      $($membership.user.login)"
}

function Read-OrgEndpoint {
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        # A list endpoint: read every page.
        [switch]$Paginate,
        # The parsed JSON root as it is: an array stays an array (Invoke-GhApi -NoEnumerate).
        [switch]$NoEnumerate
    )

    try {
        if ($NoEnumerate) {
            return , (Invoke-GhApi -Endpoint $Endpoint -NoEnumerate)
        }
        return Invoke-GhApi -Endpoint $Endpoint -Paginate:$Paginate
    }
    catch {
        # The inner exception keeps the HTTP status for Test-GhStatus.
        throw [System.Exception]::new("Cannot read $Endpoint; the gh account must be an owner with the admin:org and admin:org_hook scopes ($script:ScopeCommand). $($_.Exception.Message)", $_.Exception)
    }
}

function ConvertTo-FieldMap {
    # Field -> value of the supported fields of a section in a GitHub response; lists become [string[]].
    param(
        [AllowNull()][object]$Response,
        [Parameter(Mandatory)][string]$Section
    )

    if ($null -eq $Response) {
        return $null
    }
    $values = [ordered]@{}
    $endpoint = if ($script:Sections.Contains($Section)) { '/orgs/{org}' + $script:Sections[$Section].Path }
    foreach ($definition in (Get-SettingDefinition -Section $Section)) {
        # A row of an endpoint section that does not read that endpoint (a manual row) is not in the response.
        if ($endpoint -and (Get-SettingRead -Definition $definition).Endpoint -ne $endpoint) {
            continue
        }
        $responseField = if ($endpoint) { (Get-SettingRead -Definition $definition).Field } else { $definition.Field }
        $value = $Response.$responseField
        if ($definition.Type -eq 'list') {
            $values[$definition.Field] = [string[]]@($value | Where-Object { $null -ne $_ })
        }
        else {
            $values[$definition.Field] = $value
        }
    }
    return $values
}

function Read-OrgRepository {
    # Every repository of the organization ({Name, Archived, Visibility}), read once for the inventory, code security and
    # the ruleset.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'repositories'
    $repositories = @(Read-OrgEndpoint -Endpoint "orgs/$Organization/repos?per_page=100" -Paginate)
    return , [object[]]@($repositories | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Archived = [bool]$_.archived; Visibility = [string]$_.visibility } })
}

function Get-ConcreteEndpoint {
    # '/orgs/{org}/copilot/billing' -> 'orgs/<organization>/copilot/billing', the call Invoke-GhApi makes.
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Organization
    )

    return $Endpoint.Replace('{org}', $Organization).TrimStart('/')
}

function Get-SettingObservation {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$ReasonCode,
        [AllowNull()][object]$HttpStatus,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Reason
    )

    return [pscustomobject]@{ Status = $Status; ReasonCode = $ReasonCode; HttpStatus = $HttpStatus; Source = $Source; Reason = $Reason }
}

function Get-CheckRowOfEndpoint {
    # The check rows whose value is read from the endpoint (OpenAPI path).
    param([Parameter(Mandatory)][string]$Endpoint)

    return @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'check' } | Where-Object { (Get-SettingRead -Definition $_).Endpoint -eq $Endpoint })
}

function Find-ResponseValue {
    # @{ Value } of a field of an answer, or $null when the answer lacks it. 'a.b' reads b of the object a (GitHub
    # answers some settings as {configured, effective, ...}); a field present with the value null is found.
    param(
        [AllowNull()][object]$Response,
        [Parameter(Mandatory)][string]$Field
    )

    $node = $Response
    foreach ($part in $Field.Split('.')) {
        if ($node -isnot [System.Management.Automation.PSCustomObject] -or -not $node.PSObject.Properties[$part]) {
            return $null
        }
        $node = $node.$part
    }
    return @{ Value = $node }
}

function Add-ResponseObservation {
    # Records the field names of an answer that is an object (names, never values) and a FieldMissing observation for
    # each check row of the endpoint whose field the answer lacks: an answer that is not an object lacks all of them. A
    # field present with the value null is observed. -Values receives the value of each observed field, by row path, for the rows
    # whose value no section map holds (spec 3.4), whichever read reaches them.
    param(
        [AllowNull()][object]$Response,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ResponseFields,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Observations,
        [System.Collections.IDictionary]$Values
    )

    $isObject = $Response -is [System.Management.Automation.PSCustomObject]
    if ($isObject) {
        # An empty object ({}) has no names, not one empty name.
        $ResponseFields[$Endpoint] = [string[]]@($Response.PSObject.Properties.Name | Where-Object { $_ })
    }
    $concrete = Get-ConcreteEndpoint -Endpoint $Endpoint -Organization $Organization
    foreach ($definition in (Get-CheckRowOfEndpoint -Endpoint $Endpoint)) {
        $field = (Get-SettingRead -Definition $definition).Field
        $path = Get-SettingPath -Definition $definition
        $found = Find-ResponseValue -Response $Response -Field $field
        # An object answer that leaves the field out means its AbsentValue where GitHub documents so (interaction
        # limits answer {} when none is set).
        if (-not $found -and $isObject -and $definition.ContainsKey('AbsentValue')) {
            $found = @{ Value = $definition.AbsentValue }
        }
        if ($found) {
            # A row of a section of $script:Sections that reads this section's endpoint has its value in the section map.
            $inSectionMap = $script:Sections.Contains($definition.Section) -and ('/orgs/{org}' + $script:Sections[$definition.Section].Path) -eq $Endpoint
            if ($Values -and -not $inSectionMap) {
                $Values[$path] = $found.Value
            }
            continue
        }
        $Observations[$path] = Get-SettingObservation -Status 'NotObserved' -ReasonCode 'FieldMissing' -HttpStatus $null -Source "GET $concrete .$field" -Reason "GET $concrete answered without the field $field"
    }
}

function Get-FailedReadObservation {
    # How a failed read of a check-only endpoint is reported for a row (spec 3.4): the status comes from the error,
    # never from its message; a plan restriction needs positive evidence, the organization's plan.
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$Concrete,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [AllowNull()][string]$OrganizationPlan
    )

    $field = (Get-SettingRead -Definition $Definition).Field
    $source = "GET $Concrete .$field"
    $status = Get-GhStatus -ErrorRecord $ErrorRecord
    $absent = $null
    if ($Definition.Absent) {
        $absent = $script:AbsentCases[$Definition.Absent]
    }
    # A status case speaks only for its own endpoint: a 404 elsewhere is not the feature missing.
    if ($absent -and $status -eq $absent.Status -and $absent.Endpoint -eq (Get-SettingRead -Definition $Definition).Endpoint) {
        return Get-SettingObservation -Status 'NotApplicable' -ReasonCode 'FeatureAbsent' -HttpStatus $status -Source $source -Reason $absent.Message
    }
    if ($status -eq 401) {
        return Get-SettingObservation -Status 'NotObserved' -ReasonCode 'AuthenticationFailed' -HttpStatus $status -Source $source -Reason "GET $Concrete answered 401: the gh token is missing, expired or revoked"
    }
    if ($status -in 403, 404) {
        $plans = @($Definition.ReadRequiresPlan | Where-Object { $_ })
        if ($plans.Count -gt 0 -and $OrganizationPlan -and $OrganizationPlan -notin $plans) {
            return Get-SettingObservation -Status 'NotObserved' -ReasonCode 'PlanRestricted' -HttpStatus $status -Source $source -Reason "GET $Concrete answered $status and the organization's plan is $OrganizationPlan; reading it needs $($plans -join ' or ')"
        }
        if ($status -eq 403) {
            return Get-SettingObservation -Status 'NotObserved' -ReasonCode 'PermissionDenied' -HttpStatus $status -Source $source -Reason "GET $Concrete answered 403: the gh account may not read it"
        }
        return Get-SettingObservation -Status 'NotObserved' -ReasonCode 'NotFound' -HttpStatus $status -Source $source -Reason "GET $Concrete answered 404: not found or not visible to this token"
    }
    # Invoke-GhApi throws an HttpRequestException for a failed call, without a status when gh got no answer; any other
    # error is the parsing of an answer that came.
    $detail = 'the answer is not JSON'
    if ($null -ne $status) {
        $detail = "HTTP $status"
    }
    else {
        for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
            if ($exception -is [System.Net.Http.HttpRequestException]) {
                $detail = 'no answer'
                break
            }
        }
    }
    return Get-SettingObservation -Status 'NotObserved' -ReasonCode 'TechnicalFailure' -HttpStatus $status -Source $source -Reason "GET $Concrete failed ($detail)"
}

function Add-AbsentObservation {
    # The rows whose Absent case a 200 answer of their endpoint shows (Field = Value) do not apply: their value is
    # dropped and they become NotApplicable.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable[]]$Rows,
        [AllowNull()][object]$Response,
        [Parameter(Mandatory)][string]$Concrete,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Observations,
        [Parameter(Mandatory)][System.Collections.IDictionary]$CheckedValues
    )

    foreach ($definition in $Rows) {
        $case = $null
        if ($definition.Absent) {
            $case = $script:AbsentCases[$definition.Absent]
        }
        if ($case -and $null -ne $Response -and $Response.($case.Field) -eq $case.Value) {
            $path = Get-SettingPath -Definition $definition
            $CheckedValues.Remove($path)
            $Observations[$path] = Get-SettingObservation -Status 'NotApplicable' -ReasonCode 'FeatureAbsent' -HttpStatus $null -Source "GET $Concrete .$($case.Field)" -Reason $case.Message
        }
    }
}

function Read-CheckOnlyEndpoint {
    # Reads each endpoint that only check rows depend on, once. A failed read never stops the run: its rows become
    # observations. The endpoints an apply row reads are read by Get-GitHubOrgState, which stops on a failure. A row
    # whose Absent case this run already found (-AbsentCases, such as no Copilot plan) does not apply and is not read.
    param(
        [Parameter(Mandatory)][string]$Organization,
        [AllowNull()][string]$OrganizationPlan,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ResponseFields,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Observations,
        [Parameter(Mandatory)][System.Collections.IDictionary]$CheckedValues,
        [AllowEmptyCollection()][string[]]$AbsentCases = @()
    )

    $rows = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'check' })) {
        $read = Get-SettingRead -Definition $definition
        if (-not $read -or $read.Endpoint -in $script:ApplyReadEndpoints) {
            continue
        }
        if ($definition.Absent -and $definition.Absent -in $AbsentCases) {
            $case = $script:AbsentCases[$definition.Absent]
            $Observations[(Get-SettingPath -Definition $definition)] = Get-SettingObservation -Status 'NotApplicable' -ReasonCode 'FeatureAbsent' -HttpStatus $null -Source "GET $(Get-ConcreteEndpoint -Endpoint $case.Endpoint -Organization $Organization)" -Reason $case.Message
            continue
        }
        $rows.Add($definition)
    }
    foreach ($endpoint in @($rows | ForEach-Object { (Get-SettingRead -Definition $_).Endpoint } | Select-Object -Unique)) {
        $concrete = Get-ConcreteEndpoint -Endpoint $endpoint -Organization $Organization
        Write-StateProgress -Status $concrete
        $endpointRows = [hashtable[]]@($rows | Where-Object { (Get-SettingRead -Definition $_).Endpoint -eq $endpoint })
        try {
            # The root as it is: a single-item array is not an object.
            $response = Invoke-GhApi -Endpoint $concrete -NoEnumerate
        }
        catch {
            foreach ($definition in $endpointRows) {
                $Observations[(Get-SettingPath -Definition $definition)] = Get-FailedReadObservation -Definition $definition -Concrete $concrete -ErrorRecord $_ -OrganizationPlan $OrganizationPlan
            }
            continue
        }
        Add-ResponseObservation -Response $response -Endpoint $endpoint -Organization $Organization -ResponseFields $ResponseFields -Observations $Observations -Values $CheckedValues
        Add-AbsentObservation -Rows $endpointRows -Response $response -Concrete $concrete -Observations $Observations -CheckedValues $CheckedValues
    }
}

function Read-CopilotBillingObservation {
    # The observations of the check rows of the Copilot billing answer (an apply read, spec 5.2), and the names of the
    # Absent cases it shows: without a plan (404, or seat management unconfigured) the Copilot rows do not apply.
    param(
        [AllowNull()][object]$Billing,
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ResponseFields,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Observations,
        [Parameter(Mandatory)][System.Collections.IDictionary]$CheckedValues
    )

    $endpoint = '/orgs/{org}/copilot/billing'
    $concrete = Get-ConcreteEndpoint -Endpoint $endpoint -Organization $Organization
    $rows = [hashtable[]]@(Get-CheckRowOfEndpoint -Endpoint $endpoint)
    $absent = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $script:AbsentCases.Keys) {
        $case = $script:AbsentCases[$name]
        if ($case.Endpoint -eq $endpoint -and ($null -eq $Billing -or $Billing.($case.Field) -eq $case.Value)) {
            $absent.Add($name)
        }
    }
    if ($null -eq $Billing) {
        foreach ($definition in $rows) {
            $field = (Get-SettingRead -Definition $definition).Field
            $path = Get-SettingPath -Definition $definition
            if ($definition.Absent -and $definition.Absent -in $absent) {
                $Observations[$path] = Get-SettingObservation -Status 'NotApplicable' -ReasonCode 'FeatureAbsent' -HttpStatus 404 -Source "GET $concrete .$field" -Reason $script:AbsentCases[$definition.Absent].Message
            }
            else {
                $Observations[$path] = Get-SettingObservation -Status 'NotObserved' -ReasonCode 'NotFound' -HttpStatus 404 -Source "GET $concrete .$field" -Reason "GET $concrete answered 404: not found or not visible to this token"
            }
        }
    }
    else {
        Add-ResponseObservation -Response $Billing -Endpoint $endpoint -Organization $Organization -ResponseFields $ResponseFields -Observations $Observations -Values $CheckedValues
        Add-AbsentObservation -Rows $rows -Response $Billing -Concrete $concrete -Observations $Observations -CheckedValues $CheckedValues
    }
    return [string[]]$absent
}

function Get-GitHubOrgState {
    <#
    .SYNOPSIS
    Reads the organization settings, the inventory, the code security configuration, the Copilot seats, the ruleset and the budgets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        # The directory of the config file, where the reference copies of the required workflows are; without it the
        # state holds none and no workflow is compared.
        [AllowNull()][AllowEmptyString()][string]$ConfigDirectory
    )

    $state = [ordered]@{
        Settings = $null; Actions = $null; SelectedActions = $null; Workflow = $null
        SelfHostedRunners = $null; ForkPullRequests = $null; PrivateForkPullRequests = $null; Retention = $null
        CopilotCloudAgent = $null; Inventory = $null; CodeSecurity = $null; CopilotSeats = $null; Ruleset = $null; Budgets = $null
        Observations = [ordered]@{}; CheckedValues = [ordered]@{}; OrganizationPlan = $null; ResponseFields = [ordered]@{}
        ReadAt = $null
    }
    try {
        foreach ($section in $script:Sections.Keys) {
            # GitHub answers 409 for the selection while allowed_actions is not 'selected'; 'actions' is read first.
            if ($section -eq 'actions.selected' -and $state.Actions.allowed_actions -cne 'selected') {
                continue
            }
            $meta = $script:Sections[$section]
            Write-StateProgress -Status $meta.Reading
            # The observations need the root as it is (a single-item array is not an object); the section map and the
            # plan name read the answer as Invoke-GhApi returns it by default, its items.
            $root = Read-OrgEndpoint -Endpoint "orgs/$($Config.organization)$($meta.Path)" -NoEnumerate
            $response = $root | ForEach-Object { $_ }
            $state[$meta.StateKey] = ConvertTo-FieldMap -Response $response -Section $section
            Add-ResponseObservation -Response $root -Endpoint ('/orgs/{org}' + $meta.Path) -Organization $Config.organization -ResponseFields $state.ResponseFields -Observations $state.Observations -Values $state.CheckedValues
            if ($section -eq 'settings' -and $response.plan.name) {
                $state.OrganizationPlan = [string]$response.plan.name
            }
        }
        # Read once: the seats, the ruleset and the checked Copilot policies use it, and its absent case spares the reads
        # of the other Copilot endpoints.
        $billing = Read-CopilotBilling -Organization $Config.organization
        $absentCases = Read-CopilotBillingObservation -Billing $billing -Organization $Config.organization -ResponseFields $state.ResponseFields -Observations $state.Observations -CheckedValues $state.CheckedValues
        Read-CheckOnlyEndpoint -Organization $Config.organization -OrganizationPlan $state.OrganizationPlan -ResponseFields $state.ResponseFields -Observations $state.Observations -CheckedValues $state.CheckedValues -AbsentCases $absentCases
        $repositories = Read-OrgRepository -Organization $Config.organization
        $state.Inventory = Read-InventoryState -Organization $Config.organization -OrgRepository $repositories
        $state.CodeSecurity = Read-CodeSecurityState -Organization $Config.organization -Name $Config.codeSecurity.name -OrgRepository $repositories
        $state.CopilotSeats = Read-CopilotSeatState -Organization $Config.organization -Config $Config -Billing $billing
        $state.Ruleset = Read-RulesetState -Organization $Config.organization -Config $Config -OrgRepository $repositories -CopilotSeats $state.CopilotSeats -ConfigDirectory $ConfigDirectory
        $state.Budgets = @(Read-BudgetState -Organization $Config.organization)
    }
    finally {
        Complete-BootstrapProgress
    }
    # When the last read returned: what the run shows is GitHub as of this time (the page walk prints it).
    $state.ReadAt = [datetime]::UtcNow
    return [pscustomobject]$state
}
