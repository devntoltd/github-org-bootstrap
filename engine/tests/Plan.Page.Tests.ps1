BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    function Get-TestPageWalk {
        # The walk of a config and a state, with the plan and the warnings the run computes from them.
        param(
            [Parameter(Mandatory)][object]$Config,
            [Parameter(Mandatory)][object]$State,
            [hashtable]$Unknown = @{}
        )

        InModuleScope GitHubOrg -Parameters @{ Config = $Config; State = $State; Unknown = $Unknown } {
            param($Config, $State, $Unknown)
            if ($Unknown.Count -gt 0) {
                $script:ProbeUnknown = [ordered]@{} + $Unknown
                Mock Get-UnknownResponseField { $script:ProbeUnknown }
            }
            $today = [datetime]::UtcNow.Date
            $plan = @(Get-GitHubOrgPlan -Config $Config -CurrentState $State)
            $report = Get-RecommendationReport -Config $Config -Shape (Get-GitHubOrgConfigShape) -Today $today
            $warnings = @(Get-SettingPageWalkWarning -Config $Config -CurrentState $State -Plan $plan -Recommendations @($report.Warnings) -Reviewers @())
            $walk = Get-SettingPageWalk -Config $Config -CurrentState $State -Plan $plan -Warnings $warnings -Today $today
            [pscustomobject]@{ Walk = $walk; Plan = $plan; Warnings = $warnings; Texts = @(@($report.Warnings) + @(Get-GitHubOrgWarning -Config $Config -CurrentState $State -Plan $plan)) }
        }
    }

    function Get-TestWalkRow {
        # The row of a page of the walk by the config path of its setting.
        param([Parameter(Mandatory)][object]$Walk, [Parameter(Mandatory)][string]$Path)

        @($Walk.Pages | ForEach-Object { $_.Rows } | Where-Object { $_.Path -eq $Path })[0]
    }
}

