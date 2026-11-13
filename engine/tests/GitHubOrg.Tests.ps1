BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe '<Name>' -ForEach @(
    @{ Name = 'examples/github.json'; Path = '../examples/github.json' }
) {
    It 'is a valid config' {
        Mock -ModuleName Bootstrap.Common Write-Host { }
        $config = Import-BootstrapConfig -Path (Join-Path -Path $PSScriptRoot -ChildPath $Path)

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'covers every deviation from a recommendation with an exception' {
        Mock -ModuleName Bootstrap.Common Write-Host { }
        $config = Import-BootstrapConfig -Path (Join-Path -Path $PSScriptRoot -ChildPath $Path)

        # Any day before the first expiry: an expired exception is a runtime warning, by design, not a reason to fail CI.
        # Without exceptions, any day will do.
        $firstExpiry = ($config.exceptions | ForEach-Object { [datetime]::ParseExact($_.expiresOn, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) } | Sort-Object | Select-Object -First 1)
        $today = $firstExpiry ?? [datetime]::UtcNow.Date
        (Get-RecommendationReport -Config $config -Shape (Get-GitHubOrgConfigShape) -Today $today).Warnings | Should -BeNullOrEmpty
    }
}

Describe 'examples/github.json' {
    It 'uses placeholders for the organization and its people' {
        # A test cannot list real names (.ps1 files hold no project names), so it checks the placeholders instead.
        $config = Get-Content -Raw -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../examples/github.json') | ConvertFrom-Json

        $config.organization | Should -Be 'example-org'
        foreach ($login in @($config.inventory.owners) + @($config.copilotSeats.selected_usernames)) {
            $login | Should -BeLike 'example-*'
        }
    }
}

Describe 'Invoke-GitHubOrgBootstrap' {
    BeforeEach {
        $script:configPath = Join-Path -Path $TestDrive -ChildPath 'github.json'
        Get-TestGitHubOrgConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Mock -ModuleName GitHubOrg Assert-GhVersion { }
        Mock -ModuleName GitHubOrg Assert-GitHubOrgContext { }
        Mock -ModuleName GitHubOrg Get-GitHubOrgState { Get-DefaultTestGitHubOrgState }
        Mock -ModuleName GitHubOrg Invoke-GitHubOrgPlan { }
        Mock -ModuleName GitHubOrg Write-Warning { }
        Mock -ModuleName GitHubOrg Write-BootstrapRecommendation { }
        Mock -ModuleName GitHubOrg Write-BootstrapWaiver { }
        # The manual summary line, printed by the engine itself.
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName Bootstrap.Common Write-Host { }
        Mock -ModuleName Bootstrap.Common Read-Host { 'y' }
    }

    It 'reminds to remove the admin scopes after <Name>' -ForEach @(
        @{ Name = 'a successful run'; Arrange = { }; Run = { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -Force } }
        @{ Name = 'a dry run'; Arrange = { }; Run = { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf } }
        @{ Name = 'an abort'; Arrange = { Mock -ModuleName Bootstrap.Common Read-Host { 'n' } }; Run = { { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath } | Should -Throw '*Aborted by operator*' } }
        @{ Name = 'an error'; Arrange = { Mock -ModuleName GitHubOrg Invoke-GitHubOrgPlan { throw 'boom' } }; Run = { { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -Force } | Should -Throw 'boom' } }
    ) {
        . $Arrange

        . $Run

        Should -Invoke Write-BootstrapRecommendation -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Message -eq 'remove the admin scopes from gh until the next run:' -and $Command -eq 'gh auth refresh -h github.com -r admin:org,admin:org_hook' }
    }

    It 'does not remind when the gh account check fails' {
        Mock -ModuleName GitHubOrg Assert-GitHubOrgContext { throw 'no scope' }

        { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -Force } | Should -Throw 'no scope'

        Should -Invoke Write-BootstrapRecommendation -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'with -WhatIf prints the plan and warnings and changes nothing' {
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        Should -Invoke Assert-GitHubOrgContext -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Organization -eq 'contoso' }
        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Planned changes (16):' }
        # Eight checked settings differ, and SHA pinning becomes required.
        Should -Invoke Write-Warning -ModuleName GitHubOrg -Times 9 -Exactly
        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'reads the reference workflows from the directory of a relative config path' {
        $directory = Join-Path -Path $TestDrive -ChildPath 'cfg'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Copy-Item -LiteralPath $script:configPath -Destination $directory
        Push-Location -LiteralPath $TestDrive
        try {
            Invoke-GitHubOrgBootstrap -ConfigPath ./cfg/github.json -WhatIf
        }
        finally {
            Pop-Location
        }

        Should -Invoke Get-GitHubOrgState -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $ConfigDirectory -eq $directory }
    }

    It 'prints the name and version of the engine first' {
        $version = (Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psd1')).ModuleVersion

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -ValidateOnly

        Should -Invoke Write-Host -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Object -eq "github-org-bootstrap $version" }
    }

    It 'with -ValidateOnly validates the config and reads nothing from GitHub' {
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -ValidateOnly

        Should -Invoke Write-Host -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Object -like 'Config *github.json is valid (config format 1.0).' }
        Should -Invoke Assert-GitHubOrgContext -ModuleName GitHubOrg -Times 0 -Exactly
        Should -Invoke Get-GitHubOrgState -ModuleName GitHubOrg -Times 0 -Exactly
        Should -Invoke Write-BootstrapRecommendation -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'with -ValidateOnly stops on an invalid config' {
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = '2.0'
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -ValidateOnly } | Should -Throw '*configVersion*'
    }

    It 'with -ValidateOnly prints the recommendation warnings' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.members_can_create_repositories = $true
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -ValidateOnly

        Should -Invoke Write-Warning -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Message -like '*settings.members_can_create_repositories*' }
    }

    It 'applies the plan with -Force' {
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -Force

        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Plan.Count -eq 16 }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Done. Applied 16 change(s).' }
        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
    }

    It 'prints the warnings and waivers of one recommendation report, recommendations first' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName GitHubOrg Get-RecommendationReport { [pscustomobject]@{ Warnings = @('a recommendation'); Waivers = @('a waiver') } }
        Mock -ModuleName GitHubOrg Get-GitHubOrgWarning { 'a state warning' }
        Mock -ModuleName GitHubOrg Write-Warning { $script:calls.Add($Message) }
        Mock -ModuleName GitHubOrg Write-BootstrapWaiver { $script:calls.Add($Message) }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        $script:calls | Should -Be @('a recommendation', 'a state warning', 'a waiver')
        Should -Invoke Get-RecommendationReport -ModuleName GitHubOrg -Times 1 -Exactly
    }

    It 'prints the warnings and waivers of the workflow reviewer rule after the others' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName GitHubOrg Get-RecommendationReport { [pscustomobject]@{ Warnings = @('a recommendation'); Waivers = @('a waiver') } }
        Mock -ModuleName GitHubOrg Get-GitHubOrgWarning { 'a state warning' }
        Mock -ModuleName GitHubOrg Get-WorkflowReviewerReport { [pscustomobject]@{ NotWaived = @(); Warnings = @('a reviewer warning'); Waivers = @('a reviewer waiver') } }
        Mock -ModuleName GitHubOrg Write-Warning { $script:calls.Add($Message) }
        Mock -ModuleName GitHubOrg Write-BootstrapWaiver { $script:calls.Add($Message) }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        $script:calls | Should -Be @('a recommendation', 'a state warning', 'a reviewer warning', 'a waiver', 'a reviewer waiver')
        # Once in Test-GitHubOrgConfig, which turns NotWaived into errors, and once for the warnings and waivers.
        Should -Invoke Get-WorkflowReviewerReport -ModuleName GitHubOrg -Times 2 -Exactly
    }

    It 'prints <Name>' -ForEach @(
        @{ Name = 'an exception in force for a config without a team on the workflows as a waiver'; Patterns = @('**/CODEOWNERS'); Waiver = 1; Warning = 0 }
        @{ Name = 'an exception for a config with a team on the workflows as a warning'; Patterns = @('.github/workflows/**'); Waiver = 0; Warning = 1 }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.ruleset.rules.pullRequest.requiredReviewers[0].file_patterns = $Patterns
        $expires = [datetime]::UtcNow.Date.AddDays(60).ToString('yyyy-MM-dd')
        $config.exceptions = @("{ `"field`": `"ruleset.rules.pullRequest.requiredReviewers`", `"category`": `"waiver`", `"reason`": `"No second team yet`", `"expiresOn`": `"$expires`", `"reference`": null }" | ConvertFrom-Json)
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        Should -Invoke Write-BootstrapWaiver -ModuleName GitHubOrg -Times $Waiver -Exactly -ParameterFilter { $Message -like '*ruleset.rules.pullRequest.requiredReviewers - No second team yet' }
        Should -Invoke Write-Warning -ModuleName GitHubOrg -Times $Warning -Exactly -ParameterFilter { $Message -like 'The exception for ruleset.rules.pullRequest.requiredReviewers is not needed*' }
    }

    It 'asks after printing the plan, warnings and waivers, and applies on yes' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Bootstrap.Common Write-Host { if ($Object -like 'Planned changes*') { $script:calls.Add('plan') } }
        Mock -ModuleName GitHubOrg Write-Warning { $script:calls.Add('warning') }
        Mock -ModuleName GitHubOrg Get-RecommendationReport { [pscustomobject]@{ Warnings = @(); Waivers = @('a waiver') } }
        Mock -ModuleName GitHubOrg Write-BootstrapWaiver { $script:calls.Add('waiver') }
        Mock -ModuleName Bootstrap.Common Read-Host { $script:calls.Add('ask'); 'y' }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath

        # Every warning and waiver before the question, not only the first of each.
        $ask = $script:calls.IndexOf('ask')
        $script:calls.IndexOf('plan') | Should -Be 0
        $script:calls.LastIndexOf('warning') | Should -BeLessThan $ask
        $script:calls.LastIndexOf('waiver') | Should -BeLessThan $ask
        $script:calls.LastIndexOf('warning') | Should -BeLessThan $script:calls.IndexOf('waiver')
        $script:calls[-1] | Should -Be 'ask'
        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Prompt -eq 'Apply 16 change(s) to GitHub organization contoso? [y/N]' }
        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 1 -Exactly
    }

    It 'writes nothing when the operator answers no' {
        Mock -ModuleName Bootstrap.Common Read-Host { 'n' }

        { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath } | Should -Throw '*Aborted by operator*'

        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'rejects an invalid config before contacting GitHub and lists every error' {
        $config = Get-TestGitHubOrgConfig
        $config.organization = 'bad name'
        $config.actions.allowed_actions = 'any'
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        $thrown = { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -Force } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -Match "organization .*'bad name'"
        $thrown.Exception.Message | Should -Match "actions\.allowed_actions .*'any'"
        Should -Invoke Assert-GitHubOrgContext -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'prints warnings without asking or applying when there is nothing to change' {
        Mock -ModuleName GitHubOrg Get-GitHubOrgState {
            $state = Get-MatchingTestGitHubOrgState
            $state.Settings.two_factor_requirement_enabled = $false
            $state.Settings.email = 'security@contoso.com'
            $state.Settings.is_verified = $true
            $state
        }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath

        Should -Invoke Write-Warning -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Message -like '*two_factor_requirement_enabled is false*' }
        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'plans the code security actions with the others and changes nothing with -WhatIf' {
        Get-TestGitHubOrgConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8
        Mock -ModuleName GitHubOrg Get-GitHubOrgState {
            $state = Get-DefaultTestGitHubOrgState
            $state
        }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Planned changes (16):' }
        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'prints an exception in force after the warnings' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.members_can_invite_outside_collaborators = $true
        $expires = [datetime]::UtcNow.Date.AddDays(60).ToString('yyyy-MM-dd')
        $config.exceptions = @("{ `"field`": `"settings.members_can_invite_outside_collaborators`", `"category`": `"waiver`", `"reason`": `"Free plan`", `"expiresOn`": `"$expires`", `"reference`": null }" | ConvertFrom-Json)
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        Should -Invoke Write-BootstrapWaiver -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Message -eq "Waived until $expires (waiver): settings.members_can_invite_outside_collaborators - Free plan" }
    }
}

