BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:lintScript = Join-Path -Path $script:root -ChildPath 'tools/Invoke-Lint.ps1'
    $script:settingsPath = Join-Path -Path $script:root -ChildPath 'PSScriptAnalyzerSettings.psd1'

    # A finding as Invoke-ScriptAnalyzer returns it.
    function Get-TestFinding {
        param([string]$RuleName, [string]$ScriptName = 'a.ps1', [int]$Line = 1)

        [pscustomobject]@{ RuleName = $RuleName; Severity = 'Warning'; ScriptName = $ScriptName; Line = $Line; Message = 'm' }
    }
}

Describe 'PSScriptAnalyzerSettings.psd1' {
    # VS Code reads the file directly. With IncludeRules the analyzer runs only the listed rules, IncludeDefaultRules
    # notwithstanding, so the default rules would be off in the editor.
    It 'leaves the default rules on' {
        $settings = Import-PowerShellDataFile -Path $script:settingsPath

        $settings.Keys | Should -Not -Contain 'IncludeRules'
    }
}

Describe 'Invoke-Lint.ps1 with the repository settings' {
    It 'reports a default rule and a formatting rule' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'probe'
        New-Item -ItemType Directory -Path $folder | Out-Null
        # gci: PSAvoidUsingCmdletAliases (a default rule); '{' on its own line: PSPlaceOpenBrace (formatting).
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'probe.ps1') -Value "function Get-Probe`n{`n    gci`n}"
        Mock Write-Host { }

        { & $script:lintScript -Path $folder } | Should -Throw '*2 finding(s)*'

        Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'PSAvoidUsingCmdletAliases' }
        Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'PSPlaceOpenBrace' }
    }
}

Describe 'Invoke-Lint.ps1' {
    BeforeEach {
        Mock Get-ScriptAnalyzerRule {
            'PSAvoidUsingCmdletAliases', 'PSAvoidUsingWriteHost', 'PSPlaceOpenBrace' |
                ForEach-Object { [pscustomobject]@{ RuleName = $_ } }
        }
        Mock Invoke-ScriptAnalyzer { }
        Mock Write-Host { }
    }

    It 'runs every rule but the excluded ones in an analyzer call of its own' {
        & $script:lintScript

        Should -Invoke Invoke-ScriptAnalyzer -Times 2 -Exactly
        foreach ($rule in 'PSAvoidUsingCmdletAliases', 'PSPlaceOpenBrace') {
            Should -Invoke Invoke-ScriptAnalyzer -Times 1 -Exactly -ParameterFilter {
                "$($Settings.IncludeRules)" -eq $rule -and $Recurse
            }
        }
    }

    It 'passes the rule options of the settings to every call' {
        & $script:lintScript

        $options = (Import-PowerShellDataFile -Path $script:settingsPath).Rules
        Should -Invoke Invoke-ScriptAnalyzer -Times 2 -Exactly -ParameterFilter {
            $Settings.Rules.PSPlaceOpenBrace.OnSameLine -eq $options.PSPlaceOpenBrace.OnSameLine
        }
    }

    It 'prints nothing when nothing is found' {
        & $script:lintScript

        Should -Invoke Write-Host -Times 0
    }

    It 'prints every finding and throws with their count' {
        Mock Invoke-ScriptAnalyzer { Get-TestFinding -RuleName 'PSPlaceOpenBrace' -Line 3 } -ParameterFilter {
            "$($Settings.IncludeRules)" -eq 'PSPlaceOpenBrace'
        }
        Mock Invoke-ScriptAnalyzer { Get-TestFinding -RuleName 'PSAvoidUsingCmdletAliases' -Line 7 } -ParameterFilter {
            "$($Settings.IncludeRules)" -eq 'PSAvoidUsingCmdletAliases'
        }

        { & $script:lintScript } | Should -Throw '*2 finding(s)*'

        Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'PSPlaceOpenBrace' -and "$Object" -match 'PSAvoidUsingCmdletAliases' }
    }

    It 'fails on an error of the analyzer, which would otherwise drop the findings of the rule' {
        Mock Invoke-ScriptAnalyzer { Write-Error -Message "The term 'Get-Command' is not recognized" } -ParameterFilter {
            "$($Settings.IncludeRules)" -eq 'PSAvoidUsingCmdletAliases'
        }

        { & $script:lintScript } | Should -Throw '*PSAvoidUsingCmdletAliases*Get-Command*'
    }
}
