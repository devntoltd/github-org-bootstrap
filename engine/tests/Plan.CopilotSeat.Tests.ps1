BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    function Get-TestSeatWarning {
        # The warnings of the engine about Copilot seats.
        @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Where-Object { $_ -like '*seat*' })
    }
}

Describe 'Get-GitHubOrgPlan: Copilot seats' {
    BeforeEach {
        $script:config = Get-TestGitHubOrgConfig
        $script:state = Get-MatchingTestGitHubOrgState
    }

    It 'plans nothing when every login of the config holds a seat, in any case' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @(Get-TestCopilotSeat -Login 'OctoCat')

        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }

    It 'buys the seats of the logins without one in one action that names the cost' {
        $script:config.copilotSeats.selected_usernames = @('octocat', 'hubot', 'monalisa')

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'AddCopilotSeats'
        $plan[0].Target | Should -Be 'contoso'
        $plan[0].Method | Should -Be 'POST'
        $plan[0].Endpoint | Should -Be 'orgs/contoso/copilot/billing/selected_users'
        @($plan[0].Body.selected_usernames) | Should -Be @('hubot', 'monalisa')
        $plan[0].Summary | Should -Be '+ buy Copilot seats for hubot, monalisa: 2 x $19 a month (business)'
    }

    It 'names the price of the <PlanType> plan' -ForEach @(
        @{ PlanType = 'enterprise'; Cost = '1 x $39 a month (enterprise)' }
        @{ PlanType = 'unknown'; Cost = '1 x the price of the unknown plan' }
    ) {
        $script:config.copilotSeats.selected_usernames = @('octocat', 'hubot')
        $script:state.CopilotSeats.PlanType = $PlanType

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan[0].Summary | Should -BeLike "*: $Cost"
    }

    It 'buys the seats of a team for the members without one' {
        $script:config.copilotSeats.selected_teams = @('reviewers')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ reviewers = @('octocat', 'hubot') }

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'AddCopilotTeam'
        $plan[0].Target | Should -Be 'reviewers'
        $plan[0].Method | Should -Be 'POST'
        $plan[0].Endpoint | Should -Be 'orgs/contoso/copilot/billing/selected_teams'
        @($plan[0].Body.selected_teams) | Should -Be @('reviewers')
        $plan[0].Summary | Should -Be "+ buy Copilot seats for team 'reviewers' (hubot): 1 x `$19 a month (business)"
    }

    It 'plans nothing for a team whose members all hold a seat, or that has no members' {
        $script:config.copilotSeats.selected_teams = @('reviewers', 'empty')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ reviewers = @('octocat'); empty = @() }

        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }

    It 'plans nothing for a team that does not exist' {
        $script:config.copilotSeats.selected_teams = @('missing')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ missing = $null }

        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }

    It 'counts a seat once for a login and the teams that hold it' {
        $script:config.copilotSeats.selected_usernames = @('octocat', 'hubot')
        $script:config.copilotSeats.selected_teams = @('reviewers', 'platform')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ reviewers = @('hubot', 'monalisa'); platform = @('monalisa') }

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan.Action | Should -Be @('AddCopilotSeats', 'AddCopilotTeam')
        $plan[1].Target | Should -Be 'reviewers'
        $plan[1].Summary | Should -BeLike '*(monalisa): 1 x *'
    }

    It 'comes after the budgets, which limit what the seats use' {
        $script:config.copilotSeats.selected_usernames = @('octocat', 'hubot')
        $script:state.Budgets = @()

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        (Get-PlanIndex -Plan $plan -Action 'AddCopilotSeats' -Target 'contoso') | Should -BeGreaterThan (Get-PlanIndex -Plan $plan -Action 'CreateBudget' -Target 'ai_credits')
    }

    It 'plans nothing without a plan' {
        $script:state.CopilotSeats = $null

        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }

    It 'plans nothing while the seat management is <SeatManagement>' -ForEach @(
        @{ SeatManagement = 'assign_all' }
        @{ SeatManagement = 'disabled' }
    ) {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @() -SeatManagement $SeatManagement

        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }
}

Describe 'Get-GitHubOrgWarning: Copilot seats' {
    BeforeEach {
        $script:config = Get-TestGitHubOrgConfig
        $script:state = Get-MatchingTestGitHubOrgState
    }

    It 'reports nothing when the seats match the config' {
        (Get-TestSeatWarning).Count | Should -Be 0
    }

    It 'reports a seat that is not in the config' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @((Get-TestCopilotSeat -Login 'octocat'), (Get-TestCopilotSeat -Login 'mallory'))

        Get-TestSeatWarning | Should -Be @("Copilot seat of 'mallory' is not in copilotSeats, and it is paid every month. If it is expected, add it to copilotSeats; if not, remove it at https://github.com/organizations/contoso/settings/copilot/access.")
    }

    It 'names the team that gives a seat outside the config' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @((Get-TestCopilotSeat -Login 'octocat'), (Get-TestCopilotSeat -Login 'mallory' -Team 'contractors'))

        $warnings = @(Get-TestSeatWarning)

        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike "*'mallory' (through team 'contractors')*"
    }

    It 'accepts a seat of a member of a team of the config, in any case' {
        $script:config.copilotSeats.selected_teams = @('reviewers')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @((Get-TestCopilotSeat -Login 'octocat'), (Get-TestCopilotSeat -Login 'HUBOT')) -Teams @{ reviewers = @('hubot') }

        (Get-TestSeatWarning).Count | Should -Be 0
    }

    It 'says nothing about a seat outside the config that is being cancelled' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @((Get-TestCopilotSeat -Login 'octocat'), (Get-TestCopilotSeat -Login 'mallory' -PendingCancellation '2026-12-01'))

        (Get-TestSeatWarning).Count | Should -Be 0
    }

    It 'reports a seat of the config that is being cancelled' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @(Get-TestCopilotSeat -Login 'octocat' -PendingCancellation '2026-12-01')

        Get-TestSeatWarning | Should -Be @("Copilot seat of 'octocat' ends on 2026-12-01 although it is in copilotSeats. If it should stay, assign it again at https://github.com/organizations/contoso/settings/copilot/access; if not, remove it from copilotSeats.")
    }

    It 'reports a seat management other than selected members' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -SeatManagement 'assign_all'

        Get-TestSeatWarning | Should -Be @("Copilot seats of contoso are managed as 'assign_all', not 'assign_selected', so the engine buys no seat; 'assign_all' pays a seat for every member. Choose selected members at https://github.com/organizations/contoso/settings/copilot/access.")
    }

    It 'reports a team of the config that does not exist' {
        $script:config.copilotSeats.selected_teams = @('missing')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ missing = $null }

        Get-TestSeatWarning | Should -Be @("copilotSeats.selected_teams names 'missing', but contoso has no such team, so it gets no seats. Create the team, or remove it from the config.")
    }

    It 'reports seats in the config without a plan' {
        $script:state.CopilotSeats = $null

        Get-TestSeatWarning | Should -Be @('copilotSeats lists seats, but contoso has no Copilot plan with seat management set up, so the engine buys none. GitHub has no API for the first seat: buy Copilot Business and assign one at https://github.com/organizations/contoso/settings/copilot/access.')
    }

    It 'reports nothing without a plan when the config lists no seats' {
        $script:config.copilotSeats.selected_usernames = @()
        $script:state.CopilotSeats = $null

        (Get-TestSeatWarning).Count | Should -Be 0
    }
}
