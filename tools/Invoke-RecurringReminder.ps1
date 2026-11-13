<#
.SYNOPSIS
Opens a reminder issue for every recurring operation that is due, and prints the status of all of them.
.DESCRIPTION
A recurring operation is an issue template in .github/ISSUE_TEMPLATE with the label 'recurring' and the label
'recurring:<operation>' (<operation> is the file name without 'recurring-' and '.md'); its interval in days is in
.github/recurring-operations.psd1. Its history is every issue with that operation label: the next reminder is due when
the last one closed as completed is at least the interval old, or when none was ever completed. An open reminder is
never duplicated.

The weekly workflow .github/workflows/recurring.yml runs it. Uses gh, signed in (GH_TOKEN in Actions) and pointed at
the repository (GH_REPO in Actions, the git remote of the current directory otherwise).
.EXAMPLE
./tools/Invoke-RecurringReminder.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Folder of the issue templates.
    [string]$TemplatePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.github/ISSUE_TEMPLATE'),
    # Interval of each recurring operation, keyed by the file name of its template.
    [string]$IntervalPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.github/recurring-operations.psd1')
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

# The UTC calendar date of a timestamp from gh (a string, or a DateTime from ConvertFrom-Json).
function ConvertTo-UtcDate {
    param($Value)

    ([datetime]$Value).ToUniversalTime().Date
}

# Where an operation stands on $Today: its last completed reminder, its due date and its open reminder. The due date is
# the last completion plus the interval; without one, the creation of the open reminder, or today.
function Get-OperationStatus {
    param($Operation, [object[]]$Issue, [datetime]$Today)

    $own = @($Issue | Where-Object { @($_.labels.name) -contains $Operation.Label })
    $last = $own | Where-Object { $_.state -eq 'CLOSED' -and $_.stateReason -eq 'COMPLETED' } |
        Sort-Object -Property { ConvertTo-UtcDate $_.closedAt } -Descending | Select-Object -First 1
    $open = $own | Where-Object { $_.state -eq 'OPEN' } | Sort-Object -Property number | Select-Object -First 1

    $lastDone = if ($last) { ConvertTo-UtcDate $last.closedAt }
    $nextDue = if ($last) { $lastDone.AddDays($Operation.IntervalDays) }
    elseif ($open) { ConvertTo-UtcDate $open.createdAt }
    else { $Today }

    [pscustomobject]@{
        LastDone    = $lastDone
        LastIssue   = if ($last) { $last.number }
        NextDue     = $nextDue
        OpenIssue   = if ($open) { $open.number }
        Due         = (-not $open) -and $nextDue -le $Today
        OverdueDays = [math]::Max(0, ($Today - $nextDue).Days)
    }
}

