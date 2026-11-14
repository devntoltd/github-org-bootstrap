BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    function Get-TestRoundTripPlan {
        # Reads the fake and plans, as a run does.
        param([Parameter(Mandatory)][object]$Config)
        @(Get-GitHubOrgPlan -Config $Config -CurrentState (Get-GitHubOrgState -Config $Config))
    }

    function Get-TestBodyKey {
        # Every key of a request body at any depth, and every value of a 'type' key.
        param([AllowNull()][object]$Value)

        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                $key
                if ($key -eq 'type') {
                    $Value[$key]
                }
                Get-TestBodyKey -Value $Value[$key]
            }
        }
        elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            foreach ($item in $Value) {
                Get-TestBodyKey -Value $item
            }
        }
    }
}

# What Apply sends must be what State reads back as matching the config: on a fake that keeps what is written, a
# second plan after applying the first is empty. Plan and Apply tests check each half against hand-built shapes.
Describe 'Round trip on a fake GitHub API' {
    BeforeEach {
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
        $script:config = Get-TestGitHubOrgConfig
    }

    AfterEach {
        Unregister-TestGhFake
    }

    It 'applies every section to a permissive organization, then plans nothing' {
        Register-TestGitHubOrgFake -Resource (Get-PermissiveTestGitHubOrgResource)

        $plan = Get-TestRoundTripPlan -Config $script:config
        $plan.Action | Should -Be @(
            'UpdateOrganizationSettings', 'SetActionsPermissions', 'SetSelectedActions', 'SetWorkflowPermissions'
            'SetSelfHostedRunners', 'SetForkPullRequestApproval', 'SetPrivateForkPullRequestWorkflows', 'SetArtifactAndLogRetention'
            'SetCopilotCloudAgentAccess'
            'CreateCodeSecurityConfiguration', 'SetCodeSecurityDefault', 'AttachCodeSecurityConfiguration', 'CreateRuleset', 'CreateBudget', 'CreateBudget', 'AddCopilotSeats'
        )
        Invoke-GitHubOrgPlan -Plan $plan

        Get-TestRoundTripPlan -Config $script:config | Should -BeNullOrEmpty
    }

    It 'reads back the seat it bought as a seat of the plan' {
        Register-TestGitHubOrgFake -Resource (Get-PermissiveTestGitHubOrgResource)
        Invoke-GitHubOrgPlan -Plan (Get-TestRoundTripPlan -Config $script:config)

        $state = Get-GitHubOrgState -Config $script:config

        $state.CopilotSeats.Seats.Login | Should -Be 'octocat'
        $state.CopilotSeats.Total | Should -Be 1
        $state.Ruleset.Copilot.Seats | Should -Be 1
    }

    It 'buys a seat of a team only for the member without one' {
        # The plan posts the whole team, octocat included, who holds a seat already.
        $resource = Get-MatchingTestGitHubOrgResource
        $resource['orgs/contoso/teams/reviewers/members'] = [object[]]@([pscustomobject]@{ login = 'octocat' }, [pscustomobject]@{ login = 'hubot' })
        Register-TestGitHubOrgFake -Resource $resource
        $script:config.copilotSeats.selected_teams = @('reviewers')

        $plan = Get-TestRoundTripPlan -Config $script:config
        $plan.Action | Should -Be 'AddCopilotTeam'
        Invoke-GitHubOrgPlan -Plan $plan
        $state = Get-GitHubOrgState -Config $script:config

        @($state.CopilotSeats.Seats.Login | Sort-Object) | Should -Be @('hubot', 'octocat')
        $state.CopilotSeats.Total | Should -Be 2
        Get-TestRoundTripPlan -Config $script:config | Should -BeNullOrEmpty
    }

    It 'sends every apply field of the engine on that first run' {
        Register-TestGitHubOrgFake -Resource (Get-PermissiveTestGitHubOrgResource)

        $plan = Get-TestRoundTripPlan -Config $script:config

        # So the round trip covers every row of the settings table: a field that is never sent is never read back.
        $sent = @($plan | Where-Object Action -NE 'CreateRuleset' | ForEach-Object { $_.Body.Keys })
        $applied = InModuleScope GitHubOrg { @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'apply' -and $_.Section -notlike 'ruleset*' } | ForEach-Object { $_.Field }) }
        foreach ($field in $applied) {
            $sent | Should -Contain $field
        }

        # The ruleset body is nested: each ruleset row, the sections above it and the fields of its items are a key at
        # some depth (a rule is the value of its 'type'), under its API name.
        $rulesetSent = @(Get-TestBodyKey -Value (Get-PlanAction -Plan $plan -Action 'CreateRuleset').Body)
        $apiName = @{ pullRequest = 'pull_request'; copilotCodeReview = 'copilot_code_review'; requiredReviewers = 'required_reviewers'; organizationAdmin = 'bypass_actors'; team = 'reviewer'; repository = 'repository_id' }
        $rulesetFields = InModuleScope GitHubOrg {
            foreach ($row in @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'apply' -and $_.Section -like 'ruleset*' })) {
                @($row.Section.Split('.') | Select-Object -Skip 1) + $row.Field + @($row.Item.Keys)
            }
        }
        # enabled is no API field: it decides whether the Copilot code review rule is sent.
        foreach ($field in @($rulesetFields | Where-Object { $_ -notin 'bypass', 'rules', 'enabled' } | Select-Object -Unique)) {
            $name = $apiName[$field] ?? $field
            $rulesetSent | Should -Contain $name -Because "the ruleset field $field is sent as $name"
        }
    }

    It 'updates a drifted selection and code security configuration, then plans nothing' {
        $resource = Get-MatchingTestGitHubOrgResource
        $resource['orgs/contoso/actions/permissions/selected-actions'] = @{ github_owned_allowed = $true; verified_allowed = $true; patterns_allowed = @('azure/login@*', 'evil/action@*') }
        $resource['orgs/contoso/code-security/configurations'][1] = Get-TestCodeSecurityConfiguration -Id 42 -State 'disabled'
        $resource['orgs/contoso/code-security/configurations/defaults'] = @()
        $resource['repos/contoso/repo-b/code-security-configuration'] = $null
        Register-TestGitHubOrgFake -Resource $resource

        $plan = Get-TestRoundTripPlan -Config $script:config
        $plan.Action | Should -Be @('SetSelectedActions', 'UpdateCodeSecurityConfiguration', 'SetCodeSecurityDefault', 'AttachCodeSecurityConfiguration')
        Invoke-GitHubOrgPlan -Plan $plan

        Get-TestRoundTripPlan -Config $script:config | Should -BeNullOrEmpty
    }

    It 'restores a drifted ruleset, then plans nothing' {
        $resource = Get-MatchingTestGitHubOrgResource
        $ruleset = $resource['orgs/contoso/rulesets/7']
        $ruleset.enforcement = 'disabled'
        $ruleset.bypass_actors = @($ruleset.bypass_actors) + [pscustomobject]@{ actor_id = 5; actor_type = 'Team'; bypass_mode = 'always' }
        Register-TestGitHubOrgFake -Resource $resource

        $plan = Get-TestRoundTripPlan -Config $script:config
        $plan.Action | Should -Be 'UpdateRuleset'
        Invoke-GitHubOrgPlan -Plan $plan

        Get-TestRoundTripPlan -Config $script:config | Should -BeNullOrEmpty
        # GitHub keeps the id and updates the list of rulesets too.
        (Get-TestGhFakeResource -Endpoint 'orgs/contoso/rulesets/7').id | Should -Be 7
        @(Get-TestGhFakeResource -Endpoint 'orgs/contoso/rulesets').enforcement | Should -Be 'active'
    }

    It 'plans nothing and writes nothing for an organization that already matches' {
        Register-TestGitHubOrgFake -Resource (Get-MatchingTestGitHubOrgResource)

        Get-TestRoundTripPlan -Config $script:config | Should -BeNullOrEmpty

        @(Get-TestGhCall | Where-Object { $_.Arguments[2] -ne 'GET' }) | Should -BeNullOrEmpty
    }

    It 'plans nothing after applying, on a fake that drops what a PUT does not send' {
        $resource = Get-MatchingTestGitHubOrgResource
        $resource['orgs/contoso/actions/permissions/workflow'] = @{ default_workflow_permissions = 'write'; can_approve_pull_request_reviews = $true; new_flag = $true }
        $resource['orgs/contoso/actions/permissions/selected-actions'] = @{ github_owned_allowed = $true; verified_allowed = $true; patterns_allowed = @('azure/login@*', 'evil/action@*') }
        Register-TestGitHubOrgFake -Resource $resource

        $plan = Get-TestRoundTripPlan -Config $script:config
        $plan.Action | Should -Be 'SetSelectedActions'
        Invoke-GitHubOrgPlan -Plan $plan

        Get-TestRoundTripPlan -Config $script:config | Should -BeNullOrEmpty
        (Get-TestGhFakeResource -Endpoint 'orgs/contoso/actions/permissions/workflow').new_flag | Should -BeTrue
    }
}
