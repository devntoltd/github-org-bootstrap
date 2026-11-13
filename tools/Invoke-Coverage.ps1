<#
.SYNOPSIS
Runs every test with code coverage, prints the coverage per file and writes coverage.xml (JaCoCo).
.DESCRIPTION
Measures the module code of shared/ and of every stage (<stage>/*.psm1 and <stage>/src/*.ps1); test files and the
bootstrap.ps1 entry points are not measured. Fails (exit code 1) when a test fails or the coverage is below -Target.
In GitHub Actions the per-file table also goes to the job summary.
.EXAMPLE
./tools/Invoke-Coverage.ps1
.EXAMPLE
./tools/Invoke-Coverage.ps1 -Output Detailed -Target 90
#>
[CmdletBinding()]
param(
    # Minimum total coverage in percent.
    [ValidateRange(0, 100)]
    [double]$Target = 95,

    # Pester output verbosity.
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Normal'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent

# The Pester version of dev-tools.psd1, never a newer installed one.
. (Join-Path -Path $PSScriptRoot -ChildPath 'DevModule.ps1')
Import-DevModule -Name 'Pester'

# Module code only; a new stage directory (NN-name) is picked up without changing this list.
$codeDirectories = @(Join-Path -Path $root -ChildPath 'shared') +
@(Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -match '^\d{2}-' } | ForEach-Object { $_.FullName })
$codePaths = foreach ($directory in $codeDirectories) {
    Join-Path -Path $directory -ChildPath '*.psm1'
    $src = Join-Path -Path $directory -ChildPath 'src'
    if (Test-Path -Path $src) {
        Join-Path -Path $src -ChildPath '*.ps1'
    }
}

# Pester defaults otherwise. The modules under test run without Set-StrictMode, as CONTRIBUTING.md
# explains.
$config = New-PesterConfiguration
$config.Run.Path = $root
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @($codePaths)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = Join-Path -Path $root -ChildPath 'coverage.xml'
$config.CodeCoverage.CoveragePercentTarget = $Target
$result = Invoke-Pester -Configuration $config

function Get-RelativePath {
    param([string]$Path)

    return [System.IO.Path]::GetRelativePath($root, $Path) -replace '\\', '/'
}

$coverage = $result.CodeCoverage
$executed = ($coverage.CommandsExecuted | Group-Object -Property File -AsHashTable -AsString) ?? @{}
$missed = ($coverage.CommandsMissed | Group-Object -Property File -AsHashTable -AsString) ?? @{}
$rows = foreach ($file in @($coverage.FilesAnalyzed) | Sort-Object) {
    $hit = @($executed[$file]).Where({ $_ }).Count
    $lost = @($missed[$file]).Where({ $_ })
    $total = $hit + $lost.Count
    [pscustomobject]@{
        File        = Get-RelativePath -Path $file
        Coverage    = if ($total -gt 0) { [math]::Round(100 * $hit / $total, 1) } else { 100 }
        MissedLines = (@($lost | ForEach-Object { $_.Line } | Sort-Object -Unique) -join ', ')
    }
}
$percent = [math]::Round($coverage.CoveragePercent, 1)

$rows | Format-Table -Property File, Coverage, MissedLines -AutoSize | Out-Host
Write-Host "Coverage: $percent% (target $Target%), report: coverage.xml"

if ($env:GITHUB_STEP_SUMMARY) {
    $summary = @(
        "### Code coverage: $percent% (target $Target%)"
        ''
        '| File | Coverage | Missed lines |'
        '| --- | ---: | --- |'
        $rows | ForEach-Object { "| ``$($_.File)`` | $($_.Coverage)% | $($_.MissedLines) |" }
    )
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary
}

if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
    Write-Error "Tests failed: $($result.FailedCount) failed." -ErrorAction Continue
    exit 1
}
if ($percent -lt $Target) {
    Write-Error "Coverage $percent% is below the target $Target%." -ErrorAction Continue
    exit 1
}
