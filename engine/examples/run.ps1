#Requires -Version 7.6

<#
.SYNOPSIS
Runs the engine version pinned in engine.psd1 against github.json, both next to this script.

.DESCRIPTION
Copy this file and engine.psd1 into the repository that holds the organization's config. The engine is checked out at
the pinned commit into .engine/ next to this script (git-ignore it) and reused while the pin is unchanged; the run
stops when the pinned tag does not point at the pinned commit, and when .engine/ has local changes. The switches are those of engine/bootstrap.ps1.

.EXAMPLE
./run.ps1 -WhatIf

.EXAMPLE
./run.ps1 -ValidateOnly
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'WhatIf is forwarded to engine/bootstrap.ps1, which asks before any change; fetching the engine changes nothing in the organization.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force,

    [switch]$SkipLatestVersionCheck,

    [switch]$ManualChecklist,

    [switch]$PageWalk,

    [switch]$ValidateOnly,

    # The pin of the engine: @{ Repository = '<owner>/<name>'; Tag = 'vX.Y.Z'; Commit = '<40 hex>' }.
    [string]$ManifestPath = (Join-Path -Path $PSScriptRoot -ChildPath 'engine.psd1')
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    # Runs git and throws on a failure; returns its output.
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    $output
}

$manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
$checks = [ordered]@{ Repository = '^[\w.-]+/[\w.-]+$'; Tag = '^v\d+\.\d+\.\d+$'; Commit = '^[0-9a-f]{40}$' }
foreach ($key in $checks.Keys) {
    if ([string]$manifest[$key] -cnotmatch $checks[$key]) {
        throw "$ManifestPath`: $key '$($manifest[$key])' does not match $($checks[$key])."
    }
}
$repository = [string]$manifest.Repository
$tag = [string]$manifest.Tag
$commit = [string]$manifest.Commit
$url = "https://github.com/$repository.git"

# The commit the tag points at: the peeled line of an annotated tag, else the tag's own line.
$lines = @(Invoke-Git -Arguments @('ls-remote', $url, "refs/tags/$tag", "refs/tags/$tag^{}"))
$peeled = @($lines | Where-Object { $_ -match '\^\{\}$' })
$line = @($peeled + $lines | Where-Object { $_ }) | Select-Object -First 1
if (-not $line) {
    throw "Tag $tag not found in $repository."
}
$tagCommit = ($line -split '\s+')[0]
if ($tagCommit -cne $commit) {
    throw "Tag $tag of $repository is at $tagCommit, not at the pinned commit $commit."
}

# Reuse the checkout while it is at the pinned commit; replace it otherwise.
$engine = Join-Path -Path $PSScriptRoot -ChildPath '.engine'
$head = $null
if (Test-Path -LiteralPath (Join-Path -Path $engine -ChildPath '.git')) {
    $head = & git -C $engine rev-parse HEAD
    if ($LASTEXITCODE -ne 0) {
        $head = $null
    }
}
# Run only the pinned engine as published, and never delete a file someone changed: an edited or added file in a
# checkout stops the run before it is reused or replaced, and again after a new checkout (a post-checkout hook of the
# user's git config). Untracked files are asked for whatever the git config says.
function Assert-EngineUnchanged {
    $changes = @(Invoke-Git -Arguments @('-C', $engine, 'status', '--porcelain', '--untracked-files=all') | Where-Object { $_ })
    if ($changes) {
        throw "$engine has local changes, so it is not the pinned engine:`n$($changes -join "`n")`nRemove $engine to check out the pinned engine again."
    }
}
if ($head) {
    Assert-EngineUnchanged
}
if ($head -cne $commit) {
    if (Test-Path -LiteralPath $engine) {
        # Without a readable HEAD only an unfinished checkout (.engine/.git alone) is replaced; other files stay.
        if (-not $head) {
            $files = @(Get-ChildItem -LiteralPath $engine -Force | Where-Object { $_.Name -cne '.git' })
            if ($files) {
                throw "$engine is not a checkout of the engine and holds files:`n$($files.Name -join "`n")`nMove them elsewhere and remove $engine to check out the pinned engine."
            }
        }
        Remove-Item -LiteralPath $engine -Recurse -Force -WhatIf:$false
    }
    Invoke-Git -Arguments @('init', '-q', $engine) | Out-Null
    Invoke-Git -Arguments @('-C', $engine, 'fetch', '-q', '--depth', '1', $url, $commit) | Out-Null
    Invoke-Git -Arguments @('-C', $engine, 'checkout', '-q', '--detach', 'FETCH_HEAD') | Out-Null
    $head = Invoke-Git -Arguments @('-C', $engine, 'rev-parse', 'HEAD')
    if ($head -cne $commit) {
        throw "The engine checked out at $head, not at the pinned commit $commit."
    }
    Assert-EngineUnchanged
}

$bootstrap = Join-Path -Path $engine -ChildPath 'engine/bootstrap.ps1'
& $bootstrap -ConfigPath (Join-Path -Path $PSScriptRoot -ChildPath 'github.json') -Force:$Force -SkipLatestVersionCheck:$SkipLatestVersionCheck -ManualChecklist:$ManualChecklist -PageWalk:$PageWalk -ValidateOnly:$ValidateOnly -WhatIf:$WhatIfPreference
