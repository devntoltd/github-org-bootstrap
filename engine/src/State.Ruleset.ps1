# Ruleset reads: the organization ruleset the engine manages, the other rulesets, the teams of the required reviewers,
# and the repositories of the central workflows. Read-only.

# The predefined organization roles that give a team write access to every repository.
$script:RepositoryWriteRoles = @('all_repo_write', 'all_repo_maintain', 'all_repo_admin')

function Read-WorkflowReference {
    # File name -> text of the reference copy of each required workflow: the file of the same name in the directory of
    # the config, when there is one. A workflow without a reference copy is not compared.
    param(
        [Parameter(Mandatory)][object]$Config,
        [AllowNull()][AllowEmptyString()][string]$ConfigDirectory
    )

    # Case-sensitive like the paths GitHub compares.
    $references = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    if (-not $ConfigDirectory) {
        # The comma keeps PowerShell from unrolling the dictionary into its pairs.
        return , $references
    }
    foreach ($workflow in @($Config.ruleset.rules.workflows)) {
        $name = [System.IO.Path]::GetFileName([string]$workflow.path)
        $path = Join-Path -Path $ConfigDirectory -ChildPath $name
        if ($name -and -not $references.ContainsKey($name) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $references[$name] = Get-Content -LiteralPath $path -Raw
        }
    }
    # The comma keeps PowerShell from unrolling the dictionary into its pairs.
    return , $references
}

function Read-RulesetState {
    # The ruleset named in the config (organization rulesets only, the exact name) with its details, every other
    # ruleset, the teams and workflow sources the config names, what the plan checks them against, and the Copilot
    # plan ({PlanType, Seats}, $null without one or while Copilot code review is disabled).
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][object]$Config,
        # From Read-OrgRepository.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OrgRepository,
        # From Read-CopilotSeatState.
        [Parameter(Mandatory)][AllowNull()][object]$CopilotSeats,
        # Where the reference copies of the required workflows are: the file of the same name as each one.
        [AllowNull()][AllowEmptyString()][string]$ConfigDirectory
    )

    $name = [string]$Config.ruleset.name
    Write-StateProgress -Status 'rulesets'
    $rulesets = @(Read-OrgEndpoint -Endpoint "orgs/$Organization/rulesets?per_page=100" -Paginate)
    $organizationRulesets = @($rulesets | Where-Object { [string]$_.source_type -eq 'Organization' })
    $match = $organizationRulesets | Where-Object { [string]$_.name -ceq $name } | Select-Object -First 1
    # Creating a ruleset whose name differs only in case would fail with a less helpful message, and an update never
    # renames one.
    $taken = $organizationRulesets | Where-Object { [string]$_.name -eq $name } | Select-Object -First 1
    if (-not $match -and $taken) {
        throw "The ruleset '$($taken.name)' of '$Organization' differs from ruleset.name '$name' only in case; use the same spelling in the config, or rename the ruleset at https://github.com/organizations/$Organization/settings/rules."
    }
    $current = $null
    if ($match) {
        # The list has no rules.
        Write-StateProgress -Status "ruleset '$name'"
        $current = Read-OrgEndpoint -Endpoint "orgs/$Organization/rulesets/$($match.id)"
    }
    $others = @($organizationRulesets | Where-Object { -not $match -or [long]$_.id -ne [long]$match.id } | ForEach-Object {
            [pscustomobject]@{ Id = [long]$_.id; Name = [string]$_.name; Target = [string]$_.target; Enforcement = [string]$_.enforcement }
        })

    $teams = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($reviewer in @($Config.ruleset.rules.pullRequest.requiredReviewers)) {
        $slug = [string]$reviewer.team
        Write-StateProgress -Status "team '$slug'"
        try {
            # GitHub's slugs are lower case.
            $team = Read-OrgEndpoint -Endpoint "orgs/$Organization/teams/$($slug.ToLowerInvariant())"
            $teams[$slug] = [pscustomobject]@{ Id = [long]$team.id; Slug = [string]$team.slug; HasRepositoryWrite = $false }
        }
        catch {
            if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                throw
            }
            $teams[$slug] = $null
        }
    }
    $found = @($teams.Values | Where-Object { $null -ne $_ })
    if ($found.Count -gt 0) {
        # GitHub counts a team's approval only where the team has write access; a predefined role gives it on every
        # repository, new ones included.
        Write-StateProgress -Status 'organization roles'
        $roles = Read-OrgEndpoint -Endpoint "orgs/$Organization/organization-roles"
        $writers = [System.Collections.Generic.HashSet[long]]::new()
        foreach ($role in @($roles.roles | Where-Object { [string]$_.name -in $script:RepositoryWriteRoles })) {
            Write-StateProgress -Status 'organization roles'
            foreach ($team in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/organization-roles/$($role.id)/teams?per_page=100" -Paginate)) {
                $writers.Add([long]$team.id) | Out-Null
            }
        }
        foreach ($team in $found) {
            $team.HasRepositoryWrite = $writers.Contains($team.Id)
        }
    }

    $sources = @{}
    foreach ($workflow in @($Config.ruleset.rules.workflows)) {
        $repositoryName = [string]$workflow.repository
        $key = "$repositoryName/$($workflow.path)@$($workflow.sha)"
        Write-StateProgress -Status "workflow repository '$repositoryName'"
        try {
            $repository = Read-OrgEndpoint -Endpoint "repos/$Organization/$repositoryName"
        }
        catch {
            if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                throw
            }
            $sources[$key] = $null
            continue
        }
        # The access level applies to private and internal repositories; a public workflow runs everywhere.
        $accessLevel = $null
        if ([string]$repository.visibility -ne 'public') {
            Write-StateProgress -Status "workflow repository '$repositoryName'"
            $accessLevel = [string](Read-OrgEndpoint -Endpoint "repos/$Organization/$repositoryName/actions/permissions/access").access_level
        }
        Write-StateProgress -Status "workflow repository '$repositoryName'"
        $content = $null
        try {
            $file = Read-OrgEndpoint -Endpoint "repos/$Organization/$repositoryName/contents/$($workflow.path)?ref=$($workflow.sha)"
            # A single file comes as base64 in lines; a directory is a list, and a file over 1 MB has encoding 'none'.
            if ($file -isnot [array] -and [string]$file.type -eq 'file' -and [string]$file.encoding -eq 'base64') {
                $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(([string]$file.content -replace '\s', '')))
            }
        }
        catch {
            # The file is not there at that commit, or the commit does not exist.
            if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                throw
            }
        }
        $sources[$key] = [pscustomobject]@{
            RepositoryId = [long]$repository.id
            Visibility   = [string]$repository.visibility
            AccessLevel  = $accessLevel
            Content      = $content
        }
    }

    # Only for the warning while Copilot code review is enabled.
    $copilot = $null
    if ($Config.ruleset.rules.copilotCodeReview.enabled -eq $true -and $null -ne $CopilotSeats) {
        $copilot = [pscustomobject]@{ PlanType = $CopilotSeats.PlanType; Seats = $CopilotSeats.Total }
    }

    return [pscustomobject]@{
        Current                = $current
        OtherRulesets          = [object[]]$others
        Teams                  = $teams
        WorkflowSources        = $sources
        # Archived repositories run no workflows.
        RepositoryVisibilities = [string[]]@($OrgRepository | Where-Object { -not $_.Archived } | ForEach-Object { [string]$_.Visibility } | Sort-Object -Unique)
        References             = Read-WorkflowReference -Config $Config -ConfigDirectory $ConfigDirectory
        Copilot                = $copilot
    }
}
