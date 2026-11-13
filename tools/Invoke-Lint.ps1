<#
.SYNOPSIS
Runs PSScriptAnalyzer with the repository settings, one rule per call; prints nothing when nothing is found.
.DESCRIPTION
Runs every analyzer rule except the ExcludeRules of PSScriptAnalyzerSettings.psd1, with the rule options of that file
(a configurable rule runs only when its options set Enable = $true). Prints the findings and throws when there are
findings or when the analyzer itself fails.

One rule per call because the analyzer runs the rules of a file in parallel, and the rules that look up commands
share a cache that is not thread-safe (PowerShell/PSScriptAnalyzer#1867, PowerShell/PSScriptAnalyzer#2205): with every rule in one call, some
rules fail at random with "The term 'Get-Command' is not recognized" and their findings are lost, or pwsh crashes.
.EXAMPLE
./tools/Invoke-Lint.ps1
#>
[CmdletBinding()]
param(
    # Folder analyzed recursively.
    [string]$Path = (Split-Path -Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

# The PSScriptAnalyzer version of dev-tools.psd1, never a newer installed one.
. (Join-Path -Path $PSScriptRoot -ChildPath 'DevModule.ps1')
Import-DevModule -Name 'PSScriptAnalyzer'
$settings = Import-PowerShellDataFile -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'PSScriptAnalyzerSettings.psd1')

$findings = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$rules = Get-ScriptAnalyzerRule | Where-Object { $_.RuleName -notin $settings.ExcludeRules }
foreach ($rule in $rules) {
    $ruleSettings = @{ IncludeRules = [string[]]@($rule.RuleName); Rules = $settings.Rules }
    $errors = $null
    $result = Invoke-ScriptAnalyzer -Path $Path -Recurse -Settings $ruleSettings -ErrorAction SilentlyContinue -ErrorVariable errors
    foreach ($finding in @($result)) {
        $findings.Add($finding)
    }
    foreach ($errorRecord in @($errors)) {
        $failures.Add("$($rule.RuleName): $($errorRecord.Exception.Message)")
    }
}

if ($findings.Count -gt 0) {
    Write-Host ($findings | Format-Table -Property RuleName, Severity, ScriptName, Line, Message -AutoSize | Out-String -Width 4096)
}
if ($failures.Count -gt 0) {
    throw "PSScriptAnalyzer failed, so findings may be missing:`n$($failures -join "`n")"
}
if ($findings.Count -gt 0) {
    throw "PSScriptAnalyzer: $($findings.Count) finding(s)."
}
