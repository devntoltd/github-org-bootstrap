BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    $script:sha = '0123456789abcdef0123456789abcdef01234567'
    $script:sourceKey = ".github/.github/workflows/org-checks.yml@$script:sha"

    function Get-TestRulesetPlan {
        # The plan of an organization that matches the config but for the ruleset.
        param([object]$Config = (Get-TestGitHubOrgConfig), [Parameter(Mandatory)][object]$Ruleset)
        $state = Get-MatchingTestGitHubOrgState
        $state.Ruleset = $Ruleset
        @(Get-GitHubOrgPlan -Config $Config -CurrentState $state)
    }

    function Get-TestRulesetWarning {
        param([object]$Config = (Get-TestGitHubOrgConfig), [Parameter(Mandatory)][object]$Ruleset)
        $state = Get-MatchingTestGitHubOrgState
        $state.Ruleset = $Ruleset
        @(Get-GitHubOrgWarning -Config $Config -CurrentState $state -Plan @())
    }

    function Get-TestRule {
        # The rule of a type in ruleset details.
        param([Parameter(Mandatory)][object]$Detail, [Parameter(Mandatory)][string]$Type)
        @($Detail.rules | Where-Object { $_.type -eq $Type })[0]
    }
}

Describe 'Get-GitHubOrgPlan: ruleset' {
    It 'creates the ruleset when none has its name' {
        $plan = Get-TestRulesetPlan -Ruleset (Get-EmptyTestRulesetState)

        $plan.Count | Should -Be 1
        $action = Get-PlanAction -Plan $plan -Action 'CreateRuleset' -Target 'default-branch'
        $action.Method | Should -Be 'POST'
        $action.Endpoint | Should -Be 'orgs/contoso/rulesets'
        $action.Summary | Should -Be "+ create ruleset 'default-branch' (active) on the default branch of every repository: deletion, non_fast_forward, pull_request, copilot_code_review, workflows; bypass: OrganizationAdmin (pull_request)"
        $body = $action.Body
        (@($body.Keys) -join ',') | Should -Be 'name,target,enforcement,bypass_actors,conditions,rules'
        $body.name | Should -Be 'default-branch'
        $body.target | Should -Be 'branch'
        $body.enforcement | Should -Be 'active'
        ($body.conditions | ConvertTo-Json -Depth 5 -Compress) | Should -Be '{"repository_name":{"include":["~ALL"],"exclude":[],"protected":false},"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}}'
        ($body.bypass_actors | ConvertTo-Json -Depth 5 -Compress -AsArray) | Should -Be '[{"actor_id":null,"actor_type":"OrganizationAdmin","bypass_mode":"pull_request"}]'
        ($body.rules.type -join ',') | Should -Be 'deletion,non_fast_forward,pull_request,copilot_code_review,workflows'
        $pullRequest = $body.rules[2].parameters
        $pullRequest.required_approving_review_count | Should -Be 1
        $pullRequest.dismiss_stale_reviews_on_push | Should -BeTrue
        $pullRequest.require_last_push_approval | Should -BeTrue
        $pullRequest.require_code_owner_review | Should -BeTrue
        $pullRequest.required_review_thread_resolution | Should -BeTrue
        $pullRequest.require_extra_approval_for_unattributed_changes | Should -BeTrue
        $pullRequest.allowed_merge_methods | Should -Be @('merge')
        $pullRequest.Contains('dismissal_restriction') | Should -BeFalse
        ($pullRequest.required_reviewers | ConvertTo-Json -Depth 5 -Compress -AsArray) | Should -Be '[{"minimum_approvals":1,"file_patterns":[".github/workflows/**",".github/actions/**","**/CODEOWNERS",".github/dependabot.yml"],"reviewer":{"id":11,"type":"Team"}}]'
        ($body.rules[3].parameters | ConvertTo-Json -Depth 5 -Compress) | Should -Be '{"review_on_push":true,"review_draft_pull_requests":false}'
        ($body.rules[4].parameters | ConvertTo-Json -Depth 5 -Compress) | Should -Be "{`"do_not_enforce_on_create`":true,`"workflows`":[{`"repository_id`":21,`"path`":`".github/workflows/org-checks.yml`",`"sha`":`"$script:sha`"}]}"
    }

    It 'sends no bypass actor and no false boolean rule' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.bypass.organizationAdmin = 'none'
        $config.ruleset.rules.deletion = $false

        $action = Get-PlanAction -Plan (Get-TestRulesetPlan -Config $config -Ruleset (Get-EmptyTestRulesetState)) -Action 'CreateRuleset'

        (ConvertTo-Json -InputObject $action.Body.bypass_actors -Compress) | Should -Be '[]'
        ($action.Body.rules.type -join ',') | Should -Be 'non_fast_forward,pull_request,copilot_code_review,workflows'
        $action.Summary | Should -BeLike '*: non_fast_forward, pull_request, copilot_code_review, workflows; bypass: <none>'
    }

    It 'sends no Copilot code review rule while it is disabled' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.copilotCodeReview.enabled = $false

        $action = Get-PlanAction -Plan (Get-TestRulesetPlan -Config $config -Ruleset (Get-EmptyTestRulesetState)) -Action 'CreateRuleset'

        ($action.Body.rules.type -join ',') | Should -Be 'deletion,non_fast_forward,pull_request,workflows'
    }

    It 'removes the Copilot code review rule once it is disabled' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.copilotCodeReview.enabled = $false

        $action = Get-PlanAction -Plan (Get-TestRulesetPlan -Config $config -Ruleset (Get-MatchingTestRulesetState)) -Action 'UpdateRuleset'

        $action.Body.rules.type | Should -Not -Contain 'copilot_code_review'
        $action.Summary | Should -BeLike '*rules.copilot_code_review: present -> <none>*'
    }

    It 'plans nothing when the ruleset matches' {
        Get-TestRulesetPlan -Ruleset (Get-MatchingTestRulesetState) | Should -BeNullOrEmpty
    }

    It 'plans nothing for rules in another order, a false rule or parameter GitHub leaves out and a team slug in another case' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.deletion = $false
        $config.ruleset.rules.pullRequest.requiredReviewers[0].team = 'Platform-Admins'
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.rules = @($ruleset.Current.rules | Where-Object { $_.type -ne 'deletion' } | Sort-Object -Property type -Descending)
        (Get-TestRule -Detail $ruleset.Current -Type 'pull_request').parameters.allowed_merge_methods = @('merge')
        (Get-TestRule -Detail $ruleset.Current -Type 'copilot_code_review').parameters.PSObject.Properties.Remove('review_draft_pull_requests')
        (Get-TestRule -Detail $ruleset.Current -Type 'workflows').parameters.workflows[0] | Add-Member -NotePropertyName ref -NotePropertyValue 'refs/heads/main'

        Get-TestRulesetPlan -Config $config -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'compares the condition lists as sets' {
        # The desired lists hold one item each, so a repeated item is what tells a set from an ordered list.
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.conditions.repository_name.include = @('~ALL', '~ALL')
        $ruleset.Current.conditions.ref_name.include = @('~DEFAULT_BRANCH', '~DEFAULT_BRANCH')

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'plans nothing for an organization admin bypass that GitHub answers with an actor id' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.bypass_actors[0].actor_id = 1

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'restores the whole ruleset when <Case>' -ForEach @(
        @{ Case = 'it is disabled in GitHub'; Change = { param($d) $d.enforcement = 'disabled' }; Expected = 'enforcement: disabled -> active' }
        @{
            Case = 'a bypass actor was added'; Change = { param($d) $d.bypass_actors = @($d.bypass_actors) + [pscustomobject]@{ actor_id = 5; actor_type = 'Team'; bypass_mode = 'always' } }
            Expected = 'bypass_actors: OrganizationAdmin (pull_request), Team 5 (always) -> OrganizationAdmin (pull_request)'
        }
        @{ Case = 'the bypass mode changed'; Change = { param($d) $d.bypass_actors[0].bypass_mode = 'always' }; Expected = 'bypass_actors: OrganizationAdmin (always) -> OrganizationAdmin (pull_request)' }
        @{
            Case = 'no approval is required'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'pull_request')[0]).parameters.required_approving_review_count = 0 }
            Expected = 'rules.pull_request.required_approving_review_count: 0 -> 1'
        }
        @{
            Case = 'a merge method was added'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'pull_request')[0]).parameters.allowed_merge_methods = @('merge', 'squash') }
            Expected = 'rules.pull_request.allowed_merge_methods: [merge, squash] -> [merge]'
        }
        @{
            Case = 'a file pattern is missing'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'pull_request')[0]).parameters.required_reviewers[0].file_patterns = @('.github/workflows/**') }
            Expected = 'rules.pull_request.required_reviewers[11].file_patterns: [.github/workflows/**] -> [.github/workflows/**, .github/actions/**, **/CODEOWNERS, .github/dependabot.yml]'
        }
        @{
            Case = 'the team approvals changed'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'pull_request')[0]).parameters.required_reviewers[0].minimum_approvals = 2 }
            Expected = 'rules.pull_request.required_reviewers[11].minimum_approvals: 2 -> 1'
        }
        @{
            Case = 'another team reviews'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'pull_request')[0]).parameters.required_reviewers[0].reviewer.id = 12 }
            Expected = 'rules.pull_request.required_reviewers[12]: minimum_approvals 1, file_patterns [.github/workflows/**, .github/actions/**, **/CODEOWNERS, .github/dependabot.yml] -> <none>'
        }
        @{
            Case = 'the workflow runs at another commit'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'workflows')[0]).parameters.workflows[0].sha = 'fedcba9876543210fedcba9876543210fedcba98' }
            Expected = 'rules.workflows[.github:.github/workflows/org-checks.yml].sha: fedcba9876543210fedcba9876543210fedcba98 -> 0123456789abcdef0123456789abcdef01234567'
        }
        @{
            Case     = 'a workflow of a repository outside the config was added'
            Change   = { param($d) $p = (@($d.rules | Where-Object type -EQ 'workflows')[0]).parameters; $p.workflows = @($p.workflows) + [pscustomobject]@{ repository_id = 99; path = '.github/workflows/x.yml'; sha = 'fedcba9876543210fedcba9876543210fedcba98' } }
            Expected = 'rules.workflows[99:.github/workflows/x.yml]: sha fedcba9876543210fedcba9876543210fedcba98 -> <none>'
        }
        @{
            Case = 'the workflows are enforced on create'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'workflows')[0]).parameters.PSObject.Properties.Remove('do_not_enforce_on_create') }
            Expected = 'rules.workflows.do_not_enforce_on_create: false -> true'
        }
        @{ Case = 'a rule was removed'; Change = { param($d) $d.rules = @($d.rules | Where-Object type -NE 'non_fast_forward') }; Expected = 'rules.non_fast_forward: false -> true' }
        @{ Case = 'a rule was added'; Change = { param($d) $d.rules = @($d.rules) + [pscustomobject]@{ type = 'required_signatures' } }; Expected = 'rules.required_signatures: present -> <none>' }
        @{ Case = 'the pull request rule was removed'; Change = { param($d) $d.rules = @($d.rules | Where-Object type -NE 'pull_request') }; Expected = 'rules.pull_request: <none> -> present' }
        @{ Case = 'the Copilot code review rule was removed'; Change = { param($d) $d.rules = @($d.rules | Where-Object type -NE 'copilot_code_review') }; Expected = 'rules.copilot_code_review: <none> -> present' }
        @{
            Case = 'Copilot reviews only once'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'copilot_code_review')[0]).parameters.review_on_push = $false }
            Expected = 'rules.copilot_code_review.review_on_push: false -> true'
        }
        @{
            Case = 'Copilot reviews drafts'; Change = { param($d) (@($d.rules | Where-Object type -EQ 'copilot_code_review')[0]).parameters.review_draft_pull_requests = $true }
            Expected = 'rules.copilot_code_review.review_draft_pull_requests: true -> false'
        }
        @{ Case = 'the repositories changed'; Change = { param($d) $d.conditions.repository_name.include = @('repo-a') }; Expected = 'conditions.repository_name.include: [repo-a] -> [~ALL]' }
        @{ Case = 'protected repositories are left out'; Change = { param($d) $d.conditions.repository_name.protected = $true }; Expected = 'conditions.repository_name.protected: true -> false' }
        @{ Case = 'the target changed'; Change = { param($d) $d.target = 'tag' }; Expected = 'target: tag -> branch' }
    ) {
        $create = Get-PlanAction -Plan (Get-TestRulesetPlan -Ruleset (Get-EmptyTestRulesetState)) -Action 'CreateRuleset'
        $ruleset = Get-MatchingTestRulesetState
        & $Change $ruleset.Current

        $plan = Get-TestRulesetPlan -Ruleset $ruleset

        $plan.Count | Should -Be 1
        $action = Get-PlanAction -Plan $plan -Action 'UpdateRuleset' -Target 'default-branch'
        $action.Method | Should -Be 'PUT'
        $action.Endpoint | Should -Be 'orgs/contoso/rulesets/7'
        ($action.Body | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($create.Body | ConvertTo-Json -Depth 10 -Compress)
        $action.Summary | Should -BeLike "*$([WildcardPattern]::Escape($Expected))*"
    }

    It 'names every differing field in the update summary' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.enforcement = 'disabled'
        (Get-TestRule -Detail $ruleset.Current -Type 'pull_request').parameters.required_approving_review_count = 0

        (Get-TestRulesetPlan -Ruleset $ruleset)[0].Summary |
            Should -Be "~ update ruleset 'default-branch': enforcement: disabled -> active; rules.pull_request.required_approving_review_count: 0 -> 1"
    }

    It 'plans the ruleset after the code security actions' {
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-DefaultTestGitHubOrgState))

        (Get-PlanIndex -Plan $plan -Action 'CreateRuleset' -Target 'default-branch') |
            Should -BeGreaterThan (Get-PlanIndex -Plan $plan -Action 'AttachCodeSecurityConfiguration' -Target 'baseline')
    }
}

Describe 'Get-GitHubOrgPlan: ruleset preconditions' {
    It 'fails when the repository of a workflow does not exist' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey] = $null

        { Get-TestRulesetPlan -Ruleset $ruleset } |
            Should -Throw -ExpectedMessage "The organization ruleset requires the workflow .github/workflows/org-checks.yml of repository '.github', but contoso has no such repository. Create it with the workflow, or the ruleset would block every pull request."
    }

    It 'fails when the workflow file is not at the configured commit' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].Content = $null

        { Get-TestRulesetPlan -Ruleset $ruleset } |
            Should -Throw -ExpectedMessage "Repository '.github' has no .github/workflows/org-checks.yml at commit $script:sha. Put the commit that holds the file in ruleset.rules.workflows, or the ruleset would block every pull request."
    }

    It 'fails when the workflow file is not at the configured commit, also without a reference copy' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.References = @{}
        $ruleset.WorkflowSources[$script:sourceKey].Content = $null

        { Get-TestRulesetPlan -Ruleset $ruleset } | Should -Throw -ExpectedMessage "Repository '.github' has no *"
    }

    It 'fails when the workflow repository does not share its workflows (<_>)' -ForEach @('none', 'user') {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].AccessLevel = $_

        { Get-TestRulesetPlan -Ruleset $ruleset } |
            Should -Throw -ExpectedMessage "Repository '.github' does not share its workflows with the organization (access level '$_'). Open https://github.com/contoso/.github/settings/actions, under `"Access`" select `"Accessible from repositories in the 'contoso' organization`", and save; the ruleset would block every pull request otherwise."
    }

    It 'accepts the access level <_>' -ForEach @('organization', 'enterprise') {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].AccessLevel = $_

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'fails when a private workflow cannot run in internal and public repositories' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.RepositoryVisibilities = [string[]]@('internal', 'private', 'public')

        { Get-TestRulesetPlan -Ruleset $ruleset } |
            Should -Throw -ExpectedMessage "The workflow of repository '.github' is private and cannot run in the internal and public repositories of contoso, whose pull requests the ruleset would block. Make '.github' public, or the repositories private."
    }

    It 'fails when the <Source> workflow cannot run in <Blocked> repositories' -ForEach @(
        @{ Source = 'private'; Visibilities = @('internal', 'private'); Blocked = 'internal'; Needed = 'internal' }
        @{ Source = 'internal'; Visibilities = @('internal', 'public'); Blocked = 'public'; Needed = 'public' }
    ) {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].Visibility = $Source
        $ruleset.RepositoryVisibilities = [string[]]$Visibilities

        { Get-TestRulesetPlan -Ruleset $ruleset } | Should -Throw -ExpectedMessage "*is $Source and cannot run in the $Blocked repositories of contoso*Make '.github' $Needed,*"
    }

    It 'accepts a public workflow repository for every visibility, without an access level' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].Visibility = 'public'
        $ruleset.WorkflowSources[$script:sourceKey].AccessLevel = $null
        $ruleset.RepositoryVisibilities = [string[]]@('internal', 'private', 'public')

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'accepts an internal workflow repository for internal and private repositories' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].Visibility = 'internal'
        $ruleset.RepositoryVisibilities = [string[]]@('internal', 'private')

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
    }
}

