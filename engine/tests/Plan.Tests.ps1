BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgPlan' {
    It 'plans nothing when the organization matches the config' {
        @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-MatchingTestGitHubOrgState)).Count | Should -Be 0
    }

    It 'patches only the apply fields that differ' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_create_pages = $true
        $state.Settings.two_factor_requirement_enabled = $false

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        $plan.Count | Should -Be 1
        (@($plan[0].Body.Keys) -join ',') | Should -Be 'members_can_create_pages'
        $plan[0].Body.members_can_create_pages | Should -BeFalse
        $plan[0].Summary | Should -Be '~ update organization settings of contoso: members_can_create_pages: true -> false'
    }

    It 'plans nothing for a check field alone' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.two_factor_requirement_enabled = $false

        @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state).Count | Should -Be 0
    }

    It 'sends every field of a PUT section and summarizes only the differing ones' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.allowed_actions = 'all'

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state) -Action 'SetActionsPermissions'

        $action.Body.enabled_repositories | Should -Be 'all'
        $action.Body.allowed_actions | Should -Be 'selected'
        $action.Body.sha_pinning_required | Should -BeTrue
        $action.Summary | Should -Be '~ set Actions permissions of contoso: allowed_actions: all -> selected'
    }

    It 'sets every field of a selection GitHub does not have yet' {
        $state = Get-MatchingTestGitHubOrgState
        $state.SelectedActions = $null

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state) -Action 'SetSelectedActions'

        $action.Body.github_owned_allowed | Should -BeTrue
        $action.Body.verified_allowed | Should -BeFalse
        ($action.Body.patterns_allowed -join ',') | Should -Be 'azure/login@*,octo-org/octo-action@*'
        $action.Summary | Should -Be '~ set allowed actions of contoso: github_owned_allowed: <none> -> true; verified_allowed: <none> -> false; patterns_allowed: + azure/login@*, + octo-org/octo-action@*'
    }

    It 'sets a selection GitHub does not have yet even for an empty list' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.selected.patterns_allowed = @()
        $state = Get-MatchingTestGitHubOrgState
        $state.SelectedActions = $null

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config $config -CurrentState $state) -Action 'SetSelectedActions'

        $action.Body.patterns_allowed.Count | Should -Be 0
        $action.Summary | Should -BeLike '*; patterns_allowed: (empty list)'
    }

    It 'plans no selection while actions.selected is null' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.allowed_actions = 'local_only'
        $config.actions.selected = $null
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.allowed_actions = 'local_only'
        $state.SelectedActions = $null

        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0
    }

    It 'compares patterns as a set, ignoring order and case' {
        $state = Get-MatchingTestGitHubOrgState
        $state.SelectedActions.patterns_allowed = [string[]]@('OCTO-ORG/octo-action@*', 'azure/login@*')

        @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state).Count | Should -Be 0
    }

    It 'matches an empty pattern list against a missing one' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.selected.patterns_allowed = @()
        $state = Get-MatchingTestGitHubOrgState
        $state.SelectedActions.patterns_allowed = [string[]]@()

        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0
    }

    It 'lists added and removed patterns' {
        $state = Get-MatchingTestGitHubOrgState
        $state.SelectedActions.patterns_allowed = [string[]]@('azure/login@*', 'old-org/old-action@*')

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state) -Action 'SetSelectedActions'

        $action.Summary | Should -Be '~ set allowed actions of contoso: patterns_allowed: + octo-org/octo-action@*, - old-org/old-action@*'
        ($action.Body.patterns_allowed -join ',') | Should -Be 'azure/login@*,octo-org/octo-action@*'
    }

    It 'patches the public email when it differs' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.email = $null

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        $plan.Count | Should -Be 1
        $plan[0].Body.email | Should -Be 'security@contoso.com'
        $plan[0].Summary | Should -Be '~ update organization settings of contoso: email: <none> -> security@contoso.com'
    }

    It 'plans nothing when the public email differs only in case' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.email = 'Security@Contoso.com'
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.email = 'security@contoso.com'

        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0
    }

    It 'explains a section action: where it is, how it was read and how it is changed' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Workflow.default_workflow_permissions = 'write'

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state) -Action 'SetWorkflowPermissions'

        $action.Details | Should -Be @(
            'UI:    Actions > General > Workflow permissions  https://github.com/organizations/contoso/settings/actions'
            'Read:  GET orgs/contoso/actions/permissions/workflow .default_workflow_permissions'
            'Apply: PUT orgs/contoso/actions/permissions/workflow (the whole section)'
        )
    }

    It 'explains a patch as only the fields that differ' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_create_pages = $true

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        $plan[0].Details[-1] | Should -BeLike '*PATCH orgs/contoso (only these fields)'
    }

    It 'writes one Read line per endpoint the changed fields are read from' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_create_repositories = $true
        $state.Settings.members_can_create_pages = $true
        InModuleScope GitHubOrg {
            $script:SavedDefinitions = $script:SettingDefinitions
            $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                    if ($_.Section -eq 'settings' -and $_.Field -eq 'members_can_create_pages') {
                        $row = $_.Clone()
                        $row.Read = @{ Endpoint = '/orgs/{org}/test/other'; Field = 'members_can_create_pages' }
                        $row
                    }
                    else { $_ }
                })
        }
        try {
            $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state) -Action 'UpdateOrganizationSettings'
        }
        finally {
            InModuleScope GitHubOrg { $script:SettingDefinitions = $script:SavedDefinitions }
        }

        @($action.Details | Where-Object { $_ -like 'Read:*' }) | Should -Be @(
            'Read:  GET orgs/contoso .members_can_create_repositories'
            'Read:  GET orgs/contoso/test/other .members_can_create_pages'
        )
    }

    It 'keeps the UI lines of two pages that share a label and a group' {
        InModuleScope GitHubOrg {
            $script:SavedPages = $script:SettingPages
            $script:SavedDefinitions = $script:SettingDefinitions
            $script:SettingPages = @($script:SettingPages) + @(@{ Path = 'probe-page'; Label = 'Deploy keys'; Status = 'managed' })
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(
                @{ Section = 'settings'; Field = 'x_probe'; Type = 'boolean'; Mode = 'apply'; Page = 'probe-page'; UiGroup = 'Deploy keys'; UiLabel = 'Probe' }
            )
        }
        $config = Get-TestGitHubOrgConfig
        $config.settings | Add-Member -NotePropertyName x_probe -NotePropertyValue $false
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.deploy_keys_enabled_for_repositories = $true
        $state.Settings.x_probe = $true
        try {
            $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config $config -CurrentState $state) -Action 'UpdateOrganizationSettings'
        }
        finally {
            InModuleScope GitHubOrg {
                $script:SettingPages = $script:SavedPages
                $script:SettingDefinitions = $script:SavedDefinitions
            }
        }

        @($action.Details | Where-Object { $_ -like 'UI:*' }) | Should -Be @(
            'UI:    Deploy keys > Deploy keys  https://github.com/organizations/contoso/settings/deploy_keys'
            'UI:    Deploy keys > Deploy keys  https://github.com/organizations/contoso/settings/probe-page'
        )
    }

    It 'writes one UI line per page and group of the changed fields, none for a field without a page' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_create_public_repositories = $true
        $state.Settings.members_can_create_private_repositories = $true
        $state.Settings.deploy_keys_enabled_for_repositories = $true
        $state.Settings.members_can_create_repositories = $true

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state) -Action 'UpdateOrganizationSettings'

        @($action.Details | Where-Object { $_ -like 'UI:*' }) | Should -Be @(
            'UI:    Access > Member privileges > Repository creation  https://github.com/organizations/contoso/settings/member_privileges'
            'UI:    Deploy keys > Deploy keys  https://github.com/organizations/contoso/settings/deploy_keys'
        )
    }
}