Describe 'Invoke-GitHubOrgBootstrap manual settings' {
    BeforeEach {
        InModuleScope GitHubOrg {
            $script:SavedDefinitions = $script:SettingDefinitions
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(
                @{ Section = 'settings'; Field = 'manual_probe'; Type = 'boolean'; Mode = 'manual'; Page = 'security'; UiGroup = 'Probe group'; UiLabel = 'Probe checkbox'; Recommended = $true; Why = 'A probe reason.' }
            )
        }
        $script:configPath = Join-Path -Path $TestDrive -ChildPath 'github.json'
        $config = Get-TestGitHubOrgConfig
        $config.settings | Add-Member -NotePropertyName manual_probe -NotePropertyValue $false
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8
        $script:calls = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName GitHubOrg Assert-GhVersion { }
        Mock -ModuleName GitHubOrg Assert-GitHubOrgContext { }
        Mock -ModuleName GitHubOrg Get-GitHubOrgState { Get-DefaultTestGitHubOrgState }
        Mock -ModuleName GitHubOrg Invoke-GitHubOrgPlan { }
        Mock -ModuleName GitHubOrg Write-Warning { $script:calls.Add('warning') }
        Mock -ModuleName GitHubOrg Write-BootstrapRecommendation { }
        Mock -ModuleName GitHubOrg Write-BootstrapWaiver { }
        Mock -ModuleName GitHubOrg Write-Host { $script:calls.Add([string]$Object) }
        Mock -ModuleName Bootstrap.Common Write-Host { }
        Mock -ModuleName Bootstrap.Common Read-Host { $script:calls.Add('ask'); 'y' }
    }

    AfterEach {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = $script:SavedDefinitions
        }
    }

    It 'prints one line about the manual settings after the warnings' {
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        $summary = @($script:calls | Where-Object { $_ -like 'Manual:*' })
        $count = InModuleScope GitHubOrg { @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'manual' }).Count }
        $summary.Count | Should -Be 1
        $summary[0] | Should -BeLike "Manual: $count settings *"
        $script:calls.IndexOf($summary[0]) | Should -BeGreaterThan $script:calls.LastIndexOf('warning')
        $script:calls | Should -Not -Contain '    A probe reason.'
    }

    It 'prints the checklist with <Case>' -ForEach @(
        @{ Case = '-WhatIf'; Parameters = @{ WhatIf = $true }; EmptyPlan = $false }
        @{ Case = 'an empty plan'; Parameters = @{}; EmptyPlan = $true }
        @{ Case = '-Force'; Parameters = @{ Force = $true }; EmptyPlan = $false }
        @{ Case = 'a confirmation'; Parameters = @{}; EmptyPlan = $false }
    ) {
        if ($EmptyPlan) {
            Mock -ModuleName GitHubOrg Get-GitHubOrgState { Get-MatchingTestGitHubOrgState }
        }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -ManualChecklist @Parameters

        $script:calls | Should -Contain 'Authentication security  https://github.com/organizations/contoso/settings/security'
        $script:calls | Should -Contain '  Probe group: Probe checkbox -> expected false (recommended true)'
        $script:calls | Should -Contain '    A probe reason.'
        if ($Case -eq 'a confirmation') {
            $script:calls.IndexOf('    A probe reason.') | Should -BeLessThan $script:calls.IndexOf('ask')
        }
    }

    It 'shows the hint after the label' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                    if ($_.Field -eq 'manual_probe') {
                        $row = $_.Clone()
                        $row.Hint = 'true is "Probe on"'
                        $row
                    }
                    else { $_ }
                })
        }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain '  Probe group: Probe checkbox (true is "Probe on") -> expected false (recommended true)'
    }

    It 'says so with -ManualChecklist when no setting needs a manual check' {
        # Without manual rows the config has none of their keys; a section left without fields stays, empty.
        $manual = InModuleScope GitHubOrg {
            $rows = @($script:SavedDefinitions | Where-Object { $_.Mode -eq 'manual' })
            $script:SettingDefinitions = @($script:SavedDefinitions | Where-Object { $_.Mode -ne 'manual' })
            $rows
        }
        $config = Get-TestGitHubOrgConfig
        foreach ($row in $manual) {
            $node = $config
            foreach ($part in $row.Section.Split('.')) {
                $node = $node.$part
            }
            $node.PSObject.Properties.Remove($row.Field)
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain 'No settings need a manual check.'
        $script:calls | Where-Object { $_ -like 'Manual:*' } | Should -BeNullOrEmpty
    }

    It 'leaves the recommendation out when the config follows it' {
        $config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
        $config.settings.manual_probe = $true
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain '  Probe group: Probe checkbox -> expected true'
    }

    It 'shows the hint of a row without a label' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                    if ($_.Field -eq 'manual_probe') {
                        $row = $_.Clone()
                        $row.Remove('UiLabel')
                        $row.Hint = 'true is "Probe on"'
                        $row
                    }
                    else { $_ }
                })
        }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain '  Probe group: true is "Probe on" -> expected false (recommended true)'
    }

    It 'lists the manual rows of each page under its own address' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(
                @{ Section = 'settings'; Field = 'manual_probe_2'; Type = 'boolean'; Mode = 'manual'; Page = 'deploy_keys'; UiGroup = 'Other group'; UiLabel = 'Other probe'; Why = 'Another reason.' }
            )
        }
        $config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
        $config.settings | Add-Member -NotePropertyName manual_probe_2 -NotePropertyValue $false
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $security = $script:calls.IndexOf('Authentication security  https://github.com/organizations/contoso/settings/security')
        $deployKeys = $script:calls.IndexOf('Deploy keys  https://github.com/organizations/contoso/settings/deploy_keys')
        $deployKeys | Should -BeGreaterThan -1
        $script:calls.IndexOf('  Other group: Other probe -> expected false') | Should -Be ($deployKeys + 1)
        $script:calls.IndexOf('  Probe group: Probe checkbox -> expected false (recommended true)') | Should -BeGreaterThan $security
    }

    It 'lists the manual rows of a page in its Order' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(
                @{ Section = 'settings'; Field = 'manual_probe_2'; Type = 'boolean'; Mode = 'manual'; Page = 'security'; UiGroup = 'Probe group'; UiLabel = 'Second probe'; Why = 'A second reason.' }
            )
            $script:SavedPages = $script:SettingPages
            $script:SettingPages = @($script:SettingPages | ForEach-Object {
                    if ($_.Path -eq 'security') {
                        $page = $_.Clone()
                        $page.Order = @('settings.manual_probe_2') + @($page.Order) + @('settings.manual_probe')
                        $page
                    }
                    else { $_ }
                })
        }
        $config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
        $config.settings | Add-Member -NotePropertyName manual_probe_2 -NotePropertyValue $false
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        try {
            Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist
        }
        finally {
            InModuleScope GitHubOrg { $script:SettingPages = $script:SavedPages }
        }

        $second = $script:calls.IndexOf('  Probe group: Second probe -> expected false')
        $second | Should -BeGreaterThan -1
        $second | Should -BeLessThan $script:calls.IndexOf('  Probe group: Probe checkbox -> expected false (recommended true)')
    }

    It 'lists a manual row without a group' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                    if ($_.Field -eq 'manual_probe') {
                        $row = $_.Clone()
                        $row.Remove('UiGroup')
                        $row.UiLabel = 'Only allow secure methods'
                        $row
                    }
                    else { $_ }
                })
        }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain '  Only allow secure methods -> expected false (recommended true)'
    }

    It 'names the option of a manual row' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                    if ($_.Field -eq 'manual_probe') {
                        $row = $_.Clone()
                        $row.Type = 'enum'
                        $row.Values = @('disabled', 'enabled')
                        $row.Options = @{ disabled = 'Disabled'; enabled = 'Enabled' }
                        $row.Recommended = 'disabled'
                        $row
                    }
                    else { $_ }
                })
        }
        $config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
        $config.settings.manual_probe = 'enabled'
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain '  Probe group: Probe checkbox -> expected enabled ("Enabled") (recommended disabled ("Disabled"))'
    }

    It 'never prints the value of a sensitive row' {
        # A string, so the configured and the recommended value are text no other output holds.
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions | ForEach-Object {
                    if ($_.Field -eq 'manual_probe') {
                        $row = $_.Clone()
                        $row.Type = 'string'
                        $row.Pattern = '^\S+$'
                        $row.Rule = 'a word'
                        $row.Recommended = 'recommended-7f3a'
                        $row.Sensitive = $true
                        $row
                    }
                    else { $_ }
                })
        }
        $config = Get-Content -Raw -Path $script:configPath | ConvertFrom-Json
        $config.settings.manual_probe = 'configured-9c2e'
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8
        Mock -ModuleName GitHubOrg Write-Warning { $script:calls.Add("warning: $Message") }
        Mock -ModuleName GitHubOrg Write-BootstrapRecommendation { $script:calls.Add("recommendation: $Message $Command") }
        Mock -ModuleName Bootstrap.Common Write-Host { $script:calls.Add([string]$Object) }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        $script:calls | Should -Contain '  Probe group: Probe checkbox -> expected a value that is not shown'
        @($script:calls | Where-Object { $_ -like 'warning: settings.manual_probe *' }).Count | Should -Be 1
        @($script:calls | Where-Object { $_ -like '*configured-9c2e*' -or $_ -like '*recommended-7f3a*' }) | Should -BeNullOrEmpty
    }

    It 'prints one line about the manual settings of the config' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = $script:SavedDefinitions
        }
        Get-TestGitHubOrgConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf

        @($script:calls | Where-Object { $_ -like 'Manual: * settings have no API read*' }).Count | Should -Be 1
        $script:calls | Should -Not -Contain '    A probe reason.'
    }

    It 'lists every manual row of the config once in the checklist' {
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = $script:SavedDefinitions
        }
        Get-TestGitHubOrgConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8
        $count = InModuleScope GitHubOrg { @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'manual' }).Count }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -ManualChecklist

        @($script:calls | Where-Object { $_ -like '  * -> expected *' }).Count | Should -Be $count
    }
}