Describe 'Get-SettingPageWalk' {
    It 'marks an apply row <Mark> when <Case>' -ForEach @(
        @{ Case = 'it matches'; Mark = 'ok'; Path = 'settings.default_repository_permission'; Default = $false; Unknown = @{}; Note = $null }
        @{ Case = 'a planned action changes it'; Mark = 'apply'; Path = 'settings.default_repository_permission'; Default = $true; Unknown = @{}; Note = $null }
        @{ Case = 'its PUT section is skipped'; Mark = 'DIFF'; Path = 'actions.retention.days'; Default = $true; Unknown = @{ '/orgs/{org}/actions/permissions/artifact-and-log-retention' = @('new_field') }; Note = 'not applied this run: GitHub returned fields the engine does not know (see "Not on a settings page")' }
        @{ Case = 'its section was not read and a planned action sets it'; Mark = 'apply'; Path = 'actions.selected.verified_allowed'; Default = $true; Unknown = @{}; Note = $null }
    ) {
        $state = if ($Default) { Get-DefaultTestGitHubOrgState } else { Get-MatchingTestGitHubOrgState }

        $row = Get-TestWalkRow -Walk (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state -Unknown $Unknown).Walk -Path $Path

        $row.Mark | Should -Be $Mark
        if ($Note) { $row.Note | Should -Be $Note }
    }

    It 'marks an apply row n/a when its section was not read and nothing sets it' {
        # The config selects, GitHub does not yet, and an unknown field keeps the actions PUT, and so the selection,
        # out of this run.
        $state = Get-MatchingTestGitHubOrgState
        $state.Actions.allowed_actions = 'all'
        $state.SelectedActions = $null

        $row = Get-TestWalkRow -Walk (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state -Unknown @{ '/orgs/{org}/actions/permissions' = @('new_field') }).Walk -Path 'actions.selected.verified_allowed'

        $row.Mark | Should -Be 'n/a'
        $row.Note | Should -BeLike '*not read*'
    }

    It 'shows a setting without a page that the plan changes in the last block' {
        # members_can_create_repositories has no control of its own; the PATCH of the organization settings changes it.
        $result = Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-DefaultTestGitHubOrgState)
        $other = InModuleScope GitHubOrg -Parameters @{ Other = $result.Walk.Other } { param($Other) @(Format-SettingPageWalkOther -Other $Other) }

        $row = @($result.Walk.Other.Rows | Where-Object { $_.Path -eq 'settings.members_can_create_repositories' })[0]
        $row.Mark | Should -Be 'apply'
        @($other | Where-Object { $_ -like '    `[apply`]  settings.members_can_create_repositories: false (now true; the engine sets it after the confirmation)' }).Count | Should -Be 1
    }

    It 'marks a row whose DependsOn field is false in the config n/a while its PUT is skipped' {
        # GitHub keeps require_approval_for_fork_pr_workflows false while fork runs are off.
        $state = Get-MatchingTestGitHubOrgState
        $state.PrivateForkPullRequests.require_approval_for_fork_pr_workflows = $false

        $row = Get-TestWalkRow -Walk (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state -Unknown @{ '/orgs/{org}/actions/permissions/fork-pr-workflows-private-repos' = @('new_field') }).Walk -Path 'actions.privateForkPullRequests.require_approval_for_fork_pr_workflows'

        $row.Mark | Should -Be 'n/a'
        $row.Note | Should -Be 'not applied while run_workflows_from_fork_pull_requests is false: GitHub keeps it as it is'
    }

    It 'marks a row whose DependsOn field is false in the config n/a while another field plans the PUT' {
        # The PUT sends the field back as GitHub has it, so the row is no change.
        $state = Get-MatchingTestGitHubOrgState
        $state.PrivateForkPullRequests.require_approval_for_fork_pr_workflows = $false
        $state.PrivateForkPullRequests.send_secrets_and_variables = $true

        $result = Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state
        $row = Get-TestWalkRow -Walk $result.Walk -Path 'actions.privateForkPullRequests.require_approval_for_fork_pr_workflows'

        (Get-PlanAction -Plan $result.Plan -Action 'SetPrivateForkPullRequestWorkflows').Body.require_approval_for_fork_pr_workflows | Should -BeFalse
        $row.Mark | Should -Be 'n/a'
        $row.Note | Should -BeLike 'not applied while run_workflows_from_fork_pull_requests is false*'
    }

    It 'marks a row of a section the config sets to null n/a, without a recommendation' {
        # allowed_actions moves from selected to all: the config has no selection, GitHub still holds the old one.
        $config = Get-TestGitHubOrgConfig
        $config.actions.allowed_actions = 'all'
        $config.actions.selected = $null

        $row = Get-TestWalkRow -Walk (Get-TestPageWalk -Config $config -State (Get-MatchingTestGitHubOrgState)).Walk -Path 'actions.selected.verified_allowed'

        $row.Mark | Should -Be 'n/a'
        $row.Note | Should -Be 'not set by the config: its section is null'
        @($row.Printed) | Should -BeNullOrEmpty
    }

    It 'shows the change of a setting without a page once' {
        # The only difference: its row stands for the action, which is not repeated.
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_create_repositories = $true

        $result = Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state

        @($result.Walk.Other.Rows | ForEach-Object { $_.Path }) | Should -Be @('settings.members_can_create_repositories')
        @($result.Plan | Where-Object { $_.Action -eq 'UpdateOrganizationSettings' }).Count | Should -Be 1
        $result.Walk.Other.Actions | Should -BeNullOrEmpty
    }

    It 'names a control without a label by its group' {
        $row = Get-TestWalkRow -Walk (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-MatchingTestGitHubOrgState)).Walk -Path 'settings.default_repository_permission'

        $row.Control | Should -Be 'Base permissions'
    }

    It 'prints a warning of a row that the mark does not tell, and stops there' {
        # An expired exception on a setting that matches the config: the row is ok, the warning is not.
        $config = Get-TestGitHubOrgConfig
        $config.settings.deploy_keys_enabled_for_repositories = $true
        $config.exceptions = @([pscustomobject]@{ field = 'settings.deploy_keys_enabled_for_repositories'; reason = 'probe'; expiresOn = '2000-01-01' })
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.deploy_keys_enabled_for_repositories = $true

        $result = Get-TestPageWalk -Config $config -State $state
        $page = $result.Walk.Pages | Where-Object { $_.Path -eq 'deploy_keys' }
        $lines = InModuleScope GitHubOrg -Parameters @{ Page = $page } { param($Page) @(Format-SettingPageWalkPage -Page $Page -Index 1 -Total 1) }

        $page.Stop | Should -BeTrue
        $warning = @($result.Texts | Where-Object { $_ -like 'settings.deploy_keys_enabled_for_repositories *expired*' })
        $warning.Count | Should -Be 1
        @($lines | Where-Object { $_.Contains($warning[0]) }).Count | Should -Be 1
    }

    It 'marks a check row <Mark> when <Case>' -ForEach @(
        @{ Case = 'it matches'; Mark = 'ok'; Observation = $null }
        @{ Case = 'it differs'; Mark = 'DIFF'; Observation = $null }
        @{ Case = 'it was not observed'; Mark = '?'; Observation = 'NotObserved' }
        @{ Case = 'it does not apply'; Mark = 'n/a'; Observation = 'NotApplicable' }
    ) {
        $state = Get-MatchingTestGitHubOrgState
        if ($Mark -eq 'DIFF') { $state.Settings.two_factor_requirement_enabled = $false }
        if ($Observation) {
            $state | Add-Member -NotePropertyName Observations -NotePropertyValue ([ordered]@{
                    'settings.two_factor_requirement_enabled' = [pscustomobject]@{ Status = $Observation; ReasonCode = 'X'; HttpStatus = $null; Source = 'GET orgs/contoso'; Reason = 'the probe reason' }
                })
        }

        $row = Get-TestWalkRow -Walk (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state).Walk -Path 'settings.two_factor_requirement_enabled'

        $row.Mark | Should -Be $Mark
        if ($Mark -eq 'DIFF') {
            $row.Current | Should -Be 'false'
            $row.Expected | Should -Be 'true'
        }
        if ($Observation) { $row.Note | Should -BeLike '*the probe reason*' }
    }

    It 'never marks a manual row other than set' {
        $walk = (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-MatchingTestGitHubOrgState)).Walk
        $manual = InModuleScope GitHubOrg { @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'manual' } | ForEach-Object { Get-SettingPath -Definition $_ }) }

        $rows = @($walk.Pages | ForEach-Object { $_.Rows } | Where-Object { $_.Path -in $manual })

        $rows.Count | Should -Be $manual.Count
        @($rows | Where-Object { $_.Mark -ne 'set' }) | Should -BeNullOrEmpty
        $walk.ManualCount | Should -Be $manual.Count
    }

    It 'notes the recommendation and the waiver' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.members_can_delete_repositories = $true
        $config.settings.members_can_create_teams = $true
        $config.exceptions = @([pscustomobject]@{ field = 'settings.members_can_create_teams'; reason = 'probe'; expiresOn = '2099-01-01' })
        $state = Get-MatchingTestGitHubOrgState
        $state.Settings.members_can_delete_repositories = $true
        $state.Settings.members_can_create_teams = $true

        $walk = (Get-TestPageWalk -Config $config -State $state).Walk

        (Get-TestWalkRow -Walk $walk -Path 'settings.members_can_delete_repositories').Note | Should -Be 'recommended false'
        (Get-TestWalkRow -Walk $walk -Path 'settings.members_can_create_teams').Note | Should -Be 'waived until 2099-01-01'
    }

    It 'never shows the value of a sensitive row' {
        $row = InModuleScope GitHubOrg {
            $script:SavedDefinitions = $script:SettingDefinitions
            try {
                $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                        if ((Get-SettingPath -Definition $_) -eq 'settings.email') { $r = $_.Clone(); $r.Sensitive = $true; $r } else { $_ }
                    })
                $config = [pscustomobject]@{ organization = 'contoso'; settings = [pscustomobject]@{ email = 'secret-7f3a@contoso.com' }; exceptions = @() }
                $state = [pscustomobject]@{ Settings = [ordered]@{ email = 'other-9c2e@contoso.com' } }
                $walk = Get-SettingPageWalk -Config $config -CurrentState $state -Plan @() -Warnings @() -Today ([datetime]::UtcNow.Date)
                @($walk.Pages | ForEach-Object { $_.Rows } | Where-Object { $_.Path -eq 'settings.email' })[0]
            }
            finally {
                $script:SettingDefinitions = $script:SavedDefinitions
            }
        }

        $row.Expected | Should -Be 'a value that is not shown'
        "$($row.Current) $($row.Note)" | Should -Not -BeLike '*9c2e*'
        "$($row.Expected) $($row.Note)" | Should -Not -BeLike '*7f3a*'
    }

    It 'lists the rows of a page in its Order' {
        $walk = (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-MatchingTestGitHubOrgState)).Walk
        $order = InModuleScope GitHubOrg { (Get-SettingPage -Path 'member_privileges').Order }

        @(($walk.Pages | Where-Object { $_.Path -eq 'member_privileges' }).Rows | ForEach-Object { $_.Path }) | Should -Be $order
    }

    It 'shows an area page from its actions and warnings' {
        $state = Get-DefaultTestGitHubOrgState

        $result = Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State $state
        $rules = $result.Walk.Pages | Where-Object { $_.Path -eq 'rules' }

        $rules.Stop | Should -BeTrue
        @($rules.AreaLines | Where-Object { $_.Mark -eq 'apply' }).Count | Should -Be @($result.Plan | Where-Object { $_.Action -in @('CreateRuleset', 'UpdateRuleset') }).Count
        @($rules.AreaLines | Where-Object { $_.Mark -eq 'apply' })[0].Text | Should -Be @($result.Plan | Where-Object { $_.Action -eq 'CreateRuleset' })[0].Summary
    }

    It 'shows an area page with nothing to do as managed' {
        $walk = (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-MatchingTestGitHubOrgState)).Walk
        $hooks = $walk.Pages | Where-Object { $_.Path -eq 'hooks' }

        $hooks.Stop | Should -BeFalse
        @($hooks.AreaLines).Count | Should -Be 1
        $hooks.AreaLines[0].Mark | Should -Be 'ok'
        $hooks.AreaLines[0].Text | Should -Be 'managed by the engine, no change planned, no warning'
    }

    It 'keeps every warning and every action of the run' {
        # Review Focus 4: a warning on no settings page (the single owner, an expired exception) still shows.
        $config = Get-TestGitHubOrgConfig
        $config.settings.members_can_create_teams = $true
        $config.exceptions = @([pscustomobject]@{ field = 'settings.members_can_create_teams'; reason = 'probe'; expiresOn = '2000-01-01' })
        $state = Get-DefaultTestGitHubOrgState
        $state.Settings.two_factor_requirement_enabled = $false

        $result = Get-TestPageWalk -Config $config -State $state
        $walk = $result.Walk

        $shown = @(
            $walk.Pages | ForEach-Object { $_.Rows } | ForEach-Object { $_.Warnings }
            $walk.Pages | ForEach-Object { $_.AreaLines } | Where-Object { $_.Mark -eq 'DIFF' } | ForEach-Object { $_.Text }
            $walk.Other.Warnings | ForEach-Object { $_.Text }
        )
        @($shown | Sort-Object) | Should -Be @($result.Texts | Sort-Object)
        $actions = @(
            $walk.Pages | ForEach-Object { $_.Rows } | ForEach-Object { $_.Actions }
            $walk.Pages | ForEach-Object { $_.AreaLines } | Where-Object { $_.Mark -eq 'apply' } | ForEach-Object { $_.Text }
            $walk.Other.Actions | ForEach-Object { $_.Summary }
        ) | Select-Object -Unique
        @($actions | Sort-Object) | Should -Be @($result.Plan | ForEach-Object { $_.Summary } | Sort-Object)
        @((Get-TestWalkRow -Walk $walk -Path 'settings.members_can_create_teams').Warnings | Where-Object { $_ -like '*expired*' }).Count | Should -Be 1
        $pageless = @($result.Warnings | Where-Object { -not $_.Page -and -not $_.Path })
        $pageless.Count | Should -BeGreaterThan 0
        $other = @($walk.Other.Warnings | ForEach-Object { $_.Text })
        foreach ($warning in $pageless) { $other | Should -Contain $warning.Text }
    }

    It 'does not stop on a page with nothing to do' {
        $walk = (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-MatchingTestGitHubOrgState)).Walk

        ($walk.Pages | Where-Object { $_.Path -eq 'deploy_keys' }).Stop | Should -BeFalse
        ($walk.Pages | Where-Object { $_.Path -eq 'security' }).Stop | Should -BeTrue
    }

    It 'shows only managed pages, each once, in menu order' {
        $walk = (Get-TestPageWalk -Config (Get-TestGitHubOrgConfig) -State (Get-MatchingTestGitHubOrgState)).Walk
        $expected = InModuleScope GitHubOrg {
            @($script:SettingPages | Where-Object { $_.Area -or @(Get-PageRow -Page $_).Count -gt 0 } | ForEach-Object { $_.Path })
        }

        @($walk.Pages | ForEach-Object { $_.Path }) | Should -Be $expected
    }
}