Describe 'Get-GitHubOrgWarning' {
    It 'warns about nothing when the organization matches' {
        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-MatchingTestGitHubOrgState) -Plan @() | Should -BeNullOrEmpty
    }

    It 'names the page where an owner changes a checked setting' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.two_factor_requirement_enabled = $false
        $state.Settings.members_can_delete_repositories = $true

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings | Should -Be @(
            'two_factor_requirement_enabled is false, the config expects true. GitHub has no API to change it: open https://github.com/organizations/contoso/settings/security, under "Two-factor authentication" select "Require two-factor authentication for everyone in the contoso organization.", and save.'
            'members_can_delete_repositories is true, the config expects false. GitHub has no API to change it: open https://github.com/organizations/contoso/settings/member_privileges, under "Repository deletion and transfer" clear "Allow members to delete or transfer repositories for this organization", and save.'
        )
    }

    It 'warns that a checked setting was not observed, with the reason' {
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'settings.is_verified' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'FieldMissing'; HttpStatus = $null; Source = 'GET orgs/contoso .is_verified'; Reason = 'GET orgs/contoso answered without the field is_verified' }
            })

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings | Should -Be @('settings.is_verified is not observed: GET orgs/contoso answered without the field is_verified. The config expects true; check it on https://github.com/organizations/contoso/settings/domains.')
    }

    It 'names an empty list in a not-observed warning' {
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'actions.selected.patterns_allowed' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'FieldMissing'; HttpStatus = $null; Source = 'x'; Reason = 'GET x answered without the field patterns_allowed' }
            })
        $config = Get-TestGitHubOrgConfig
        $config.actions.selected.patterns_allowed = @()

        $warnings = @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan @())

        $warnings[0] | Should -BeLike '*The config expects (empty list); check it on*'
    }

    It 'matches a nullable checked setting that is null in GitHub and in the config' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.secret_scanning_push_protection_custom_link = $null

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings | Where-Object { $_ -like 'secret_scanning_push_protection_custom_link *' } | Should -BeNullOrEmpty
    }

    It 'warns about a nullable checked setting that is null in GitHub only' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.secret_scanning_push_protection_custom_link = 'https://example.com/secrets'

        $warnings = @(Get-GitHubOrgWarning -Config $config -CurrentState (Get-MatchingTestGitHubOrgState) -Plan @())

        @($warnings | Where-Object { $_ -like 'secret_scanning_push_protection_custom_link is <none>, the config expects https://example.com/secrets.*' }).Count | Should -Be 1
    }

    It 'warns about a row without a page without a link' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(@{ Section = 'testCheck'; Field = 'hidden'; Type = 'boolean'; Mode = 'check'; NoUi = $true; Page = $null; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'hidden' } })
        }
        $config = Get-TestGitHubOrgConfig
        $config | Add-Member -NotePropertyName testCheck -NotePropertyValue ([pscustomobject]@{ hidden = $true })
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'testCheck.hidden' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'NotFound'; HttpStatus = 404; Source = 'GET orgs/contoso/test/check .hidden'; Reason = 'GET orgs/contoso/test/check answered 404: not found or not visible to this token' }
            })
        try {
            $warnings = @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan @())
        }
        finally {
            InModuleScope GitHubOrg { $script:SettingDefinitions = @($script:SettingDefinitions | Where-Object { $_.Section -ne 'testCheck' }) }
        }

        $warnings | Should -Be @('testCheck.hidden is not observed: GET orgs/contoso/test/check answered 404: not found or not visible to this token. The config expects true.')
    }

    It 'never compares a setting it did not observe' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.two_factor_requirement_enabled = $false
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'settings.two_factor_requirement_enabled' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'PermissionDenied'; HttpStatus = 403; Source = 'GET orgs/contoso .two_factor_requirement_enabled'; Reason = 'GET orgs/contoso answered 403: the gh account may not read it' }
            })

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike 'settings.two_factor_requirement_enabled is not observed: *403*settings/security.'
    }

    It 'reports settings that do not apply in one line per absent case: <Expected>' -ForEach @(
        @{ Paths = @('settings.is_verified', 'settings.two_factor_requirement_enabled'); Expected = '2 checked settings are not checked: the organization has no Copilot plan.' }
        @{ Paths = @('settings.is_verified'); Expected = '1 checked setting is not checked: the organization has no Copilot plan.' }
    ) {
        $state = Get-MatchingTestGitHubOrgState
        $observation = [pscustomobject]@{ Status = 'NotApplicable'; ReasonCode = 'FeatureAbsent'; HttpStatus = 404; Source = 'GET orgs/contoso/copilot/billing .x'; Reason = 'the organization has no Copilot plan' }
        $observations = [ordered]@{}
        foreach ($path in $Paths) {
            $observations[$path] = $observation
        }
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue $observations

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings | Should -Be @($Expected)
    }

    It 'warns about nothing new for a state without observations' {
        $state = Get-MatchingTestGitHubOrgState

        $state.PSObject.Properties['Observations'] | Should -BeNullOrEmpty
        @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @()).Count | Should -Be 0
    }

    It 'checks the member privileges that only the web UI changes' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_create_teams = $true
        $state.Settings.members_can_delete_issues = $true
        $state.Settings.readers_can_create_discussions = $true

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        # The full text of such a warning: the test above.
        $warnings.Count | Should -Be 3
        $warnings[0] | Should -BeLike 'members_can_create_teams is true,*settings/member_privileges, under "Team creation rules" clear "Allow members to create teams"*'
        $warnings[1] | Should -BeLike 'members_can_delete_issues is true,*settings/member_privileges, under "Issue deletion" clear "Allow repository administrators to delete issues for this organization"*'
        $warnings[2] | Should -BeLike 'readers_can_create_discussions is true,*settings/member_privileges, under "Repository discussions" clear "Allow users with read access to create discussions"*'
        @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state).Count | Should -Be 0
    }

    It 'tells an owner to verify a domain when the organization is not verified' {
        $config = Get-TestGitHubOrgConfig
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.is_verified = $false

        $warnings = @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan @())

        # A setting with a hint instead of a checkbox; the start of the warning is the test of the checkbox above.
        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike 'is_verified is false, *: open https://github.com/organizations/contoso/settings/domains, add a domain the organization owns and verify it with the DNS TXT record GitHub shows.'
        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0
    }

    It 'warns before SHA pinning becomes required' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.sha_pinning_required = $false
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan $plan |
            Should -Be 'SHA pinning becomes required: once applied, GitHub runs an action only when a workflow references it by full commit SHA, so every workflow in the organization that uses a tag or branch will fail. Before applying, in every repository replace ''uses: owner/action@v1.2.3'' with ''uses: owner/action@<40-character commit SHA> # v1.2.3'' (the SHA: gh api repos/owner/action/commits/v1.2.3 --jq .sha); see engine/README.md#requirements.'
    }

    It 'does not warn when SHA pinning is already required' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.allowed_actions = 'all'
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan $plan | Should -BeNullOrEmpty
    }
}

