# Organization ruleset actions and warnings: one ruleset on the default branch of every repository, created or replaced
# whole. Pure: no GitHub calls.

# Rules without parameters, sent when the config sets them to true; GitHub leaves out a rule it does not have.
$script:RulesetBooleanRules = @('deletion', 'non_fast_forward')
# Access levels of a private or internal repository that let other repositories of the organization run its workflows.
$script:WorkflowAccessLevels = @('organization', 'enterprise')
# Visibility of the repository of a workflow -> visibilities of the repositories it can run on
# (https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets).
$script:WorkflowRunsOn = @{
    public   = @('public', 'internal', 'private')
    internal = @('internal', 'private')
    private  = @('private')
}
# Bypass actors whose actor_id GitHub ignores: the actor type alone names them.
$script:BypassActorTypesWithoutId = @('OrganizationAdmin', 'DeployKey')

function Get-RulesetTeam {
    # The team of a slug in the ruleset state, the slug compared case-insensitively; $null for a team that does not
    # exist.
    param(
        [AllowNull()][System.Collections.IDictionary]$Teams,
        [Parameter(Mandatory)][string]$Slug
    )

    foreach ($key in @($Teams.Keys)) {
        if ($key -ieq $Slug) {
            return $Teams[$key]
        }
    }
    return $null
}

function Get-WorkflowSource {
    # The repository and file of a workflows entry in the ruleset state; $null for a repository that does not exist.
    param(
        [Parameter(Mandatory)][object]$Ruleset,
        [Parameter(Mandatory)][object]$Workflow
    )
    return $Ruleset.WorkflowSources["$($Workflow.repository)/$($Workflow.path)@$($Workflow.sha)"]
}

function Get-RulesetBody {
    # The request body of the whole ruleset (create and update alike), with the ids of the teams and repositories.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Ruleset
    )

    $section = $Config.ruleset
    $bypass = @()
    if ($section.bypass.organizationAdmin -eq 'pull_request') {
        $bypass = @([ordered]@{ actor_id = $null; actor_type = 'OrganizationAdmin'; bypass_mode = 'pull_request' })
    }

    $rules = [System.Collections.Generic.List[object]]::new()
    foreach ($type in $script:RulesetBooleanRules) {
        if ($section.rules.$type -eq $true) {
            $rules.Add([ordered]@{ type = $type })
        }
    }
    # dismissal_restriction is left to GitHub's default: only admins bypass, so restricting dismissal adds nothing.
    $parameters = [ordered]@{}
    $pullRequest = Get-ConfiguredValue -Config $Config -Section 'ruleset.rules.pullRequest'
    foreach ($field in @($pullRequest.Keys | Where-Object { $_ -ne 'requiredReviewers' })) {
        $value = $pullRequest[$field]
        if ($field -eq 'allowed_merge_methods') {
            $value = [string[]]@($value)
        }
        $parameters[$field] = $value
    }
    $parameters.required_reviewers = [object[]]@(foreach ($reviewer in @($section.rules.pullRequest.requiredReviewers)) {
            [ordered]@{
                minimum_approvals = $reviewer.minimum_approvals
                file_patterns     = [string[]]@($reviewer.file_patterns)
                reviewer          = [ordered]@{ id = (Get-RulesetTeam -Teams $Ruleset.Teams -Slug ([string]$reviewer.team)).Id; type = 'Team' }
            }
        })
    $rules.Add([ordered]@{ type = 'pull_request'; parameters = $parameters })
    if ($section.rules.copilotCodeReview.enabled -eq $true) {
        $copilot = Get-ConfiguredValue -Config $Config -Section 'ruleset.rules.copilotCodeReview'
        $copilot.Remove('enabled')
        $rules.Add([ordered]@{ type = 'copilot_code_review'; parameters = $copilot })
    }
    $workflows = [object[]]@(foreach ($workflow in @($section.rules.workflows)) {
            [ordered]@{ repository_id = (Get-WorkflowSource -Ruleset $Ruleset -Workflow $workflow).RepositoryId; path = [string]$workflow.path; sha = [string]$workflow.sha }
        })
    # A repository created after the ruleset has no commit the workflow could check yet.
    $rules.Add([ordered]@{ type = 'workflows'; parameters = [ordered]@{ do_not_enforce_on_create = $true; workflows = $workflows } })

    return [ordered]@{
        name          = [string]$section.name
        target        = 'branch'
        enforcement   = [string]$section.enforcement
        bypass_actors = [object[]]$bypass
        conditions    = [ordered]@{
            repository_name = [ordered]@{ include = [string[]]@('~ALL'); exclude = [string[]]@(); protected = $false }
            ref_name        = [ordered]@{ include = [string[]]@('~DEFAULT_BRANCH'); exclude = [string[]]@() }
        }
        rules         = $rules.ToArray()
    }
}

