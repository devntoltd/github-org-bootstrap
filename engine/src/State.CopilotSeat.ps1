# GitHub reads of the Copilot plan and its seats.

function Read-CopilotBilling {
    # GET orgs/<org>/copilot/billing as GitHub answers it (the root as it is), read once per run for the seats, the
    # ruleset and the checked Copilot policies; $null on a 404. Any other failure stops the run: the seats are apply work.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'Copilot plan'
    try {
        $billing = Read-OrgEndpoint -Endpoint "orgs/$Organization/copilot/billing" -NoEnumerate
    }
    catch {
        if (Test-GhStatus -ErrorRecord $_ -StatusCode 404) {
            return $null
        }
        throw
    }
    # Only a 404 means no plan: an empty or other answer must not pass for one.
    if ($billing -isnot [System.Management.Automation.PSCustomObject]) {
        throw "GET orgs/$Organization/copilot/billing answered with something that is not an object; re-run, and if it stays, check the Copilot page of the organization."
    }
    return $billing
}

function Read-CopilotSeatState {
    # The Copilot plan with its seats: {PlanType, SeatManagement, Total, Seats, Teams}. Seats holds
    # {Login, Team, PendingCancellation}; Teams is slug -> logins of each team of the config, $null for a team that does
    # not exist: GitHub lists seats, not the teams it was given, so the plan compares a team through its members.
    # $null without a plan: an organization that never bought Copilot gets 200 with seat management 'unconfigured'
    # (seen on GitHub Team, 2026-11-03), so that is no plan too, as a 404 (Billing $null) is.
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][object]$Config,
        # The answer of Read-CopilotBilling.
        [AllowNull()][object]$Billing
    )

    $billing = $Billing
    if ($null -eq $billing -or [string]$billing.seat_management_setting -eq 'unconfigured') {
        return $null
    }

    Write-StateProgress -Status 'Copilot seats'
    # Each page is an object whose seats property holds the items.
    $seats = foreach ($page in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/copilot/billing/seats?per_page=100" -Paginate)) {
        foreach ($seat in @($page.seats | Where-Object { $null -ne $_ })) {
            $pending = $seat.pending_cancellation_date
            [pscustomobject]@{
                Login               = [string]$seat.assignee.login
                Team                = if ($seat.assigning_team) { [string]$seat.assigning_team.slug }
                PendingCancellation = if ($null -ne $pending) { [string]$pending }
            }
        }
    }

    $teams = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($team in @($Config.copilotSeats.selected_teams)) {
        Write-StateProgress -Status "members of team '$team'"
        try {
            $members = @(Read-OrgEndpoint -Endpoint "orgs/$Organization/teams/$team/members?per_page=100" -Paginate)
            $teams[$team] = [string[]]@($members | ForEach-Object { [string]$_.login })
        }
        catch {
            if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                throw
            }
            $teams[$team] = $null
        }
    }

    return [pscustomobject]@{
        PlanType       = [string]$billing.plan_type
        SeatManagement = [string]$billing.seat_management_setting
        Total          = [int]$billing.seat_breakdown.total
        Seats          = [object[]]@($seats)
        Teams          = $teams
    }
}
