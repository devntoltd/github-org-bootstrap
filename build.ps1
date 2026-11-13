#Requires -Version 7.6

<#
.SYNOPSIS
Runs the checks of CI locally, or a developer script of tools/, from a menu or by name.

.DESCRIPTION
The checks and tools are those of build.psd1. './build.ps1 all' runs every check without stopping at a failed one,
prints a summary and exits with 1 when a check failed; a check whose command is missing is skipped with what to
install. './build.ps1 <name>' runs one check or tool and passes every other argument to it. Without arguments it
shows a numbered menu. The tools that write to GitHub run with -WhatIf only: their real run is recurring.yml's.

Checks and tools run from the repository root, wherever build.ps1 is started: a relative path among the parameters
is relative to the root, as with npm run or make (./build.ps1 lint -Path ./engine).

.EXAMPLE
./build.ps1

.EXAMPLE
./build.ps1 all

.EXAMPLE
./build.ps1 tests -Target 90
#>
# Not an advanced script on purpose, like run.ps1: every argument it does not bind stays in $args, with its parameter
# name, and reaches the check or tool.
param(
    # A check or tool of build.psd1, or all; without it the menu is shown.
    [string]$Name
)

$ErrorActionPreference = 'Stop'
# A failed check is its exit code, not an error, even when the session's profile turns that on.
$PSNativeCommandUseErrorActionPreference = $false
$manifest = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'build.psd1')
$checks = @($manifest.Checks)
$tools = @($manifest.Tools)
$names = @('all') + @($checks.Name) + @($tools.Name)

function Invoke-BuildCheck {
    # Runs one check from the current location and sets $Row.Result to passed, failed or skipped. The output of the
    # check is not captured: it goes on to the caller, and from a terminal straight to the console, colors included.
    param([hashtable]$Check, [object[]]$ExtraArgument = @(), [pscustomobject]$Row)

    if (-not (Get-Command -Name $Check.Command -ErrorAction SilentlyContinue)) {
        $install = if ($Check.Install) { $Check.Install } else { './tools/Install-DevTools.ps1' }
        Write-Host "Skipped: $($Check.Command) not found. Install: $install."
        $Row.Result = 'skipped'
        return
    }
    $tokenSet = $false
    if ($Check.GitHubToken -and -not $env:GH_TOKEN) {
        $token = if (Get-Command -Name 'gh' -ErrorAction SilentlyContinue) { gh auth token 2>$null }
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Host 'Skipped: no GH_TOKEN and no token from gh. Install: gh auth login.'
            $Row.Result = 'skipped'
            return
        }
        $env:GH_TOKEN = ([string]$token).Trim()
        $tokenSet = $true
    }
    try {
        $arguments = @(@($Check.Arguments) + $ExtraArgument | Where-Object { $null -ne $_ })
        # A check that is a script runs in this process and may set no exit code.
        $global:LASTEXITCODE = 0
        & $Check.Command @arguments
        $Row.Result = if ($LASTEXITCODE -eq 0) { 'passed' } else { 'failed' }
    }
    catch {
        # A check that throws fails alone: the ones after it still run.
        Write-Host "Failed: $($_.Exception.Message)"
        $Row.Result = 'failed'
    }
    finally {
        if ($tokenSet) {
            Remove-Item -Path 'Env:GH_TOKEN'
        }
    }
}

function Invoke-BuildCheckList {
    # Runs the checks in order without stopping at a failed one and prints a summary; $Failed gets the number of
    # failed checks. Nothing is returned, so the output of the checks is not captured.
    param([object[]]$Check, [object[]]$ExtraArgument = @(), [ref]$Failed)

    $rows = @($Check | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Result = $null; Seconds = 0 } })
    for ($i = 0; $i -lt $Check.Count; $i++) {
        Write-Host "== $($Check[$i].Name) ($($i + 1)/$($Check.Count)) =="
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-BuildCheck -Check $Check[$i] -ExtraArgument $ExtraArgument -Row $rows[$i]
        $rows[$i].Seconds = $watch.Elapsed.TotalSeconds
    }
    $width = ($rows | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    Write-Host ''
    foreach ($row in $rows) {
        Write-Host ('{0}  {1}  {2,6:0.0}s' -f $row.Name.PadRight($width), $row.Result.PadRight(7), $row.Seconds)
    }
    $count = @{}
    foreach ($outcome in 'passed', 'failed', 'skipped') {
        $count[$outcome] = @($rows | Where-Object { $_.Result -eq $outcome }).Count
    }
    Write-Host "$($count.passed) passed, $($count.failed) failed, $($count.skipped) skipped"
    $Failed.Value = $count.failed
}

if ($Name) {
    if ($names -notcontains $Name) {
        throw "Unknown name '$Name'. Names: $($names -join ', ')."
    }
}
elseif ($args.Count -gt 0) {
    throw 'Name the check or tool to pass parameters: ./build.ps1 <name> <parameters>.'
}
else {
    $entries = @(@{ Name = 'all'; Description = 'Every check below, then a summary' }) + $checks + $tools
    $width = ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    Write-Host 'Checks'
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ($i -eq $checks.Count + 1) {
            Write-Host 'Tools'
        }
        Write-Host ('{0,4}  {1}  {2}' -f ($i + 1), $entries[$i].Name.PadRight($width), $entries[$i].Description)
    }
    Write-Host ''
    Write-Host 'Parameters: ./build.ps1 <name> [parameters]'

    $number = 0
    while ($true) {
        $answer = Read-Host -Prompt 'Number (Enter to quit)'
        if (-not $answer) {
            return
        }
        # TryParse accepts white space around the number.
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $entries.Count) {
            break
        }
        Write-Host "Enter a number from 1 to $($entries.Count), or press Enter to quit."
    }
    $Name = $entries[$number - 1].Name
}

# As in run.ps1: $args keeps -Switch:$value as the name and a separate [bool], and @args would pass them on as the
# switch and a positional value.
if (@($args | Where-Object { $_ -is [bool] }).Count -gt 0) {
    throw 'Pass switches without a value: -Force, not -Force:$false.'
}
if ($Name -eq 'all' -and $args.Count -gt 0) {
    throw "Name one check to pass parameters: ./build.ps1 <check> <parameters>; 'all' takes none."
}

$tool = $tools | Where-Object { $_.Name -eq $Name }
$failures = 0
# The checks use paths relative to the repository root.
Push-Location -Path $PSScriptRoot
try {
    if ($tool) {
        $parameters = $tool.Parameters
        & (Join-Path -Path $PSScriptRoot -ChildPath $tool.Script) @parameters @args
        return
    }
    $list = if ($Name -eq 'all') { $checks } else { @($checks | Where-Object { $_.Name -eq $Name }) }
    Invoke-BuildCheckList -Check $list -ExtraArgument $args -Failed ([ref]$failures)
}
finally {
    Pop-Location
}
exit ([int]($failures -gt 0))
