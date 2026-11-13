#Requires -Version 7.6

<#
.SYNOPSIS
Applies the GitHub organization settings described in a config file and reports those that only an owner can change in
the web UI.

.EXAMPLE
./engine/bootstrap.ps1 -ConfigPath ./github.json -WhatIf

.EXAMPLE
./engine/bootstrap.ps1 -ConfigPath ./github.json -WhatIf -PageWalk

.EXAMPLE
./engine/bootstrap.ps1 -ConfigPath ./github.json -Force

.EXAMPLE
./engine/bootstrap.ps1 -ConfigPath ./github.json -ValidateOnly
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'WhatIf is forwarded to Invoke-GitHubOrgBootstrap, which calls ShouldProcess.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    # The config of the organization; it lives in the organization's own repository, never in the engine.
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [switch]$Force,

    # Skip the lookup of the latest gh release (offline or slow networks).
    [switch]$SkipLatestVersionCheck,

    # Also list the settings only a person can check, with the page of each.
    [switch]$ManualChecklist,

    # Also walk the settings pages one at a time, in the order of the settings menu, each row as the run read it.
    [switch]$PageWalk,

    # Only validate the config, offline: no gh, no sign-in, no GitHub call (a CI check of a config change).
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

# The engine needs no PowerShell modules besides shared.
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../shared/Bootstrap.Common.psm1') -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubOrg.psd1') -Force

# The gh version check runs inside, after the config is validated.
Invoke-GitHubOrgBootstrap -ConfigPath $ConfigPath -Force:$Force -ManualChecklist:$ManualChecklist -PageWalk:$PageWalk -ValidateOnly:$ValidateOnly -SkipLatestVersionCheck:$SkipLatestVersionCheck -WhatIf:$WhatIfPreference
