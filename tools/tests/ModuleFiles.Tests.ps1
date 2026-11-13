BeforeDiscovery {
    $root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:stageFiles = @(Get-ChildItem -Path $root -Filter 'modules.psd1' -Recurse -Depth 1 |
            ForEach-Object { @{ Stage = $_.Directory.Name; Path = $_.FullName } })
}

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

    It 'locks only modules a stage names' {
        $named = @(foreach ($file in Get-ChildItem -Path $root -Filter 'modules.psd1' -Recurse -Depth 1) {
                (Import-PowerShellDataFile -Path $file.FullName).Modules
            })
        foreach ($name in $lock.Keys) {
            $named | Should -Contain $name
        }
    }
}

# No stage of this repository has a modules.psd1 while the engine needs no runtime module.
Describe '<Stage>/modules.psd1' -ForEach $stageFiles -AllowNullOrEmptyForEach {
    It 'names locked modules, each once' {
        $modules = @((Import-PowerShellDataFile -Path $Path).Modules)

        $modules.Count | Should -BeGreaterThan 0
        @($modules | Sort-Object -Unique).Count | Should -Be $modules.Count
        foreach ($name in $modules) {
            $lock.Keys | Should -Contain $name
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
