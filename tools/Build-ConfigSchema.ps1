<#
.SYNOPSIS
Writes engine/github.schema.json, the JSON Schema of the config, generated from the engine's shape.
.DESCRIPTION
Run after changing a shape (a field, a rule, a recommendation); the tests fail while a committed schema is stale.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path -Path $root -ChildPath 'shared/Bootstrap.Common.psm1') -Force

$stages = @(
    @{ Directory = 'engine'; Module = 'GitHubOrg.psm1'; Shape = 'Get-GitHubOrgConfigShape'; File = 'github.schema.json'; Title = 'github-org-bootstrap config' }
)
foreach ($stage in $stages) {
    $directory = Join-Path -Path $root -ChildPath $stage.Directory
    Import-Module (Join-Path -Path $directory -ChildPath $stage.Module) -Force
    $text = ConvertTo-ConfigSchema -Shape (& $stage.Shape) -Title $stage.Title
    # UTF-8 without BOM and LF, as .gitattributes stores it, so the drift tests compare equal on every platform.
    [System.IO.File]::WriteAllText((Join-Path -Path $directory -ChildPath $stage.File), $text, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $($stage.Directory)/$($stage.File)"
}
