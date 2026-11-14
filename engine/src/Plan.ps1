# Diffs the config against the current state into actions and warnings. Pure: no GitHub calls.

$script:ShaPinningWarning = 'SHA pinning becomes required: once applied, GitHub runs an action only when a workflow references it by full commit SHA, so every workflow in the organization that uses a tag or branch will fail. Before applying, in every repository replace ''uses: owner/action@v1.2.3'' with ''uses: owner/action@<40-character commit SHA> # v1.2.3'' (the SHA: gh api repos/owner/action/commits/v1.2.3 --jq .sha); see engine/README.md#requirements.'

function Get-NameSet {
    # A case-insensitive set of names (logins, hosts, slugs, action patterns); $null items are left out.
    param([AllowNull()][object]$Value)
    return , [System.Collections.Generic.HashSet[string]]::new([string[]]@($Value | Where-Object { $null -ne $_ }), [StringComparer]::OrdinalIgnoreCase)
}

function Compare-NameSet {
    # The names only in Actual (Extra) and only in Expected (Missing), compared case-insensitively
    # (docs/architecture.md, "Case in comparisons"); each in the order of its own list.
    param(
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual
    )

    $expectedSet = Get-NameSet -Value $Expected
    $actualSet = Get-NameSet -Value $Actual
    [pscustomobject]@{
        Extra   = [string[]]@($Actual | Where-Object { $null -ne $_ -and -not $expectedSet.Contains($_) })
        Missing = [string[]]@($Expected | Where-Object { $null -ne $_ -and -not $actualSet.Contains($_) })
    }
}

function Test-SettingEqual {
    # Lists compare as case-insensitive sets (GitHub keeps its own order), email addresses case-insensitively; other
    # values compare exactly.
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [AllowNull()][object]$Current,
        [AllowNull()][object]$Desired
    )

    if ($Definition.Type -eq 'list') {
        return (Get-NameSet -Value $Current).SetEquals([string[]]@($Desired | Where-Object { $null -ne $_ }))
    }
    # A row that may be null matches null; elsewhere a missing value is never a match.
    if ($Definition.Nullable -and $null -eq $Current -and $null -eq $Desired) {
        return $true
    }
    if ($Definition.Type -eq 'email') {
        return ($null -ne $Current) -and ($Current -ieq $Desired)
    }
    return ($null -ne $Current) -and ($Current -ceq $Desired)
}

function Format-SettingValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return '<none>'
    }
    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }
    if ($Value -is [array]) {
        if ($Value.Count -eq 0) {
            return '(empty list)'
        }
        return @($Value) -join ', '
    }
    return [string]$Value
}

function Format-ListChange {
    param(
        [Parameter(Mandatory)][string]$Field,
        [AllowNull()][object]$Current,
        [AllowNull()][object]$Desired
    )

    $difference = Compare-NameSet -Expected $Current -Actual $Desired
    $parts = @($difference.Extra | ForEach-Object { "+ $_" }) + @($difference.Missing | ForEach-Object { "- $_" })
    if ($parts.Count -eq 0) {
        return "${Field}: (empty list)"
    }
    return "${Field}: $($parts -join ', ')"
}

function Get-InactiveDependency {
    # The DependsOn field of a row while the config sets it to false, else $null. GitHub then ignores the row's field
    # and keeps it as it is: comparing it would plan the same change on every run, so the plan leaves it alone and a
    # PUT sends back what GitHub has.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$Definition
    )

    if ($Definition.DependsOn -and (Get-ConfiguredValue -Config $Config -Section $Definition.Section)[$Definition.DependsOn] -ne $true) {
        return $Definition.DependsOn
    }
    return $null
}

