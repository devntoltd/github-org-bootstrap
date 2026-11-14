BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:installScript = Join-Path -Path $script:root -ChildPath 'tools/Install-DevTools.ps1'

    # Stand-ins for the native commands, so Pester can mock them on a machine without them.
    function actionlint { }
    function zizmor { }
    function winget { }
    function git { }
}

Describe 'dev-tools.psd1' {
    It 'pins the <Name> version that .github/workflows/ci.yml uses' -ForEach @(
        @{ Name = 'actionlint'; Step = 'actionlint' }
        @{ Name = 'zizmor'; Step = 'zizmor' }
        @{ Name = 'betterleaks'; Step = 'Betterleaks' }
        @{ Name = 'lychee'; Step = 'Markdown links' }
        @{ Name = 'editorconfig-checker'; Step = 'EditorConfig' }
        @{ Name = 'shellcheck'; Step = 'shellcheck' }
    ) {
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $workflow = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw

        # VERSION of a run: step, or version / lycheeVersion (-match ignores case) in the with: of an action; v1.2.3 is 1.2.3.
        $found = if ($workflow -match "(?s)- name: $Step\r?\n.*?(VERSION|version): (?<version>\S+)") { $Matches.version -replace '^v', '' }
        $found | Should -Not -BeNullOrEmpty
        $found | Should -Be $tools.Tools[$Name].Version
    }

    # The central workflow (engine/examples/org-checks.yml) is copied by hand to the organization's .github repository, so its
    # pins must follow the ones of ci.yml, which Dependabot and the dependency check keep current. Dependabot never
    # updates the reference copy, so its pull requests fail here until the copy follows: the message says what to do.
    BeforeAll {
        $script:orgChecksBecause = 'every pin of ci.yml that engine/examples/org-checks.yml shares must match there: raise the same action or tool in engine/examples/org-checks.yml in this pull request (Dependabot does not update it), then copy it to the .github repository of the organization and put the new merge commit in github.json (engine/README.md, Manual setup)'
    }

    It 'pins the <Name> version and SHA-256 of ci.yml in engine/examples/org-checks.yml' -ForEach @(
        @{ Name = 'actionlint'; Step = 'actionlint' }
        @{ Name = 'shellcheck'; Step = 'shellcheck' }
        @{ Name = 'betterleaks'; Step = 'Betterleaks' }
    ) {
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $ci = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw
        $org = Get-Content -Path (Join-Path -Path $script:root -ChildPath 'engine/examples/org-checks.yml') -Raw
        $pattern = "(?s)- name: $Step\r?\n.*?VERSION: (?<version>\S+)\r?\n\s+SHA256: (?<sha>\S+)"

        $ci -match $pattern | Should -BeTrue
        $expected = $Matches
        $org -match $pattern | Should -BeTrue
        $Matches.version | Should -Be $tools.Tools[$Name].Version -Because $script:orgChecksBecause
        $Matches.sha | Should -Be $expected.sha -Because $script:orgChecksBecause
    }

    It 'pins the zizmor version of dev-tools.psd1 in engine/examples/org-checks.yml' {
        $tools = Import-PowerShellDataFile -Path (Join-Path -Path $script:root -ChildPath 'dev-tools.psd1')
        $org = Get-Content -Path (Join-Path -Path $script:root -ChildPath 'engine/examples/org-checks.yml') -Raw

        $org -match '(?s)- name: zizmor\r?\n.*?version: (?<version>\S+)' | Should -BeTrue
        $Matches.version | Should -Be $tools.Tools['zizmor'].Version -Because $script:orgChecksBecause
    }

    # GitHub's release downloads answer 504 at times (2026-11-08: four reruns of one pull request), and curl -f fails the
    # step at once without a retry. --retry alone retries 5xx answers and timeouts; --retry-all-errors would retry a 404
    # of a wrong version too, so it is left out and a bad pin fails at once.
    It 'retries every download of <File> on a transient error, within a time limit' -ForEach @(
        @{ File = '.github/workflows/ci.yml' }
        @{ File = 'engine/examples/org-checks.yml' }
    ) {
        $workflow = Get-Content -Path (Join-Path -Path $script:root -ChildPath $File) -Raw

        $downloads = @([regex]::Matches($workflow, '(?m)^\s*curl .*$') | ForEach-Object { $_.Value.Trim() })
        $downloads.Count | Should -BeGreaterThan 0
        foreach ($download in $downloads) {
            $download | Should -Match '\s--retry \d+(\s|$)' -Because 'a download retries a 5xx answer or a timeout'
            $download | Should -Match '\s--retry-max-time \d+(\s|$)' -Because 'the retries of a download end after a time limit'
            $download | Should -Not -Match '\s--retry-all-errors(\s|$)' -Because 'a 404 of a wrong version fails at once'
        }
    }

    It 'pins every action of engine/examples/org-checks.yml to the SHA ci.yml uses' {
        $ci = Get-Content -Path (Join-Path -Path $script:root -ChildPath '.github/workflows/ci.yml') -Raw
        $org = Get-Content -Path (Join-Path -Path $script:root -ChildPath 'engine/examples/org-checks.yml') -Raw

        $uses = [regex]::Matches($org, '(?m)^\s*(?:- )?uses: (?<action>[^@\s]+)@(?<sha>\S+)')
        $uses.Count | Should -BeGreaterThan 0
        foreach ($use in $uses) {
            $action = [regex]::Escape($use.Groups['action'].Value)
            $ci | Should -Match "uses: $action@$($use.Groups['sha'].Value)\s" -Because $script:orgChecksBecause
        }
    }
}

