# engine/examples/run.ps1, the wrapper a config repository copies: run from a copy in the test drive, with git mocked
# and the engine replaced by a stub bootstrap.ps1 that records how it was called.
BeforeAll {
    # Stand-in for the native command, so Pester can mock it on a machine without it.
    function git { }

    $script:source = Join-Path -Path $PSScriptRoot -ChildPath '../examples/run.ps1'
    $script:commit = 'a' * 40
    $script:other = 'b' * 40

    # The stub engine: writes its bound switches, the config and -WhatIf to calls.json next to run.ps1.
    $script:stub = @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$ConfigPath, [switch]$Force, [switch]$SkipLatestVersionCheck, [switch]$ManualChecklist, [switch]$PageWalk, [switch]$ValidateOnly)
$switches = @($PSBoundParameters.Keys | Where-Object { $PSBoundParameters[$_] -is [switch] -and $PSBoundParameters[$_] })
@{ ConfigPath = $ConfigPath; Switches = $switches; WhatIf = [bool]$WhatIfPreference } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../calls.json') -WhatIf:$false
'@
}

Describe 'engine/examples/run.ps1' {
    BeforeEach {
        $directory = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $directory | Out-Null
        $script:run = Join-Path -Path $directory -ChildPath 'run.ps1'
        Copy-Item -LiteralPath $script:source -Destination $script:run
        Set-Content -LiteralPath (Join-Path -Path $directory -ChildPath 'engine.psd1') -Value "@{ Repository = 'example-owner/github-org-bootstrap'; Tag = 'v1.0.0'; Commit = '$script:commit' }"
        # Shared with the mocks, whose bodies do not see this file's script scope: a closure keeps the reference.
        $state = @{ Directory = $directory; Head = $null; Status = @(); TagLines = @("$script:commit`trefs/tags/v1.0.0"); Commit = $script:commit; Stub = $script:stub }
        $script:state = $state

        Mock git { $global:LASTEXITCODE = 0; $state.TagLines }.GetNewClosure() -ParameterFilter { $args[0] -eq 'ls-remote' }
        Mock git { $global:LASTEXITCODE = 0 } -ParameterFilter { $args[0] -eq 'init' }
        Mock git { $global:LASTEXITCODE = 0 } -ParameterFilter { $args -contains 'fetch' }
        Mock git {
            $global:LASTEXITCODE = 0
            $state.Head = $state.Commit
            $engine = Join-Path -Path $state.Directory -ChildPath '.engine/engine'
            New-Item -ItemType Directory -Path $engine -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'bootstrap.ps1') -Value $state.Stub
        }.GetNewClosure() -ParameterFilter { $args -contains 'checkout' }
        Mock git { $global:LASTEXITCODE = 0; $state.Head }.GetNewClosure() -ParameterFilter { $args -contains 'rev-parse' }
        # Untracked files show only when asked for, as with status.showUntrackedFiles=no in the user's git config.
        Mock git { $global:LASTEXITCODE = 0; if ($args -contains '--untracked-files=all') { $state.Status } }.GetNewClosure() -ParameterFilter { $args -contains 'status' }

        function Initialize-TestEngine {
            # A checkout already in place at $Head: .engine/.git and the stub engine.
            param([Parameter(Mandatory)][string]$Head)

            $engine = Join-Path -Path $script:state.Directory -ChildPath '.engine/engine'
            New-Item -ItemType Directory -Path $engine, (Join-Path -Path $script:state.Directory -ChildPath '.engine/.git') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $engine -ChildPath 'bootstrap.ps1') -Value $script:stub
            $script:state.Head = $Head
        }

        function Get-TestCall {
            $path = Join-Path -Path $script:state.Directory -ChildPath 'calls.json'
            if (Test-Path -LiteralPath $path) { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json }
        }
    }

    It 'stops when the tag is not at the pinned commit' {
        $script:state.TagLines = @("$script:other`trefs/tags/v1.0.0")

        { & $script:run -WhatIf } | Should -Throw "Tag v1.0.0 of example-owner/github-org-bootstrap is at $script:other, not at the pinned commit $script:commit."
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -BeNullOrEmpty
    }

    It 'uses the peeled commit of an annotated tag' {
        $script:state.TagLines = @("$script:other`trefs/tags/v1.0.0", "$script:commit`trefs/tags/v1.0.0^{}")

        & $script:run -WhatIf

        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'reuses .engine at the pinned commit' {
        Initialize-TestEngine -Head $script:commit

        & $script:run -WhatIf

        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'stops when .engine at the pinned commit has local changes' {
        Initialize-TestEngine -Head $script:commit
        $script:state.Status = @(' M engine/src/Plan.ps1', '?? extra.ps1')

        { & $script:run -WhatIf } | Should -Throw '*.engine*has local changes*engine/src/Plan.ps1*extra.ps1*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -BeNullOrEmpty
        Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/bootstrap.ps1' | Should -Exist
    }

    It 'stops when .engine at another commit has local changes, before replacing it' {
        Initialize-TestEngine -Head $script:other
        $script:state.Status = @('?? extra.ps1')

        { & $script:run -WhatIf } | Should -Throw '*.engine*has local changes*extra.ps1*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Join-Path -Path $script:state.Directory -ChildPath '.engine/engine/bootstrap.ps1' | Should -Exist
    }

    It 'stops when a new checkout has local changes' {
        # Such as a post-checkout hook of the user's git config would make.
        $script:state.Status = @(' M engine/bootstrap.ps1')

        { & $script:run -WhatIf } | Should -Throw '*.engine*has local changes*engine/bootstrap.ps1*'
        Get-TestCall | Should -BeNullOrEmpty
    }

    It 'stops when .engine is not a checkout and holds files' {
        $file = Join-Path -Path $script:state.Directory -ChildPath '.engine/notes.txt'
        New-Item -ItemType File -Path $file -Force | Out-Null

        { & $script:run -WhatIf } | Should -Throw '*.engine*not a checkout*notes.txt*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq 'init' }
        $file | Should -Exist
    }

    It 'replaces .engine that holds only an unfinished checkout' {
        # An interrupted first fetch: .engine/.git without a commit, so HEAD cannot be read.
        New-Item -ItemType Directory -Path (Join-Path -Path $script:state.Directory -ChildPath '.engine/.git') -Force | Out-Null

        & $script:run -WhatIf

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args -contains 'fetch' }
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'replaces .engine at another commit' {
        Initialize-TestEngine -Head $script:other

        & $script:run -WhatIf

        Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args -contains 'fetch' -and $args -contains ('a' * 40) }
        Get-TestCall | Should -Not -BeNullOrEmpty
    }

    It 'forwards the switches and -WhatIf' {
        & $script:run -WhatIf -PageWalk

        $call = Get-TestCall
        $call.ConfigPath | Should -Be (Join-Path -Path $script:state.Directory -ChildPath 'github.json')
        # Only the switches given, -WhatIf among them; the others are bound as false.
        @($call.Switches | Sort-Object) | Should -Be @('PageWalk', 'WhatIf')
        $call.WhatIf | Should -BeTrue
    }

    It 'rejects a manifest with a short commit' {
        Set-Content -LiteralPath (Join-Path -Path $script:state.Directory -ChildPath 'engine.psd1') -Value "@{ Repository = 'example-owner/github-org-bootstrap'; Tag = 'v1.0.0'; Commit = 'abc' }"

        { & $script:run -WhatIf } | Should -Throw '*Commit*'
        Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq 'ls-remote' }
    }
}
