BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Assert-GitHubOrgContext' {
    BeforeEach {
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg Write-BootstrapRecommendation { }
        $script:routes = @{
            'GET user/memberships/orgs/contoso'    = Get-TestGhResponse -Body @{ state = 'active'; role = 'admin'; user = @{ login = 'octocat' } }
            'GET orgs/contoso/actions/permissions' = Get-TestGhResponse -Body @{ enabled_repositories = 'all' }
            'GET orgs/contoso/hooks'               = Get-TestGhListResponse -Items @()
        }
        Register-TestGhRoute -Route $script:routes
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'passes for an active owner and shows the organization and account without asking' {
        Mock -ModuleName Bootstrap.Common Read-Host { 'y' }

        Assert-GitHubOrgContext -Organization 'contoso'

        Should -Invoke Write-Host -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Object -eq 'Organization: contoso' }
        Should -Invoke Write-Host -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Object -eq 'Account:      octocat' }
        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
        Should -Invoke Write-BootstrapRecommendation -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'explains an unreadable membership' {
        Register-TestGhRoute -Route @{}

        { Assert-GitHubOrgContext -Organization 'contoso' } |
            Should -Throw "*Cannot read your membership in the GitHub organization 'contoso'*gh auth login*HTTP 404*"
    }

    It 'rejects a pending membership' {
        $script:routes['GET user/memberships/orgs/contoso'] = Get-TestGhResponse -Body @{ state = 'pending'; role = 'admin'; user = @{ login = 'octocat' } }
        Register-TestGhRoute -Route $script:routes

        { Assert-GitHubOrgContext -Organization 'contoso' } | Should -Throw "*membership in 'contoso' is 'pending'*accept the invitation*"
    }

    It 'requires an owner' {
        $script:routes['GET user/memberships/orgs/contoso'] = Get-TestGhResponse -Body @{ state = 'active'; role = 'member'; user = @{ login = 'octocat' } }
        Register-TestGhRoute -Route $script:routes

        { Assert-GitHubOrgContext -Organization 'contoso' } | Should -Throw "*must be an owner of 'contoso'*'member'*"
    }

    It 'asks for both scopes when the Actions settings cannot be read' {
        $script:routes['GET orgs/contoso/actions/permissions'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Resource not accessible (HTTP 403)' }
        Register-TestGhRoute -Route $script:routes

        { Assert-GitHubOrgContext -Organization 'contoso' } |
            Should -Throw "Cannot read the Actions settings of 'contoso': gh needs the admin:org scope. Run: gh auth refresh -h github.com -s admin:org,admin:org_hook. *HTTP 403*"
        Should -Invoke Write-BootstrapRecommendation -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'asks for the admin:org_hook scope when the webhooks cannot be read' {
        $script:routes['GET orgs/contoso/hooks'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Not Found (HTTP 404)' }
        Register-TestGhRoute -Route $script:routes

        { Assert-GitHubOrgContext -Organization 'contoso' } |
            Should -Throw "Cannot read the webhooks of 'contoso': gh needs the admin:org_hook scope. Run: gh auth refresh -h github.com -s admin:org,admin:org_hook. *HTTP 404*"
        # admin:org is granted at this point: remind to remove it although the run stops here.
        Should -Invoke Write-BootstrapRecommendation -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Command -like '* -r admin:org,admin:org_hook' }
    }
}

Describe 'Get-GitHubOrgState' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Progress { }
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'shows a progress step for each read and clears it at the end' {
        # Every section and code security without repositories: one call per read, so a new read without its
        # progress step fails here.
        Register-TestGhRoute -Route (Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(Get-TestCodeSecurityConfiguration))

        Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) | Out-Null

        $reads = @(Get-TestGhCall).Count
        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times $reads -Exactly -ParameterFilter { $Activity -eq 'Reading current state' -and $Status }
        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Activity -eq 'Reading current state' -and $Completed }
    }

    It 'clears the progress when a read fails' {
        Register-TestGhRoute -Route @{}

        { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*Cannot read orgs/contoso*'
        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Activity -eq 'Reading current state' -and $Completed }
    }

    It 'records when the reads ended, in UTC' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState))
        $before = [datetime]::UtcNow

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $after = [datetime]::UtcNow
        $state.ReadAt.Kind | Should -Be 'Utc'
        $state.ReadAt | Should -BeGreaterOrEqual $before
        $state.ReadAt | Should -BeLessOrEqual $after
    }

    It 'reads the four settings of the organization' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState))

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Settings.default_repository_permission | Should -Be 'none'
        $state.Settings.two_factor_requirement_enabled | Should -BeTrue
        $state.Actions.allowed_actions | Should -Be 'selected'
        ($state.SelectedActions.patterns_allowed -join ',') | Should -Be 'azure/login@*,octo-org/octo-action@*'
        $state.Workflow.default_workflow_permissions | Should -Be 'read'
    }

    It 'keeps only the supported fields' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso'] = Get-TestGhResponse -Body @{ login = 'contoso'; default_repository_permission = 'read' }
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Settings.Contains('login') | Should -BeFalse
        $state.Settings.default_repository_permission | Should -Be 'read'
    }

    It 'does not read the selection while allowed_actions is not selected' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-DefaultTestGitHubOrgState))

        (Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)).SelectedActions | Should -BeNullOrEmpty
        @(Get-TestGhCall | Where-Object { $_.Arguments -contains 'orgs/contoso/actions/permissions/selected-actions' }).Count | Should -Be 0
    }

    It 'fails on a 409 of selected-actions while allowed_actions is selected' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/actions/permissions/selected-actions'] = Get-TestGhConflict
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*orgs/contoso/actions/permissions/selected-actions*Conflict*'
    }

    It 'fails on any other error of selected-actions' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/actions/permissions/selected-actions'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 500)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*orgs/contoso/actions/permissions/selected-actions*HTTP 500*'
    }

    It 'reads a missing pattern list as an empty list' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/actions/permissions/selected-actions'] = Get-TestGhResponse -Body @{ github_owned_allowed = $true; verified_allowed = $false; patterns_allowed = $null }
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.SelectedActions.patterns_allowed.Count | Should -Be 0
    }

    It 'suggests the admin:org scope when a read fails' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes.Remove('GET orgs/contoso/actions/permissions/workflow')
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } |
            Should -Throw '*Cannot read orgs/contoso/actions/permissions/workflow*gh auth refresh -h github.com -s admin:org,admin:org_hook*HTTP 404*'
    }
}

