# Code security reads: the configuration the engine manages, the defaults and the configuration of each repository. Read-only.

function Read-CodeSecurityState {
    # The configuration named in the config (organization configurations only, the exact name), which
    # configurations are defaults for new repositories, and the configuration of every repository.
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Name,
        # From Read-OrgRepository.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OrgRepository
    )

    Write-StateProgress -Status 'code security configurations'
    $configurations = @(Read-OrgEndpoint -Endpoint "orgs/$Organization/code-security/configurations?per_page=100" -Paginate)
    $match = $configurations | Where-Object { $_.target_type -eq 'organization' -and [string]$_.name -ceq $Name } | Select-Object -First 1
    # Names are unique across the organization whatever their case, so creating the configuration would fail with a
    # less helpful message, and an update never renames one.
    $taken = $configurations | Where-Object { [string]$_.name -eq $Name } | Select-Object -First 1
    if (-not $match -and $taken) {
        switch ([string]$taken.target_type) {
            'organization' {
                throw "The code security configuration '$($taken.name)' of '$Organization' differs from codeSecurity.name '$Name' only in case; use the same spelling in the config, or rename the configuration at https://github.com/organizations/$Organization/settings/security_products."
            }
            'global' { throw "'$Name' is the name of a built-in GitHub code security configuration; choose another codeSecurity.name." }
            'enterprise' { throw "'$Name' is the name of an enterprise code security configuration; choose another codeSecurity.name." }
            default { throw "'$Name' is the name of a code security configuration of type '$($taken.target_type)'; choose another codeSecurity.name." }
        }
    }
    $configuration = $null
    if ($match) {
        $configuration = [pscustomobject]@{
            Id          = [long]$match.id
            Name        = [string]$match.name
            Description = [string]$match.description
            Enforcement = [string]$match.enforcement
            Settings    = ConvertTo-FieldMap -Response $match -Section 'codeSecurity.settings'
        }
    }

    Write-StateProgress -Status 'code security defaults'
    $default = $null
    $otherDefaults = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/code-security/configurations/defaults")) {
        if ($configuration -and [long]$entry.configuration.id -eq $configuration.Id) {
            $default = [string]$entry.default_for_new_repos
        }
        else {
            $otherDefaults.Add([pscustomobject]@{ Name = [string]$entry.configuration.name; DefaultForNewRepos = [string]$entry.default_for_new_repos })
        }
    }

    # Archived repositories are read-only, so attaching a configuration to them could never succeed and the attach
    # would be planned on every run.
    $names = [string[]]@($OrgRepository | Where-Object { -not $_.Archived } | ForEach-Object { $_.Name })
    # A handful of list reads instead of one read per repository. The list is documented for organization
    # configurations; it also answers for the built-in GitHub ones (checked 2026-10-04). A repository of an
    # enterprise configuration (not checked), and one a list shows as detached, is read on its own below.
    $listed = @{}
    foreach ($candidate in @($configurations | Where-Object { $_.target_type -in 'organization', 'global' })) {
        Write-StateProgress -Status "repositories of code security configuration '$($candidate.name)'"
        foreach ($item in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/code-security/configurations/$($candidate.id)/repositories?per_page=100" -Paginate)) {
            if ([string]$item.status -ne 'detached') {
                $listed[[string]$item.repository.name] = [pscustomobject]@{ status = $item.status; configuration = $candidate }
            }
        }
    }

    $repositories = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($repository in $names) {
        $attached = $listed[$repository]
        if (-not $attached) {
            Write-StateProgress -Status "code security configuration of repository '$repository'"
            $endpoint = "repos/$Organization/$repository/code-security-configuration"
            try {
                # 204 No Content (no configuration) reaches us as $null.
                $attached = Read-OrgEndpoint -Endpoint $endpoint
            }
            catch {
                # Deleted, renamed or transferred since the repository list was read; the warnings report it.
                if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                    throw
                }
                $skipped.Add($repository)
                continue
            }
        }
        $entry = [pscustomobject]@{ Name = $repository; ConfigurationId = $null; ConfigurationName = $null; Status = $null }
        if ($attached) {
            $entry.ConfigurationId = [long]$attached.configuration.id
            $entry.ConfigurationName = [string]$attached.configuration.name
            $entry.Status = [string]$attached.status
        }
        $repositories.Add($entry)
    }

    return [pscustomobject]@{
        Configuration       = $configuration
        Default             = $default
        OtherDefaults       = $otherDefaults.ToArray()
        Repositories        = $repositories.ToArray()
        SkippedRepositories = $skipped.ToArray()
    }
}