Describe 'Get-GitHubOrgWarning: checked settings outside the endpoint sections' {
    BeforeEach {
        InModuleScope GitHubOrg {
            $script:SavedDefinitions = $script:SettingDefinitions
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(
                @{ Section = 'testCheck'; Field = 'level'; Type = 'enum'; Values = @('low', 'high'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/test/check'; Field = 'level' }; Page = 'security'; UiGroup = 'Level'; Options = @{ low = 'Low'; high = 'High' } }
            )
        }
        $script:config = Get-TestGitHubOrgConfig
        $script:config | Add-Member -NotePropertyName testCheck -NotePropertyValue ([pscustomobject]@{ level = 'low' })
        $script:state = Get-MatchingTestGitHubOrgState
    }

    AfterEach {
        InModuleScope GitHubOrg { $script:SettingDefinitions = $script:SavedDefinitions }
    }

    It 'compares a checked setting outside the endpoint sections' {
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{ 'testCheck.level' = 'high' })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings | Should -Be @('testCheck.level is high, the config expects low. GitHub has no API to change it: open https://github.com/organizations/contoso/settings/security, under "Level" choose "Low", and save.')
    }

    It 'says a writable checked setting is not applied yet' {
        InModuleScope GitHubOrg { $script:SettingDefinitions[-1].Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/test/check' } }
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{ 'testCheck.level' = 'high' })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        InModuleScope GitHubOrg { $script:SettingDefinitions[-1].Remove('Write') }
        $warnings | Should -HaveCount 1
        $warnings[0] | Should -BeLike 'testCheck.level is high, the config expects low. this tool does not apply it yet: open *'
        $warnings | Where-Object { $_ -like '*no API*' } | Should -BeNullOrEmpty
    }

    It 'ends the warning of a row without a page after the reason' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions[-1].Remove('UiGroup')
            $script:SettingDefinitions[-1].Remove('Options')
            $script:SettingDefinitions[-1].Page = $null
            $script:SettingDefinitions[-1].NoUi = $true
        }
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{ 'testCheck.level' = 'high' })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings | Should -Be @('testCheck.level is high, the config expects low. GitHub has no API to change it.')
    }

    It 'names no option for a value the page does not offer' {
        $script:config.testCheck.level = 'high'
        InModuleScope GitHubOrg { $script:SettingDefinitions[-1].Options = @{ low = 'Low' } }
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{ 'testCheck.level' = 'low' })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings | Should -Be @('testCheck.level is low, the config expects high. GitHub has no API to change it: open https://github.com/organizations/contoso/settings/security, under "Level" set the value the config expects, and save.')
    }

    It 'warns with a value outside the known values' {
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{ 'testCheck.level' = 'unconfigured' })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings | Should -HaveCount 1
        $warnings[0] | Should -BeLike 'testCheck.level is unconfigured, the config expects low.*'
    }

    It 'does not compare a checked setting it did not observe' {
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{})
        $script:state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'testCheck.level' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'NotFound'; HttpStatus = 404; Source = 'GET orgs/contoso/test/check .level'; Reason = 'GET orgs/contoso/test/check answered 404: not found or not visible to this token' }
            })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings | Should -HaveCount 1
        $warnings[0] | Should -BeLike 'testCheck.level is not observed: *'
    }

    It 'keeps the warnings of the endpoint sections first' {
        $script:state.Settings.is_verified = $false
        $script:state | Add-Member -NotePropertyName CheckedValues -NotePropertyValue ([ordered]@{ 'testCheck.level' = 'high' })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings | Should -HaveCount 2
        $warnings[0] | Should -BeLike 'is_verified is false,*'
        $warnings[1] | Should -BeLike 'testCheck.level is high,*'
    }
}