Describe 'Get-GitHubOrgState: Actions policies' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Progress { }
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'reads the four Actions policies and the deploy keys setting' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState))

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Settings.deploy_keys_enabled_for_repositories | Should -BeFalse
        $state.SelfHostedRunners.enabled_repositories | Should -Be 'none'
        $state.ForkPullRequests.approval_policy | Should -Be 'all_external_contributors'
        $state.PrivateForkPullRequests.send_write_tokens_to_workflows | Should -BeFalse
        $state.Retention.days | Should -Be 30
    }

    It 'reads the repository access of the Copilot cloud agent' {
        $state = Get-MatchingTestGitHubOrgState
        $state.CopilotCloudAgent.enabled_repositories = 'selected'
        Register-TestGhRoute -Route (Get-TestGhRoute -State $state)

        (Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)).CopilotCloudAgent.enabled_repositories | Should -Be 'selected'
    }

    It 'keeps only the supported retention field' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/actions/permissions/artifact-and-log-retention'] = Get-TestGhResponse -Body @{ days = 90; maximum_allowed_days = 400 }
        Register-TestGhRoute -Route $routes

        $retention = (Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)).Retention

        $retention.days | Should -Be 90
        $retention.Contains('maximum_allowed_days') | Should -BeFalse
    }

}

Describe 'Get-GitHubOrgState: observations' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Progress { }
    }

    AfterEach {
        Unregister-TestGhStub
        InModuleScope GitHubOrg { $script:SettingDefinitions = @($script:SettingDefinitions | Where-Object { $_.Section -ne 'testCheck' }) }
    }

    It 'records a checked field missing from the answer as not observed' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso'] = Get-TestGhResponse -Body @{ login = 'contoso'; default_repository_permission = 'none' }
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $observation = $state.Observations['settings.is_verified']
        $observation.Status | Should -Be 'NotObserved'
        $observation.ReasonCode | Should -Be 'FieldMissing'
        $observation.HttpStatus | Should -BeNullOrEmpty
        $observation.Source | Should -Be 'GET orgs/contoso .is_verified'
        $observation.Reason | Should -Be 'GET orgs/contoso answered without the field is_verified'
        $state.Observations.Contains('settings.default_repository_permission') | Should -BeFalse
    }

    It 'keeps a field GitHub answers with null as observed' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $settings = [ordered]@{ login = 'contoso' }
        foreach ($key in (Get-MatchingTestGitHubOrgState).Settings.Keys) {
            $settings[$key] = (Get-MatchingTestGitHubOrgState).Settings[$key]
        }
        $settings['is_verified'] = $null
        $routes['GET orgs/contoso'] = Get-TestGhResponse -Body $settings
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Observations.Contains('settings.is_verified') | Should -BeFalse
        $state.Settings.is_verified | Should -BeNullOrEmpty
    }

    It 'records no response fields for an answer that is not an object' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/actions/permissions/workflow'] = Get-TestGhListResponse -Items @()
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.ResponseFields.Contains('/orgs/{org}/actions/permissions/workflow') | Should -BeFalse
    }

    It 'records no response fields for a section answer that is a single-item array' {
        # Invoke-GhApi enumerates a JSON array by default, so a single item would look like the object itself.
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso'] = Get-TestGhListResponse -Items @(@{ is_verified = $true })
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.ResponseFields.Contains('/orgs/{org}') | Should -BeFalse
        $state.Observations['settings.is_verified'].ReasonCode | Should -Be 'FieldMissing'
    }

    It 'keeps the value of a check row outside the sections that reads a section endpoint' {
        $newRow = @{ Section = 'testCheck'; Field = 'level'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}'; Field = 'level' }; Page = 'security' }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $settings = [ordered]@{ login = 'contoso'; level = 'high' }
        foreach ($key in (Get-MatchingTestGitHubOrgState).Settings.Keys) {
            $settings[$key] = (Get-MatchingTestGitHubOrgState).Settings[$key]
        }
        $routes['GET orgs/contoso'] = Get-TestGhResponse -Body $settings
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Observations.Contains('testCheck.level') | Should -BeFalse
        $state.CheckedValues['testCheck.level'] | Should -Be 'high'
        # A row of a section keeps its value in the section map only.
        $state.CheckedValues.Contains('settings.is_verified') | Should -BeFalse
        $state.Settings.Contains('is_verified') | Should -BeTrue
    }

    It 'records a check row outside the sections as missing when a section endpoint answers without its field' {
        $newRow = @{ Section = 'testCheck'; Field = 'level'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}'; Field = 'level' }; Page = 'security' }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState))

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Observations['testCheck.level'].ReasonCode | Should -Be 'FieldMissing'
        $state.CheckedValues.Contains('testCheck.level') | Should -BeFalse
    }

    It 'records no response fields for a check-only answer that is a single-item array' {
        $newRow = @{ Section = 'testCheck'; Field = 'level'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'level' }; Page = 'security' }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/test/check'] = Get-TestGhListResponse -Items @(@{ level = 'high' })
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.ResponseFields.Contains('/orgs/{org}/test/check') | Should -BeFalse
        $state.Observations['testCheck.level'].ReasonCode | Should -Be 'FieldMissing'
        $state.CheckedValues.Contains('testCheck.level') | Should -BeFalse
    }

    It 'records the field names of each answer and the plan name' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso'] = Get-TestGhResponse -Body @{ login = 'contoso'; plan = @{ name = 'team' } }
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.ResponseFields['/orgs/{org}'] | Should -Contain 'login'
        $state.ResponseFields['/orgs/{org}'] | Should -Contain 'plan'
        $state.ResponseFields['/orgs/{org}/actions/permissions'] | Should -Contain 'allowed_actions'
        $state.OrganizationPlan | Should -Be 'team'
    }

    It 'has no plan name when the answer carries none' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState))

        (Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)).OrganizationPlan | Should -BeNullOrEmpty
    }

    It 'reads a check-only endpoint as <Code>' -ForEach @(
        @{ Code = 'Observed'; Output = '{"level":"high"}'; ExitCode = 0 }
        @{ Code = 'AuthenticationFailed'; Output = 'gh: Bad credentials (HTTP 401)'; Status = 401; Reason = 'GET orgs/contoso/test/check answered 401: the gh token is missing, expired or revoked' }
        @{ Code = 'PermissionDenied'; Output = 'gh: Forbidden (HTTP 403)'; Status = 403; Reason = 'GET orgs/contoso/test/check answered 403: the gh account may not read it' }
        @{ Code = 'NotFound'; Output = 'gh: Not Found (HTTP 404)'; Status = 404; Reason = 'GET orgs/contoso/test/check answered 404: not found or not visible to this token' }
        @{ Code = 'TechnicalFailure'; Output = 'gh: Server Error (HTTP 500)'; Status = 500; Reason = 'GET orgs/contoso/test/check failed (HTTP 500)' }
        @{ Code = 'TechnicalFailure'; Output = 'error connecting to api.github.com'; Reason = 'GET orgs/contoso/test/check failed (no answer)' }
        @{ Code = 'TechnicalFailure'; Output = '<html>maintenance</html>'; ExitCode = 0; Reason = 'GET orgs/contoso/test/check failed (the answer is not JSON)' }
        @{ Code = 'PlanRestricted'; Output = 'gh: Forbidden (HTTP 403)'; Status = 403; Row = @{ ReadRequiresPlan = @('enterprise') }; Reason = "GET orgs/contoso/test/check answered 403 and the organization's plan is team; reading it needs enterprise" }
        @{ Code = 'NotFound'; Output = 'gh: Not Found (HTTP 404)'; Status = 404; Row = @{ ReadRequiresPlan = @('team') } }
        @{ Code = 'PermissionDenied'; Output = 'gh: Forbidden (HTTP 403)'; Status = 403; Row = @{ PlanRestriction = 'GitHub Enterprise Cloud only' } }
    ) {
        $newRow = @{ Section = 'testCheck'; Field = 'level'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'level' }; Page = 'security' }
        foreach ($key in $Row.Keys) {
            $newRow[$key] = $Row[$key]
        }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso'] = Get-TestGhResponse -Body @{ login = 'contoso'; plan = @{ name = 'team' } }
        $routes['GET orgs/contoso/test/check'] = [pscustomobject]@{ ExitCode = $(if ($null -ne $ExitCode) { $ExitCode } else { 1 }); Output = $Output }
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        if ($Code -eq 'Observed') {
            $state.Observations.Contains('testCheck.level') | Should -BeFalse
            $state.CheckedValues['testCheck.level'] | Should -Be 'high'
            return
        }
        $observation = $state.Observations['testCheck.level']
        $observation.ReasonCode | Should -Be $Code
        $observation.HttpStatus | Should -Be $Status
        $observation.Status | Should -Be $(if ($Code -eq 'FeatureAbsent') { 'NotApplicable' } else { 'NotObserved' })
        if ($Reason) {
            $observation.Reason | Should -Be $Reason
        }
        $observation.Source | Should -Be 'GET orgs/contoso/test/check .level'
        $state.CheckedValues.Contains('testCheck.level') | Should -BeFalse
    }

    It 'reads a nested field of an answer: <Case>' -ForEach @(
        @{ Case = 'present'; Body = @{ effort = @{ configured = 'high'; effective = 'high' } }; Value = 'high' }
        @{ Case = 'null'; Body = @{ effort = @{ configured = $null; effective = 'medium' } }; Value = $null }
        @{ Case = 'missing'; Body = @{ effort = @{ effective = 'medium' } }; Missing = $true }
        @{ Case = 'not an object'; Body = @{ effort = 'high' }; Missing = $true }
    ) {
        $newRow = @{ Section = 'testCheck'; Field = 'effort'; Type = 'string'; Nullable = $true; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'effort.configured' }; Page = 'security'; UiGroup = 'Effort' }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/test/check'] = Get-TestGhResponse -Body $Body
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        if ($Missing) {
            $state.Observations['testCheck.effort'].ReasonCode | Should -Be 'FieldMissing'
            $state.Observations['testCheck.effort'].Reason | Should -Be 'GET orgs/contoso/test/check answered without the field effort.configured'
            return
        }
        $state.Observations.Contains('testCheck.effort') | Should -BeFalse
        $state.CheckedValues.Contains('testCheck.effort') | Should -BeTrue
        $state.CheckedValues['testCheck.effort'] | Should -Be $Value
    }

    It 'records no field names for an empty object answer' {
        # GitHub answers {} for an interaction limit that is not set (seen 2026-11-08).
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/interaction-limits'] = [pscustomobject]@{ ExitCode = 0; Output = '{}' }
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        @($state.ResponseFields['/orgs/{org}/interaction-limits']).Count | Should -Be 0
        $state.CheckedValues['interactionLimits.limit'] | Should -Be 'none'
    }

    It 'reads a field an unset answer leaves out as its AbsentValue: <Case>' -ForEach @(
        @{ Case = 'unset'; Body = @{}; Value = 'none' }
        @{ Case = 'set'; Body = @{ limit = 'existing_users'; origin = 'organization'; expires_at = '2026-11-09T10:00:00Z' }; Value = 'existing_users' }
    ) {
        $newRow = @{ Section = 'testCheck'; Field = 'limit'; Type = 'enum'; Values = @('none', 'existing_users'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'limit' }; AbsentValue = 'none'; Page = 'security'; UiGroup = 'Limit' }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/test/check'] = Get-TestGhResponse -Body $Body
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Observations.Contains('testCheck.limit') | Should -BeFalse
        $state.CheckedValues['testCheck.limit'] | Should -Be $Value
    }

    It 'records an answer that is not an object as not observed, an AbsentValue notwithstanding: <Case>' -ForEach @(
        @{ Case = 'an empty array'; Items = @() }
        @{ Case = 'a single-item array'; Items = @(@{ limit = 'existing_users' }) }
    ) {
        $newRow = @{ Section = 'testCheck'; Field = 'limit'; Type = 'enum'; Values = @('none', 'existing_users'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'limit' }; AbsentValue = 'none'; Page = 'security'; UiGroup = 'Limit' }
        InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/test/check'] = Get-TestGhListResponse -Items $Items
        Register-TestGhRoute -Route $routes

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Observations['testCheck.limit'].ReasonCode | Should -Be 'FieldMissing'
        $state.CheckedValues.Contains('testCheck.limit') | Should -BeFalse
        $state.ResponseFields.Contains('/orgs/{org}/test/check') | Should -BeFalse
    }

    It 'reads <Path> from its endpoint' -ForEach @(
        @{ Path = 'interactionLimits.limit'; Value = 'none' }
        @{ Path = 'interactionLimits.pull_request_cap_enabled'; Value = $false }
        @{ Path = 'immutableReleases.enforced_repositories'; Value = 'all' }
        @{ Path = 'dependabot.default_level'; Value = 'public' }
    ) {
        Register-TestGhRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState))

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Observations.Contains($Path) | Should -BeFalse
        $state.CheckedValues[$Path] | Should -Be $Value
    }

    Context 'the Copilot policies' {
        BeforeEach {
            $script:seatState = Get-MatchingTestGitHubOrgState
        }

        It 'reads the Copilot policies of the billing and code review answers' {
            Register-TestGhRoute -Route (Get-TestGhRoute -State $script:seatState)

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations.Keys | Where-Object { $_ -like 'copilot.*' } | Should -BeNullOrEmpty
            $state.CheckedValues['copilot.policies.public_code_suggestions'] | Should -Be 'block'
            $state.CheckedValues['copilot.policies.ide_chat'] | Should -Be 'enabled'
            $state.CheckedValues['copilot.policies.code_review'] | Should -Be 'enabled'
            $state.CheckedValues.Contains('copilot.codeReview.default_review_effort') | Should -BeTrue
            $state.CheckedValues['copilot.codeReview.default_review_effort'] | Should -BeNullOrEmpty
            $state.CheckedValues['copilot.runnerType.code_review_runner_type'] | Should -Be 'standard'
            $state.CheckedValues['copilot.runnerType.code_review_allow_repository_customization'] | Should -BeFalse
        }

        It 'records a Copilot code review endpoint that answers 404 as not observed' {
            $routes = Get-TestGhRoute -State $script:seatState
            $routes.Remove('GET orgs/contoso/copilot/code-review/settings')
            Register-TestGhRoute -Route $routes

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations['copilot.codeReview.default_review_effort'].ReasonCode | Should -Be 'NotFound'
        }

        It 'reports every Copilot policy as not applicable without a plan' {
            $routes = Get-TestGhRoute -State $script:seatState
            $routes.Remove('GET orgs/contoso/copilot/billing')
            Register-TestGhRoute -Route $routes

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $copilot = @($state.Observations.Keys | Where-Object { $_ -like 'copilot.*' })
            $copilot.Count | Should -BeGreaterThan 0
            @($copilot | Where-Object { $state.Observations[$_].Status -ne 'NotApplicable' }) | Should -BeNullOrEmpty
            @(Get-TestGhCall | Where-Object { ($_.Arguments -join ' ') -like '*copilot/code-review*' }).Count | Should -Be 0
        }
    }

    Context 'check rows of the Copilot billing answer' {
        BeforeEach {
            $newRow = @{ Section = 'testCheck'; Field = 'chat'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/billing'; Field = 'ide_chat' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Chat' }
            InModuleScope GitHubOrg -Parameters @{ NewRow = $newRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
            $script:seatState = Get-MatchingTestGitHubOrgState
            $script:seatState | Add-Member -NotePropertyName CopilotSeats -NotePropertyValue (Get-TestCopilotSeatState) -Force
        }

        It 'reads a checked Copilot setting from the billing answer' {
            Register-TestGhRoute -Route (Get-TestGhRoute -State $script:seatState)

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations.Contains('testCheck.chat') | Should -BeFalse
            $state.CheckedValues['testCheck.chat'] | Should -Be 'enabled'
            $state.CopilotSeats.SeatManagement | Should -Be 'assign_selected'
        }

        It 'records a Copilot setting missing from the billing answer as not observed' {
            $routes = Get-TestGhRoute -State $script:seatState
            $billing = (Get-TestCopilotSeatResource -CopilotSeats $script:seatState.CopilotSeats)['orgs/contoso/copilot/billing']
            $billing.PSObject.Properties.Remove('ide_chat')
            $routes['GET orgs/contoso/copilot/billing'] = Get-TestGhResponse -Body $billing
            Register-TestGhRoute -Route $routes

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations['testCheck.chat'].ReasonCode | Should -Be 'FieldMissing'
            $state.Observations['testCheck.chat'].Source | Should -Be 'GET orgs/contoso/copilot/billing .ide_chat'
        }

        It 'reports the Copilot policies as not applicable without a plan: <Case>' -ForEach @(
            @{ Case = '404' }
            @{ Case = 'unconfigured' }
        ) {
            $routes = Get-TestGhRoute -State $script:seatState
            $routes.Remove('GET orgs/contoso/copilot/billing/seats?per_page=100')
            if ($Case -eq '404') {
                $routes.Remove('GET orgs/contoso/copilot/billing')
            }
            else {
                $routes['GET orgs/contoso/copilot/billing'] = Get-TestGhResponse -Body (Get-TestCopilotBilling)
            }
            Register-TestGhRoute -Route $routes

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations['testCheck.chat'].Status | Should -Be 'NotApplicable'
            $state.Observations['testCheck.chat'].ReasonCode | Should -Be 'FeatureAbsent'
            $state.CheckedValues.Contains('testCheck.chat') | Should -BeFalse
            $state.CopilotSeats | Should -BeNullOrEmpty
        }

        It 'stops on a billing answer that is not an object: <Case>' -ForEach @(
            @{ Case = 'empty'; Output = '' }
            @{ Case = 'null'; Output = 'null' }
            @{ Case = 'array'; Output = '[]' }
        ) {
            # Only a 404 means no plan; an answer without content must not pass for one.
            $routes = Get-TestGhRoute -State $script:seatState
            $routes['GET orgs/contoso/copilot/billing'] = [pscustomobject]@{ ExitCode = 0; Output = $Output }
            Register-TestGhRoute -Route $routes

            { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*orgs/contoso/copilot/billing*not an object*'
        }

        It 'still stops on another failed read of the billing' {
            $routes = Get-TestGhRoute -State $script:seatState
            $routes['GET orgs/contoso/copilot/billing'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 500)' }
            Register-TestGhRoute -Route $routes

            { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*Cannot read orgs/contoso/copilot/billing*HTTP 500*'
        }

        It 'reports a Copilot endpoint as not applicable without a plan, without reading it' {
            $otherRow = @{ Section = 'testCheck'; Field = 'effort'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/copilot'; Field = 'effort' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Effort' }
            InModuleScope GitHubOrg -Parameters @{ NewRow = $otherRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
            $routes = Get-TestGhRoute -State $script:seatState
            $routes.Remove('GET orgs/contoso/copilot/billing')
            $routes['GET orgs/contoso/test/copilot'] = Get-TestGhResponse -Body @{ effort = 'medium' }
            Register-TestGhRoute -Route $routes

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations['testCheck.effort'].Status | Should -Be 'NotApplicable'
            @(Get-TestGhCall | Where-Object { $_.Arguments -contains 'orgs/contoso/test/copilot' }).Count | Should -Be 0
        }

        It 'takes a status case only on its own endpoint' {
            $otherRow = @{ Section = 'testCheck'; Field = 'effort'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/copilot'; Field = 'effort' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Effort' }
            InModuleScope GitHubOrg -Parameters @{ NewRow = $otherRow } { $script:SettingDefinitions = @($script:SettingDefinitions) + @($NewRow) }
            Register-TestGhRoute -Route (Get-TestGhRoute -State $script:seatState)

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.Observations['testCheck.effort'].Status | Should -Be 'NotObserved'
            $state.Observations['testCheck.effort'].ReasonCode | Should -Be 'NotFound'
        }

        It 'reads the billing once' {
            Register-TestGhRoute -Route (Get-TestGhRoute -State $script:seatState)

            Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) | Out-Null

            @(Get-TestGhCall | Where-Object { $_.Arguments -contains 'orgs/contoso/copilot/billing' }).Count | Should -Be 1
        }

        It 'records the field names of the billing answer' {
            Register-TestGhRoute -Route (Get-TestGhRoute -State $script:seatState)

            $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

            $state.ResponseFields['/orgs/{org}/copilot/billing'] | Should -Contain 'seat_management_setting'
        }
    }

    It 'still stops on a failed read of an apply endpoint' {
        $routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $routes['GET orgs/contoso/actions/permissions/workflow'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Forbidden (HTTP 403)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*Cannot read orgs/contoso/actions/permissions/workflow*HTTP 403*'
    }
}
