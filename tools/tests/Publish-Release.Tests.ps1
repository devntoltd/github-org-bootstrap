BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:releaseScript = Join-Path -Path $script:root -ChildPath 'tools/Publish-Release.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    $script:commit = 'a' * 40
    $script:other = 'b' * 40
}

Describe 'Publish-Release.ps1' {
    BeforeEach {
        $folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:manifest = Join-Path -Path $folder -ChildPath 'Engine.psd1'
        Set-Content -Path $script:manifest -Value "@{ ModuleVersion = '1.1.0'; RootModule = 'Engine.psm1' }"
        $script:module = Join-Path -Path $folder -ChildPath 'Common.psm1'
        Set-Content -Path $script:module -Value "`$script:GitHubApiVersion = '2026-03-10'"
        $script:changelog = Join-Path -Path $folder -ChildPath 'CHANGELOG.md'
        Set-Content -Path $script:changelog -Value (@(
                '# Changelog'
                ''
                '## [Unreleased]'
                ''
                '## [1.1.0] - 2026-11-20'
                ''
                '### Changed'
                ''
                '- The new behavior.'
                ''
                '## [1.0.0] - 2026-11-13'
                ''
                '### Added'
                ''
                '- The first release.'
                ''
                '[Unreleased]: https://example.test/compare/v1.1.0...HEAD'
                '[1.1.0]: https://example.test/compare/v1.0.0...v1.1.0'
            ) -join "`n")
        $script:paths = @{ ManifestPath = $script:manifest; ChangelogPath = $script:changelog; ModulePath = $script:module; Commit = $script:commit }
        $script:summary = Join-Path -Path $folder -ChildPath 'summary.md'
        $env:GITHUB_STEP_SUMMARY = $script:summary

        # The refs of 'git/matching-refs/tags/<tag>', the annotated tag objects by sha, and 'gh release list'.
        $script:TestRefs = @()
        $script:TestTagObjects = @{}
        $script:TestReleases = @(@{ tagName = 'v1.0.0'; isDraft = $false })
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test: the fixtures are found by name (dynamic scoping), so their names
        # must not clash with variables of the script.
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'api') {
                $path = $args[-1]
                if ($path -like 'repos/{owner}/{repo}/git/matching-refs/tags/*') { return ConvertTo-Json -InputObject @($TestRefs) -Depth 5 }
                if ($path -like 'repos/{owner}/{repo}/git/tags/*') { return $TestTagObjects[($path -split '/')[-1]] | ConvertTo-Json -Depth 5 }
            }
            switch ($args[0..1] -join ' ') {
                'release list' { ConvertTo-Json -InputObject @($TestReleases) }
                'release create' { 'https://example.test/releases/tag/v1.1.0' }
            }
        }
        Mock Write-Host { }

        function Get-TestRef {
            # A ref as 'git/matching-refs' returns it: a commit (lightweight tag) or a tag object (annotated tag).
            param([string]$Name, [string]$Sha, [string]$Type = 'commit')

            @{ ref = "refs/tags/$Name"; object = @{ sha = $Sha; type = $Type } }
        }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    It 'publishes the release of a new version at the commit, with the changelog section as notes' {
        & $script:releaseScript @paths

        $created = Get-GhCall -Command 'release create'
        $created.Count | Should -Be 1
        $created[0][2] | Should -Be 'v1.1.0'
        Get-GhOption -Call $created[0] -Name '--target' | Should -Be $script:commit
        Get-GhOption -Call $created[0] -Name '--title' | Should -Be 'v1.1.0'
        # The section only: neither its heading, nor the next release, nor the link definitions.
        Get-GhOption -Call $created[0] -Name '--notes' | Should -Be "### Changed`n`n- The new behavior."
        $created[0] | Should -Contain '--latest'
        $created[0] | Should -Not -Contain '--draft'
    }

    It 'sends the pinned REST API version with every gh api call' {
        & $script:releaseScript @paths

        $api = @($TestGhCalls | Where-Object { $_[0] -eq 'api' })
        $api.Count | Should -BeGreaterThan 0
        foreach ($call in $api) {
            Get-GhOption -Call $call -Name '--header' | Should -Be 'X-GitHub-Api-Version: 2026-03-10'
        }
    }

    It 'does nothing when the release of the version exists' {
        # Every commit of main after the release: the tag is at an earlier commit.
        $script:TestRefs = @(Get-TestRef -Name 'v1.1.0' -Sha $script:other)
        $script:TestReleases = @(@{ tagName = 'v1.1.0'; isDraft = $false })

        & $script:releaseScript @paths

        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
        Get-Content -Raw -Path $script:summary | Should -Match '\| 1\.1\.0 \| v1\.1\.0 \| released \|'
    }

    It 'publishes only the release when the tag exists at the commit (<Kind>)' -ForEach @(
        @{ Kind = 'lightweight' }
        @{ Kind = 'annotated' }
    ) {
        if ($Kind -eq 'annotated') {
            $script:TestRefs = @(Get-TestRef -Name 'v1.1.0' -Sha ('c' * 40) -Type 'tag')
            $script:TestTagObjects[('c' * 40)] = @{ object = @{ sha = $script:commit; type = 'commit' } }
        }
        else {
            $script:TestRefs = @(Get-TestRef -Name 'v1.1.0' -Sha $script:commit)
        }

        & $script:releaseScript @paths

        (Get-GhCall -Command 'release create').Count | Should -Be 1
    }

    It 'stops before any write when the tag is at another commit' {
        # A ref of another tag with the same prefix does not count.
        $script:TestRefs = @((Get-TestRef -Name 'v1.1.0' -Sha $script:other), (Get-TestRef -Name 'v1.1.0-rc' -Sha $script:commit))

        { & $script:releaseScript @paths } | Should -Throw "*v1.1.0 is at $script:other, not at $script:commit*"
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
    }

    It 'stops before any write when a draft release of the tag exists' {
        $script:TestReleases = @(@{ tagName = 'v1.1.0'; isDraft = $true })

        { & $script:releaseScript @paths } | Should -Throw '*draft release v1.1.0*'
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
    }

    It 'stops before any gh call when the changelog has <Case>' -ForEach @(
        @{ Case = 'no section of the version'; Version = '1.2.0' }
        @{ Case = 'an empty section of the version'; Version = '1.1.0'; Empty = $true }
    ) {
        Set-Content -Path $script:manifest -Value "@{ ModuleVersion = '$Version'; RootModule = 'Engine.psm1' }"
        if ($Empty) {
            Set-Content -Path $script:changelog -Value "# Changelog`n`n## [1.1.0] - 2026-11-20`n`n## [1.0.0] - 2026-11-13`n`n- The first release."
        }

        { & $script:releaseScript @paths } | Should -Throw "*CHANGELOG.md has no notes under ## ``[$Version``]*"
        $TestGhCalls | Should -BeNullOrEmpty
    }

    It 'with -WhatIf reads but publishes nothing' {
        & $script:releaseScript @paths -WhatIf

        Get-GhCall -Command 'release list' | Should -Not -BeNullOrEmpty
        Get-GhCall -Command 'release create' | Should -BeNullOrEmpty
        Get-Content -Raw -Path $script:summary | Should -Match '\| 1\.1\.0 \| v1\.1\.0 \| new \|'
    }

    It 'takes the commit of the run from GITHUB_SHA' {
        $saved = $env:GITHUB_SHA
        $env:GITHUB_SHA = $script:other
        try {
            $paths.Remove('Commit')
            & $script:releaseScript @paths
        }
        finally {
            $env:GITHUB_SHA = $saved
        }

        Get-GhOption -Call (Get-GhCall -Command 'release create')[0] -Name '--target' | Should -Be $script:other
    }
}
