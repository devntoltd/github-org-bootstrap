BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgState: budgets' {
    BeforeEach {
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
        $script:state = Get-MatchingTestGitHubOrgState
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'reads the budgets of every page with their alerts' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET organizations/contoso/settings/billing/budgets?per_page=100'] = Get-TestGhObjectPagesResponse -PageSize 1 -Property budgets -Items @($script:state.Budgets | ForEach-Object { ConvertTo-TestBudgetResponse -Budget $_ })
        Register-TestGhRoute -Route $routes

        $budgets = @((Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)).Budgets)

        ($budgets.Sku -join ',') | Should -Be 'actions,ai_credits'
        $budgets[1].Id | Should -Be 'budget-2'
        $budgets[1].Type | Should -Be 'BundlePricing'
        $budgets[1].Scope | Should -Be 'organization'
        $budgets[1].Amount | Should -Be 50
        $budgets[1].PreventFurtherUsage | Should -BeTrue
        $budgets[1].WillAlert | Should -BeTrue
        @($budgets[1].Recipients) | Should -Be @('octocat', 'hubot')
    }

    It 'reads an organization without budgets' {
        $script:state.Budgets = @()
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        @((Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)).Budgets).Count | Should -Be 0
    }

    It 'stops when the budgets cannot be read' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET organizations/contoso/settings/billing/budgets?per_page=100'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig) } | Should -Throw '*organizations/contoso/settings/billing/budgets*'
    }
}
