<#
.SYNOPSIS
Publishes the GitHub Release of ModuleVersion of engine/GitHubOrg.psd1 when it has none, and prints the status.
.DESCRIPTION
The release is vX.Y.Z at the commit of the run: title vX.Y.Z, the notes of the section ## [X.Y.Z] of CHANGELOG.md,
marked Latest, never a draft; gh release create also creates the tag when it is missing. A version that has its
release already is left alone, so every push to main runs this and only the merge of a release pull request publishes.

The repository has immutable releases: a published release and its tag never change afterwards. So the script stops
before any write when the changelog has no notes for the version, when the tag is at another commit, or when a draft
release of the tag exists. A tag at the commit without a release (a run that stopped in between) gets its release.

The job release of .github/workflows/ci.yml runs it after every check of the commit passed (decision
docs/decisions/2026-11-14-release-workflow.md). Uses gh, signed in (GH_TOKEN in Actions) and pointed at the repository
(GH_REPO in Actions, the git remote of the current directory otherwise).
.EXAMPLE
./tools/Publish-Release.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The manifest whose ModuleVersion is the version of the release.
    [string]$ManifestPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'engine/GitHubOrg.psd1'),
    # The changelog with the section of the version.
    [string]$ChangelogPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'CHANGELOG.md'),
    # The module that pins the REST API version the gh api calls send.
    [string]$ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'shared/GitHubOrg.Common.psm1'),
    # The commit to release: GITHUB_SHA in Actions, HEAD otherwise.
    [string]$Commit
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

$version = [string](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion
$tag = "v$version"

# The notes: the lines under '## [X.Y.Z]' up to the next heading of that level or the link definitions at the end.
$notes = [System.Collections.Generic.List[string]]::new()
$inSection = $false
foreach ($line in Get-Content -Path $ChangelogPath) {
    if ($line -match '^## ') {
        if ($inSection) { break }
        $inSection = $line -match ('^## \[' + [regex]::Escape($version) + '\]')
        continue
    }
    if ($inSection) {
        if ($line -match '^\[[^\]]+\]: ') { break }
        $notes.Add($line)
    }
}
$notesText = ($notes -join "`n").Trim()
if (-not $notesText) {
    throw "$(Split-Path -Path $ChangelogPath -Leaf) has no notes under ## [$version]: move the entries of the release under it first."
}

if (-not $Commit) {
    $Commit = $env:GITHUB_SHA
}
if (-not $Commit) {
    $Commit = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "git rev-parse HEAD failed with exit code $LASTEXITCODE."
    }
}

$pinned = Get-PinnedGitHubApiVersion -Path $ModulePath
$header = @('--header', "X-GitHub-Api-Version: $pinned")

# A published release: every commit of main after the release pull request, the tag at an earlier commit.
$release = @(Invoke-Gh release list --json 'tagName,isDraft' --limit 1000 | ConvertFrom-Json) |
    Where-Object { $_.tagName -ceq $tag } | Select-Object -First 1
if ($release -and $release.isDraft) {
    throw "A draft release $tag exists; publish or delete it by hand, then run this again."
}

if (-not $release) {
    # A tag without a release must be at this commit, peeled when it is annotated. matching-refs lists every tag the
    # name starts, so only the exact ref counts.
    $ref = @(Invoke-Gh api @header "repos/{owner}/{repo}/git/matching-refs/tags/$tag" | ConvertFrom-Json) |
        Where-Object { $_.ref -ceq "refs/tags/$tag" } | Select-Object -First 1
    if ($ref) {
        $tagCommit = [string]$ref.object.sha
        if ($ref.object.type -eq 'tag') {
            $tagCommit = [string](Invoke-Gh api @header "repos/{owner}/{repo}/git/tags/$tagCommit" | ConvertFrom-Json).object.sha
        }
        if ($tagCommit -cne $Commit) {
            throw "Tag $tag is at $tagCommit, not at $Commit, the commit of this run, and has no release; move the tag or raise ModuleVersion."
        }
    }
}

$status = if ($release) {
    'released'
}
elseif ($PSCmdlet.ShouldProcess("$tag at $Commit", 'gh release create')) {
    Invoke-Gh release create $tag --target $Commit --title $tag --notes $notesText --latest | Out-Null
    'published'
}
else {
    'new'
}

Write-Host "Release ${tag}: $status"
Add-StepSummary -Line '## Release', '', '| Version | Tag | Release |', '|---|---|---|', "| $version | $tag | $status |"