function Format-RulesetList {
    param([AllowNull()][object]$Value)
    return "[$(@($Value | Where-Object { $null -ne $_ }) -join ', ')]"
}

function Test-OrdinalSetEqual {
    # Whether two lists hold the same strings, in any order, compared case-sensitively.
    param([AllowNull()][object]$First, [AllowNull()][object]$Second)

    $set = [System.Collections.Generic.HashSet[string]]::new([string[]]@($First | Where-Object { $null -ne $_ }), [StringComparer]::Ordinal)
    return $set.SetEquals([string[]]@($Second | Where-Object { $null -ne $_ }))
}

function Format-BypassActor {
    param([Parameter(Mandatory)][object]$Actor)

    $name = [string]$Actor.actor_type
    if ($name -notin $script:BypassActorTypesWithoutId) {
        $name += " $($Actor.actor_id)"
    }
    return "$name ($($Actor.bypass_mode))"
}

function Format-RequiredReviewer {
    param([Parameter(Mandatory)][object]$Reviewer)
    return "minimum_approvals $($Reviewer.minimum_approvals), file_patterns $(Format-RulesetList $Reviewer.file_patterns)"
}

function Compare-RequiredReviewer {
    # The differences of required_reviewers, keyed by the team id.
    param([AllowNull()][object]$Desired, [AllowNull()][object]$Current)

    $path = 'rules.pull_request.required_reviewers'
    $currentById = @{}
    foreach ($reviewer in @($Current | Where-Object { $null -ne $_ })) {
        $currentById[[string]$reviewer.reviewer.id] = $reviewer
    }
    $desiredIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($reviewer in @($Desired)) {
        $id = [string]$reviewer.reviewer.id
        $desiredIds.Add($id) | Out-Null
        $have = $currentById[$id]
        if ($null -eq $have) {
            "$path[$id]: <none> -> $(Format-RequiredReviewer $reviewer)"
            continue
        }
        if ($have.minimum_approvals -ne $reviewer.minimum_approvals) {
            "$path[$id].minimum_approvals: $(Format-SettingValue $have.minimum_approvals) -> $($reviewer.minimum_approvals)"
        }
        if (-not (Test-OrdinalSetEqual -First $have.file_patterns -Second $reviewer.file_patterns)) {
            "$path[$id].file_patterns: $(Format-RulesetList $have.file_patterns) -> $(Format-RulesetList $reviewer.file_patterns)"
        }
    }
    foreach ($id in @($currentById.Keys | Where-Object { -not $desiredIds.Contains($_) } | Sort-Object)) {
        "$path[$id]: $(Format-RequiredReviewer $currentById[$id]) -> <none>"
    }
}

function Format-WorkflowKey {
    # "<repository>:<path>" of a "<repository id>:<path>" key, the repository by name, or by id for a repository the
    # config does not name.
    param(
        [Parameter(Mandatory)][string]$Key,
        # Repository id (as a string) -> name.
        [Parameter(Mandatory)][hashtable]$RepositoryName
    )

    $id, $path = $Key.Split(':', 2)
    $name = $RepositoryName[$id] ?? $id
    return "${name}:$path"
}

