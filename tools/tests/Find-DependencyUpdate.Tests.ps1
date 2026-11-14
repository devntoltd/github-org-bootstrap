BeforeAll {
    $script:findScript = Join-Path -Path $PSScriptRoot -ChildPath '../Find-DependencyUpdate.ps1'
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')
    $script:now = [datetime]::new(2026, 10, 5, 6, 0, 0, [System.DateTimeKind]::Utc)

    # A version as Find-PSResource -Version * returns it, published $Days days before $now.
    function Get-TestGalleryVersion {
        param([string]$Name, [string]$Version, [int]$Days)

        [pscustomobject]@{ Name = $Name; Version = [version]$Version; PublishedDate = $script:now.AddDays(-$Days); Prerelease = '' }
    }

    # A release as 'gh api repos/{repo}/releases' returns it.
    function Get-TestRelease {
        param([string]$Tag, [string]$Published, [switch]$Draft, [switch]$Prerelease)

        [ordered]@{ tag_name = $Tag; published_at = $Published; draft = [bool]$Draft; prerelease = [bool]$Prerelease; html_url = "https://example.test/$Tag" }
    }
}

Describe 'Find-DependencyUpdate.ps1' {
    BeforeEach {
        $script:folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'modules.lock.psd1') -Value @(
            '# Exact versions.'
            '@{'
            "    'Example.Base' = '5.5.3'"
            "    'Example.Tool' = '10.2.1'"
            '}'
        )
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'dev-tools.psd1') -Value @(
            '@{'
            '    Modules = @{'
            "        'Pester' = '6.2.0'"
            '    }'
            '    Tools   = @{'
            "        'lychee' = @{ WinGetId = 'lycheeverse.lychee'; Version = '0.24.2'; Repository = 'lycheeverse/lychee' }"
            '    }'
            '}'
        )
        # The module that pins the GitHub REST API version.
        $shared = (New-Item -ItemType Directory -Path (Join-Path -Path $folder -ChildPath 'shared')).FullName
        Set-Content -Path (Join-Path -Path $shared -ChildPath 'Bootstrap.Common.psm1') -Value "`$script:GitHubApiVersion = '2026-03-10'"
        $script:TestReleases = @(Get-TestRelease -Tag 'lychee-v0.24.2' -Published '2026-08-01T00:00:00Z')
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test: the fixtures are found by name (dynamic scoping). It answers the
        # page of the releases the endpoint asks for, as GitHub does (per_page 30 and page 1 by default).
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            $size = if ($args[1] -match '[?&]per_page=(\d+)') { [int]$Matches[1] } else { 30 }
            $number = if ($args[1] -match '[?&]page=(\d+)') { [int]$Matches[1] } else { 1 }
            ConvertTo-Json -InputObject @($TestReleases | Select-Object -Skip (($number - 1) * $size) -First $size) -Depth 5
        }
        Mock Find-PSResource { Get-TestGalleryVersion -Name $Name -Version '5.5.3' -Days 100 } -ParameterFilter { $Name -eq 'Example.Base' }
        Mock Find-PSResource { Get-TestGalleryVersion -Name $Name -Version '10.2.1' -Days 100 } -ParameterFilter { $Name -eq 'Example.Tool' }
        Mock Find-PSResource { Get-TestGalleryVersion -Name $Name -Version '6.2.0' -Days 100 } -ParameterFilter { $Name -eq 'Pester' }
        Mock Write-Host { }
        $script:arguments = @{ Root = $folder; Now = $now; PassThru = $true }
    }

    It 'finds nothing while every locked version is the newest' {
        $result = & $findScript @arguments

        @($result.Candidates) | Should -BeNullOrEmpty
        @($result.Quarantined) | Should -BeNullOrEmpty
        Should -Invoke Find-PSResource -Times 1 -Exactly -ParameterFilter { $Name -eq 'Example.Base' -and $Version -eq '*' -and $Repository -eq 'PSGallery' }
        $releaseCalls = @($TestGhCalls | Where-Object { $_[0] -eq 'api' -and $_[1] -eq 'repos/lycheeverse/lychee/releases?per_page=100&page=1' })
        $releaseCalls.Count | Should -Be 1
        Get-GhOption -Call $releaseCalls[0] -Name '--header' | Should -Be 'X-GitHub-Api-Version: 2026-03-10'
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Every locked version is the newest.' }
    }

    It 'takes the newest version out of quarantine and lists the newer one still in it' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Base' } {
            Get-TestGalleryVersion -Name $Name -Version '5.5.3' -Days 100
            Get-TestGalleryVersion -Name $Name -Version '5.6.0' -Days 10
            Get-TestGalleryVersion -Name $Name -Version '5.7.0' -Days 3
        }

        $result = & $findScript @arguments

        $candidate = @($result.Candidates)
        $candidate.Count | Should -Be 1
        $candidate[0].Kind | Should -Be 'Module'
        $candidate[0].File | Should -Be 'modules.lock.psd1'
        $candidate[0].Locked | Should -Be '5.5.3'
        $candidate[0].Version | Should -Be '5.6.0'
        $candidate[0].Published | Should -Be '2026-09-25'
        $candidate[0].Notes | Should -Be 'https://www.powershellgallery.com/packages/Example.Base/5.6.0'
        $waiting = @($result.Quarantined)
        $waiting.Count | Should -Be 1
        $waiting[0].Version | Should -Be '5.7.0'
        $waiting[0].Until | Should -Be '2026-10-09'
    }

    It 'lists a version in quarantine when no newer version is out of it' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Pester' } {
            Get-TestGalleryVersion -Name $Name -Version '6.2.0' -Days 100
            Get-TestGalleryVersion -Name $Name -Version '6.3.0' -Days 1
        }

        $result = & $findScript @arguments

        @($result.Candidates) | Should -BeNullOrEmpty
        @($result.Quarantined).Name | Should -Be @('Pester')
        @($result.Quarantined)[0].File | Should -Be 'dev-tools.psd1'
    }

    It 'skips unlisted versions, which the Gallery dates 1900-01-01' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Base' } {
            Get-TestGalleryVersion -Name $Name -Version '5.5.3' -Days 100
            [pscustomobject]@{ Name = $Name; Version = [version]'5.6.0'; PublishedDate = [datetime]'1900-01-01'; Prerelease = '' }
        }

        $result = & $findScript @arguments

        @($result.Candidates) | Should -BeNullOrEmpty
        @($result.Quarantined) | Should -BeNullOrEmpty
    }

    It 'takes only the tags of the tool itself, not those of its other packages' {
        $script:TestReleases = @(
            Get-TestRelease -Tag 'lychee-lib-v0.25.0' -Published '2026-09-01T00:00:00Z'
            Get-TestRelease -Tag 'lychee-v0.24.2' -Published '2026-08-01T00:00:00Z'
        )

        $result = & $findScript @arguments

        @($result.Candidates) | Should -BeNullOrEmpty
    }

    It 'reads the next page of releases until one holds the locked version' {
        # A full first page of the repository's other package, the tool's own releases on the second.
        $script:TestReleases = @(
            1..100 | ForEach-Object { Get-TestRelease -Tag "lychee-lib-v0.$(200 - $_).0" -Published '2026-09-10T00:00:00Z' }
            Get-TestRelease -Tag 'lychee-v0.25.0' -Published '2026-09-01T00:00:00Z'
            Get-TestRelease -Tag 'lychee-v0.24.2' -Published '2026-08-01T00:00:00Z'
            Get-TestRelease -Tag 'lychee-v0.24.1' -Published '2026-07-01T00:00:00Z'
        )

        $result = & $findScript @arguments

        @($result.Candidates).Version | Should -Be @('0.25.0')
        @($TestGhCalls | ForEach-Object { $_[1] }) | Should -Be @(
            'repos/lycheeverse/lychee/releases?per_page=100&page=1'
            'repos/lycheeverse/lychee/releases?per_page=100&page=2'
        )
    }

    It 'reads no further page once one holds the locked version' {
        $script:TestReleases = @(
            1..99 | ForEach-Object { Get-TestRelease -Tag "lychee-lib-v0.$(200 - $_).0" -Published '2026-09-10T00:00:00Z' }
            Get-TestRelease -Tag 'lychee-v0.24.2' -Published '2026-08-01T00:00:00Z'
            Get-TestRelease -Tag 'lychee-v0.24.1' -Published '2026-07-01T00:00:00Z'
        )

        & $findScript @arguments | Out-Null

        $TestGhCalls.Count | Should -Be 1
    }

    It 'reads tool releases, skipping drafts and prereleases, from tags with a prefix' {
        $script:TestReleases = @(
            Get-TestRelease -Tag 'nightly' -Published '2026-09-01T00:00:00Z' -Prerelease
            Get-TestRelease -Tag 'lychee-v0.26.0' -Published '2026-09-02T00:00:00Z' -Draft
            Get-TestRelease -Tag 'lychee-v0.25.0' -Published '2026-09-01T00:00:00Z'
            Get-TestRelease -Tag 'lychee-v0.24.2' -Published '2026-08-01T00:00:00Z'
        )

        $result = & $findScript @arguments

        $candidate = @($result.Candidates)
        $candidate.Count | Should -Be 1
        $candidate[0].Kind | Should -Be 'Tool'
        $candidate[0].File | Should -Be 'dev-tools.psd1'
        $candidate[0].Version | Should -Be '0.25.0'
        $candidate[0].Notes | Should -Be 'https://example.test/lychee-v0.25.0'
    }

    It 'writes the module candidates into the lock files with -UpdateLock and leaves the comments and tools' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Base' } { Get-TestGalleryVersion -Name $Name -Version '5.6.0' -Days 10 }
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Pester' } { Get-TestGalleryVersion -Name $Name -Version '6.3.0' -Days 10 }
        $script:TestReleases = @(Get-TestRelease -Tag 'lychee-v0.25.0' -Published '2026-09-01T00:00:00Z')

        & $findScript @arguments -UpdateLock | Out-Null

        $lockPath = Join-Path -Path $folder -ChildPath 'modules.lock.psd1'
        $lock = Import-PowerShellDataFile -Path $lockPath
        $lock['Example.Base'] | Should -Be '5.6.0'
        $lock['Example.Tool'] | Should -Be '10.2.1'
        (Get-Content -Path $lockPath -Raw) | Should -Match '# Exact versions\.'
        $devTools = Import-PowerShellDataFile -Path (Join-Path -Path $folder -ChildPath 'dev-tools.psd1')
        $devTools.Modules.Pester | Should -Be '6.3.0'
        $devTools.Tools.lychee.Version | Should -Be '0.24.2'
    }

    It 'writes the result as JSON with -OutFile' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Pester' } { Get-TestGalleryVersion -Name $Name -Version '6.3.0' -Days 10 }
        $out = Join-Path -Path $folder -ChildPath 'candidates.json'

        & $findScript -Root $folder -Now $now -OutFile $out

        $json = Get-Content -Path $out -Raw | ConvertFrom-Json
        @($json.Candidates).Name | Should -Be @('Pester')
        @($json.Quarantined) | Should -BeNullOrEmpty
    }
}