Describe 'Test-InteractiveHost' {
    It 'says <Expected> for <Case>' -ForEach @(
        @{ Case = 'a terminal'; UserInteractive = $true; InputRedirected = $false; Arguments = @('pwsh', '-File', 'bootstrap.ps1'); Expected = $true }
        @{ Case = 'redirected input'; UserInteractive = $true; InputRedirected = $true; Arguments = @('pwsh'); Expected = $false }
        @{ Case = 'no user session'; UserInteractive = $false; InputRedirected = $false; Arguments = @('pwsh'); Expected = $false }
        @{ Case = '-NonInteractive'; UserInteractive = $true; InputRedirected = $false; Arguments = @('pwsh', '-NonInteractive', '-File', 'bootstrap.ps1'); Expected = $false }
        @{ Case = 'its abbreviation -noni'; UserInteractive = $true; InputRedirected = $false; Arguments = @('pwsh', '-noni', '-Command', 'x'); Expected = $false }
        @{ Case = 'a script argument that starts like it'; UserInteractive = $true; InputRedirected = $false; Arguments = @('pwsh', '-File', 'bootstrap.ps1', '-NonInteresting'); Expected = $true }
    ) {
        InModuleScope GitHubOrg -Parameters $_ {
            param($UserInteractive, $InputRedirected, $Arguments, $Expected)
            Test-InteractiveHost -UserInteractive $UserInteractive -InputRedirected $InputRedirected -Arguments $Arguments | Should -Be $Expected
        }
    }
}