Describe 'Get-GitHubOrgWarning: unknown response fields' {
    BeforeEach {
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName Bootstrap.Common Write-Progress { }
    }

    AfterEach {
        Unregister-TestGhFake
    }

    It 'warns about fields GitHub returned that the catalog does not know: <Case>' -ForEach @(
        @{ Case = 'one'; Fields = @('new_field_x'); Expected = "GET orgs/contoso returned the field 'new_field_x', which this tool does not know: add a row for it, or list it under Fields of GET /orgs/{org} in engine/api-endpoints.psd1 with the reason." }
        @{ Case = 'two'; Fields = @('new_field_x', 'new_field_y'); Expected = "GET orgs/contoso returned the fields 'new_field_x', 'new_field_y', which this tool does not know: add a row for each, or list each under Fields of GET /orgs/{org} in engine/api-endpoints.psd1 with the reason." }
    ) {
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}' = [string[]]@(@('login', 'id') + $Fields) })

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings | Should -Be @($Expected)
    }

    It 'reports the Copilot policies of an organization without a Copilot plan in one line' {
        $resource = Get-MatchingTestGitHubOrgResource
        $resource.Remove('orgs/contoso/copilot/billing')
        Register-TestGitHubOrgFake -Resource $resource
        $config = Get-TestGitHubOrgConfig
        $config.copilotSeats.selected_usernames = @()
        $config.ruleset.rules.copilotCodeReview.enabled = $false
        $state = Get-GitHubOrgState -Config $config

        $warnings = @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan @())

        @($warnings | Where-Object { $_ -like '* checked settings are not checked: the organization has no Copilot plan.' }).Count | Should -Be 1
        $warnings | Where-Object { $_ -like 'copilot.*' } | Should -BeNullOrEmpty
    }

    It 'names an unknown field but never its value' {
        $resource = Get-MatchingTestGitHubOrgResource
        $resource['orgs/contoso'].token = 'ghp_example'
        Register-TestGitHubOrgFake -Resource $resource
        $config = Get-TestGitHubOrgConfig
        $state = Get-GitHubOrgState -Config $config

        $warnings = @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan @())

        # The fake answers every other read as the catalog knows it: token is the only unknown field of the round trip.
        $unknown = @($warnings | Where-Object { $_ -like '*which this tool does not know*' })
        $unknown.Count | Should -Be 1
        $unknown[0] | Should -BeLike "GET orgs/contoso returned the field 'token',*"
        $warnings | Where-Object { $_ -like '*ghp_example*' } | Should -BeNullOrEmpty
    }

    It 'warns about nothing for a field the catalog lists as unmanaged' {
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{
                '/orgs/{org}'                                         = [string[]]@('login', 'id', 'plan', 'billing_email', 'default_repository_permission', 'is_verified')
                '/orgs/{org}/actions/permissions/self-hosted-runners' = [string[]]@('enabled_repositories', 'selected_repositories_url')
            })

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @() | Should -BeNullOrEmpty
    }

    It 'scans only the answers of GETs that track response fields' {
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{
                '/orgs/{org}'                              = [string[]]@('login', 'extra_a')
                '/orgs/{org}/code-security/configurations' = [string[]]@('extra_b')
                '/orgs/{org}/no-such-endpoint'             = [string[]]@('extra_c')
            })

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike "GET orgs/contoso returned the field 'extra_a',*"
    }

    It 'never takes a Body field for a known response field' {
        # A write-only field: the PATCH accepts it, the GET does not document it.
        $patch = InModuleScope GitHubOrg { $script:ApiCatalog.Paths['/orgs/{org}'].PATCH }
        $body = $patch.Body
        $patch.Body = @($body) + 'x_write_only'
        try {
            $state = Get-MatchingTestGitHubOrgState
            $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}' = [string[]]@('login', 'x_write_only') })

            $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())
        }
        finally {
            $patch.Body = $body
        }

        $warnings | Should -HaveCount 1
        $warnings[0] | Should -BeLike "GET orgs/contoso returned the field 'x_write_only',*"
    }
}