function Get-SectionAction {
    # The action for one section, or nothing when its apply fields already match or the section is null (only
    # actions.selected can be). A missing current state (no selection yet) counts every field as a change.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Section,
        [AllowNull()][System.Collections.IDictionary]$Current
    )

    if ($null -eq (Get-ConfigSection -Config $Config -Section $Section)) {
        return
    }
    $desired = Get-ConfiguredValue -Config $Config -Section $Section
    $definitions = @(Get-SettingDefinition -Section $Section | Where-Object { $_.Mode -eq 'apply' })
    $changes = [System.Collections.Generic.List[string]]::new()
    $changed = [ordered]@{}
    $ignored = @($definitions | Where-Object { Get-InactiveDependency -Config $Config -Definition $_ } | ForEach-Object { $_.Field })
    foreach ($definition in $definitions) {
        $field = $definition.Field
        if ($field -in $ignored) {
            continue
        }
        $currentValue = $null
        if ($null -ne $Current) {
            $currentValue = $Current[$field]
            if (Test-SettingEqual -Definition $definition -Current $currentValue -Desired $desired[$field]) {
                continue
            }
        }
        $changed[$field] = $desired[$field]
        if ($definition.Type -eq 'list') {
            $changes.Add((Format-ListChange -Field $field -Current $currentValue -Desired $desired[$field]))
        }
        else {
            $changes.Add("${field}: $(Format-SettingValue $currentValue) -> $(Format-SettingValue $desired[$field])")
        }
    }
    if ($changed.Count -eq 0) {
        return
    }

    $meta = $script:Sections[$Section]
    $body = [ordered]@{}
    # A PATCH changes only what it carries; a PUT replaces the whole setting, every field of which is in the config.
    $fields = if ($meta.Method -eq 'PATCH') { @($changed.Keys) } else { @($definitions | ForEach-Object { $_.Field }) }
    foreach ($definition in @($definitions | Where-Object { $_.Field -in $fields })) {
        $field = $definition.Field
        $value = $desired[$field]
        if ($field -in $ignored -and $null -ne $Current -and $null -ne $Current[$field]) {
            $value = $Current[$field]
        }
        if ($definition.Type -eq 'list') {
            $body[$field] = [string[]]@($value | Where-Object { $null -ne $_ })
        }
        else {
            $body[$field] = $value
        }
    }

    [pscustomobject]@{
        Action   = $meta.Action
        Target   = [string]$Config.organization
        Method   = $meta.Method
        Endpoint = "orgs/$($Config.organization)$($meta.Path)"
        Body     = $body
        Summary  = "~ $($meta.Label) of $($Config.organization): $($changes -join '; ')"
        Details  = Get-SectionActionDetail -Organization ([string]$Config.organization) -Meta $meta -Changed @($definitions | Where-Object { $changed.Contains($_.Field) })
    }
}

function Get-SectionActionDetail {
    # The lines under an action: where each changed field is in the web UI, which endpoint it was read from and how it
    # is written. The Read lines group by each field's own read endpoint, not by the section's.
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][hashtable]$Meta,
        [Parameter(Mandatory)][hashtable[]]$Changed
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $seenUi = @{}
    foreach ($definition in $Changed) {
        $page = if ($definition.ContainsKey('Page')) { Get-SettingPage -Path $definition.Page } else { $null }
        if ($null -eq $page) {
            continue
        }
        $where = $page.Label
        if ($definition.ContainsKey('UiGroup')) {
            $where += " > $($definition.UiGroup)"
        }
        # One line per page and group: the page by its path, which is unique where a label need not be.
        $key = "$($page.Path)|$($definition.UiGroup)"
        if ($seenUi.ContainsKey($key)) {
            continue
        }
        $seenUi[$key] = $true
        $lines.Add("UI:    $where  https://github.com/organizations/$Organization/settings/$($page.Path)")
    }

    $reads = [ordered]@{}
    foreach ($definition in $Changed) {
        $read = Get-SettingRead -Definition $definition
        if ($null -eq $read) {
            continue
        }
        if (-not $reads.Contains($read.Endpoint)) {
            $reads[$read.Endpoint] = [System.Collections.Generic.List[string]]::new()
        }
        $reads[$read.Endpoint].Add(".$($read.Field)")
    }
    foreach ($endpoint in $reads.Keys) {
        $path = $endpoint.Replace('/orgs/{org}', "orgs/$Organization")
        $lines.Add("Read:  GET $path $($reads[$endpoint] -join ', ')")
    }

    $scope = if ($Meta.Method -eq 'PATCH') { 'only these fields' } else { 'the whole section' }
    $lines.Add("Apply: $($Meta.Method) orgs/$Organization$($Meta.Path) ($scope)")
    return [string[]]$lines
}

