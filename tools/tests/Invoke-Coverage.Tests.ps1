BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:coverageScript = Join-Path -Path $script:root -ChildPath 'tools/Invoke-Coverage.ps1'
    # Pester mocks only commands that exist; the script dot-sources the same file.
    . (Join-Path -Path $script:root -ChildPath 'tools/DevModule.ps1')
}

Describe 'Invoke-Coverage.ps1' {
    BeforeEach {
        Mock Import-DevModule { }
        Mock Invoke-Pester {
            [pscustomobject]@{
                FailedCount  = 0
                Result       = 'Passed'
                CodeCoverage = [pscustomobject]@{
                    CoveragePercent  = 100
                    FilesAnalyzed    = @()
                    CommandsExecuted = @()
                    CommandsMissed   = @()
                }
            }
        }
        Mock Out-Host { }
        Mock Write-Host { }
        # In CI GITHUB_STEP_SUMMARY is set: the stand-in result must not reach the job summary of the real run.
        Mock Add-Content { }
    }

    # Module code is every .psm1 and every .ps1 in a src directory, outside the tests and outside a pinned engine
    # checkout; a directory move must not drop any of it from the measurement without a failing test.
    It 'measures every module file of the repository' {
        $expected = @(Get-ChildItem -Path $root -Recurse -File -Include '*.psm1', '*.ps1' |
                Where-Object {
                    $relative = [System.IO.Path]::GetRelativePath($root, $_.FullName) -replace '\\', '/'
                    $relative -notmatch '(^|/)(tests|\.engine|\.git)/' -and
                    ($_.Extension -eq '.psm1' -or $_.Directory.Name -eq 'src')
                } | ForEach-Object { $_.FullName } | Sort-Object)
        $expected | Should -Contain (Join-Path -Path $root -ChildPath 'engine/GitHubOrg.psm1')

        & $coverageScript

        Should -Invoke Invoke-Pester -Times 1 -Exactly
        Should -Invoke Invoke-Pester -ParameterFilter {
            $script:measured = @($Configuration.CodeCoverage.Path.Value | Get-ChildItem -File | ForEach-Object { $_.FullName })
            $true
        }
        @($script:measured | Sort-Object -Unique) | Should -Be $expected
    }
}