function Compare-RulesetWorkflow {
    # The differences of the workflows rule, its workflows keyed by repository id and path, and shown by repository
    # name (Format-WorkflowKey).
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Desired,
        [AllowNull()][object]$Current,
        # Repository id (as a string) -> name.
        [Parameter(Mandatory)][hashtable]$RepositoryName
    )

    $currentFlag = $Current.do_not_enforce_on_create -eq $true
    if ($currentFlag -ne $Desired.do_not_enforce_on_create) {
        "rules.workflows.do_not_enforce_on_create: $(Format-SettingValue $currentFlag) -> $(Format-SettingValue $Desired.do_not_enforce_on_create)"
    }
    $currentByKey = @{}
    foreach ($workflow in @($Current.workflows | Where-Object { $null -ne $_ })) {
        $currentByKey["$($workflow.repository_id):$($workflow.path)"] = $workflow
    }
    $desiredKeys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($workflow in @($Desired.workflows)) {
        $key = "$($workflow.repository_id):$($workflow.path)"
        $desiredKeys.Add($key) | Out-Null
        $have = $currentByKey[$key]
        if ($null -eq $have) {
            "rules.workflows[$(Format-WorkflowKey -Key $key -RepositoryName $RepositoryName)]: <none> -> sha $($workflow.sha)"
        }
        elseif ([string]$have.sha -cne $workflow.sha) {
            "rules.workflows[$(Format-WorkflowKey -Key $key -RepositoryName $RepositoryName)].sha: $(Format-SettingValue $have.sha) -> $($workflow.sha)"
        }
    }
    foreach ($key in @($currentByKey.Keys | Where-Object { -not $desiredKeys.Contains($_) } | Sort-Object)) {
        "rules.workflows[$(Format-WorkflowKey -Key $key -RepositoryName $RepositoryName)]: sha $($currentByKey[$key].sha) -> <none>"
    }
}