Describe 'Get-GitHubOrgWarning: ruleset' {
    It 'reports a reviewer team that does not exist and plans no ruleset change' {
        $ruleset = Get-EmptyTestRulesetState
        $ruleset.Teams['platform-admins'] = $null

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be "Team 'platform-admins' of ruleset.rules.pullRequest.requiredReviewers does not exist in contoso, so the ruleset cannot name it; the engine leaves the ruleset unchanged. Create the team (engine/README.md, Manual setup), or remove it from the config."
    }

    It 'reports a reviewer team without write access to every repository' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Teams['platform-admins'].HasRepositoryWrite = $false

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be "Team 'platform-admins' has no write access to every repository of contoso, so its approvals do not count and pull requests that change its file patterns wait for an organization admin. Assign it the organization role `"All-repository write`" at https://github.com/organizations/contoso/settings/org_role_assignments."
    }

    It 'reports Copilot code review without a Copilot plan and still plans the rule' {
        $ruleset = Get-EmptyTestRulesetState
        $ruleset.Copilot = $null

        (Get-PlanAction -Plan (Get-TestRulesetPlan -Ruleset $ruleset) -Action 'CreateRuleset').Body.rules.type | Should -Contain 'copilot_code_review'
        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be 'ruleset.rules.copilotCodeReview asks Copilot to review every pull request, but contoso has no Copilot Business or Enterprise plan, so no pull request gets a review. Buy Copilot Business (engine/README.md, Copilot code review), or set ruleset.rules.copilotCodeReview.enabled to false.'
    }

    It 'reports Copilot code review without a Copilot seat' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Copilot.Seats = 0

        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be 'ruleset.rules.copilotCodeReview asks Copilot to review every pull request, but no member of contoso has a Copilot seat, so only authors with a license of their own get a review. Assign seats at https://github.com/organizations/contoso/settings/copilot/seat_management.'
    }

    It 'does not report the Copilot plan while Copilot code review is disabled' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.copilotCodeReview.enabled = $false
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.rules = @($ruleset.Current.rules | Where-Object type -NE 'copilot_code_review')
        $ruleset.Copilot = $null

        Get-TestRulesetWarning -Config $config -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'reports another organization ruleset' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.OtherRulesets = @([pscustomobject]@{ Id = 9; Name = 'legacy'; Target = 'tag'; Enforcement = 'evaluate' })

        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be "Ruleset 'legacy' (tag, evaluate) is not in the config; the engine leaves it alone. Review it at https://github.com/organizations/contoso/settings/rules/9."
    }

    It 'reports a condition the engine does not model and plans no ruleset change' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.conditions | Add-Member -NotePropertyName repository_property -NotePropertyValue ([pscustomobject]@{ include = @([pscustomobject]@{ name = 'tier'; property_values = @('prod') }); exclude = @() })

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be 'Ruleset ''default-branch'' has conditions.repository_property = {"include":[{"name":"tier","property_values":["prod"]}],"exclude":[]}, which the engine does not model: it neither compares nor sets the field, and the field can narrow which repositories the ruleset applies to or loosen a rule. Review it at https://github.com/organizations/contoso/settings/rules/7; remove it there unless it is wanted, or add the field to the engine.'
    }

    It 'reports a field of a condition the engine does not model' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.Current.conditions.ref_name | Add-Member -NotePropertyName match -NotePropertyValue 'none'

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
        Get-TestRulesetWarning -Ruleset $ruleset | Should -BeLike "*has conditions.ref_name.match = `"none`", which the engine does not model*"
    }

    It 'reports a rule parameter the engine does not model and plans no ruleset change' {
        $ruleset = Get-MatchingTestRulesetState
        (Get-TestRule -Detail $ruleset.Current -Type 'pull_request').parameters | Add-Member -NotePropertyName allow_self_approval -NotePropertyValue $true

        Get-TestRulesetPlan -Ruleset $ruleset | Should -BeNullOrEmpty
        Get-TestRulesetWarning -Ruleset $ruleset | Should -BeLike '*has rules.pull_request.allow_self_approval = true, which the engine does not model*'
    }

    It 'does not report the parameters of a rule the engine removes' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.copilotCodeReview.enabled = $false
        $ruleset = Get-MatchingTestRulesetState
        (Get-TestRule -Detail $ruleset.Current -Type 'copilot_code_review').parameters | Add-Member -NotePropertyName review_languages -NotePropertyValue @('en')

        (Get-PlanAction -Plan (Get-TestRulesetPlan -Config $config -Ruleset $ruleset) -Action 'UpdateRuleset').Summary | Should -BeLike '*rules.copilot_code_review: present -> <none>*'
        Get-TestRulesetWarning -Config $config -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'reports a central workflow that differs from the reference copy' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].Content = "name: changed`n"

        Get-TestRulesetWarning -Ruleset $ruleset |
            Should -Be "The workflow .github/workflows/org-checks.yml of repository '.github' at commit 0123456 differs from org-checks.yml beside the config. Copy that file into '.github' by a pull request, then put its merge commit in ruleset.rules.workflows."
    }

    It 'does not report a central workflow that differs only in line endings and the final newline' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.References['org-checks.yml'] = "name: checks`non: pull_request`n"
        $ruleset.WorkflowSources[$script:sourceKey].Content = "name: checks`r`non: pull_request`r`n`r`n"

        Get-TestRulesetWarning -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'compares a workflow of any name that has a reference copy' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.workflows[0].path = '.github/workflows/other.yml'
        $ruleset = Get-MatchingTestRulesetState
        $source = $ruleset.WorkflowSources[$script:sourceKey]
        $source.Content = "name: other`n"
        $ruleset.WorkflowSources = @{ ".github/.github/workflows/other.yml@$script:sha" = $source }
        $ruleset.References = @{ 'other.yml' = "name: reference`n" }
        (Get-TestRule -Detail $ruleset.Current -Type 'workflows').parameters.workflows[0].path = '.github/workflows/other.yml'

        Get-TestRulesetPlan -Config $config -Ruleset $ruleset | Should -BeNullOrEmpty
        $warnings = @(Get-TestRulesetWarning -Config $config -Ruleset $ruleset)
        $warnings | Should -HaveCount 1
        $warnings[0] | Should -BeLike '*.github/workflows/other.yml*differs from other.yml beside the config*'
    }

    It 'skips a workflow without a reference copy' {
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.References = @{}
        $ruleset.WorkflowSources[$script:sourceKey].Content = "name: changed`n"

        Get-TestRulesetWarning -Ruleset $ruleset | Should -BeNullOrEmpty
    }

    It 'compares only the workflow that has a reference copy' {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.workflows += ('{ "repository": ".github", "path": ".github/workflows/other.yml", "sha": "' + $script:sha + '" }' | ConvertFrom-Json)
        $ruleset = Get-MatchingTestRulesetState
        $ruleset.WorkflowSources[$script:sourceKey].Content = "name: changed`n"
        $ruleset.WorkflowSources[".github/.github/workflows/other.yml@$script:sha"] = [pscustomobject]@{ RepositoryId = 21; Visibility = 'private'; AccessLevel = 'organization'; Content = "name: other`n" }

        $warnings = @(Get-TestRulesetWarning -Config $config -Ruleset $ruleset | Where-Object { $_ -like '*beside the config*' })
        $warnings | Should -HaveCount 1
        $warnings[0] | Should -BeLike '*.github/workflows/org-checks.yml*'
    }
}
