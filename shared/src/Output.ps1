# Output of a run: progress, plan, recommendations, waivers, summary and the confirmation. Dot-sourced into
# Bootstrap.Common, so its functions share that module's scope (Pester -ModuleName Bootstrap.Common mocks).

# Progress of the two slow steps of a run, shown while reading the state and while applying the plan; the caller
# calls Complete-BootstrapProgress in a finally block so the bar disappears on errors too.
$script:StateActivity = 'Reading current state'
$script:ApplyActivity = 'Applying changes'

function Write-StateProgress {
    <#
    .SYNOPSIS
    Shows which read of the current state runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    Write-Progress -Activity $script:StateActivity -Status $Status
}

function Write-ApplyProgress {
    <#
    .SYNOPSIS
    Shows which plan action runs: "<n>/<total>: <summary>", with the share of actions done before it.
    .PARAMETER Index
    Zero-based position of the action in the plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Index,

        [Parameter(Mandatory)]
        [int]$Total,

        [Parameter(Mandatory)]
        [string]$Summary
    )

    Write-Progress -Activity $script:ApplyActivity -Status "$($Index + 1)/${Total}: $Summary" -PercentComplete ([int](100 * $Index / $Total))
}

function Complete-BootstrapProgress {
    <#
    .SYNOPSIS
    Clears the state and apply progress bars.
    #>
    [CmdletBinding()]
    param()

    Write-Progress -Activity $script:StateActivity -Completed
    Write-Progress -Activity $script:ApplyActivity -Completed
}

function Write-BootstrapPlan {
    <#
    .SYNOPSIS
    Prints the planned actions, or a message that nothing needs to change.
    .DESCRIPTION
    Each action prints its Summary; the lines of its Details, when it has any (the engine: the web UI page, the read
    endpoint and the write of the changed fields), follow it, indented further. An action without Details prints its
    Summary alone.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )

    if ($Plan.Count -eq 0) {
        Write-Host 'No changes: everything matches the config.'
        return
    }

    Write-Host "Planned changes ($($Plan.Count)):"
    foreach ($action in $Plan) {
        Write-Host "  $($action.Summary)"
        foreach ($detail in $action.Details) {
            Write-Host "      $detail"
        }
    }
}

function Write-BootstrapRecommendation {
    <#
    .SYNOPSIS
    Prints something the operator should do after the run: optional, so not a warning.
    .DESCRIPTION
    A blank line, the 'Recommended:' label in cyan (the color PowerShell leaves free: red is for errors, yellow for
    warnings, green for formatting) followed by the message, then the command on its own line, easy to copy. No color
    when $PSStyle.OutputRendering is PlainText (output redirected, or NO_COLOR set).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Command
    )

    $label = 'Recommended:'
    if ($PSStyle.OutputRendering -ne 'PlainText') {
        $label = "$($PSStyle.Foreground.Cyan)$label$($PSStyle.Reset)"
    }
    Write-Host ''
    Write-Host "$label $Message"
    Write-Host "  $Command"
}

function Write-BootstrapWaiver {
    <#
    .SYNOPSIS
    Prints an exception in force: a deliberate, dated deviation from a recommended value. Shown on every run so it
    stays visible, but not a warning: someone already decided.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)

    Write-Host $Message
}

function Write-BootstrapSummary {
    <#
    .SYNOPSIS
    Prints how many changes were applied and which objects were already up to date.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Applied,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Unchanged
    )

    Write-Host "Done. Applied $($Applied.Count) change(s)."
    if ($Unchanged.Count -gt 0) {
        Write-Host "Already up to date: $($Unchanged -join ', ')"
    }
}

function Confirm-BootstrapRun {
    <#
    .SYNOPSIS
    Asks the operator to confirm; throws unless the answer is y or yes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $answer = ([string](Read-Host $Prompt)).Trim()
    if ($answer -notin @('y', 'yes')) {
        throw 'Aborted by operator.'
    }
}

function Confirm-BootstrapPlan {
    <#
    .SYNOPSIS
    Returns $true when the printed plan should be applied: not empty, not -WhatIf, and confirmed (or -Force).
    .DESCRIPTION
    Called after the plan, warnings and waivers are printed, so the operator answers knowing what will change. Cmdlet
    is the engine's $PSCmdlet, so -WhatIf given to the engine applies. Anything but y/yes throws.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Calls ShouldProcess on the cmdlet of the engine, which supports it.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [switch]$Force
    )

    if ($Plan.Count -eq 0) {
        return $false
    }
    $operation = "Apply $($Plan.Count) change(s)"
    if (-not $Cmdlet.ShouldProcess($Target, $operation)) {
        return $false
    }
    if (-not $Force) {
        # ${}: '?' is valid in a variable name, so "$Target?" would read a variable named 'Target?'.
        Confirm-BootstrapRun -Prompt "$operation to ${Target}? [y/N]"
    }
    return $true
}
