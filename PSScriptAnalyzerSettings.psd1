@{
    # Every rule runs except these. Interactive operator script: console output via Write-Host is intended.
    # No IncludeRules: with it the analyzer runs only the listed rules (IncludeDefaultRules notwithstanding), so the
    # default rules would be off. A configurable rule below runs when its options set Enable = $true.
    # ./tools/Invoke-Lint.ps1 (CI, the Lint task) runs one rule per call; see the script for why.
    # PSMissingModuleManifestField: it takes every .psd1 without manifest keys, such as the empty modules.lock.psd1,
    # for a manifest; the one real manifest, engine/GitHubOrg.psd1, is checked by engine/tests/Manifest.Tests.ps1.
    ExcludeRules = @('PSAvoidUsingWriteHost', 'PSMissingModuleManifestField')

    # Off by default and left off:
    # - PSAvoidLongLines: about 1000 lines over 120 characters, mostly test data and messages that are kept whole.
    # - PSUseConstrainedLanguageMode: the scripts run in FullLanguage only (Az and gh need it).
    # - PSUseCompatibleSyntax/Commands/Types: every bootstrap.ps1 requires PowerShell 7.6, and the analyzer's
    #   compatibility profiles stop at 7.0; CI runs on Linux, so a Windows-only command fails the tests there.
    Rules        = @{
        # The formatting rules of the CodeFormattingStroustrup preset with its options, so CI, the Lint task and
        # VS Code check the formatting Invoke-Formatter -Settings ./PSScriptAnalyzerSettings.psd1 produces.
        PSPlaceOpenBrace                          = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace                         = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation                = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }
        # CheckPipeForRedundantWhitespace and CheckParameter are off in the preset and on here.
        PSUseConsistentWhitespace                 = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $true
            CheckSeparator                          = $true
            CheckParameter                          = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSAlignAssignmentStatement                = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing                        = @{
            Enable = $true
        }

        # Off by default, on here.
        PSAvoidSemicolonsAsLineTerminators        = @{
            Enable = $true
        }
        PSAvoidExclaimOperator                    = @{
            Enable = $true
        }
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }
        # function Get-X { param(...) }, not function Get-X(...).
        PSUseConsistentParametersKind             = @{
            Enable         = $true
            ParametersKind = 'ParamBlock'
        }
    }
}
