<#
.SYNOPSIS
Writes engine/settings.md, the reference of the settings pages and API endpoints, generated from the catalog.
.DESCRIPTION
Run after changing a row, a settings page or engine/api-endpoints.psd1; the tests fail while the committed file is stale.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path -Path $root -ChildPath 'shared/Bootstrap.Common.psm1') -Force
Import-Module (Join-Path -Path $root -ChildPath 'engine/GitHubOrg.psm1') -Force

$text = Get-GitHubOrgSettingReference
# UTF-8 without BOM and LF, as .gitattributes stores it, so the drift test compares equal on every platform.
[System.IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'engine/settings.md'), $text, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Wrote engine/settings.md'