function Get-SkippedPutSection {
    # The sections whose PUT the plan leaves out. A PUT replaces the whole section: with a field in GitHub's answer that
    # the engine does not know, it could reset it. With 'actions' left out, allowed_actions stays as it is, so a selection
    # is planned only when GitHub already has 'selected' (State read SelectedActions); otherwise GitHub answers 409.
    param([Parameter(Mandatory)][object]$CurrentState)

    $unknown = Get-UnknownResponseField -State $CurrentState
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($section in $script:Sections.Keys) {
        if ($script:Sections[$section].Method -eq 'PUT' -and $unknown.Contains('/orgs/{org}' + $script:Sections[$section].Path)) {
            $skipped.Add($section)
        }
    }
    if ($skipped.Contains('actions') -and -not $skipped.Contains('actions.selected') -and $null -eq $CurrentState.SelectedActions) {
        $skipped.Add('actions.selected')
    }
    return [string[]]$skipped
}

function Get-GitHubOrgPlan {
    <#
    .SYNOPSIS
    Returns the ordered actions that bring the organization to the config.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [object]$CurrentState
    )

    $skipped = Get-SkippedPutSection -CurrentState $CurrentState
    foreach ($section in $script:Sections.Keys) {
        if ($section -in $skipped) {
            continue
        }
        Get-SectionAction -Config $Config -Section $section -Current $CurrentState.($script:Sections[$section].StateKey)
    }
    Get-CodeSecurityAction -Config $Config -Current $CurrentState.CodeSecurity
    Get-RulesetAction -Config $Config -Ruleset $CurrentState.Ruleset
    Get-BudgetAction -Config $Config -Current $CurrentState.Budgets
    Get-CopilotSeatAction -Config $Config -Current $CurrentState.CopilotSeats
}

function Get-TaggedWarning {
    # A warning with the settings page and the row it belongs to, either or both $null.
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][string]$Page,
        [AllowNull()][string]$Path
    )

    [pscustomobject]@{ Text = $Text; Page = $(if ($Page) { $Page } else { $null }); Path = $(if ($Path) { $Path } else { $null }) }
}

function Get-ObservationWarning {
    # One warning item per setting a run could not observe, with the reason, tagged with its row; one per absent case
    # for the settings that do not apply (no Copilot plan), without a row. Rows in the order of the definitions.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Observations
    )

    $absent = [ordered]@{}
    foreach ($definition in @($script:SettingDefinitions | Where-Object { $Observations.Contains((Get-SettingPath -Definition $_)) })) {
        $path = Get-SettingPath -Definition $definition
        $observation = $Observations[$path]
        if ($observation.Status -eq 'NotApplicable') {
            $absent[$observation.Reason] = 1 + [int]$absent[$observation.Reason]
            continue
        }
        $expected = 'a value that is not shown'
        if (-not $definition.Sensitive) {
            $expected = Format-SettingValue (Get-ConfiguredValue -Config $Config -Section $definition.Section)[$definition.Field]
        }
        if (-not $definition.Page) {
            # No page shows it (NoUi): nothing to check by hand.
            Get-TaggedWarning -Text "$path is not observed: $($observation.Reason). The config expects $expected." -Page $null -Path $path
            continue
        }
        Get-TaggedWarning -Text "$path is not observed: $($observation.Reason). The config expects $expected; check it on https://github.com/organizations/$($Config.organization)/settings/$($definition.Page)." -Page $definition.Page -Path $path
    }
    foreach ($message in $absent.Keys) {
        $count = $absent[$message]
        $settings = if ($count -eq 1) { '1 checked setting is' } else { "$count checked settings are" }
        Get-TaggedWarning -Text "$settings not checked: $message." -Page $null -Path $null
    }
}

function Get-ManualRow {
    # The rows no API reads or writes, in the order of the definitions.
    return @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'manual' })
}

