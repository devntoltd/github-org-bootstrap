<#
.SYNOPSIS
Opens an issue to review a GitHub REST API version newer than the one Invoke-GhApi pins, and prints the status.
.DESCRIPTION
The pinned version is $script:GitHubApiVersion in shared/Bootstrap.Common.psm1; the versions GitHub supports come from
'gh api versions'. For a newer version the script opens one issue from the template
.github/ISSUE_TEMPLATE/github-api-version.md (its title with the version appended, its labels, which must include
'github-api-version', and assignees; above its body the version marker and the two versions). An issue with that label
whose body is marked with the version, open or closed (closing it as not planned stays on the pinned version), keeps
another from opening; the next newer version opens a new one.

The weekly workflow .github/workflows/recurring.yml runs it. Uses gh, signed in (GH_TOKEN in Actions) and pointed at
the repository (GH_REPO in Actions, the git remote of the current directory otherwise).
.EXAMPLE
./tools/Invoke-GitHubApiVersionCheck.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The module that pins the version.
    [string]$ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'shared/Bootstrap.Common.psm1'),
    # The issue template of the review.
    [string]$TemplatePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.github/ISSUE_TEMPLATE/github-api-version.md')
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

# The label the issues are matched by.
$label = 'github-api-version'

$template = Assert-IssueTemplate -Path $TemplatePath -Label $label

$pinned = Get-PinnedGitHubApiVersion -Path $ModulePath

# Versions are dates (yyyy-MM-dd), so the ordinal order is the release order.
$versionArguments = @('api', 'versions')
$latest = @(Invoke-Gh @versionArguments | ConvertFrom-Json | ForEach-Object { [string]$_ } | Sort-Object -Descending)[0]

$status = if ([string]::CompareOrdinal($latest, $pinned) -le 0) {
    'ok'
}
else {
    $marker = "<!-- github-api-version: $latest -->"
    $existing = Find-IssueByMarker -Issue @(Get-LabeledIssue -Label $label) -Marker $marker
    $context = "GitHub supports REST API version ``$latest``; the engines pin ``$pinned`` (```$script:GitHubApiVersion`` in ``shared/Bootstrap.Common.psm1``)."
    $issue = @{
        Title            = "$($template.Title) $latest"
        Body             = "$marker`n$context`n`n$($template.Body)"
        Label            = $template.Labels
        Assignee         = $template.Assignees
        Target           = $latest
        LabelDescription = 'Issue of tools/Invoke-GitHubApiVersionCheck.ps1'
    }
    if ($existing) {
        "$(([string]$existing.state).ToLowerInvariant()) #$($existing.number)"
    }
    elseif ($number = New-IssueFromTemplate @issue) {
        "opened #$number"
    }
    else {
        'new'
    }
}

Write-Host "GitHub REST API: pinned $pinned, latest $latest, $status"
Add-StepSummary -Line '## GitHub REST API version', '', '| Pinned | Latest | Status |', '|---|---|---|', "| $pinned | $latest | $status |"
