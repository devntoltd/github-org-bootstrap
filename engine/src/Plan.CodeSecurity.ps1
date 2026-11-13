# Code security actions and warnings: an object with a lifecycle (create, update, default, attach). Pure: no GitHub calls.

# Statuses of a repository's code security configuration that need nothing: in effect, or on its way
# (https://docs.github.com/en/code-security/reference/security-at-scale/configuration-statuses). Any other status is a
# warning, a status GitHub adds later included; 'failed' has its own.
$script:CodeSecurityStatusesInEffect = @('attached', 'attaching', 'updating', 'enforced', 'enterprise_enforced')
$script:CodeSecurityStatusMeanings = @{
    removed               = 'a repository admin changed a setting it controls'
    removed_by_enterprise = 'an enterprise configuration conflicts with it'
    detached              = 'the repository is detached from it'
}

function Test-DefaultOverlap {
    # Whether two default_for_new_repos values cover some of the same repositories.
    param([string]$First, [string]$Second)

    if ('none' -in @($First, $Second) -or -not $First -or -not $Second) {
        return $false
    }
    return ($First -eq 'all') -or ($Second -eq 'all') -or ($First -eq $Second)
}

function Get-CodeSecurityAction {
    # Create or update the configuration, make it the default, attach it to repositories without one.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Current
    )

    $section = $Config.codeSecurity
    $name = [string]$section.name
    $base = "orgs/$($Config.organization)/code-security/configurations"
    $desired = Get-ConfiguredValue -Config $Config -Section 'codeSecurity.settings'

    if ($null -eq $Current.Configuration) {
        # The id is known only after the create call; Invoke-GitHubOrgPlan replaces the token.
        $path = "$base/{configuration_id}"
        $enforcement = [string]$section.enforcement
        $body = [ordered]@{ name = $name; enforcement = $enforcement; description = [string]$section.description }
        foreach ($field in $desired.Keys) {
            $body[$field] = $desired[$field]
        }
        $summary = "+ create code security configuration '$name' ($enforcement): " + (@($desired.Keys | ForEach-Object { "${_}: $($desired[$_])" }) -join ', ')
        [pscustomobject]@{
            Action   = 'CreateCodeSecurityConfiguration'
            Target   = $name
            Method   = 'POST'
            Endpoint = $base
            Body     = $body
            Summary  = $summary
        }
    }
    else {
        $path = "$base/$($Current.Configuration.Id)"
        $changed = [ordered]@{}
        $changes = [System.Collections.Generic.List[string]]::new()
        if ([string]$section.description -cne $Current.Configuration.Description) {
            $changed.description = [string]$section.description
            $changes.Add("description: '$($Current.Configuration.Description)' -> '$($section.description)'")
        }
        if ([string]$section.enforcement -cne $Current.Configuration.Enforcement) {
            $changed.enforcement = [string]$section.enforcement
            $changes.Add("enforcement: $(Format-SettingValue $Current.Configuration.Enforcement) -> $($section.enforcement)")
        }
        foreach ($field in $desired.Keys) {
            $currentValue = $Current.Configuration.Settings[$field]
            if ($currentValue -cne $desired[$field]) {
                $changed[$field] = $desired[$field]
                $changes.Add("${field}: $(Format-SettingValue $currentValue) -> $($desired[$field])")
            }
        }
        if ($changed.Count -gt 0) {
            [pscustomobject]@{
                Action   = 'UpdateCodeSecurityConfiguration'
                Target   = $name
                Method   = 'PATCH'
                Endpoint = $path
                Body     = $changed
                Summary  = "~ update code security configuration '$name': $($changes -join '; ')"
            }
        }
    }

    $wanted = [string]$section.default_for_new_repos
    # Not being a default is the same as 'none'.
    $currentDefault = if ($Current.Default) { [string]$Current.Default } else { 'none' }
    if ($wanted -cne $currentDefault) {
        $replaced = @($Current.OtherDefaults | Where-Object { Test-DefaultOverlap -First $wanted -Second $_.DefaultForNewRepos } |
                ForEach-Object { "'$($_.Name)' ($($_.DefaultForNewRepos))" })
        $summary = "~ make code security configuration '$name' the default for new repositories: $(Format-SettingValue $Current.Default) -> $wanted"
        if ($replaced.Count -gt 0) {
            $summary += "; replaces $($replaced -join ', ')"
        }
        [pscustomobject]@{
            Action   = 'SetCodeSecurityDefault'
            Target   = $name
            Method   = 'PUT'
            Endpoint = "$path/defaults"
            Body     = [ordered]@{ default_for_new_repos = $wanted }
            Summary  = $summary
        }
    }

    $unattached = @($Current.Repositories | Where-Object { $null -eq $_.ConfigurationId } | ForEach-Object { $_.Name })
    if ($unattached.Count -gt 0) {
        [pscustomobject]@{
            Action   = 'AttachCodeSecurityConfiguration'
            Target   = $name
            Method   = 'POST'
            Endpoint = "$path/attach"
            Body     = [ordered]@{ scope = 'all_without_configurations' }
            Summary  = "+ attach code security configuration '$name' to the repositories without one: $($unattached -join ', ')"
        }
    }
}

function Get-CodeSecurityWarning {
    # Repositories on another configuration, an attach that failed or no longer in effect, and repositories whose
    # configuration could not be read.
    param(
        [Parameter(Mandatory)][object]$Config,
        [AllowNull()][object]$CodeSecurity
    )

    $name = [string]$Config.codeSecurity.name
    $page = "https://github.com/organizations/$($Config.organization)/settings/security_products"
    $ownId = $null
    if ($CodeSecurity.Configuration) {
        $ownId = $CodeSecurity.Configuration.Id
    }
    foreach ($repository in @($CodeSecurity.Repositories)) {
        if ($null -eq $repository.ConfigurationId) {
            continue
        }
        if ($repository.ConfigurationId -ne $ownId) {
            "Repository '$($repository.Name)' uses code security configuration '$($repository.ConfigurationName)', not '$name'. The engine leaves it alone; to switch it, open $page and apply '$name' to the repository."
        }
        elseif ($repository.Status -eq 'failed') {
            "Attaching code security configuration '$name' to repository '$($repository.Name)' failed. Open $page to see why, then re-run."
        }
        elseif ($repository.Status -cnotin $script:CodeSecurityStatusesInEffect) {
            $meaning = $script:CodeSecurityStatusMeanings[$repository.Status]
            if (-not $meaning) {
                $meaning = "GitHub reports the status $($repository.Status)"
            }
            # The configuration is still attached, so the attach of the plan (repositories without one) skips it.
            "Code security configuration '$name' is not in effect on repository '$($repository.Name)': $meaning ($($repository.Status)). The engine does not re-attach it; open $page and apply '$name' to the repository again."
        }
    }
    foreach ($repository in @($CodeSecurity.SkippedRepositories | Where-Object { $_ })) {
        "Repository '$repository' was listed, but its code security configuration could not be read: GitHub answered 404 (deleted, renamed or transferred during the run, or the gh account cannot see it). It is left out of this run; re-run to check it."
    }
}
