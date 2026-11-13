# The entry point in a child pwsh, with a native fake gh first on PATH: the import order, the gh version check and the
# forwarding of -WhatIf only break in bootstrap.ps1, which no other test runs.
BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/tests/NativeGh.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    $script:ghDirectory = Join-Path -Path $TestDrive -ChildPath 'gh'
    Register-TestNativeGh -Directory $script:ghDirectory
    $script:configPath = Join-Path -Path $TestDrive -ChildPath 'github.json'
    Get-TestGitHubOrgConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:configPath -Encoding utf8
    $script:bootstrap = Join-Path -Path $PSScriptRoot -ChildPath '../bootstrap.ps1'
    $script:pwsh = (Get-Process -Id $PID).Path

    function Get-TestRoute {
        # Every read of a run against a new organization: the latest gh release and REST API version, the context
        # check, the state (no ruleset yet) and an empty code security.
        $routes = Get-TestGhRoute -State (Get-DefaultTestGitHubOrgState)
        $routes['GET repos/cli/cli/releases/latest'] = Get-TestGhResponse -Body @{ tag_name = 'v2.102.0' }
        $routes['GET versions'] = Get-TestGhListResponse -Items @('2026-03-10', '2022-11-28')
        $routes['GET user/memberships/orgs/contoso'] = Get-TestGhResponse -Body @{ state = 'active'; role = 'admin'; user = @{ login = 'octocat' } }
        $routes['GET orgs/contoso/hooks'] = Get-TestGhListResponse -Items @()
        return Add-TestCodeSecurityRoute -Route $routes
    }
}

AfterAll {
    Unregister-TestNativeGh
}

Describe 'engine/bootstrap.ps1' {
    It 'requires -ConfigPath' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route (Get-TestRoute)

        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -WhatIf 2>&1 | ForEach-Object { [string]$_ }

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'ConfigPath'
        @(Get-TestNativeGhCall -Directory $script:ghDirectory) | Should -BeNullOrEmpty
    }

    It 'with -WhatIf prints the gh version and the plan, and only reads' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route (Get-TestRoute)

        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -WhatIf -ConfigPath $script:configPath 2>&1 | ForEach-Object { [string]$_ }
        $exitCode = $LASTEXITCODE

        $text = $output -join "`n"
        $exitCode | Should -Be 0 -Because $text
        $text | Should -Match 'gh\s+installed 2\.101\.0\s+minimum 2\.48\.0\s+latest 2\.102\.0  \(update available\)'
        $text | Should -Match 'GitHub REST API\s+pinned 2026-03-10\s+latest 2026-03-10'
        $text | Should -Match 'Planned changes \(\d+\):'
        $text | Should -Match "\+ create ruleset 'default-branch'"
        $calls = @(Get-TestNativeGhCall -Directory $script:ghDirectory)
        @($calls | Where-Object { $_.Arguments[0] -eq 'api' -and $_.Arguments[2] -ne 'GET' }) | Should -BeNullOrEmpty
    }

    It 'stops on a config of another format before any gh call' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route (Get-TestRoute)
        $path = Join-Path -Path $TestDrive -ChildPath 'other-format.json'
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = '2.0'
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8

        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -WhatIf -ConfigPath $path 2>&1 | ForEach-Object { [string]$_ }

        $LASTEXITCODE | Should -Not -Be 0
        # The error view wraps and colors the message, so only its parts are matched.
        ($output -join "`n") | Should -Match 'is invalid:'
        ($output -join "`n") | Should -Match 'configVersion'
        @(Get-TestNativeGhCall -Directory $script:ghDirectory) | Should -BeNullOrEmpty
    }

    It 'with -ValidateOnly validates the config on a machine without gh' {
        # No directory with a gh in it stays on PATH, the fake's included: a CI job that validates a config has no gh.
        $separator = [System.IO.Path]::PathSeparator
        $saved = $env:PATH
        $env:PATH = @($env:PATH -split $separator | Where-Object {
                $_ -and -not (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'gh')) -and -not (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'gh.exe'))
            }) -join $separator
        try {
            Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -ValidateOnly -ConfigPath $script:configPath 2>&1 | ForEach-Object { [string]$_ }
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:PATH = $saved
        }

        $exitCode | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Match 'is valid \(config format 1\.0\)\.'
    }

    It 'takes -ManualChecklist and prints the checklist' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route (Get-TestRoute)

        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -WhatIf -ManualChecklist -ConfigPath $script:configPath 2>&1 | ForEach-Object { [string]$_ }

        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Match 'Personal access tokens > Settings  https://github\.com/organizations/contoso/settings/personal-access-tokens'
        ($output -join "`n") | Should -Match '(?m)^  .+ -> expected .+$'
    }

    It 'takes -PageWalk without stopping when the host is not interactive' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route (Get-TestRoute)

        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -WhatIf -PageWalk -ConfigPath $script:configPath 2>&1 | ForEach-Object { [string]$_ }

        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Match 'Page walk of the state read at \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC'
        ($output -join "`n") | Should -Match 'manual settings were not checked by this run; the walk records nothing\.'
    }

    It 'stops before any API call when gh is too old, and takes -SkipLatestVersionCheck' {
        $routes = Get-TestRoute
        $routes['--version'] = @{ ExitCode = 0; Output = 'gh version 2.47.0 (2024-04-03)' }
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route $routes

        $output = & $script:pwsh -NoProfile -NonInteractive -File $script:bootstrap -WhatIf -SkipLatestVersionCheck -ConfigPath $script:configPath 2>&1 | ForEach-Object { [string]$_ }

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'latest skipped'
        ($output -join "`n") | Should -Match 'gh 2\.47\.0 is older than 2\.48\.0'
        @(Get-TestNativeGhCall -Directory $script:ghDirectory | Where-Object { $_.Arguments[0] -eq 'api' }) | Should -BeNullOrEmpty
    }
}
