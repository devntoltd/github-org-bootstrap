# Uses functions from shared/GitHubOrg.Common.psm1; the caller (bootstrap.ps1, tests) imports it first.
$ErrorActionPreference = 'Stop'

# Dot-sourced so every function lives in this module's scope (Pester -ModuleName GitHubOrg mocks rely on it).
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Config.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Config.Catalog.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Config.Inventory.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Config.Budget.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Config.CopilotSeat.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/State.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/State.Budget.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/State.CodeSecurity.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/State.CopilotSeat.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/State.Inventory.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/State.Ruleset.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.Budget.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.CodeSecurity.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.CopilotSeat.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.Inventory.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.Ruleset.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Plan.Page.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'src/Apply.ps1')

function Test-InteractiveHost {
    # Whether a person can answer at a stop: never in CI, with -NonInteractive (or its abbreviations down to -noni)
    # among the options of pwsh, or with redirected input. Arguments after -File or -Command belong to the script.
    param(
        [bool]$UserInteractive = [Environment]::UserInteractive,
        [bool]$InputRedirected = [Console]::IsInputRedirected,
        [string[]]$Arguments = [Environment]::GetCommandLineArgs()
    )

    $options = foreach ($argument in @($Arguments | Select-Object -Skip 1)) {
        if ($argument -match '^-(f|file|c|command|ec|encodedcommand)$') {
            break
        }
        $argument
    }
    $nonInteractive = @($options | Where-Object { $_ -match '^-noni(n(t(e(r(a(c(t(i(ve?)?)?)?)?)?)?)?)?)?$' }).Count -gt 0
    return $UserInteractive -and -not $InputRedirected -and -not $nonInteractive
}

function Open-SettingPage {
    # Opens a settings page in the browser; prints the address when that fails, and the walk goes on.
    param([Parameter(Mandatory)][string]$Url)

    try {
        # -WhatIf of the run reaches here; opening a page changes nothing on GitHub.
        Start-Process -FilePath $Url -WhatIf:$false -Confirm:$false -ErrorAction Stop
    }
    catch {
        Write-Host "Open $Url"
    }
}

$script:WalkPrompt = 'Enter: next page, q: end the walk. Enter confirms nothing.'

function Invoke-SettingPageWalk {
    # Prints the walk page by page and, with a person at the keyboard, opens and stops at each page that needs one.
    # Enter only moves on and q only ends the walk: nothing is confirmed or written.
    param([Parameter(Mandatory)][object]$Walk)

    $interactive = Test-InteractiveHost
    Write-Host (Format-SettingPageWalkStart -ReadAt $Walk.ReadAt)
    $pages = @($Walk.Pages)
    $other = @(Format-SettingPageWalkOther -Other $Walk.Other)
    $ended = $false
    for ($index = 0; $index -lt $pages.Count; $index++) {
        $page = $pages[$index]
        foreach ($line in @(Format-SettingPageWalkPage -Page $page -Index ($index + 1) -Total $pages.Count)) {
            Write-Host $line
        }
        if ($page.Stop -and $interactive) {
            Open-SettingPage -Url $page.Url
            Write-Host $script:WalkPrompt
            if ([string](Read-Host) -replace '\s', '' -ieq 'q') {
                $ended = $true
                break
            }
        }
    }
    if (-not $ended -and $other.Count -gt 0) {
        foreach ($line in $other) {
            Write-Host $line
        }
        if ($interactive) {
            Write-Host $script:WalkPrompt
            [void](Read-Host)
        }
    }
    Write-Host (Format-SettingPageWalkEnd -ManualCount $Walk.ManualCount)
}

