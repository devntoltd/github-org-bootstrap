<#
.SYNOPSIS
Opens or updates one issue for the module and tool versions newer than the lock and out of quarantine.
.DESCRIPTION
The candidates come from CandidatePath (the JSON of Find-DependencyUpdate.ps1 -OutFile, which the weekly workflow
.github/workflows/recurring.yml passes with the result of the tests and module imports on the new module versions) or, without it, from
running Find-DependencyUpdate.ps1. The issue comes from the template .github/ISSUE_TEMPLATE/dependency-update.md (its
title, labels, which must include 'dependency-update', and assignees; above its body a marker per candidate, the
table, the versions in quarantine and the test result). An open issue with the label is updated; a closed one whose
markers hold every candidate keeps another from opening (closing it as not planned stays on the lock); a new
candidate opens a new one.

Uses gh, signed in (GH_TOKEN in Actions) and pointed at the repository (GH_REPO in Actions, the git remote of the
current directory otherwise).
.EXAMPLE
./tools/Invoke-DependencyUpdateCheck.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The JSON of Find-DependencyUpdate.ps1 -OutFile; without it the script runs the finder.
    [string]$CandidatePath,
    # The outcome of the test and import steps of the workflow (failure when either failed); empty when they did not run.
    [ValidateSet('success', 'failure', 'skipped', 'cancelled', '')]
    [string]$TestResult = '',
    # The workflow run, linked from the test result.
    [string]$RunUrl,
    # The repository root, for the finder.
    [string]$Root = (Split-Path -Path $PSScriptRoot -Parent),
    # The issue template.
    [string]$TemplatePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.github/ISSUE_TEMPLATE/dependency-update.md')
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

# The label the issues are matched by.
$label = 'dependency-update'

$template = Assert-IssueTemplate -Path $TemplatePath -Label $label

$result = if ($CandidatePath) {
    Get-Content -Path $CandidatePath -Raw | ConvertFrom-Json
}
else {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Find-DependencyUpdate.ps1') -Root $Root -PassThru
}
$candidates = @($result.Candidates | Where-Object { $_ })
$quarantined = @($result.Quarantined | Where-Object { $_ })

$status = if ($candidates.Count -eq 0) {
    'no updates'
}
else {
    $markers = @($candidates | ForEach-Object { "<!-- dependency-update: $($_.Name) $($_.Version) -->" })
    $hasModule = @($candidates | Where-Object { $_.Kind -eq 'Module' }).Count -gt 0
    $tests = if (-not $hasModule -or $TestResult -in '', 'skipped') {
        'not run'
    }
    else {
        @{ success = 'passed'; failure = 'failed'; cancelled = 'cancelled' }[$TestResult]
    }
    $testLine = "Tests and module imports on the new module versions: **$tests**"
    if ($RunUrl -and $tests -ne 'not run') {
        $testLine += " ([run]($RunUrl))"
    }
    $body = @(
        $markers
        ''
        '| Name | Kind | Locked | Candidate | Published | Release notes |'
        '|---|---|---|---|---|---|'
        $candidates | ForEach-Object { "| $($_.Name) | $(([string]$_.Kind).ToLowerInvariant()) | $($_.Locked) | $($_.Version) | $($_.Published) | [notes]($($_.Notes)) |" }
        ''
        if ($quarantined) {
            $quarantined | ForEach-Object { "- $($_.Name) $($_.Version) is in quarantine until $($_.Until)." }
            ''
        }
        $testLine
        ''
        $template.Body
    ) -join "`n"

    $issues = @(Get-LabeledIssue -Label $label)
    $open = $issues | Where-Object { $_.state -eq 'OPEN' } | Select-Object -First 1
    # A closed issue that holds every candidate: closing it as not planned stays on the lock.
    $closed = Find-IssueByMarker -Issue @($issues | Where-Object { $_.state -ne 'OPEN' }) -Marker $markers
    $issue = @{
        Title            = $template.Title
        Body             = $body
        Label            = $template.Labels
        Assignee         = $template.Assignees
        Target           = @($candidates | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', '
        LabelDescription = 'Issue of tools/Invoke-DependencyUpdateCheck.ps1'
    }
    if ($open) {
        if ($PSCmdlet.ShouldProcess("#$($open.number)", 'gh issue edit')) {
            $editArguments = @('issue', 'edit', [string]$open.number, '--body', $body)
            Invoke-Gh @editArguments | Out-Null
            "updated #$($open.number)"
        }
        else {
            "open #$($open.number)"
        }
    }
    elseif ($closed) {
        "closed #$($closed.number)"
    }
    elseif ($number = New-IssueFromTemplate @issue) {
        "opened #$number"
    }
    else {
        'new'
    }
}

Write-Host "Dependency updates: $($candidates.Count) candidate(s), $status"
Add-StepSummary -Line (@('## Dependency updates', '', "Status: $status", '') + @($candidates | ForEach-Object { "- $($_.Name) $($_.Locked) -> $($_.Version)" }))