function Get-ManualSummary {
    # One line about the settings only a person can check, or $null without such rows.
    $rows = @(Get-ManualRow)
    if ($rows.Count -eq 0) {
        return $null
    }
    $settings = if ($rows.Count -eq 1) { '1 setting has' } else { "$($rows.Count) settings have" }
    return "Manual: $settings no API read; this run did not check them. List them: rerun with -WhatIf -ManualChecklist."
}

function Format-ManualValue {
    # A value of a manual row, with the option label of the page after it when the row names one.
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [AllowNull()][object]$Value
    )

    $text = Format-SettingValue $Value
    if ($Definition.Options -and $null -ne $Value -and $Definition.Options.ContainsKey([string]$Value)) {
        $text += " (`"$($Definition.Options[[string]$Value])`")"
    }
    return $text
}

function Resolve-UiText {
    # A row with <organization> in its UI words replaced by the organization of the config: the page shows its name there.
    param(
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$Organization
    )

    $row = $Definition.Clone()
    foreach ($key in @('UiGroup', 'UiLabel', 'Hint')) {
        if ($row[$key]) { $row[$key] = ([string]$row[$key]).Replace('<organization>', $Organization) }
    }
    if ($row.Options) {
        $options = @{}
        foreach ($value in $row.Options.Keys) { $options[$value] = ([string]$row.Options[$value]).Replace('<organization>', $Organization) }
        $row.Options = $options
    }
    return $row
}

function Get-ControlText {
    # The control of a row as the page names it, with the hint after it: the label, the hint alone without one.
    param([Parameter(Mandatory)][hashtable]$Definition)

    if ($Definition.UiLabel -and $Definition.Hint) {
        return "$($Definition.UiLabel) ($($Definition.Hint))"
    }
    if ($Definition.UiLabel) {
        return $Definition.UiLabel
    }
    return $Definition.Hint
}

function Get-ManualChecklist {
    # Per settings page (in the order of the page list) the address, then per row where it is, the value the
    # config expects and why. A sensitive row never shows its value. Without manual rows one line says so, which
    # confirms the switch.
    param([Parameter(Mandatory)][object]$Config)

    if (@(Get-ManualRow).Count -eq 0) {
        return 'No settings need a manual check.'
    }
    foreach ($page in $script:SettingPages) {
        $onPage = @(Get-PageRow -Page $page | Where-Object { $_.Mode -eq 'manual' })
        if ($onPage.Count -eq 0) {
            continue
        }
        "$($page.Label)  https://github.com/organizations/$($Config.organization)/settings/$($page.Path)"
        foreach ($row in $onPage) {
            $definition = Resolve-UiText -Definition $row -Organization ([string]$Config.organization)
            $what = Get-ControlText -Definition $definition
            if ($definition.Sensitive) {
                $expected = 'a value that is not shown'
            }
            else {
                $value = (Get-ConfiguredValue -Config $Config -Section $definition.Section)[$definition.Field]
                $expected = Format-ManualValue -Definition $definition -Value $value
                if ($definition.ContainsKey('Recommended') -and (Format-SettingValue $definition.Recommended) -ne (Format-SettingValue $value)) {
                    $expected += " (recommended $(Format-ManualValue -Definition $definition -Value $definition.Recommended))"
                }
            }
            $where = if ($definition.UiGroup) { "$($definition.UiGroup): $what" } else { $what }
            "  $where -> expected $expected"
            "    $($definition.Why)"
        }
    }
}

function Get-CheckMismatchWarning {
    # The warning for a checked setting whose value differs from the config, or $null when it matches. A row of an
    # endpoint section is named by its field (as always), any other by its config path. A row GitHub could write says
    # the engine does not apply it yet; Options name the choice on the page for an enum without a checkbox.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$Definition,
        [AllowNull()][object]$Current
    )

    $desired = (Get-ConfiguredValue -Config $Config -Section $Definition.Section)[$Definition.Field]
    $Definition = Resolve-UiText -Definition $Definition -Organization ([string]$Config.organization)
    if (Test-SettingEqual -Definition $Definition -Current $Current -Desired $desired) {
        return $null
    }
    $name = if ($script:Sections.Contains($Definition.Section)) { $Definition.Field } else { Get-SettingPath -Definition $Definition }
    $why = if (Get-SettingWrite -Definition $Definition) { 'this tool does not apply it yet' } else { 'GitHub has no API to change it' }
    $url = "https://github.com/organizations/$($Config.organization)/settings/$($Definition.Page)"
    $mismatch = "$name is $(Format-SettingValue $Current), the config expects $(Format-SettingValue $desired). $why"
    # No page shows it (NoUi): nothing to open.
    if (-not $Definition.Page) {
        return "$mismatch."
    }
    if ($Definition.Hint) {
        return "${mismatch}: open $url, $($Definition.Hint)."
    }
    if ($Definition.Options) {
        # A value the page offers no option for (unconfigured, null) is named by the config only.
        # A control with a label of its own is named after its group; one without is named by the group.
        $control = if ($Definition.UiLabel) { "under `"$($Definition.UiGroup)`" set `"$($Definition.UiLabel)`" to" } else { "under `"$($Definition.UiGroup)`" choose" }
        if ($null -ne $desired -and $Definition.Options.ContainsKey([string]$desired)) {
            return "${mismatch}: open $url, $control `"$($Definition.Options[[string]$desired])`", and save."
        }
        if ($Definition.UiLabel) {
            return "${mismatch}: open $url, under `"$($Definition.UiGroup)`" set `"$($Definition.UiLabel)`" to the value the config expects, and save."
        }
        return "${mismatch}: open $url, under `"$($Definition.UiGroup)`" set the value the config expects, and save."
    }
    $verb = 'clear'
    if ($desired -eq $true) {
        $verb = 'select'
    }
    return "${mismatch}: open $url, under `"$($Definition.UiGroup)`" $verb `"$($Definition.UiLabel)`", and save."
}