function Compare-RulesetBody {
    # "<path>: <current> -> <desired>" for every field of the body that differs from the ruleset GitHub has; fields
    # GitHub adds (ids, links, dates, the ref of a workflow) are not compared.
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Desired,
        [AllowNull()][object]$Current,
        # Repository id (as a string) -> name, for the workflows.
        [Parameter(Mandatory)][hashtable]$RepositoryName
    )

    $differences = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @('name', 'target', 'enforcement')) {
        if ($Current.$field -cne $Desired[$field]) {
            $differences.Add("${field}: $(Format-SettingValue $Current.$field) -> $($Desired[$field])")
        }
    }

    $currentActors = @($Current.bypass_actors | Where-Object { $null -ne $_ } | ForEach-Object { Format-BypassActor -Actor $_ })
    $desiredActors = @($Desired.bypass_actors | ForEach-Object { Format-BypassActor -Actor $_ })
    if (-not (Test-OrdinalSetEqual -First $currentActors -Second $desiredActors)) {
        $format = { param($actors) if ($actors.Count -eq 0) { '<none>' } else { $actors -join ', ' } }
        $differences.Add("bypass_actors: $(& $format $currentActors) -> $(& $format $desiredActors)")
    }

    foreach ($condition in $Desired.conditions.Keys) {
        foreach ($field in $Desired.conditions[$condition].Keys) {
            $path = "conditions.$condition.$field"
            $want = $Desired.conditions[$condition][$field]
            $have = $Current.conditions.$condition.$field
            if ($want -is [bool]) {
                # GitHub's default for a missing flag is false.
                $have = $have -eq $true
                if ($have -ne $want) {
                    $differences.Add("${path}: $(Format-SettingValue $have) -> $(Format-SettingValue $want)")
                }
            }
            elseif (-not (Test-OrdinalSetEqual -First $have -Second $want)) {
                $differences.Add("${path}: $(Format-RulesetList $have) -> $(Format-RulesetList $want)")
            }
        }
    }

    $currentRules = @{}
    foreach ($rule in @($Current.rules | Where-Object { $null -ne $_ })) {
        $currentRules[[string]$rule.type] = $rule
    }
    $desiredRules = @{}
    foreach ($rule in $Desired.rules) {
        $desiredRules[$rule.type] = $rule
    }
    foreach ($type in $script:RulesetBooleanRules) {
        $have = $currentRules.ContainsKey($type)
        $want = $desiredRules.ContainsKey($type)
        if ($have -ne $want) {
            $differences.Add("rules.${type}: $(Format-SettingValue $have) -> $(Format-SettingValue $want)")
        }
    }
    foreach ($type in @($desiredRules.Keys | Where-Object { $_ -notin $script:RulesetBooleanRules } | Sort-Object)) {
        if (-not $currentRules.ContainsKey($type)) {
            $differences.Add("rules.${type}: <none> -> present")
        }
    }
    foreach ($type in @($currentRules.Keys | Where-Object { $_ -notin $script:RulesetBooleanRules -and -not $desiredRules.ContainsKey($_) } | Sort-Object)) {
        $differences.Add("rules.${type}: present -> <none>")
    }

    if ($desiredRules.pull_request -and $currentRules.ContainsKey('pull_request')) {
        $want = $desiredRules.pull_request.parameters
        $have = $currentRules.pull_request.parameters
        foreach ($field in @($want.Keys | Where-Object { $_ -ne 'required_reviewers' })) {
            $path = "rules.pull_request.$field"
            $haveValue = $have.$field
            if ($field -eq 'allowed_merge_methods') {
                if (-not (Test-OrdinalSetEqual -First $haveValue -Second $want[$field])) {
                    $differences.Add("${path}: $(Format-RulesetList $haveValue) -> $(Format-RulesetList $want[$field])")
                }
                continue
            }
            if ($want[$field] -is [bool]) {
                $haveValue = $haveValue -eq $true
            }
            if ($null -eq $haveValue -or $haveValue -cne $want[$field]) {
                $differences.Add("${path}: $(Format-SettingValue $haveValue) -> $(Format-SettingValue $want[$field])")
            }
        }
        foreach ($difference in @(Compare-RequiredReviewer -Desired $want.required_reviewers -Current $have.required_reviewers)) {
            $differences.Add($difference)
        }
    }
    if ($desiredRules.copilot_code_review -and $currentRules.ContainsKey('copilot_code_review')) {
        $want = $desiredRules.copilot_code_review.parameters
        $have = $currentRules.copilot_code_review.parameters
        foreach ($field in $want.Keys) {
            # GitHub's default for a missing flag is false.
            $haveValue = $have.$field -eq $true
            if ($haveValue -ne $want[$field]) {
                $differences.Add("rules.copilot_code_review.${field}: $(Format-SettingValue $haveValue) -> $(Format-SettingValue $want[$field])")
            }
        }
    }
    if ($desiredRules.workflows -and $currentRules.ContainsKey('workflows')) {
        foreach ($difference in @(Compare-RulesetWorkflow -Desired $desiredRules.workflows.parameters -Current $currentRules.workflows.parameters -RepositoryName $RepositoryName)) {
            $differences.Add($difference)
        }
    }
    return [string[]]$differences.ToArray()
}

function Get-UnmodeledRulesetField {
    # "<path> = <JSON value>" for every condition, condition field and rule parameter of the ruleset GitHub has that
    # the body does not carry; only rules the body keeps, since a rule it leaves out is planned away whole.
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Desired,
        [Parameter(Mandatory)][object]$Current
    )

    $format = { param($path, $value) "$path = $(ConvertTo-Json -InputObject $value -Compress -Depth 10)" }
    foreach ($condition in @($Current.conditions.PSObject.Properties)) {
        if (-not $Desired.conditions.Contains($condition.Name)) {
            & $format "conditions.$($condition.Name)" $condition.Value
            continue
        }
        foreach ($field in @($condition.Value.PSObject.Properties | Where-Object { -not $Desired.conditions[$condition.Name].Contains($_.Name) })) {
            & $format "conditions.$($condition.Name).$($field.Name)" $field.Value
        }
    }
    $desiredRules = @{}
    foreach ($rule in $Desired.rules) {
        $desiredRules[$rule.type] = $rule
    }
    foreach ($rule in @($Current.rules | Where-Object { $null -ne $_.parameters -and $desiredRules.ContainsKey([string]$_.type) })) {
        $known = $desiredRules[[string]$rule.type].parameters
        foreach ($parameter in @($rule.parameters.PSObject.Properties | Where-Object { $null -eq $known -or -not $known.Contains($_.Name) })) {
            & $format "rules.$($rule.type).$($parameter.Name)" $parameter.Value
        }
    }
}

