<#
.SYNOPSIS
Installs what the checks of CONTRIBUTING.md need and sets up the git settings of this clone.
.DESCRIPTION
Run once on a new machine or clone, and again after a version changes; it skips what is already in place.

- Command-line tools (the Tools of dev-tools.psd1): the exact versions CI uses, through winget. Without winget (not
  Windows), it warns with what to install.
- PowerShell modules (modules.lock.psd1 and the Modules of dev-tools.psd1): first a check that every dependency the
  Gallery lists for a locked version is locked in the same file, with a version in its range; then the exact versions
  for the current user with Install-PSResource -SkipDependencyCheck, the Authenticode signature checked on Windows.
- git config --local: core.hooksPath .githooks (the secret scan of the staged changes before every commit) and
  blame.ignoreRevsFile .git-blame-ignore-revs (git blame skips the formatting commits).

winget changes PATH only for new sessions: open a new terminal before running the checks.
.EXAMPLE
./tools/Install-DevTools.ps1 -WhatIf
.EXAMPLE
./tools/Install-DevTools.ps1 -ModulesOnly
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Only the PowerShell modules: no command-line tools, no git settings (what CI runs).
    [switch]$ModulesOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent

# The first x.y.z in the output of '<command> --version', or $null when the command is not found.
function Get-ToolVersion {
    param([string]$Command)

    if (-not (Get-Command -Name $Command -ErrorAction SilentlyContinue)) {
        return $null
    }
    $text = (& $Command --version 2>&1) -join "`n"
    if ($text -match '\d+\.\d+\.\d+') {
        return $Matches[0]
    }
    return $null
}

# Whether $Version is inside a NuGet version range as the Gallery reports it: '[5.5.3, )', '(1.0, 2.0]', '[1.0]' or a
# bare minimum '5.5.3'.
function Test-VersionInRange {
    param([version]$Version, [string]$Range)

    $text = $Range.Trim()
    if ($text -notmatch '^[\[\(]') {
        return $Version -ge [version]$text
    }
    if ($text -match '^\[(?<exact>[^,\]]+)\]$') {
        return $Version -eq [version]$Matches.exact.Trim()
    }
    if ($text -notmatch '^(?<open>[\[\(])\s*(?<min>[^,]*?)\s*,\s*(?<max>[^\]\)]*?)\s*(?<close>[\]\)])$') {
        throw "Unknown version range '$Range'."
    }
    if ($Matches.min) {
        $min = [version]$Matches.min
        if ($Version -lt $min -or ($Matches.open -eq '(' -and $Version -eq $min)) {
            return $false
        }
    }
    if ($Matches.max) {
        $max = [version]$Matches.max
        if ($Version -gt $max -or ($Matches.close -eq ')' -and $Version -eq $max)) {
            return $false
        }
    }
    return $true
}

$devTools = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'dev-tools.psd1')

if (-not $ModulesOnly) {
    $tools = $devTools.Tools
    $hasWinget = [bool](Get-Command -Name winget -ErrorAction SilentlyContinue)
    foreach ($name in $tools.Keys | Sort-Object) {
        $tool = $tools[$name]
        $current = Get-ToolVersion -Command $name
        if ($current -eq $tool.Version) {
            Write-Host "$name $current is installed"
            continue
        }
        $found = if ($current) { "found $current" } else { 'not found' }
        if (-not $hasWinget) {
            Write-Warning "$name $($tool.Version) is needed ($found); install it from its release page."
            continue
        }
        if ($PSCmdlet.ShouldProcess("$($tool.WinGetId) $($tool.Version) ($found)", 'winget install')) {
            winget install --exact --id $tool.WinGetId --version $tool.Version --source winget --accept-package-agreements --accept-source-agreements
            # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE: that version is installed, but this session started before
            # winget added it to PATH.
            if ($LASTEXITCODE -eq -1978335189) {
                Write-Warning "$name $($tool.Version) is installed, but not on the PATH of this session; open a new terminal."
            }
            elseif ($LASTEXITCODE -ne 0) {
                throw "winget install $($tool.WinGetId) $($tool.Version) failed with exit code $LASTEXITCODE."
            }
        }
    }
}

$lock = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'modules.lock.psd1')
$moduleSets = [ordered]@{ 'modules.lock.psd1' = $lock; 'dev-tools.psd1' = $devTools.Modules }

# Installs run with -SkipDependencyCheck, so every dependency the Gallery lists must be locked in the same file.
$findings = [System.Collections.Generic.List[string]]::new()
foreach ($file in $moduleSets.Keys) {
    $set = $moduleSets[$file]
    foreach ($name in $set.Keys | Sort-Object) {
        $found = Find-PSResource -Name $name -Version $set[$name] -Repository PSGallery -Type Module
        foreach ($dependency in @($found.Dependencies | Where-Object { $_ })) {
            $range = [string]$dependency.VersionRange
            if (-not $set.Contains($dependency.Name)) {
                $findings.Add("$name $($set[$name]) needs $($dependency.Name) $range, which is not in $file.")
                continue
            }
            if (-not (Test-VersionInRange -Version $set[$dependency.Name] -Range $range)) {
                $findings.Add("$name $($set[$name]) needs $($dependency.Name) $range; $file locks $($set[$dependency.Name]).")
            }
        }
    }
}
if ($findings.Count -gt 0) {
    throw "Module dependencies:`n$(($findings | ForEach-Object { " - $_" }) -join "`n")"
}

# Exact versions, never their dependencies (checked above); the signature on Windows, where the operators run.
$signature = @{}
if ($IsWindows) {
    $signature.AuthenticodeCheck = $true
}
foreach ($file in $moduleSets.Keys) {
    $set = $moduleSets[$file]
    foreach ($name in $set.Keys | Sort-Object) {
        $version = $set[$name]
        if (Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -eq [version]$version }) {
            Write-Host "$name $version is installed ($file)"
            continue
        }
        if ($PSCmdlet.ShouldProcess("$name $version ($file)", 'Install-PSResource')) {
            Install-PSResource -Name $name -Version $version -Repository PSGallery -Scope CurrentUser -SkipDependencyCheck -TrustRepository @signature
            Write-Host "Installed $name $version ($file)"
        }
    }
}

if ($ModulesOnly) {
    return
}

# Settings of this clone: the secret scan of the staged changes before every commit, and git blame skipping the
# formatting commits (GitHub reads .git-blame-ignore-revs by itself).
$gitSettings = [ordered]@{
    'core.hooksPath'       = '.githooks'
    'blame.ignoreRevsFile' = '.git-blame-ignore-revs'
}
foreach ($key in $gitSettings.Keys) {
    $value = $gitSettings[$key]
    $current = git -C $root config --local --get $key
    if ($LASTEXITCODE -eq 0 -and $current -eq $value) {
        Write-Host "git $key is $value"
    }
    elseif ($PSCmdlet.ShouldProcess($root, "git config --local $key $value")) {
        git -C $root config --local $key $value
        if ($LASTEXITCODE -ne 0) {
            throw "git config $key failed with exit code $LASTEXITCODE."
        }
    }
}
