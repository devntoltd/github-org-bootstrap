BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../DevModule.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/tests/TestModule.ps1')
}

Describe 'Import-DevModule' {
    BeforeEach {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        Add-TestModule -Root $folder -Name 'Fake.Dev' -Version '1.0.0'
        Add-TestModule -Root $folder -Name 'Fake.Dev' -Version '2.0.0'
        $script:devTools = Join-Path -Path $folder -ChildPath 'dev-tools.psd1'
        Set-Content -Path $devTools -Value "@{ Modules = @{ 'Fake.Dev' = '1.0.0'; 'Fake.Absent' = '1.0.0' }; Tools = @{} }"
        $script:savedModulePath = $env:PSModulePath
        $env:PSModulePath = $folder + [System.IO.Path]::PathSeparator + $env:PSModulePath
    }

    AfterEach {
        Get-Module -Name 'Fake.*' | Remove-Module -Force
        $env:PSModulePath = $script:savedModulePath
    }

    It 'loads the version of dev-tools.psd1 although a newer one is installed' {
        Import-DevModule -Name 'Fake.Dev' -Path $devTools

        @(Get-Module -Name 'Fake.Dev').Version | Should -Be @([version]'1.0.0')
    }

    It 'throws with the install hint when the version is not installed' {
        { Import-DevModule -Name 'Fake.Absent' -Path $devTools } | Should -Throw '*Fake.Absent 1.0.0 (dev-tools.psd1) is not installed*./tools/Install-DevTools.ps1*'
    }

    It 'throws when the module is not in dev-tools.psd1' {
        { Import-DevModule -Name 'Fake.Unknown' -Path $devTools } | Should -Throw '*Fake.Unknown is not in the Modules of dev-tools.psd1*'
    }

    It 'throws when another version is already loaded' {
        Import-Module -Name 'Fake.Dev' -RequiredVersion '2.0.0' -Global

        { Import-DevModule -Name 'Fake.Dev' -Path $devTools } | Should -Throw '*Fake.Dev 2.0.0 is loaded in this session*start a new pwsh*'
    }
}