# The recurring operations: the Markdown templates with the label 'recurring', each with its interval. Throws with every
# problem found, before any call to GitHub.
function Get-RecurringOperation {
    param([string]$TemplatePath, [string]$IntervalPath)

    $intervals = Import-PowerShellDataFile -Path $IntervalPath
    $intervalFile = Split-Path -Path $IntervalPath -Leaf
    $templates = @{}
    foreach ($file in Get-ChildItem -Path $TemplatePath -Filter '*.md' -File) {
        $templates[$file.Name] = Read-IssueTemplate -Path $file.FullName
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $intervals.Keys | Sort-Object) {
        if (-not $templates.ContainsKey($name)) {
            $problems.Add("${intervalFile}: '$name' is not a template in $TemplatePath.")
        }
        elseif (@($templates[$name].Fields.labels) -notcontains 'recurring') {
            $problems.Add("${intervalFile}: '$name' has no label 'recurring'.")
        }
    }

    $operations = foreach ($name in $templates.Keys | Sort-Object) {
        $template = $templates[$name]
        $labels = [string[]]@($template.Fields.labels | Where-Object { $_ })
        if ($labels -notcontains 'recurring') {
            continue
        }
        $label = 'recurring:' + ([System.IO.Path]::GetFileNameWithoutExtension($name) -replace '^recurring-', '')
        $interval = if ($intervals.ContainsKey($name)) { $intervals[$name].IntervalDays }
        if (-not $intervals.ContainsKey($name)) {
            $problems.Add("${name}: no interval in $intervalFile.")
        }
        elseif (-not ($interval -is [int] -and $interval -gt 0)) {
            $problems.Add("${name}: IntervalDays in $intervalFile must be a whole number above 0, got '$interval'.")
        }
        if (-not $template.Fields.title) {
            $problems.Add("${name}: the front matter has no title.")
        }
        if ($labels -notcontains $label) {
            $problems.Add("${name}: the labels must include '$label' (the file name without 'recurring-' and '.md').")
        }
        [pscustomobject]@{
            Template     = $name
            Label        = $label
            Title        = $template.Fields.title
            Labels       = $labels
            Assignees    = [string[]]@($template.Fields.assignees | Where-Object { $_ })
            Body         = $template.Body
            IntervalDays = $interval
        }
    }

    if ($problems.Count -gt 0) {
        throw "The recurring operations are not valid:`n- $($problems -join "`n- ")"
    }
    $operations
}

$operations = @(Get-RecurringOperation -TemplatePath $TemplatePath -IntervalPath $IntervalPath)

$today = (Get-Date).ToUniversalTime().Date
# gh arguments go in arrays: the analyzer reads a list of bare words as positional parameters of Invoke-Gh.
$listArguments = @('issue', 'list', '--label', 'recurring', '--state', 'all', '--limit', '1000',
    '--json', 'number,title,labels,state,stateReason,closedAt,createdAt,url')
$issues = @(Invoke-Gh @listArguments | ConvertFrom-Json)

# Every run, even with nothing due: the operator also opens the templates by hand, and GitHub drops a missing label.
$labelDescription = 'Reminder of a recurring operation (tools/Invoke-RecurringReminder.ps1)'
Add-MissingLabel -Name (@('recurring') + @($operations | ForEach-Object { $_.Label })) -Description $labelDescription

$rows = foreach ($operation in $operations) {
    $status = Get-OperationStatus -Operation $operation -Issue $issues -Today $today
    $nextDue = $status.NextDue.ToString('yyyy-MM-dd')
    $state = if ($status.OpenIssue -and $status.OverdueDays -gt 0) {
        "open #$($status.OpenIssue), overdue by $($status.OverdueDays) days"
    }
    elseif ($status.OpenIssue) {
        "open #$($status.OpenIssue)"
    }
    elseif (-not $status.Due) {
        'ok'
    }
    else {
        $title = "$($operation.Title) (due $nextDue)"
        $context = if ($status.LastDone) {
            "Every $($operation.IntervalDays) days; last done $($status.LastDone.ToString('yyyy-MM-dd')) in #$($status.LastIssue)."
        }
        else {
            "Every $($operation.IntervalDays) days; never done before."
        }
        $issue = @{
            Title            = $title
            Body             = "$context`n`n$($operation.Body)"
            Label            = $operation.Labels
            Assignee         = $operation.Assignees
            Target           = $title
            LabelDescription = $labelDescription
        }
        if ($number = New-IssueFromTemplate @issue) {
            "opened #$number"
        }
        else {
            'due'
        }
    }
    [pscustomobject]@{
        Operation   = $operation.Title -replace '^\[Recurring\]\s*', ''
        Every       = "$($operation.IntervalDays) days"
        'Last done' = if ($status.LastDone) { "$($status.LastDone.ToString('yyyy-MM-dd')) (#$($status.LastIssue))" } else { 'never' }
        'Next due'  = $nextDue
        Status      = $state
    }
}

# A wide line, so that a narrow terminal wraps the table instead of dropping its right-most columns.
Write-Host ($rows | Format-Table -AutoSize | Out-String -Width 4096)
$lines = @('## Recurring operations', '', '| Operation | Every | Last done | Next due | Status |', '|---|---|---|---|---|')
$lines += @($rows | ForEach-Object { "| $($_.Operation) | $($_.Every) | $($_.'Last done') | $($_.'Next due') | $($_.Status) |" })
Add-StepSummary -Line $lines
