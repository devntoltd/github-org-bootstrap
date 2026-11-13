# The budgets in the plan and their warnings. Pure: no GitHub calls.

function Find-Budget {
    # The budget of the organization with the type and product of a config entry, or $null. A budget of a repository
    # or a user has its own limit, so it is not this one.
    param(
        [AllowEmptyCollection()][object[]]$Budgets,
        [Parameter(Mandatory)][object]$Entry
    )
    @($Budgets | Where-Object { $_.Scope -ceq 'organization' -and $_.Type -ceq $Entry.budget_type -and $_.Sku -ceq $Entry.budget_product_sku }) | Select-Object -First 1
}

function Get-BudgetAction {
    # Creates the budgets of the config that are missing and updates those that differ; the recipients are always the
    # owners, so an address added elsewhere is planned away. A budget that is not in the config is only a warning.
    param(
        [Parameter(Mandatory)][object]$Config,
        [AllowEmptyCollection()][object[]]$Current
    )

    $organization = [string]$Config.organization
    $base = "organizations/$organization/settings/billing/budgets"
    $owners = [string[]]@($Config.inventory.owners)
    foreach ($entry in @($Config.budgets)) {
        $sku = [string]$entry.budget_product_sku
        $budget = Find-Budget -Budgets $Current -Entry $entry
        if ($null -eq $budget) {
            [pscustomobject]@{
                Action   = 'CreateBudget'
                Target   = $sku
                Method   = 'POST'
                Endpoint = $base
                Body     = [ordered]@{
                    budget_type           = [string]$entry.budget_type
                    budget_product_sku    = $sku
                    budget_scope          = 'organization'
                    budget_amount         = $entry.budget_amount
                    prevent_further_usage = [bool]$entry.prevent_further_usage
                    budget_alerting       = [ordered]@{ will_alert = $true; alert_recipients = $owners }
                }
                Summary  = "+ create budget '$sku' ($($entry.budget_type)): budget_amount: $($entry.budget_amount), prevent_further_usage: $(Format-SettingValue ([bool]$entry.prevent_further_usage)), alert_recipients: $($owners -join ', ')"
            }
            continue
        }

        $changed = [ordered]@{}
        $changes = [System.Collections.Generic.List[string]]::new()
        if ($budget.Amount -ne $entry.budget_amount) {
            $changed.budget_amount = $entry.budget_amount
            $changes.Add("budget_amount: $($budget.Amount) -> $($entry.budget_amount)")
        }
        if ($budget.PreventFurtherUsage -ne [bool]$entry.prevent_further_usage) {
            $changed.prevent_further_usage = [bool]$entry.prevent_further_usage
            $changes.Add("prevent_further_usage: $(Format-SettingValue $budget.PreventFurtherUsage) -> $(Format-SettingValue ([bool]$entry.prevent_further_usage))")
        }
        $recipients = Compare-NameSet -Expected $owners -Actual $budget.Recipients
        if (-not $budget.WillAlert) {
            $changes.Add('will_alert: false -> true')
        }
        if (@($recipients.Missing).Count -gt 0 -or @($recipients.Extra).Count -gt 0) {
            $marked = @($recipients.Missing | ForEach-Object { "+ $_" }) + @($recipients.Extra | ForEach-Object { "- $_" })
            $changes.Add("alert_recipients: $($marked -join ', ')")
        }
        if (-not $budget.WillAlert -or @($recipients.Missing).Count -gt 0 -or @($recipients.Extra).Count -gt 0) {
            $changed.budget_alerting = [ordered]@{ will_alert = $true; alert_recipients = $owners }
        }
        if ($changed.Count -gt 0) {
            [pscustomobject]@{
                Action   = 'UpdateBudget'
                Target   = $sku
                Method   = 'PATCH'
                Endpoint = "$base/$($budget.Id)"
                Body     = $changed
                Summary  = "~ update budget '$sku': $($changes -join '; ')"
            }
        }
    }
}

function Get-BudgetWarning {
    # Warnings for a budget that is not in the config, and for AI credits stopped at 0 while a Copilot plan needs them.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$CurrentState
    )

    $organization = [string]$Config.organization
    $entries = @($Config.budgets)
    foreach ($budget in @($CurrentState.Budgets | Where-Object { $_ })) {
        $known = @($entries | Where-Object { $budget.Scope -ceq 'organization' -and $_.budget_type -ceq $budget.Type -and $_.budget_product_sku -ceq $budget.Sku })
        if ($known.Count -eq 0) {
            "Budget '$($budget.Sku)' ($($budget.Type), $($budget.Scope)) is not in budgets. If it is expected, add it to budgets; if not, delete it at https://github.com/organizations/$organization/settings/billing/budgets."
        }
    }
    # A review is charged in AI credits, so a stop at 0 ends the reviews once the included credits are gone.
    $credits = @($entries | Where-Object { $_.budget_product_sku -ceq 'ai_credits' }) | Select-Object -First 1
    if ($null -ne $credits -and $credits.budget_amount -eq 0 -and $credits.prevent_further_usage -and $null -ne $CurrentState.Ruleset.Copilot) {
        "budgets stops 'ai_credits' at 0 while $organization has a Copilot plan, so Copilot code review stops as soon as the included credits are used up. Raise budget_amount in budgets."
    }
}
