# The shape of the Copilot seats: who holds a paid seat. Pure: no GitHub calls.

function Get-CopilotSeatNode {
    # The shape node of the seats, in the names of GitHub's API.
    $team = @{ Type = 'string'; Pattern = $script:TeamSlugPattern; Rule = $script:TeamSlugRule }
    @{
        Type        = 'object'
        Description = 'Who holds a Copilot seat; every seat is paid. A login or team without a seat is planned, a seat outside this list is only a warning.'
        Fields      = [ordered]@{
            selected_usernames = @{ Type = 'array'; Unique = $true; Items = Get-ConfigPatternNode -Name Login; Description = 'Logins that hold a seat of their own; [] for none.' }
            selected_teams     = @{ Type = 'array'; Unique = $true; Items = $team; Description = 'Slugs of the teams whose members hold a seat; [] for none.' }
        }
    }
}