Describe 'Get-GitHubOrgPlan: Actions policies' {
    It 'plans nothing when the policies match' {
        $config = Get-TestGitHubOrgConfig

        @(Get-GitHubOrgPlan -Config $config -CurrentState (Get-MatchingTestGitHubOrgState)).Count | Should -Be 0
    }

    It 'summarizes each policy change for an organization with permissive defaults' {
        # The order of the actions and their endpoints: the round trip (RoundTrip.Tests.ps1).
        $config = Get-TestGitHubOrgConfig

        $plan = @(Get-GitHubOrgPlan -Config $config -CurrentState (Get-DefaultTestGitHubOrgState))

        @($plan | Where-Object { $_.Action -notlike '*CodeSecurity*' -and $_.Action -notlike '*Ruleset' -and $_.Action -notlike '*Budget' } | ForEach-Object Target | Select-Object -Unique) | Should -Be 'contoso'
        (Get-PlanAction -Plan $plan -Action 'UpdateOrganizationSettings').Body.deploy_keys_enabled_for_repositories | Should -BeFalse
        (Get-PlanAction -Plan $plan -Action 'SetSelfHostedRunners').Summary | Should -Be '~ set self-hosted runner access of contoso: enabled_repositories: all -> none'
        (Get-PlanAction -Plan $plan -Action 'SetForkPullRequestApproval').Summary | Should -Be '~ set fork pull request approval of contoso: approval_policy: first_time_contributors -> all_external_contributors'
        (Get-PlanAction -Plan $plan -Action 'SetPrivateForkPullRequestWorkflows').Summary | Should -Be '~ set private repository fork pull request workflows of contoso: run_workflows_from_fork_pull_requests: true -> false; send_write_tokens_to_workflows: true -> false; send_secrets_and_variables: true -> false'
        $retention = Get-PlanAction -Plan $plan -Action 'SetArtifactAndLogRetention'
        $retention.Summary | Should -Be '~ set artifact and log retention of contoso: days: 90 -> 30'
        $retention.Body.days | Should -Be 30
    }

    It 'leaves a field alone while the field it depends on is false in the config, and sends what GitHub has' {
        # GitHub answers the PUT without an error but keeps require_approval_for_fork_pr_workflows false while
        # workflows from forks do not run, so comparing it would plan the same change on every run.
        $config = Get-TestGitHubOrgConfig
        $state = Get-MatchingTestGitHubOrgState
        $state.PrivateForkPullRequests.require_approval_for_fork_pr_workflows = $false

        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0

        $state.PrivateForkPullRequests.send_secrets_and_variables = $true
        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config $config -CurrentState $state) -Action 'SetPrivateForkPullRequestWorkflows'
        $action.Summary | Should -Not -BeLike '*require_approval_for_fork_pr_workflows*'
        $action.Body.require_approval_for_fork_pr_workflows | Should -BeFalse
    }

    It 'compares a dependent field once the field it depends on is true in the config' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.privateForkPullRequests.run_workflows_from_fork_pull_requests = $true
        $state = Get-MatchingTestGitHubOrgState
        $state.PrivateForkPullRequests.require_approval_for_fork_pr_workflows = $false

        $action = Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config $config -CurrentState $state) -Action 'SetPrivateForkPullRequestWorkflows'

        $action.Summary | Should -BeLike '*require_approval_for_fork_pr_workflows: false -> true*'
        $action.Body.require_approval_for_fork_pr_workflows | Should -BeTrue
    }

    It 'sets the repository access of the Copilot cloud agent, and only that' {
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-DefaultTestGitHubOrgState))

        $action = Get-PlanAction -Plan $plan -Action 'SetCopilotCloudAgentAccess'
        $action.Summary | Should -Be '~ set Copilot cloud agent repository access of contoso: enabled_repositories: all -> none'
        $action.Method | Should -Be 'PUT'
        $action.Endpoint | Should -Be 'orgs/contoso/copilot/coding-agent/permissions'
        @($action.Body.Keys) | Should -Be @('enabled_repositories')
        $action.Body.enabled_repositories | Should -Be 'none'
    }

    It 'leaves the repositories of the Copilot cloud agent alone while the access is selected' {
        $config = Get-TestGitHubOrgConfig
        $config.copilotCloudAgent.enabled_repositories = 'selected'
        $state = Get-MatchingTestGitHubOrgState
        $state.CopilotCloudAgent.enabled_repositories = 'selected'

        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0
    }

    It 'compares days by value whatever the numeric type' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.retention.days = [long]30
        $state = Get-MatchingTestGitHubOrgState
        $state.Retention.days = [int]30

        @(Get-GitHubOrgPlan -Config $config -CurrentState $state).Count | Should -Be 0
    }
}