function Invoke-GitHubOrgBootstrap {
    <#
    .SYNOPSIS
    Validates the config, checks the gh account, prints the plan and warnings, asks to confirm and applies the plan.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Confirm-BootstrapPlan calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [switch]$Force,

        # Also list the settings only a person can check.
        [switch]$ManualChecklist,

        # Also walk the settings pages one at a time, as the run read them.
        [switch]$PageWalk,

        # Only validate the config and print its recommendation warnings and waivers; no GitHub call.
        [switch]$ValidateOnly,

        # Skip the lookup of the latest gh release and REST API version (offline or slow networks).
        [switch]$SkipLatestVersionCheck
    )

    # The release that runs, first, so every output and bug report names it; the manifest holds it.
    $version = (Import-PowerShellDataFile -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubOrg.psd1')).ModuleVersion
    Write-Host "github-org-bootstrap $version"

    # One day for the whole run, so validation and the expiry of exceptions agree.
    $today = [datetime]::UtcNow.Date
    $config = Import-BootstrapConfig -Path $ConfigPath -Validate { param($config) Test-GitHubOrgConfig -Config $config -Today $today }
    if ($ValidateOnly) {
        Write-Host "Config $ConfigPath is valid (config format $($config.configVersion))."
        $recommendations = Get-RecommendationReport -Config $config -Shape (Get-GitHubOrgConfigShape) -Today $today
        $reviewers = Get-WorkflowReviewerReport -Config $config -Today $today
        foreach ($warning in @($recommendations.Warnings) + @($reviewers.Warnings)) {
            Write-Warning $warning
        }
        foreach ($waiver in @($recommendations.Waivers) + @($reviewers.Waivers)) {
            Write-BootstrapWaiver -Message $waiver
        }
        return
    }
    # After the config: a config the engine cannot read stops the run before any gh call.
    Assert-GhVersion -SkipLatestVersionCheck:$SkipLatestVersionCheck
    Assert-GitHubOrgContext -Organization $config.organization

    try {
        # The reference copies of the required workflows are beside the config, wherever the run starts.
        $configDirectory = Split-Path -Path (Resolve-Path -LiteralPath $ConfigPath).ProviderPath -Parent
        $state = Get-GitHubOrgState -Config $config -ConfigDirectory $configDirectory
        $plan = @(Get-GitHubOrgPlan -Config $config -CurrentState $state)
        Write-BootstrapPlan -Plan $plan
        # One report for the warnings and the waivers, so they cannot disagree. The desired state first: a setting
        # that differs from its recommendation, without an exception in force.
        $recommendations = Get-RecommendationReport -Config $config -Shape (Get-GitHubOrgConfigShape) -Today $today
        # Validation failed on its NotWaived already; what is left are the exceptions of the reviewer rule.
        $reviewers = Get-WorkflowReviewerReport -Config $config -Today $today
        foreach ($warning in @($recommendations.Warnings) + @(Get-GitHubOrgWarning -Config $config -CurrentState $state -Plan $plan) + @($reviewers.Warnings)) {
            Write-Warning $warning
        }
        foreach ($waiver in @($recommendations.Waivers) + @($reviewers.Waivers)) {
            Write-BootstrapWaiver -Message $waiver
        }
        # Before the question, so it shows with -WhatIf, an empty plan and -Force.
        $manual = Get-ManualSummary
        if ($manual) {
            Write-Host $manual
        }
        if ($ManualChecklist) {
            foreach ($line in @(Get-ManualChecklist -Config $config)) {
                Write-Host $line
            }
        }
        if ($PageWalk) {
            $walkWarnings = @(Get-SettingPageWalkWarning -Config $config -CurrentState $state -Plan $plan -Recommendations @($recommendations.Warnings) -Reviewers @($reviewers.Warnings))
            Invoke-SettingPageWalk -Walk (Get-SettingPageWalk -Config $config -CurrentState $state -Plan $plan -Warnings $walkWarnings -Today $today)
        }

        if (-not (Confirm-BootstrapPlan -Plan $plan -Target "GitHub organization $($config.organization)" -Cmdlet $PSCmdlet -Force:$Force)) {
            return
        }

        Invoke-GitHubOrgPlan -Plan $plan
        Write-BootstrapSummary -Applied $plan -Unchanged @()
    }
    finally {
        # The context check passed, so the token has the admin scopes; also after an error or an abort.
        Write-ScopeRemoveRecommendation
    }
}

Export-ModuleMember -Function Test-GitHubOrgConfig, Get-GitHubOrgConfigShape, Get-GitHubOrgSettingReference, Get-GitHubOrgReadField, Get-WorkflowReviewerReport, Assert-GitHubOrgContext, Get-GitHubOrgState, Get-GitHubOrgPlan, Get-GitHubOrgWarning, Invoke-GitHubOrgPlan, Invoke-GitHubOrgBootstrap
