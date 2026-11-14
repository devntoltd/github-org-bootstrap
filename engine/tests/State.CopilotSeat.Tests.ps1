BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgState: Copilot seats' {
    BeforeEach {
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
        $script:config = Get-TestGitHubOrgConfig
        $script:state = Get-MatchingTestGitHubOrgState
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'reads the plan, the seat management and the seats of every page' {
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Seats @(
            Get-TestCopilotSeat -Login 'octocat'
            Get-TestCopilotSeat -Login 'hubot' -Team 'reviewers' -PendingCancellation '2026-12-01'
        )
        $routes = Get-TestGhRoute -State $script:state
        $seats = (Get-TestCopilotSeatResource -CopilotSeats $script:state.CopilotSeats)['orgs/contoso/copilot/billing/seats'].seats
        $routes['GET orgs/contoso/copilot/billing/seats?per_page=100'] = Get-TestGhObjectPagesResponse -PageSize 1 -Property seats -Items $seats
        Register-TestGhRoute -Route $routes

        $copilot = (Get-GitHubOrgState -Config $script:config).CopilotSeats

        $copilot.PlanType | Should -Be 'business'
        $copilot.SeatManagement | Should -Be 'assign_selected'
        $copilot.Total | Should -Be 2
        $copilot.Seats.Login | Should -Be @('octocat', 'hubot')
        $copilot.Seats[0].Team | Should -BeNullOrEmpty
        $copilot.Seats[0].PendingCancellation | Should -BeNullOrEmpty
        $copilot.Seats[1].Team | Should -Be 'reviewers'
        $copilot.Seats[1].PendingCancellation | Should -Be '2026-12-01'
    }

    It 'reads the members of a team of the config' {
        $script:config.copilotSeats.selected_teams = @('reviewers')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ reviewers = @('octocat', 'hubot') }
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        (Get-GitHubOrgState -Config $script:config).CopilotSeats.Teams['reviewers'] | Should -Be @('octocat', 'hubot')
    }

    It 'keeps an empty team apart from a team that does not exist' {
        $script:config.copilotSeats.selected_teams = @('empty', 'missing')
        $script:state.CopilotSeats = Get-TestCopilotSeatState -Teams @{ empty = @() }
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        $teams = (Get-GitHubOrgState -Config $script:config).CopilotSeats.Teams

        $null -eq $teams['empty'] | Should -BeFalse
        @($teams['empty']).Count | Should -Be 0
        $teams.ContainsKey('missing') | Should -BeTrue
        $null -eq $teams['missing'] | Should -BeTrue
    }

    It 'stops when the members of a team cannot be read' {
        $script:config.copilotSeats.selected_teams = @('reviewers')
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET orgs/contoso/teams/reviewers/members?per_page=100'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*orgs/contoso/teams/reviewers/members*HTTP 502*'
    }

    It 'has no plan when GitHub answers 404' {
        $routes = Get-TestGhRoute -State $script:state
        $routes.Remove('GET orgs/contoso/copilot/billing')
        $routes.Remove('GET orgs/contoso/copilot/billing/seats?per_page=100')
        Register-TestGhRoute -Route $routes

        (Get-GitHubOrgState -Config $script:config).CopilotSeats | Should -BeNullOrEmpty
    }

    It 'has no plan when GitHub answers an unconfigured seat management' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET orgs/contoso/copilot/billing'] = Get-TestGhResponse -Body (Get-TestCopilotBilling)
        $routes.Remove('GET orgs/contoso/copilot/billing/seats?per_page=100')
        Register-TestGhRoute -Route $routes

        (Get-GitHubOrgState -Config $script:config).CopilotSeats | Should -BeNullOrEmpty
    }

    It 'stops when the seats cannot be read' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET orgs/contoso/copilot/billing/seats?per_page=100'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*orgs/contoso/copilot/billing/seats*HTTP 502*'
    }
}