Describe 'Get-GitHubOrgPlan: summaries' {
    It 'starts every summary with the marker of the other stages: + creates or adds, ~ changes' {
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-DefaultTestGitHubOrgState))

        $plan.Count | Should -BeGreaterThan 0
        @($plan | Where-Object Summary -NotMatch '^[+~] [a-z]') | Should -BeNullOrEmpty
    }
}

Describe 'Get-GitHubOrgPlan: unknown response fields' {
    It 'plans no change to a PUT section with an unknown field' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Workflow.default_workflow_permissions = 'write'
        $state.Retention.days = 90
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}/actions/permissions/workflow' = [string[]]@('default_workflow_permissions', 'new_flag') })

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        Get-PlanAction -Plan $plan -Action 'SetWorkflowPermissions' | Should -BeNullOrEmpty
        Get-PlanAction -Plan $plan -Action 'SetArtifactAndLogRetention' | Should -Not -BeNullOrEmpty
    }

    It 'still patches the organization settings with an unknown field' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.default_repository_permission = 'admin'
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}' = [string[]]@('login', 'new_flag') })

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        Get-PlanAction -Plan $plan -Action 'UpdateOrganizationSettings' | Should -Not -BeNullOrEmpty
    }

    It 'plans no selection while the skipped Actions permissions would leave allowed_actions unchanged' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.allowed_actions = 'all'
        $state.SelectedActions = $null
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}/actions/permissions' = [string[]]@('enabled_repositories', 'new_flag') })

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        Get-PlanAction -Plan $plan -Action 'SetActionsPermissions' | Should -BeNullOrEmpty
        Get-PlanAction -Plan $plan -Action 'SetSelectedActions' | Should -BeNullOrEmpty
    }

    It 'still plans the selection when GitHub already has allowed_actions selected' {
        $state = Get-MatchingTestGitHubOrgState
        $state.SelectedActions.github_owned_allowed = $false
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}/actions/permissions' = [string[]]@('enabled_repositories', 'new_flag') })

        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)

        Get-PlanAction -Plan $plan -Action 'SetActionsPermissions' | Should -BeNullOrEmpty
        Get-PlanAction -Plan $plan -Action 'SetSelectedActions' | Should -Not -BeNullOrEmpty
    }

    It 'explains why it plans no change to the section' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Workflow.default_workflow_permissions = 'write'
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}/actions/permissions/workflow' = [string[]]@('default_workflow_permissions', 'new_flag') })

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings | Should -Be @("GET orgs/contoso/actions/permissions/workflow returned the field 'new_flag', which this tool does not know. The engine replaces workflow permissions as a whole and could reset it, so it plans no change to it until it is a row or listed under Fields of GET /orgs/{org}/actions/permissions/workflow in engine/api-endpoints.psd1.")
    }

    It 'says nothing about a skipped change when the section already matches' {
        $state = Get-MatchingTestGitHubOrgState
        $state | Add-Member -NotePropertyName ResponseFields -NotePropertyValue ([ordered]@{ '/orgs/{org}/actions/permissions/workflow' = [string[]]@('default_workflow_permissions', 'new_flag') })

        $warnings = @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @())

        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike "GET orgs/contoso/actions/permissions/workflow returned the field 'new_flag', which this tool does not know: add a row for it,*"
    }
}