function Assert-RulesetPrecondition {
    # Throws when a central workflow cannot run, since the ruleset would then block every pull request.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Ruleset
    )

    $organization = [string]$Config.organization
    foreach ($workflow in @($Config.ruleset.rules.workflows)) {
        $repository = [string]$workflow.repository
        $source = Get-WorkflowSource -Ruleset $Ruleset -Workflow $workflow
        if ($null -eq $source) {
            throw "The organization ruleset requires the workflow $($workflow.path) of repository '$repository', but $organization has no such repository. Create it with the workflow, or the ruleset would block every pull request."
        }
        if ($null -eq $source.Content) {
            throw "Repository '$repository' has no $($workflow.path) at commit $($workflow.sha). Put the commit that holds the file in ruleset.rules.workflows, or the ruleset would block every pull request."
        }
        # A public workflow runs everywhere; the state reads no access level for it.
        if ($source.Visibility -ne 'public' -and $source.AccessLevel -notin $script:WorkflowAccessLevels) {
            throw "Repository '$repository' does not share its workflows with the organization (access level '$($source.AccessLevel)'). Open https://github.com/$organization/$repository/settings/actions, under `"Access`" select `"Accessible from repositories in the '$organization' organization`", and save; the ruleset would block every pull request otherwise."
        }
        $runsOn = @($script:WorkflowRunsOn[[string]$source.Visibility])
        $blocked = @($Ruleset.RepositoryVisibilities | Where-Object { $_ -notin $runsOn })
        if ($blocked.Count -gt 0) {
            $needed = if ('public' -in $blocked) { 'public' } else { 'internal' }
            throw "The workflow of repository '$repository' is $($source.Visibility) and cannot run in the $($blocked -join ' and ') repositories of $organization, whose pull requests the ruleset would block. Make '$repository' $needed, or the repositories private."
        }
    }
}

function Get-RulesetAction {
    # Create the ruleset, or replace it whole when a field differs; nothing while a reviewer team does not exist (a
    # warning names it). Throws when a central workflow cannot run.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Ruleset
    )

    Assert-RulesetPrecondition -Config $Config -Ruleset $Ruleset
    foreach ($reviewer in @($Config.ruleset.rules.pullRequest.requiredReviewers)) {
        if ($null -eq (Get-RulesetTeam -Teams $Ruleset.Teams -Slug ([string]$reviewer.team))) {
            return
        }
    }

    $name = [string]$Config.ruleset.name
    $base = "orgs/$($Config.organization)/rulesets"
    $body = Get-RulesetBody -Config $Config -Ruleset $Ruleset
    if ($null -eq $Ruleset.Current) {
        $actors = @($body.bypass_actors | ForEach-Object { Format-BypassActor -Actor $_ })
        $bypass = if ($actors.Count -eq 0) { '<none>' } else { $actors -join ', ' }
        [pscustomobject]@{
            Action   = 'CreateRuleset'
            Target   = $name
            Method   = 'POST'
            Endpoint = $base
            Body     = $body
            Summary  = "+ create ruleset '$name' ($($body.enforcement)) on the default branch of every repository: $(@($body.rules | ForEach-Object { $_.type }) -join ', '); bypass: $bypass"
        }
        return
    }
    $repositoryName = @{}
    foreach ($workflow in @($Config.ruleset.rules.workflows)) {
        $repositoryName[[string](Get-WorkflowSource -Ruleset $Ruleset -Workflow $workflow).RepositoryId] = [string]$workflow.repository
    }
    $differences = @(Compare-RulesetBody -Desired $body -Current $Ruleset.Current -RepositoryName $repositoryName)
    if ($differences.Count -gt 0) {
        [pscustomobject]@{
            Action   = 'UpdateRuleset'
            Target   = $name
            Method   = 'PUT'
            Endpoint = "$base/$($Ruleset.Current.id)"
            Body     = $body
            Summary  = "~ update ruleset '$name': $($differences -join '; ')"
        }
    }
}

