$ErrorActionPreference = 'Stop'

# The GitHub REST API version every call of Invoke-GhApi asks for: the engines are verified against its response shapes
# (raise it only after verifying them again, see CONTRIBUTING.md). Without the header GitHub picks its own default.
# Kept in this file: the weekly scripts in tools/ read this line by path (Get-PinnedGitHubApiVersion).
$script:GitHubApiVersion = '2026-03-10'

# One row of the versions a run prints first (Assert-GhVersion): name, installed, the label 'minimum' and its version,
# latest and a note.
$script:VersionRowFormat = '  {0,-26} installed {1,-8} {2,-7} {3,-8} latest {4}{5}'

# The areas of the module, dot-sourced so they share this module's scope.
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/ConfigShape.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Config.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Output.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/GitHub.ps1')

Export-ModuleMember -Function @(
    # src/ConfigShape.ps1, src/Config.ps1
    'Get-ConfigPattern', 'Get-ConfigPatternNode', 'Test-IsGuid', 'Test-ConfigShape', 'Get-ExceptionShape', 'Test-ExceptionList', 'Get-RecommendationReport',
    'Get-ItemExceptionReport', 'Get-RuleExceptionReport', 'ConvertTo-ConfigSchema', 'Import-BootstrapConfig'
    # src/Output.ps1
    'Write-StateProgress', 'Write-ApplyProgress', 'Complete-BootstrapProgress', 'Write-BootstrapPlan', 'Write-BootstrapRecommendation',
    'Write-BootstrapWaiver', 'Write-BootstrapSummary', 'Confirm-BootstrapPlan'
    # src/GitHub.ps1
    'Assert-GhVersion', 'Invoke-GhApi', 'Test-GhStatus', 'Get-GhStatus'
)