Describe 'Get-GitHubOrgWarningItem' {
    It 'returns the same warnings as text, in order' {
        $state = Get-DefaultTestGitHubOrgState
        $state.Settings.two_factor_requirement_enabled = $false
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'settings.is_verified' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'FieldMissing'; HttpStatus = $null; Source = 'GET orgs/contoso .is_verified'; Reason = 'GET orgs/contoso answered without the field is_verified' }
            })
        $config = Get-TestGitHubOrgConfig
        $plan = @(Get-GitHubOrgPlan -Config $config -CurrentState $state)

        $items = InModuleScope GitHubOrg -Parameters @{ Config = $config; State = $state; Plan = $plan } {
            param($Config, $State, $Plan)
            @(Get-GitHubOrgWarningItem -Config $Config -CurrentState $State -Plan $Plan)
        }

        $expected = @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan $plan)
        $expected.Count | Should -BeGreaterThan 2
        @($items | ForEach-Object { $_.Text }) | Should -Be $expected
    }

    It 'tags a warning of <Source> with the page <Page>' -ForEach @(
        @{ Source = 'Get-CodeSecurityWarning'; Page = 'security_products' }
        @{ Source = 'Get-RulesetWarning'; Page = 'rules' }
        @{ Source = 'Get-CopilotSeatWarning'; Page = 'copilot/seat_management' }
        @{ Source = 'Get-BudgetWarning'; Page = 'billing/budgets' }
        @{ Source = 'Get-WebhookWarning'; Page = 'hooks' }
        @{ Source = 'Get-AppWarning'; Page = 'installations' }
        @{ Source = 'Get-OwnerWarning'; Page = $null }
        @{ Source = 'Get-OutsideCollaboratorWarning'; Page = $null }
        @{ Source = 'Get-InvitationWarning'; Page = $null }
    ) {
        $item = InModuleScope GitHubOrg -Parameters @{ Source = $Source; Config = (Get-TestGitHubOrgConfig); State = (Get-MatchingTestGitHubOrgState) } {
            param($Source, $Config, $State)
            Mock $Source { 'probe warning' }
            @(Get-GitHubOrgWarningItem -Config $Config -CurrentState $State -Plan @() | Where-Object { $_.Text -eq 'probe warning' })
        }

        $item.Count | Should -Be 1
        $item[0].Page | Should -Be $Page
        $item[0].Path | Should -BeNullOrEmpty
    }

    It 'tags a checked mismatch and an observation with their row' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.two_factor_requirement_enabled = $false
        $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                'settings.is_verified' = [pscustomobject]@{ Status = 'NotObserved'; ReasonCode = 'FieldMissing'; HttpStatus = $null; Source = 'GET orgs/contoso .is_verified'; Reason = 'GET orgs/contoso answered without the field is_verified' }
            })

        $items = InModuleScope GitHubOrg -Parameters @{ State = $state; Config = (Get-TestGitHubOrgConfig) } {
            param($State, $Config)
            @(Get-GitHubOrgWarningItem -Config $Config -CurrentState $State -Plan @())
        }

        $mismatch = @($items | Where-Object { $_.Text -like 'two_factor_requirement_enabled is false*' })[0]
        $mismatch.Path | Should -Be 'settings.two_factor_requirement_enabled'
        $mismatch.Page | Should -Be 'security'
        $observation = @($items | Where-Object { $_.Text -like 'settings.is_verified is not observed*' })[0]
        $observation.Path | Should -Be 'settings.is_verified'
        $observation.Page | Should -Be 'domains'
    }

    It 'tags no page on an unknown response field or the SHA pinning notice' {
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.sha_pinning_required = $false
        $config = Get-TestGitHubOrgConfig
        $plan = @(Get-GitHubOrgPlan -Config $config -CurrentState $state)
        $items = InModuleScope GitHubOrg -Parameters @{ State = $state; Config = $config; Plan = $plan } {
            param($State, $Config, $Plan)
            Mock Get-UnknownResponseField { [ordered]@{ '/orgs/{org}' = @('new_field') } }
            @(Get-GitHubOrgWarningItem -Config $Config -CurrentState $State -Plan $Plan)
        }

        $tagged = @($items | Where-Object { $_.Text -like 'GET orgs/contoso returned the field*' -or $_.Text -eq (InModuleScope GitHubOrg { $script:ShaPinningWarning }) })
        $tagged.Count | Should -Be 2
        @($tagged | Where-Object { $_.Page -or $_.Path }) | Should -BeNullOrEmpty
    }
}

