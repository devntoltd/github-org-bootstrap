BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgPlan: budgets' {
    BeforeEach {
        $script:config = Get-TestGitHubOrgConfig
        $script:state = Get-MatchingTestGitHubOrgState
    }

    It 'plans nothing when every budget matches' {
        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }

    It 'creates a missing budget for the organization, alerting the owners' {
        $script:state.Budgets = @($script:state.Budgets[1])

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'CreateBudget'
        $plan[0].Method | Should -Be 'POST'
        $plan[0].Endpoint | Should -Be 'organizations/contoso/settings/billing/budgets'
        $plan[0].Summary | Should -Be "+ create budget 'actions' (ProductPricing): budget_amount: 0, prevent_further_usage: true, alert_recipients: octocat, hubot"
        $plan[0].Body.budget_type | Should -Be 'ProductPricing'
        $plan[0].Body.budget_product_sku | Should -Be 'actions'
        $plan[0].Body.budget_scope | Should -Be 'organization'
        $plan[0].Body.budget_amount | Should -Be 0
        $plan[0].Body.prevent_further_usage | Should -BeTrue
        $plan[0].Body.budget_alerting.will_alert | Should -BeTrue
        @($plan[0].Body.budget_alerting.alert_recipients) | Should -Be @('octocat', 'hubot')
    }

    It 'updates only what differs' {
        $script:state.Budgets[0].Amount = 5

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'UpdateBudget'
        $plan[0].Method | Should -Be 'PATCH'
        $plan[0].Endpoint | Should -Be 'organizations/contoso/settings/billing/budgets/budget-1'
        $plan[0].Summary | Should -Be "~ update budget 'actions': budget_amount: 5 -> 0"
        @($plan[0].Body.Keys) | Should -Be @('budget_amount')
    }

    It 'turns the stop at the limit back on' {
        $script:state.Budgets[0].PreventFurtherUsage = $false

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan[0].Summary | Should -BeLike '*prevent_further_usage: false -> true'
        $plan[0].Body.prevent_further_usage | Should -BeTrue
    }

    It 'turns the alerts back on' {
        $script:state.Budgets[0].WillAlert = $false

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan[0].Summary | Should -BeLike '*will_alert: false -> true'
        $plan[0].Body.budget_alerting.will_alert | Should -BeTrue
    }

    It 'removes a recipient who is not an owner and adds a missing owner' {
        $script:state.Budgets[0].Recipients = [string[]]@('octocat', 'mallory')

        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state)

        $plan[0].Summary | Should -Be "~ update budget 'actions': alert_recipients: + hubot, - mallory"
        @($plan[0].Body.budget_alerting.alert_recipients) | Should -Be @('octocat', 'hubot')
    }

    It 'compares recipients as GitHub logins, ignoring case and order' {
        $script:state.Budgets[0].Recipients = [string[]]@('HUBOT', 'OctoCat')

        @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state).Count | Should -Be 0
    }

    It 'creates the budget of the organization beside <Case> of the same product' -ForEach @(
        @{ Case = 'a budget of a repository'; Change = { param($b) $b.Scope = 'repository' } }
        @{ Case = 'a budget of another type'; Change = { param($b) $b.Type = 'SkuPricing' } }
    ) {
        & $Change $script:state.Budgets[0]

        (Get-PlanAction -Plan @(Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state) -Action 'CreateBudget').Target | Should -Be 'actions'
    }

    It 'plans after the ruleset' {
        $plan = @(Get-GitHubOrgPlan -Config $script:config -CurrentState (Get-DefaultTestGitHubOrgState))

        (Get-PlanIndex -Plan $plan -Action 'CreateBudget' -Target 'actions') | Should -BeGreaterThan (Get-PlanIndex -Plan $plan -Action 'CreateRuleset' -Target 'default-branch')
    }
}

Describe 'Get-GitHubOrgWarning: budgets' {
    BeforeEach {
        $script:config = Get-TestGitHubOrgConfig
        $script:state = Get-MatchingTestGitHubOrgState
    }

    It 'warns about a budget that is not in the config, and leaves it' {
        $script:state.Budgets += Get-TestBudgetState -Id 'budget-9' -Sku 'packages'

        Get-GitHubOrgPlan -Config $script:config -CurrentState $script:state | Should -BeNullOrEmpty
        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "Budget 'packages' (ProductPricing, organization) is not in budgets. If it is expected, add it to budgets; if not, delete it at https://github.com/organizations/contoso/settings/billing/budgets."
    }

    It 'warns that a Copilot plan with no AI credits budget stops the reviews' {
        $script:config.budgets[1].budget_amount = 0
        $script:state.Budgets[1].Amount = 0

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "budgets stops 'ai_credits' at 0 while contoso has a Copilot plan, so Copilot code review stops as soon as the included credits are used up. Raise budget_amount in budgets."
    }

    It 'says nothing about AI credits <Case>' -ForEach @(
        @{ Case = 'without a Copilot plan'; Arrange = { $script:config.budgets[1].budget_amount = 0; $script:state.Budgets[1].Amount = 0; $script:state.Ruleset.Copilot = $null } }
        @{ Case = 'with an amount'; Arrange = { } }
        @{ Case = 'that do not stop'; Arrange = { $script:config.budgets[1].budget_amount = 0; $script:config.budgets[1].prevent_further_usage = $false; $script:state.Budgets[1].Amount = 0; $script:state.Budgets[1].PreventFurtherUsage = $false } }
    ) {
        . $Arrange

        @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Where-Object { $_ -like '*ai_credits*' }).Count | Should -Be 0
    }
}
