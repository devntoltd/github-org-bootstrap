BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:lock = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'modules.lock.psd1')
}

Describe 'modules.lock.psd1' {
    It 'holds an exact version for every module' {
        # Empty while the engine needs no runtime module.
        foreach ($name in $lock.Keys) {
            $lock[$name] | Should -Match '^\d+\.\d+\.\d+(\.\d+)?$' -Because $name
        }
    }
}

Describe 'dev-tools.psd1' {
    BeforeAll {
        $script:devTools = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'dev-tools.psd1')
    }

    It 'holds an exact version for every module of the checks' {
        @($devTools.Modules.Keys | Sort-Object) | Should -Be @('Pester', 'PSScriptAnalyzer')
        foreach ($name in $devTools.Modules.Keys) {
            $devTools.Modules[$name] | Should -Match '^\d+\.\d+\.\d+$' -Because $name
        }
    }

    It 'has a winget package, an exact version and a GitHub repository for every tool' {
        $devTools.Tools.Count | Should -BeGreaterThan 0
        foreach ($name in $devTools.Tools.Keys) {
            $tool = $devTools.Tools[$name]
            $tool.WinGetId | Should -Not -BeNullOrEmpty -Because $name
            $tool.Version | Should -Match '^\d+\.\d+\.\d+$' -Because $name
            $tool.Repository | Should -Match '^[\w.-]+/[\w.-]+$' -Because $name
        }
    }
}
