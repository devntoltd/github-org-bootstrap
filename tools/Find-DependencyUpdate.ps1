<#
.SYNOPSIS
Lists the versions of the locked modules and tools that are newer than the lock and out of quarantine.
.DESCRIPTION
Modules: modules.lock.psd1 and the Modules of dev-tools.psd1, with every stable version in the PowerShell Gallery
(Find-PSResource). Tools: the Tools of dev-tools.psd1, with the releases of their GitHub Repository (gh api; drafts and
prereleases left out). A candidate is the newest version published at least QuarantineDays before Now and newer than
the locked one; a newer version still in quarantine is listed with the date it leaves it.

-OutFile writes the result as JSON ({ Candidates, Quarantined }); -UpdateLock writes the module candidates into the
lock files of Root (the weekly workflow tests them in its checkout; never committed). Uses gh, signed in (GH_TOKEN in
Actions).
.EXAMPLE
./tools/Find-DependencyUpdate.ps1
#>
[CmdletBinding()]
param(
    # The repository root with modules.lock.psd1 and dev-tools.psd1.
    [string]$Root = (Split-Path -Path $PSScriptRoot -Parent),
    # Days a version must be published before it becomes a candidate.
    [int]$QuarantineDays = 7,
    # The time of the check (UTC).
    [datetime]$Now = [datetime]::UtcNow,
    # Where to write the result as JSON.
    [string]$OutFile,
    # Write the module candidates into the lock files.
    [switch]$UpdateLock,
    # Return the result.
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

$lockFile = 'modules.lock.psd1'
$devFile = 'dev-tools.psd1'
$lock = Import-PowerShellDataFile -Path (Join-Path -Path $Root -ChildPath $lockFile)
$devTools = Import-PowerShellDataFile -Path (Join-Path -Path $Root -ChildPath $devFile)
$cutoff = $Now.AddDays(-$QuarantineDays)
# The most GitHub returns per page of releases.
$releasePageSize = 100
$apiVersion = Get-PinnedGitHubApiVersion -Path (Join-Path -Path $Root -ChildPath 'shared/Bootstrap.Common.psm1')
$candidates = [System.Collections.Generic.List[object]]::new()
$quarantined = [System.Collections.Generic.List[object]]::new()

# One entry of the result for a release ({ Version, Published, Notes }) of a locked module or tool.
function ConvertTo-UpdateEntry {
    param([string]$Kind, [string]$Name, [string]$File, [string]$Locked, [object]$Release)

    [ordered]@{
        Kind = $Kind; Name = $Name; File = $File; Locked = $Locked; Version = [string]$Release.Version
        Published = $Release.Published.ToString('yyyy-MM-dd'); Notes = $Release.Notes
    }
}

# Adds the candidate and the newest version in quarantine of one locked module or tool.
function Add-Update {
    param([string]$Kind, [string]$Name, [string]$File, [string]$Locked, [object[]]$Release)

    $newer = @($Release | Where-Object { $_.Version -gt [version]$Locked } | Sort-Object -Property Version -Descending)
    $candidate = $newer | Where-Object { $_.Published -le $cutoff } | Select-Object -First 1
    $waiting = $newer | Where-Object { $_.Published -gt $cutoff -and (-not $candidate -or $_.Version -gt $candidate.Version) } |
        Select-Object -First 1
    if ($candidate) {
        $candidates.Add([pscustomobject](ConvertTo-UpdateEntry -Kind $Kind -Name $Name -File $File -Locked $Locked -Release $candidate))
    }
    if ($waiting) {
        $entry = ConvertTo-UpdateEntry -Kind $Kind -Name $Name -File $File -Locked $Locked -Release $waiting
        $entry.Until = $waiting.Published.AddDays($QuarantineDays).ToString('yyyy-MM-dd')
        $quarantined.Add([pscustomobject]$entry)
    }
}

foreach ($set in @(@{ File = $lockFile; Modules = $lock }, @{ File = $devFile; Modules = $devTools.Modules })) {
    foreach ($name in $set.Modules.Keys | Sort-Object) {
        # Stable versions only; a version without a publish date stays in quarantine. An unlisted version, often one
        # pulled for a reason, comes with the date 1900-01-01 and would pass the quarantine at once: left out.
        $releases = @(Find-PSResource -Name $name -Version '*' -Repository PSGallery -Type Module |
                Where-Object { -not $_.PublishedDate -or ([datetime]$_.PublishedDate).Year -ge 2000 } | ForEach-Object {
                    [pscustomobject]@{
                        Version   = [version]$_.Version
                        Published = if ($_.PublishedDate) { ([datetime]$_.PublishedDate).ToUniversalTime() } else { $Now }
                        Notes     = "https://www.powershellgallery.com/packages/$name/$($_.Version)"
                    }
                })
        Add-Update -Kind 'Module' -Name $name -File $set.File -Locked $set.Modules[$name] -Release $releases
    }
}
foreach ($name in $devTools.Tools.Keys | Sort-Object) {
    $tool = $devTools.Tools[$name]
    # Newest first, page by page until one holds the locked version or an older one, or the last page: the releases of
    # another package of the repository (lychee-lib) can fill a page before the tool's own.
    $releases = [System.Collections.Generic.List[object]]::new()
    for ($page = 1; ; $page++) {
        $releaseArguments = @('api', "repos/$($tool.Repository)/releases?per_page=$releasePageSize&page=$page", '--header', "X-GitHub-Api-Version: $apiVersion")
        $items = @(Invoke-Gh @releaseArguments | ConvertFrom-Json)
        $own = @($items | Where-Object { -not $_.draft -and -not $_.prerelease } | ForEach-Object {
                # Tags such as v1.2.3 or lychee-v0.24.2; not those of other packages of the repository (lychee-lib-v0.24.2).
                if ($_.tag_name -match "^(?:$([regex]::Escape($name))-)?v?(\d+\.\d+\.\d+)$") {
                    [pscustomobject]@{ Version = [version]$Matches[1]; Published = ([datetime]$_.published_at).ToUniversalTime(); Notes = $_.html_url }
                }
            })
        $releases.AddRange([object[]]$own)
        if ($items.Count -lt $releasePageSize -or @($own | Where-Object { $_.Version -le [version]$tool.Version }).Count -gt 0) {
            break
        }
    }
    Add-Update -Kind 'Tool' -Name $name -File $devFile -Locked $tool.Version -Release @($releases)
}

if ($UpdateLock) {
    foreach ($candidate in $candidates | Where-Object { $_.Kind -eq 'Module' }) {
        $path = Join-Path -Path $Root -ChildPath $candidate.File
        $text = Get-Content -Path $path -Raw
        $pattern = "(?m)^(\s*'?$([regex]::Escape($candidate.Name))'?\s*=\s*')$([regex]::Escape($candidate.Locked))(')"
        if ($text -notmatch $pattern) {
            throw "$($candidate.File) has no line '$($candidate.Name)' = '$($candidate.Locked)'."
        }
        Set-Content -Path $path -Value ($text -replace $pattern, "`${1}$($candidate.Version)`${2}") -NoNewline
    }
}

foreach ($candidate in $candidates) {
    Write-Host "$($candidate.Name) $($candidate.Locked) -> $($candidate.Version) (published $($candidate.Published))"
}
foreach ($waiting in $quarantined) {
    Write-Host "$($waiting.Name) $($waiting.Version) is in quarantine until $($waiting.Until)"
}
if ($candidates.Count -eq 0 -and $quarantined.Count -eq 0) {
    Write-Host 'Every locked version is the newest.'
}

$result = [pscustomobject]@{ Candidates = @($candidates); Quarantined = @($quarantined) }
if ($OutFile) {
    ConvertTo-Json -InputObject $result -Depth 5 | Set-Content -Path $OutFile
}
if ($PassThru) {
    $result
}
