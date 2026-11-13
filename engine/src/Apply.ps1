# Executes plan actions against GitHub. The only place that writes to it.

function Invoke-GitHubOrgPlan {
    <#
    .SYNOPSIS
    Sends each planned change to GitHub in order, stopping at the first error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    try {
        $index = 0
        # Set by CreateCodeSecurityConfiguration; later actions reference it as {configuration_id}.
        $createdId = $null
        foreach ($action in $Plan) {
            Write-ApplyProgress -Index $index -Total $Plan.Count -Summary $action.Summary
            $index++
            $endpoint = $action.Endpoint
            if ($endpoint.Contains('{configuration_id}')) {
                if ($null -eq $createdId) {
                    throw "'$($action.Summary)' needs the id of the code security configuration created in this run, but the create response had none; re-run to pick up the configuration."
                }
                $endpoint = $endpoint.Replace('{configuration_id}', [string]$createdId)
            }
            $response = Invoke-GhApi -Method $action.Method -Endpoint $endpoint -Body $action.Body
            if ($action.Action -eq 'CreateCodeSecurityConfiguration') {
                $createdId = $response.id
            }
            Write-Host "  done: $($action.Summary)"
        }
    }
    finally {
        Complete-BootstrapProgress
    }
}
