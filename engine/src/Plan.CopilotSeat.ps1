# The Copilot seats in the plan and their warnings. Pure: no GitHub calls.

# Dollars a seat and month, for the plan to name the cost (https://github.com/features/copilot/plans).
$script:CopilotSeatPrices = @{ business = 19; enterprise = 39 }

function Format-CopilotSeatCost {
    # What the seats cost, or how many of them for a plan type without a known price.
    param(
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][string]$PlanType
    )

    if ($script:CopilotSeatPrices.ContainsKey($PlanType)) {
        return "$Count x `$$($script:CopilotSeatPrices[$PlanType]) a month ($PlanType)"
    }
    return "$Count x the price of the $PlanType plan"
}

function Get-CopilotSeatAction {
    # Buys the seats of the config that are missing. GitHub answers 422 unless selected members are chosen, and without
    # a plan or with another seat management the warnings say what to do. A team is planned only for members without a
    # seat: GitHub does not list the teams it was given, and a team with nothing to buy would be planned on every run.
    param(
        [Parameter(Mandatory)][object]$Config,
        [AllowNull()][object]$Current
    )

    if ($null -eq $Current -or $Current.SeatManagement -cne 'assign_selected') {
        return
    }
    $organization = [string]$Config.organization
    $base = "orgs/$organization/copilot/billing"
    $holders = [string[]]@($Current.Seats | ForEach-Object { $_.Login })
    $missing = (Compare-NameSet -Expected @($Config.copilotSeats.selected_usernames) -Actual $holders).Missing
    if (@($missing).Count -gt 0) {
        [pscustomobject]@{
            Action   = 'AddCopilotSeats'
            Target   = $organization
            Method   = 'POST'
            Endpoint = "$base/selected_users"
            Body     = [ordered]@{ selected_usernames = [string[]]$missing }
            Summary  = "+ buy Copilot seats for $($missing -join ', '): $(Format-CopilotSeatCost -Count @($missing).Count -PlanType $Current.PlanType)"
        }
    }

    # One seat per person, so a login or team planned above is not counted again.
    $covered = Get-NameSet -Value (@($holders) + @($missing))
    foreach ($team in @($Config.copilotSeats.selected_teams)) {
        $members = @($Current.Teams[$team] | Where-Object { $null -ne $_ -and -not $covered.Contains($_) })
        if ($members.Count -eq 0) {
            continue
        }
        $members | ForEach-Object { [void]$covered.Add($_) }
        [pscustomobject]@{
            Action   = 'AddCopilotTeam'
            Target   = [string]$team
            Method   = 'POST'
            Endpoint = "$base/selected_teams"
            Body     = [ordered]@{ selected_teams = [string[]]@($team) }
            Summary  = "+ buy Copilot seats for team '$team' ($($members -join ', ')): $(Format-CopilotSeatCost -Count $members.Count -PlanType $Current.PlanType)"
        }
    }
}

function Get-CopilotSeatWarning {
    # Warnings for seats the config asks for but the engine cannot buy, a seat outside the config, a seat of the config
    # that is being cancelled and a team that does not exist. The engine never cancels a seat.
    param(
        [Parameter(Mandatory)][object]$Config,
        [AllowNull()][object]$Current
    )

    $organization = [string]$Config.organization
    $page = "https://github.com/organizations/$organization/settings/copilot/access"
    $users = @($Config.copilotSeats.selected_usernames)
    $teams = @($Config.copilotSeats.selected_teams)
    if ($null -eq $Current) {
        if ($users.Count -gt 0 -or $teams.Count -gt 0) {
            "copilotSeats lists seats, but $organization has no Copilot plan with seat management set up, so the engine buys none. GitHub has no API for the first seat: buy Copilot Business and assign one at $page."
        }
        return
    }

    if ($Current.SeatManagement -cne 'assign_selected') {
        $reason = 'so the engine buys no seat'
        if ($Current.SeatManagement -ceq 'assign_all') {
            $reason += "; 'assign_all' pays a seat for every member"
        }
        "Copilot seats of $organization are managed as '$($Current.SeatManagement)', not 'assign_selected', $reason. Choose selected members at $page."
    }

    $members = @($teams | ForEach-Object { $Current.Teams[$_] })
    $wanted = Get-NameSet -Value (@($users) + @($members))
    foreach ($seat in @($Current.Seats | Where-Object { $_ })) {
        $listed = $wanted.Contains($seat.Login)
        if ($listed -and $seat.PendingCancellation) {
            "Copilot seat of '$($seat.Login)' ends on $($seat.PendingCancellation) although it is in copilotSeats. If it should stay, assign it again at $page; if not, remove it from copilotSeats."
        }
        elseif (-not $listed -and -not $seat.PendingCancellation) {
            $through = ''
            if ($seat.Team) {
                $through = " (through team '$($seat.Team)')"
            }
            "Copilot seat of '$($seat.Login)'$through is not in copilotSeats, and it is paid every month. If it is expected, add it to copilotSeats; if not, remove it at $page."
        }
    }

    foreach ($team in $teams) {
        if ($null -eq $Current.Teams[$team]) {
            "copilotSeats.selected_teams names '$team', but $organization has no such team, so it gets no seats. Create the team, or remove it from the config."
        }
    }
}
