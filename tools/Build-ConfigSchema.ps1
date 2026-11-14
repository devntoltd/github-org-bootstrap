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
Import-Module (Join-Path -Path $root -ChildPath 'shared/GitHubOrg.Common.psm1') -Force
Import-Module (Join-Path -Path $root -ChildPath 'engine/GitHubOrg.psm1') -Force

$text = ConvertTo-ConfigSchema -Shape (Get-GitHubOrgConfigShape) -Title 'github-org-bootstrap config'
# UTF-8 without BOM and LF, as .gitattributes stores it, so the drift tests compare equal on every platform.
[System.IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'engine/github.schema.json'), $text, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Wrote engine/github.schema.json'