function ConvertTo-ComparableContent {
    # File text without the differences git and editors make: line endings and the final newlines.
    param([AllowNull()][string]$Content)
    return ($Content -replace "`r`n", "`n").TrimEnd("`n")
}

function Get-RulesetWarning {
    # Reviewer teams that are missing or whose approvals do not count, Copilot code review without a Copilot plan or
    # seat, other organization rulesets, and a central workflow that differs from the reference copy.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Ruleset
    )

    $organization = [string]$Config.organization
    foreach ($reviewer in @($Config.ruleset.rules.pullRequest.requiredReviewers)) {
        $slug = [string]$reviewer.team
        $team = Get-RulesetTeam -Teams $Ruleset.Teams -Slug $slug
        if ($null -eq $team) {
            "Team '$slug' of ruleset.rules.pullRequest.requiredReviewers does not exist in $organization, so the ruleset cannot name it; the engine leaves the ruleset unchanged. Create the team (engine/README.md, Manual setup), or remove it from the config."
        }
        elseif (-not $team.HasRepositoryWrite) {
            "Team '$slug' has no write access to every repository of $organization, so its approvals do not count and pull requests that change its file patterns wait for an organization admin. Assign it the organization role `"All-repository write`" at https://github.com/organizations/$organization/settings/org_role_assignments."
        }
    }
    # The rule only asks for a review, so without Copilot pull requests merge as before: a warning, not an error.
    if ($Config.ruleset.rules.copilotCodeReview.enabled -eq $true) {
        $asks = 'ruleset.rules.copilotCodeReview asks Copilot to review every pull request, but'
        if ($null -eq $Ruleset.Copilot) {
            "$asks $organization has no Copilot Business or Enterprise plan, so no pull request gets a review. Buy Copilot Business (engine/README.md, Copilot code review), or set ruleset.rules.copilotCodeReview.enabled to false."
        }
        elseif ($Ruleset.Copilot.Seats -lt 1) {
            "$asks no member of $organization has a Copilot seat, so only authors with a license of their own get a review. Assign seats at https://github.com/organizations/$organization/settings/copilot/seat_management."
        }
    }
    # A warning, not a change: a parameter GitHub adds with a default would otherwise plan an update on every run.
    if ($null -ne $Ruleset.Current) {
        $body = Get-RulesetBody -Config $Config -Ruleset $Ruleset
        foreach ($field in @(Get-UnmodeledRulesetField -Desired $body -Current $Ruleset.Current)) {
            "Ruleset '$($Ruleset.Current.name)' has $field, which the engine does not model: it neither compares nor sets the field, and the field can narrow which repositories the ruleset applies to or loosen a rule. Review it at https://github.com/organizations/$organization/settings/rules/$($Ruleset.Current.id); remove it there unless it is wanted, or add the field to the engine."
        }
    }
    foreach ($other in @($Ruleset.OtherRulesets | Where-Object { $null -ne $_ })) {
        "Ruleset '$($other.Name)' ($($other.Target), $($other.Enforcement)) is not in the config; the engine leaves it alone. Review it at https://github.com/organizations/$organization/settings/rules/$($other.Id)."
    }
    foreach ($workflow in @($Config.ruleset.rules.workflows)) {
        # Only a workflow with a reference copy beside the config is compared.
        $name = [System.IO.Path]::GetFileName([string]$workflow.path)
        if (-not $Ruleset.References -or -not $Ruleset.References.ContainsKey($name)) {
            continue
        }
        $reference = ConvertTo-ComparableContent -Content $Ruleset.References[$name]
        $source = Get-WorkflowSource -Ruleset $Ruleset -Workflow $workflow
        if ($null -eq $source -or $null -eq $source.Content) {
            continue
        }
        if ((ConvertTo-ComparableContent -Content $source.Content) -cne $reference) {
            "The workflow $($workflow.path) of repository '$($workflow.repository)' at commit $(([string]$workflow.sha).Substring(0, 7)) differs from $name beside the config. Copy that file into '$($workflow.repository)' by a pull request, then put its merge commit in ruleset.rules.workflows."
        }
    }
}