Describe 'Format-SettingPageWalk' {
    It 'formats a page' {
        $lines = InModuleScope GitHubOrg {
            $page = [pscustomobject]@{
                Path = 'probe'; Label = 'Probe > Page'; Url = 'https://github.com/organizations/contoso/settings/probe'; Area = $null; ReviewedOn = '2026-11-09'; Stop = $true; AreaLines = @()
                Rows = @(
                    [pscustomobject]@{ Group = 'First group'; Control = 'Checked box'; Mark = 'ok'; Expected = 'true'; Current = 'true'; Note = $null; Why = 'ok reason' }
                    [pscustomobject]@{ Group = 'First group'; Control = 'Applied box'; Mark = 'apply'; Expected = 'false'; Current = 'true'; Note = $null; Why = 'apply reason' }
                    [pscustomobject]@{ Group = 'Second group'; Control = 'Checked menu'; Mark = 'DIFF'; Expected = 'block ("Blocked")'; Current = 'allow'; Note = 'recommended block'; Why = 'diff reason' }
                    [pscustomobject]@{ Group = 'Second group'; Control = 'Unread box'; Mark = '?'; Expected = 'true'; Current = $null; Note = 'GET answered 403'; Why = 'unread reason' }
                    [pscustomobject]@{ Group = 'Second group'; Control = 'Absent box'; Mark = 'n/a'; Expected = 'true'; Current = $null; Note = 'no Copilot plan; recommended false'; Why = 'absent reason' }
                    [pscustomobject]@{ Group = 'Third group'; Control = 'Manual box'; Mark = 'set'; Expected = 'false'; Current = $null; Note = $null; Why = 'manual reason' }
                )
            }
            Format-SettingPageWalkPage -Page $page -Index 3 -Total 29
        }

        $lines | Should -Be @(
            '[3/29] Probe > Page  https://github.com/organizations/contoso/settings/probe  (UI read 2026-11-09)'
            '  First group'
            '    [ok]     Checked box: true'
            '    [apply]  Applied box: false (now true; the engine sets it after the confirmation)'
            '  Second group'
            '    [DIFF]   Checked menu: block ("Blocked") (now allow; recommended block)'
            '             diff reason'
            '    [?]      Unread box: true (GET answered 403)'
            '    [n/a]    Absent box: true (no Copilot plan; recommended false)'
            '  Third group'
            '    [set]    Manual box: false'
            '             manual reason'
        )
    }

    It 'formats a page with nothing to do in two lines' {
        $lines = InModuleScope GitHubOrg {
            $page = [pscustomobject]@{ Path = 'probe'; Label = 'Probe'; Url = 'https://x/probe'; Area = $null; ReviewedOn = $null; Stop = $false; AreaLines = @()
                Rows = @([pscustomobject]@{ Group = 'G'; Control = 'C'; Mark = 'ok'; Expected = 'true'; Current = 'true'; Note = $null; Why = 'w' }, [pscustomobject]@{ Group = 'G'; Control = 'D'; Mark = 'ok'; Expected = 'true'; Current = 'true'; Note = $null; Why = 'w' })
            }
            Format-SettingPageWalkPage -Page $page -Index 1 -Total 2
        }

        $lines | Should -Be @('[1/2] Probe  https://x/probe', '  [ok] 2 settings match')
    }

    It 'counts only matching rows on a page with nothing to do, and keeps the reasons of the others' {
        $lines = InModuleScope GitHubOrg {
            $page = [pscustomobject]@{ Path = 'probe'; Label = 'Probe'; Url = 'https://x/probe'; Area = $null; ReviewedOn = $null; Stop = $false; AreaLines = @()
                Rows = @(
                    [pscustomobject]@{ Group = 'G'; Control = 'C'; Mark = 'ok'; Expected = 'true'; Current = 'true'; Note = $null; Why = 'w' }
                    [pscustomobject]@{ Group = 'H'; Control = 'D'; Mark = 'n/a'; Expected = '<none>'; Current = $null; Note = 'not set by the config: its section is null'; Why = 'w' }
                )
            }
            Format-SettingPageWalkPage -Page $page -Index 1 -Total 2
        }

        $lines | Should -Be @(
            '[1/2] Probe  https://x/probe'
            '  [ok] 1 settings match'
            '  H'
            '    [n/a]    D: <none> (not set by the config: its section is null)'
        )
    }

    It 'starts with the time of the read' {
        InModuleScope GitHubOrg { Format-SettingPageWalkStart -ReadAt ([datetime]::SpecifyKind([datetime]::new(2026, 11, 9, 14, 3, 12), 'Utc')) } |
            Should -Be 'Page walk of the state read at 2026-11-09 14:03:12 UTC. The marks show that read, not the pages now.'
    }

    It 'starts without a time for a state without one' {
        InModuleScope GitHubOrg { Format-SettingPageWalkStart -ReadAt $null } |
            Should -Be 'Page walk of the state read by this run. The marks show that read, not the pages now.'
    }

    It 'ends with the manual count' {
        InModuleScope GitHubOrg { Format-SettingPageWalkEnd -ManualCount 68 } |
            Should -Be '68 manual settings were not checked by this run; the walk records nothing.'
    }
}