Describe 'Open-SettingPage' {
    It 'opens the page also under -WhatIf, which the usual walk runs with' {
        InModuleScope GitHubOrg {
            # Start-Process follows the -WhatIf preference of the run unless it is told otherwise.
            Mock Start-Process { }
            $WhatIfPreference = $true

            Open-SettingPage -Url 'https://github.com/organizations/contoso/settings/security'

            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'https://github.com/organizations/contoso/settings/security' -and $PesterBoundParameters.ContainsKey('WhatIf') -and -not $WhatIf }
        }
    }
}

Describe 'Invoke-GitHubOrgBootstrap page walk' {
    BeforeEach {
        $script:configPath = Join-Path -Path $TestDrive -ChildPath 'github.json'
        Get-TestGitHubOrgConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:opened = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName GitHubOrg Assert-GhVersion { }
        Mock -ModuleName GitHubOrg Assert-GitHubOrgContext { }
        Mock -ModuleName GitHubOrg Get-GitHubOrgState {
            $state = Get-MatchingTestGitHubOrgState
            $state | Add-Member -NotePropertyName ReadAt -NotePropertyValue ([datetime]::SpecifyKind([datetime]::new(2026, 11, 9, 14, 3, 12), 'Utc'))
            $state
        }
        Mock -ModuleName GitHubOrg Invoke-GitHubOrgPlan { }
        Mock -ModuleName GitHubOrg Write-Warning { $script:calls.Add("warning: $Message") }
        Mock -ModuleName GitHubOrg Write-BootstrapRecommendation { }
        Mock -ModuleName GitHubOrg Write-BootstrapWaiver { }
        Mock -ModuleName GitHubOrg Write-Host { $script:calls.Add([string]$Object) }
        Mock -ModuleName GitHubOrg Test-InteractiveHost { $true }
        Mock -ModuleName GitHubOrg Open-SettingPage { $script:opened.Add($Url) }
        Mock -ModuleName GitHubOrg Read-Host { $script:calls.Add('next'); '' }
        Mock -ModuleName Bootstrap.Common Write-Host { }
        Mock -ModuleName Bootstrap.Common Read-Host { $script:calls.Add('ask'); 'y' }
    }

    It 'walks the pages before the confirmation with <Case>' -ForEach @(
        @{ Case = '-WhatIf'; Parameters = @{ WhatIf = $true } }
        @{ Case = '-Force'; Parameters = @{ Force = $true } }
        @{ Case = 'a confirmation'; Parameters = @{} }
    ) {
        Mock -ModuleName GitHubOrg Get-GitHubOrgState { Get-DefaultTestGitHubOrgState }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -PageWalk @Parameters

        $start = $script:calls.IndexOf('Page walk of the state read by this run. The marks show that read, not the pages now.')
        $lastWarning = @($script:calls | Where-Object { $_ -like 'warning: *' })[-1]
        $start | Should -BeGreaterThan $script:calls.LastIndexOf($lastWarning)
        $end = @($script:calls | Where-Object { $_ -like '* manual settings were not checked by this run; the walk records nothing.' })
        $end.Count | Should -Be 1
        $script:calls.IndexOf($end[0]) | Should -BeGreaterThan $start
        if ($Case -eq 'a confirmation') {
            $script:calls.IndexOf($end[0]) | Should -BeLessThan $script:calls.IndexOf('ask')
        }
    }

    It 'stops and opens only the pages with something to do' {
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk

        $headers = @($script:calls | Where-Object { $_ -match '^\[\d+/\d+\] ' })
        $stops = @($script:calls | Where-Object { $_ -eq 'next' })
        $stops.Count | Should -Be $script:opened.Count
        $stops.Count | Should -BeGreaterThan 0
        $stops.Count | Should -BeLessThan $headers.Count
        $script:opened | Should -Contain 'https://github.com/organizations/contoso/settings/security'
        $script:opened | Should -Not -Contain 'https://github.com/organizations/contoso/settings/deploy_keys'
    }

    It 'prints the time of the read first and the prompt at a stop' {
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk

        $script:calls | Should -Contain 'Page walk of the state read at 2026-11-09 14:03:12 UTC. The marks show that read, not the pages now.'
        $script:calls | Should -Contain 'Enter: next page, q: end the walk. Enter confirms nothing.'
    }

    It 'ends the walk on q and still asks to confirm' {
        Mock -ModuleName GitHubOrg Get-GitHubOrgState { Get-DefaultTestGitHubOrgState }
        Mock -ModuleName GitHubOrg Read-Host { $script:calls.Add('next'); 'q' }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -PageWalk

        @($script:calls | Where-Object { $_ -eq 'next' }).Count | Should -Be 1
        $end = @($script:calls | Where-Object { $_ -like '* manual settings were not checked by this run; the walk records nothing.' })
        $end.Count | Should -Be 1
        $script:calls.IndexOf($end[0]) | Should -BeLessThan $script:calls.IndexOf('ask')
        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 1 -Exactly
    }

    It 'changes no mark and writes nothing on Enter' {
        Mock -ModuleName GitHubOrg Set-Content { }
        Mock -ModuleName GitHubOrg Out-File { }
        Mock -ModuleName GitHubOrg New-Item { }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk
        $first = @($script:calls)
        $script:calls.Clear()
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk

        @($script:calls) | Should -Be $first
        @($first | Where-Object { $_ -like '    `[set`]*' }).Count | Should -BeGreaterThan 0
        Should -Invoke Invoke-GitHubOrgPlan -ModuleName GitHubOrg -Times 0 -Exactly
        Should -Invoke Set-Content -ModuleName GitHubOrg -Times 0 -Exactly
        Should -Invoke Out-File -ModuleName GitHubOrg -Times 0 -Exactly
        Should -Invoke New-Item -ModuleName GitHubOrg -Times 0 -Exactly
    }

    It 'neither stops nor opens a page without an interactive host' {
        Mock -ModuleName GitHubOrg Test-InteractiveHost { $false }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk

        @($script:calls | Where-Object { $_ -eq 'next' }) | Should -BeNullOrEmpty
        $script:opened | Should -BeNullOrEmpty
        @($script:calls | Where-Object { $_ -match '^\[\d+/\d+\] ' }).Count | Should -BeGreaterThan 1
    }

    It 'prints the same warnings with and without -PageWalk' {
        Mock -ModuleName GitHubOrg Get-GitHubOrgState { Get-DefaultTestGitHubOrgState }

        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf
        $without = @($script:calls | Where-Object { $_ -like 'warning: *' })
        $script:calls.Clear()
        Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk

        $without.Count | Should -BeGreaterThan 0
        @($script:calls | Where-Object { $_ -like 'warning: *' }) | Should -Be $without
    }

    It 'calls no API during the walk' {
        Mock -ModuleName Bootstrap.Common Invoke-GhApi { throw 'no API call expected' }
        Mock -ModuleName GitHubOrg Invoke-GhApi { throw 'no API call expected' }

        { Invoke-GitHubOrgBootstrap -ConfigPath $script:configPath -WhatIf -PageWalk } | Should -Not -Throw
    }
}
