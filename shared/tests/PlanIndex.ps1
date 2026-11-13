# The position of the action $Action on $Target in a plan of any stage, -1 when the plan has none.
function Get-PlanIndex {
    param([object[]]$Plan, [string]$Action, [string]$Target)

    for ($i = 0; $i -lt $Plan.Count; $i++) {
        if ($Plan[$i].Action -eq $Action -and $Plan[$i].Target -eq $Target) {
            return $i
        }
    }
    return -1
}

# The first action $Action of a plan of any stage, on $Target when it is given; $null when the plan has none (an index
# of -1 would read the last action instead).
function Get-PlanAction {
    param([object[]]$Plan, [string]$Action, [string]$Target)

    @($Plan | Where-Object { $_.Action -eq $Action -and (-not $Target -or $_.Target -eq $Target) }) | Select-Object -First 1
}
