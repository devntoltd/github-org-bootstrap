# engine/GitHubOrg.psd1: the version, the PowerShell floor and the exports of the engine module.
BeforeAll {
    $script:manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psd1'
    $script:changelogPath = Join-Path -Path $PSScriptRoot -ChildPath '../../CHANGELOG.md'
}

Describe 'engine/GitHubOrg.psd1' {
    It 'is a valid module manifest of GitHubOrg.psm1 for PowerShell 7.6' {
        $manifest = Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop

        $manifest.RootModule | Should -Be 'GitHubOrg.psm1'
        $manifest.PowerShellVersion | Should -Be ([version]'7.6')
    }

    It 'exports exactly the functions the module exports' {
        $data = Import-PowerShellDataFile -Path $script:manifestPath
        Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
        $module = Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force -PassThru

        @($data.FunctionsToExport | Sort-Object) | Should -Be @($module.ExportedFunctions.Keys | Sort-Object)
    }

    It 'has the version of the latest release in CHANGELOG.md' {
        $data = Import-PowerShellDataFile -Path $script:manifestPath
        $latest = Get-Content -LiteralPath $script:changelogPath | Where-Object { $_ -match '^## \[(\d+\.\d+\.\d+)\]' } | Select-Object -First 1
        $latest | Should -Not -BeNullOrEmpty

        $latest | Should -Match ('^## \[' + [regex]::Escape($data.ModuleVersion) + '\]')
    }
}