Describe 'Install-DevTools.ps1' {
    BeforeEach {
        # Before the Get-Module mock: Pester resolves the mocked command through Get-Module.
        Mock Install-PSResource { }
        Mock Find-PSResource { [pscustomobject]@{ Name = $Name; Version = $Version; Dependencies = @() } }
        Mock Import-PowerShellDataFile -ParameterFilter { $Path -like '*dev-tools.psd1' } {
            @{
                Modules = @{ Pester = '6.2.0' }
                Tools   = @{
                    actionlint = @{ WinGetId = 'rhysd.actionlint'; Version = '1.7.12'; Repository = 'rhysd/actionlint' }
                    zizmor     = @{ WinGetId = 'zizmor.zizmor'; Version = '1.30.1'; Repository = 'zizmorcore/zizmor' }
                }
            }
        }
        Mock Import-PowerShellDataFile -ParameterFilter { $Path -like '*modules.lock.psd1' } { @{ 'Example.Base' = '5.5.3'; 'Example.Tool' = '10.2.1' } }
        Mock Get-Module -ParameterFilter { $ListAvailable } {
            @{
                Pester         = [pscustomobject]@{ Version = [version]'6.2.0' }
                'Example.Base' = [pscustomobject]@{ Version = [version]'5.5.3' }
                'Example.Tool' = [pscustomobject]@{ Version = [version]'10.2.1' }
            }[$Name]
        }
        Mock actionlint { '1.7.12'; 'installed by downloading from release page' }
        Mock zizmor { 'zizmor 1.30.1' }
        Mock winget { $global:LASTEXITCODE = 0 }
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args -contains 'core.hooksPath' -and $args -contains '--get') { '.githooks' }
            if ($args -contains 'blame.ignoreRevsFile' -and $args -contains '--get') { '.git-blame-ignore-revs' }
        }
        Mock Write-Host { }
        Mock Write-Warning { }
    }

    It 'installs nothing when every tool, module and the hook are in place' {
        & $script:installScript

        Should -Invoke winget -Times 0
        Should -Invoke Install-PSResource -Times 0
        Should -Invoke git -Times 0 -ParameterFilter { $args -notcontains '--get' }
    }

    It 'installs a missing tool at the pinned version through winget' {
        Mock zizmor { }

        & $script:installScript

        Should -Invoke winget -Times 1 -Exactly -ParameterFilter {
            ($args -join ' ') -like 'install --exact --id zizmor.zizmor --version 1.30.1 *'
        }
    }

    It 'installs the pinned version when another version is installed' {
        Mock actionlint { '1.7.11' }

        & $script:installScript

        Should -Invoke winget -Times 1 -Exactly -ParameterFilter {
            ($args -join ' ') -like 'install --exact --id rhysd.actionlint --version 1.7.12 *'
        }
    }

    It 'throws when winget fails' {
        Mock actionlint { '1.7.11' }
        Mock winget { $global:LASTEXITCODE = 1 }

        { & $script:installScript } | Should -Throw '*winget*rhysd.actionlint*'
    }

    It 'warns to open a new terminal when winget has the tool but this session does not find it' {
        Mock zizmor { }
        # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE: installed at that version, PATH of this session not updated yet.
        Mock winget { $global:LASTEXITCODE = -1978335189 }

        { & $script:installScript } | Should -Not -Throw
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*zizmor 1.30.1 is installed*open a new terminal*' }
    }

    It 'warns instead of installing when winget is not available' {
        Mock actionlint { '1.7.11' }
        $getCommand = Get-Command -Name Get-Command -CommandType Cmdlet
        Mock Get-Command { & $getCommand @PesterBoundParameters }
        Mock Get-Command -ParameterFilter { $Name -eq 'winget' } { $null }

        & $script:installScript

        Should -Invoke winget -Times 0
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*actionlint 1.7.12*' }
    }

    It 'installs exactly the locked version, without dependencies, when only another one is installed' {
        Mock Get-Module -ParameterFilter { $ListAvailable } {
            @{
                Pester         = [pscustomobject]@{ Version = [version]'6.3.0' }
                'Example.Base' = [pscustomobject]@{ Version = [version]'5.5.3' }
                'Example.Tool' = [pscustomobject]@{ Version = [version]'10.2.1' }
            }[$Name]
        }

        & $script:installScript

        Should -Invoke Install-PSResource -Times 1 -Exactly
        Should -Invoke Install-PSResource -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Pester' -and $Version -eq '6.2.0' -and $Scope -eq 'CurrentUser' -and $SkipDependencyCheck -and $TrustRepository -and
            $Repository -eq 'PSGallery' -and [bool]$AuthenticodeCheck -eq [bool]$IsWindows
        }
    }

    It 'refuses a dependency that is not locked, before installing anything' {
        Mock Get-Module -ParameterFilter { $ListAvailable } { $null }
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Tool' } {
            [pscustomobject]@{ Name = 'Example.Tool'; Version = '10.2.1'; Dependencies = @([pscustomobject]@{ Name = 'Example.Other'; VersionRange = '[1.0.0, )' }) }
        }

        { & $script:installScript } | Should -Throw '*Example.Tool 10.2.1 needs Example.Other `[1.0.0, ), which is not in modules.lock.psd1*'
        Should -Invoke Install-PSResource -Times 0
    }

    It 'refuses a locked dependency outside the range' {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Tool' } {
            [pscustomobject]@{ Name = 'Example.Tool'; Version = '10.2.1'; Dependencies = @([pscustomobject]@{ Name = 'Example.Base'; VersionRange = '[5.6.0, )' }) }
        }

        { & $script:installScript } | Should -Throw '*Example.Tool 10.2.1 needs Example.Base `[5.6.0, ); modules.lock.psd1 locks 5.5.3*'
    }

    It 'reads the version range <Range> of the Gallery' -ForEach @(
        @{ Range = '[5.5.3, )'; Ok = $true }
        @{ Range = '5.5.3'; Ok = $true }
        @{ Range = '[5.5.3]'; Ok = $true }
        @{ Range = '(5.5.3, 6.0.0)'; Ok = $false }
        @{ Range = '[5.0.0, 5.5.3]'; Ok = $true }
        @{ Range = '[5.0.0, 5.5.3)'; Ok = $false }
    ) {
        Mock Find-PSResource -ParameterFilter { $Name -eq 'Example.Tool' } {
            [pscustomobject]@{ Name = 'Example.Tool'; Version = '10.2.1'; Dependencies = @([pscustomobject]@{ Name = 'Example.Base'; VersionRange = $Range }) }
        }

        if ($Ok) {
            { & $script:installScript } | Should -Not -Throw
        }
        else {
            { & $script:installScript } | Should -Throw '*locks 5.5.3*'
        }
    }

    It 'installs only the modules with -ModulesOnly' {
        Mock zizmor { }
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript -ModulesOnly

        Should -Invoke winget -Times 0
        Should -Invoke git -Times 0
        Should -Invoke Find-PSResource -Times 3 -Exactly
    }

    It 'enables the pre-commit hook for this clone only' {
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '* config --local core.hooksPath .githooks' }
    }

    It 'makes git blame skip the formatting commits for this clone only' {
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains 'blame.ignoreRevsFile' -and $args -contains '--get' }

        & $script:installScript

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like '* config --local blame.ignoreRevsFile .git-blame-ignore-revs' }
        Should -Invoke git -Times 0 -ParameterFilter { ($args -join ' ') -like '* config --local core.hooksPath .githooks' }
    }

    It 'changes nothing with -WhatIf' {
        Mock actionlint { '1.7.11' }
        Mock Get-Module -ParameterFilter { $ListAvailable } { $null }
        Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args -contains '--get' }

        & $script:installScript -WhatIf

        Should -Invoke winget -Times 0
        Should -Invoke Install-PSResource -Times 0
        Should -Invoke git -Times 0 -ParameterFilter { $args -notcontains '--get' }
    }
}