function Get-GitHubOrgWarningItem {
    <#
    .SYNOPSIS
    The warnings of Get-GitHubOrgWarning, in its order, each {Text, Page, Path}: the settings page and the row it belongs to, or $null. The page walk places them by it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [object]$CurrentState,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    $warnings = [System.Collections.Generic.List[object]]::new()
    # A state built without observations observed everything.
    $observations = $CurrentState.PSObject.Properties['Observations'].Value
    if ($null -eq $observations) {
        $observations = @{}
    }
    foreach ($section in $script:Sections.Keys) {
        $current = $CurrentState.($script:Sections[$section].StateKey)
        foreach ($definition in @(Get-SettingDefinition -Section $section | Where-Object { $_.Mode -eq 'check' })) {
            # A value that was not read is never compared with the config.
            if ($observations.Contains((Get-SettingPath -Definition $definition))) {
                continue
            }
            $currentValue = $null
            if ($null -ne $current) {
                $currentValue = $current[$definition.Field]
            }
            $warning = Get-CheckMismatchWarning -Config $Config -Definition $definition -Current $currentValue
            if ($warning) {
                $warnings.Add((Get-TaggedWarning -Text $warning -Page $definition.Page -Path (Get-SettingPath -Definition $definition)))
            }
        }
    }
    # Rows outside the endpoint sections keep their value in CheckedValues (spec 3.4).
    $checkedValues = $CurrentState.PSObject.Properties['CheckedValues'].Value
    foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'check' -and -not $script:Sections.Contains($_.Section) })) {
        $path = Get-SettingPath -Definition $definition
        if ($observations.Contains($path) -or $null -eq $checkedValues -or -not $checkedValues.Contains($path)) {
            continue
        }
        $warning = Get-CheckMismatchWarning -Config $Config -Definition $definition -Current $checkedValues[$path]
        if ($warning) {
            $warnings.Add((Get-TaggedWarning -Text $warning -Page $definition.Page -Path $path))
        }
    }

    foreach ($warning in @(Get-ObservationWarning -Config $Config -Observations $observations)) {
        $warnings.Add($warning)
    }
    # Field names only: the value of a field the engine does not know may be a secret.
    $unknown = Get-UnknownResponseField -State $CurrentState
    foreach ($endpoint in $unknown.Keys) {
        $concrete = Get-ConcreteEndpoint -Endpoint $endpoint -Organization ([string]$Config.organization)
        $names = @($unknown[$endpoint] | ForEach-Object { "'$_'" }) -join ', '
        $one = @($unknown[$endpoint]).Count -eq 1
        $returned = if ($one) { "returned the field $names" } else { "returned the fields $names" }
        # The skipped PUT is worth a word only when it would have changed something.
        $putSection = @(Get-SkippedPutSection -CurrentState $CurrentState | Where-Object { ('/orgs/{org}' + $script:Sections[$_].Path) -eq $endpoint }) | Select-Object -First 1
        if ($putSection -and (Get-SectionAction -Config $Config -Section $putSection -Current $CurrentState.($script:Sections[$putSection].StateKey))) {
            $them = if ($one) { 'it' } else { 'them' }
            $until = if ($one) { 'it is a row' } else { 'each is a row' }
            $warnings.Add((Get-TaggedWarning -Page $null -Path $null -Text "GET $concrete $returned, which this tool does not know. The engine replaces $($script:Sections[$putSection].Reading) as a whole and could reset $them, so it plans no change to it until $until or listed under Fields of GET $endpoint in engine/api-endpoints.psd1."))
            continue
        }
        $add = if ($one) { 'add a row for it, or list it' } else { 'add a row for each, or list each' }
        $warnings.Add((Get-TaggedWarning -Page $null -Path $null -Text "GET $concrete $returned, which this tool does not know: $add under Fields of GET $endpoint in engine/api-endpoints.psd1 with the reason."))
    }

    $permissions = @($Plan | Where-Object { $_.Action -eq 'SetActionsPermissions' }) | Select-Object -First 1
    if ($permissions -and $permissions.Body.sha_pinning_required -eq $true -and $CurrentState.Actions.sha_pinning_required -ne $true) {
        $warnings.Add((Get-TaggedWarning -Text $script:ShaPinningWarning -Page $null -Path $null))
    }

    # The areas, each on its page; the inventory part by part, in the order of Get-InventoryWarning.
    $sources = @(
        @{ Page = 'security_products'; Warnings = { Get-CodeSecurityWarning -Config $Config -CodeSecurity $CurrentState.CodeSecurity } }
        @{ Page = $null; Warnings = { Get-OwnerWarning -Config $Config -Inventory $CurrentState.Inventory } }
        @{ Page = 'installations'; Warnings = { Get-AppWarning -Config $Config -Inventory $CurrentState.Inventory } }
        @{ Page = 'hooks'; Warnings = { Get-WebhookWarning -Config $Config -Inventory $CurrentState.Inventory } }
        @{ Page = $null; Warnings = { Get-OutsideCollaboratorWarning -Config $Config -Inventory $CurrentState.Inventory } }
        @{ Page = $null; Warnings = { Get-InvitationWarning -Config $Config -Inventory $CurrentState.Inventory } }
        @{ Page = 'rules'; Warnings = { Get-RulesetWarning -Config $Config -Ruleset $CurrentState.Ruleset } }
        @{ Page = 'copilot/seat_management'; Warnings = { Get-CopilotSeatWarning -Config $Config -Current $CurrentState.CopilotSeats } }
        @{ Page = 'billing/budgets'; Warnings = { Get-BudgetWarning -Config $Config -CurrentState $CurrentState } }
    )
    foreach ($source in $sources) {
        foreach ($warning in @(& $source.Warnings)) {
            $warnings.Add((Get-TaggedWarning -Text $warning -Page $source.Page -Path $null))
        }
    }
    return $warnings.ToArray()
}

function Get-GitHubOrgWarning {
    <#
    .SYNOPSIS
    Returns warnings about the organization: checked settings that differ from the config, SHA pinning about to become required, code security repositories, the inventory, the ruleset, the budgets and the Copilot seats. Settings that differ from their recommendation come from Get-RecommendationReport.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [object]$CurrentState,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    return [string[]]@(Get-GitHubOrgWarningItem -Config $Config -CurrentState $CurrentState -Plan $Plan | ForEach-Object { $_.Text })
}
