# GitHub reads of the budgets.

function Read-BudgetState {
    # The budgets of the organization: {Id, Type, Sku, Scope, Amount, PreventFurtherUsage, WillAlert, Recipients}.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'budgets'
    # Each page is an object whose budgets property holds the items.
    foreach ($page in @(Read-OrgEndpoint -Endpoint "organizations/$Organization/settings/billing/budgets?per_page=100" -Paginate)) {
        foreach ($budget in @($page.budgets | Where-Object { $null -ne $_ })) {
            [pscustomobject]@{
                Id                  = [string]$budget.id
                Type                = [string]$budget.budget_type
                Sku                 = [string]$budget.budget_product_sku
                Scope               = [string]$budget.budget_scope
                Amount              = $budget.budget_amount
                PreventFurtherUsage = [bool]$budget.prevent_further_usage
                WillAlert           = [bool]$budget.budget_alerting.will_alert
                Recipients          = [string[]]@($budget.budget_alerting.alert_recipients | Where-Object { $null -ne $_ })
            }
        }
    }
}