Describe 'Get-ManualSummary' {
    It 'counts the manual settings: <Expected>' -ForEach @(
        @{ Count = 2; Expected = 'Manual: 2 settings have no API read; this run did not check them. List them: rerun with -WhatIf -ManualChecklist.' }
        @{ Count = 1; Expected = 'Manual: 1 setting has no API read; this run did not check them. List them: rerun with -WhatIf -ManualChecklist.' }
    ) {
        $summary = InModuleScope GitHubOrg -Parameters @{ Count = $Count } {
            $saved = $script:SettingDefinitions
            try {
                $script:SettingDefinitions = @(@($saved | Where-Object { $_.Mode -ne 'manual' }) + @($saved | Where-Object { $_.Mode -eq 'manual' } | Select-Object -First $Count))
                Get-ManualSummary
            }
            finally {
                $script:SettingDefinitions = $saved
            }
        }

        $summary | Should -Be $Expected
    }
}

Describe 'Get-ManualChecklist' {
    It 'says so when no setting needs a manual check' {
        $lines = InModuleScope GitHubOrg -Parameters @{ Config = Get-TestGitHubOrgConfig } {
            $saved = $script:SettingDefinitions
            try {
                $script:SettingDefinitions = @($saved | Where-Object { $_.Mode -ne 'manual' })
                @(Get-ManualChecklist -Config $Config)
            }
            finally {
                $script:SettingDefinitions = $saved
            }
        }

        $lines | Should -Be @('No settings need a manual check.')
    }
}
