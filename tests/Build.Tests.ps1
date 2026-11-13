BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:buildScript = Join-Path -Path $script:root -ChildPath 'build.ps1'
}

Describe 'build.psd1' {
    BeforeAll {
        $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'build.psd1')
        $script:checks = @($manifest.Checks)
        $script:tools = @($manifest.Tools)
        $script:names = @($checks.Name) + @($tools.Name)
    }

    It 'has a check for every step of ci.yml and a step for every check' {
        # Steps that prepare the job instead of checking anything.
        $setupSteps = @('Install modules')
        $ciSteps = @(Select-String -Path (Join-Path -Path $root -ChildPath '.github/workflows/ci.yml') -Pattern '^\s*- name:\s*(.+?)\s*$' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } |
                Where-Object { $_ -notin $setupSteps })

        $ciSteps.Count | Should -BeGreaterThan 0
        @($checks.CiStep | Sort-Object) | Should -Be @($ciSteps | Sort-Object)
    }

    It 'lints every workflow of .github/workflows and engine/examples/org-checks.yml with actionlint, in build.psd1 and ci.yml' {
        # actionlint takes the files by name to reach the reference copy outside .github/workflows, and then checks
        # only those: a workflow added later must be named in both places.
        $expected = @(Get-ChildItem -Path (Join-Path -Path $root -ChildPath '.github/workflows') -File |
                Where-Object { $_.Extension -in '.yml', '.yaml' } |
                ForEach-Object { ".github/workflows/$($_.Name)" }) + 'engine/examples/org-checks.yml'
        $actionlint = $checks | Where-Object { $_.Name -eq 'actionlint' }
        $workflow = Get-Content -Raw -Path (Join-Path -Path $root -ChildPath '.github/workflows/ci.yml')
        $workflow -match '(?s)- name: actionlint\r?\n.*?"\$RUNNER_TEMP/actionlint" -color -shellcheck="\$RUNNER_TEMP/shellcheck" (?<files>[^\r\n]+)' |
            Should -BeTrue
        $ciFiles = $Matches.files -split '\s+'

        $because = 'a workflow file must be named in the actionlint Arguments of build.psd1 and in the actionlint step of ci.yml'
        @($actionlint.Arguments | Sort-Object) | Should -Be @($expected | Sort-Object) -Because $because
        @($ciFiles | Sort-Object) | Should -Be @($expected | Sort-Object) -Because $because
    }

    It 'runs every script of tools/' {
        # GitHubIssue.ps1 and DevModule.ps1 are libraries the scripts dot-source, not scripts to run.
        $scripts = @(Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'tools') -Filter '*.ps1' -File |
                Where-Object { $_.Name -notin 'GitHubIssue.ps1', 'DevModule.ps1' } |
                ForEach-Object { "tools/$($_.Name)" })
        $referenced = @($checks | ForEach-Object { $_.Arguments }) + @($tools.Script) |
            Where-Object { $_ -like 'tools/*.ps1' }

        @($referenced | Sort-Object -Unique) | Should -Be @($scripts | Sort-Object)
    }

    It 'points to existing scripts' {
        foreach ($tool in $tools) {
            # Test-Path is case-sensitive on Linux (CI), so a wrong case fails there.
            Test-Path -Path (Join-Path -Path $root -ChildPath $tool.Script) -PathType Leaf | Should -BeTrue -Because $tool.Script
        }
    }

    It 'has unique names, none of them all, each with a description' {
        @($names | Sort-Object -Unique).Count | Should -Be $names.Count
        $names | Should -Not -Contain 'all'
        foreach ($entry in @($checks) + @($tools)) {
            $entry.Description | Should -Not -BeNullOrEmpty -Because $entry.Name
        }
    }

    It 'runs the scripts that write to GitHub with -WhatIf only' {
        foreach ($path in 'tools/Invoke-RecurringReminder.ps1', 'tools/Invoke-GitHubApiVersionCheck.ps1', 'tools/Invoke-DependencyUpdateCheck.ps1') {
            $tool = $tools | Where-Object { $_.Script -eq $path }
            $tool.Parameters.WhatIf | Should -BeTrue -Because $path
        }
    }

    It 'installs the command of every check through Install-DevTools.ps1 or names its own install' {
        $devTools = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'dev-tools.psd1')
        foreach ($check in $checks | Where-Object { $_.Command -ne 'pwsh' }) {
            ($devTools.Tools.ContainsKey($check.Command) -or [bool]$check.Install) | Should -BeTrue -Because "$($check.Command) of '$($check.Name)'"
        }
    }

    It 'has a VS Code task for all and for every check and tool, and names only those' {
        # tasks.json has comments, which ConvertFrom-Json accepts.
        $tasks = @((Get-Content -Raw -Path (Join-Path -Path $root -ChildPath '.vscode/tasks.json') | ConvertFrom-Json).tasks)
        $taskNames = @(foreach ($task in $tasks) {
                $arguments = @($task.args)
                $index = [array]::IndexOf($arguments, '${workspaceFolder}/build.ps1')
                if ($index -ge 0) {
                    $arguments[$index + 1]
                }
            })

        @($taskNames | Sort-Object) | Should -Be @(@('all') + $names | Sort-Object)
    }
}

Describe 'build.ps1' {
    BeforeAll {
        # Pester mocks only commands that exist: the tests that need a token mock this stub.
        function gh { }

        # A copy next to a test manifest, fake checks and fake tools, run from outside its folder like the real one.
        $script:folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        Copy-Item -Path $buildScript -Destination $folder
        $script:build = Join-Path -Path $folder -ChildPath 'build.ps1'
        $script:callLog = Join-Path -Path $folder -ChildPath 'calls.log'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $folder -ChildPath 'checks'), (Join-Path -Path $folder -ChildPath 'tools')

        # A fake check logs its name, extra arguments and the token it sees to calls.log by a relative path (so the
        # log lands in the copy's folder only when build.ps1 runs it from there), then exits with -Code.
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'checks/check.ps1') -Value @'
param([string]$Name, [int]$Code)
Add-Content -Path 'calls.log' -Value "$Name [$($args -join ' ')] token=$env:GH_TOKEN"
"output of $Name"
exit $Code
'@
        # A check that is a PowerShell script runs in the same process, and throws instead of exiting.
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'checks/throw.ps1') -Value "throw 'Check broke.'"
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'tools/tool.ps1') -Value @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$Value = 'default')
[pscustomobject]@{ Value = $Value; WhatIf = [bool]$WhatIfPreference }
'@
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'tools/broken.ps1') -Value "throw 'Tool failed.'"
        $script:manifestPath = Join-Path -Path $folder -ChildPath 'build.psd1'
        Set-Content -Path $manifestPath -Value @'
@{
    Checks = @(
        @{ Name = 'first'; Description = 'First check'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'checks/check.ps1', '-Name', 'first', '-Code', '0'); CiStep = 'First' }
        @{ Name = 'failing'; Description = 'Failing check'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'checks/check.ps1', '-Name', 'failing', '-Code', '1'); CiStep = 'Failing' }
        @{ Name = 'missing'; Description = 'Missing tool'; Command = 'no-such-command-for-tests'; Arguments = @(); Install = 'the missing tool'; CiStep = 'Missing' }
        @{ Name = 'unknown'; Description = 'Missing dev tool'; Command = 'no-such-dev-tool-for-tests'; Arguments = @(); CiStep = 'Unknown' }
        @{ Name = 'token'; Description = 'Needs a token'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'checks/check.ps1', '-Name', 'token', '-Code', '0'); GitHubToken = $true; CiStep = 'Token' }
        @{ Name = 'last'; Description = 'Last check'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'checks/check.ps1', '-Name', 'last', '-Code', '0'); CiStep = 'Last' }
    )
    Tools = @(
        @{ Name = 'tool'; Description = 'A tool'; Script = 'tools/tool.ps1'; Parameters = @{} }
        @{ Name = 'status'; Description = 'Status only'; Script = 'tools/tool.ps1'; Parameters = @{ WhatIf = $true } }
        @{ Name = 'broken'; Description = 'A failing tool'; Script = 'tools/broken.ps1'; Parameters = @{} }
    )
}
'@
    }

    BeforeEach {
        Remove-Item -Path $callLog -ErrorAction SilentlyContinue
        # A developer's own token must not leak into the tests; restored in AfterEach.
        $script:savedToken = $env:GH_TOKEN
        $env:GH_TOKEN = $null

        # The mock runs inside the script under test and finds the list by name (dynamic scoping).
        $script:TestHostLines = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $TestHostLines.Add([string]$Object) }
    }

    AfterEach {
        $env:GH_TOKEN = $savedToken
    }

    Context 'checks' {
        It 'runs every check with all, keeps going after a failure and exits with 1' {
            Mock gh { 'test-token' }

            & $build all

            $LASTEXITCODE | Should -Be 1
            @(Get-Content -Path $callLog | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('first', 'failing', 'token', 'last')
            $TestHostLines | Should -Contain '== first (1/6) =='
            $TestHostLines | Should -Contain '== last (6/6) =='
            $TestHostLines | Should -Contain '3 passed, 1 failed, 2 skipped'
            @($TestHostLines | Where-Object { $_ -match '^failing\s+failed\s' }).Count | Should -Be 1
            @($TestHostLines | Where-Object { $_ -match '^missing\s+skipped\s' }).Count | Should -Be 1
        }

        It 'exits with 0 when every check it runs passes' {
            & $build first

            $LASTEXITCODE | Should -Be 0
            $TestHostLines | Should -Contain '1 passed, 0 failed, 0 skipped'
        }

        It 'exits with the result when run with pwsh -File' {
            & pwsh -NoProfile -NonInteractive -File $build first *> $null
            $LASTEXITCODE | Should -Be 0

            & pwsh -NoProfile -NonInteractive -File $build failing *> $null
            $LASTEXITCODE | Should -Be 1
        }

        It 'skips a missing command with what to install, without failing' {
            & $build missing
            $LASTEXITCODE | Should -Be 0
            $TestHostLines | Should -Contain 'Skipped: no-such-command-for-tests not found. Install: the missing tool.'

            & $build unknown
            $TestHostLines | Should -Contain 'Skipped: no-such-dev-tool-for-tests not found. Install: ./tools/Install-DevTools.ps1.'
            $TestHostLines | Should -Contain '0 passed, 0 failed, 1 skipped'
        }

        It 'passes the arguments after a check name to the check' {
            & $build first -Target 90

            Get-Content -Path $callLog | Should -Be @('first [-Target 90] token=')
        }

        It 'matches the name in any case' {
            & $build FIRST

            Get-Content -Path $callLog | Should -Be @('first [] token=')
        }

        It 'sets GH_TOKEN from gh for a check that needs it and removes it afterwards' {
            Mock gh { 'test-token' }

            & $build token

            Get-Content -Path $callLog | Should -Be @('token [] token=test-token')
            $env:GH_TOKEN | Should -BeNullOrEmpty
        }

        It 'keeps a GH_TOKEN that is set' {
            Mock gh { 'test-token' }
            $env:GH_TOKEN = 'own-token'

            & $build token

            Get-Content -Path $callLog | Should -Be @('token [] token=own-token')
            $env:GH_TOKEN | Should -Be 'own-token'
            Should -Invoke gh -Times 0 -Exactly
        }

        It 'skips a check that needs a token when gh has none' {
            Mock gh { }

            & $build token

            $LASTEXITCODE | Should -Be 0
            Test-Path -Path $callLog | Should -BeFalse
            $TestHostLines | Should -Contain 'Skipped: no GH_TOKEN and no token from gh. Install: gh auth login.'
        }

        It 'passes the output of a check through, instead of capturing it' {
            $output = & $build first

            $output | Should -Contain 'output of first'
        }

        It 'keeps going after a check that throws' {
            $manifest = Get-Content -Raw -Path $manifestPath
            try {
                Set-Content -Path $manifestPath -Value @'
@{
    Checks = @(
        @{ Name = 'throwing'; Description = 'Throwing check'; Command = './checks/throw.ps1'; Arguments = @(); CiStep = 'Throwing' }
        @{ Name = 'last'; Description = 'Last check'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'checks/check.ps1', '-Name', 'last', '-Code', '0'); CiStep = 'Last' }
    )
    Tools = @()
}
'@
                & $build all
            }
            finally {
                Set-Content -Path $manifestPath -Value $manifest
            }

            $LASTEXITCODE | Should -Be 1
            Get-Content -Path $callLog | Should -Be @('last [] token=')
            $TestHostLines | Should -Contain 'Failed: Check broke.'
            $TestHostLines | Should -Contain '1 passed, 1 failed, 0 skipped'
        }

        It 'keeps going when the session turns a failed native command into an error' {
            Mock gh { 'test-token' }
            # Set in a profile, it reaches the script through dynamic scope.
            $PSNativeCommandUseErrorActionPreference = $true

            & $build all

            $LASTEXITCODE | Should -Be 1
            $TestHostLines | Should -Contain '3 passed, 1 failed, 2 skipped'
        }

        It 'rejects arguments after all' {
            { & $build all -Target 90 } | Should -Throw -ExpectedMessage "Name one check to pass parameters: ./build.ps1 <check> <parameters>; 'all' takes none."
            Test-Path -Path $callLog | Should -BeFalse
        }
    }

    Context 'tools' {
        It 'runs a tool with the arguments after its name' {
            (& $build tool).Value | Should -Be 'default'

            $result = & $build tool -Value 'other value'

            $result.Value | Should -Be 'other value'
            $result.WhatIf | Should -BeFalse
        }

        It 'passes the parameters of the manifest as parameters, -WhatIf as the switch' {
            $result = & $build status

            $result.WhatIf | Should -BeTrue
            $result.Value | Should -Be 'default'
        }

        It 'lets the error of a tool through and restores the location' {
            $before = (Get-Location).Path

            { & $build broken } | Should -Throw -ExpectedMessage 'Tool failed.'
            (Get-Location).Path | Should -Be $before
        }

        It 'rejects a switch with a value' {
            { & $build tool -WhatIf:$false } | Should -Throw -ExpectedMessage 'Pass switches without a value: -Force, not -Force:$false.'
        }
    }

    Context 'names' {
        It 'rejects an unknown name and lists the names' {
            { & $build nope } | Should -Throw -ExpectedMessage "Unknown name 'nope'. Names: all, first, failing, missing, unknown, token, last, tool, status, broken."
        }
    }

    Context 'menu' {
        BeforeEach {
            # Answers given to the menu, in order; an unexpected extra question fails on the empty queue.
            $script:TestAnswers = [System.Collections.Generic.Queue[string]]::new()
            Mock Read-Host { $TestAnswers.Dequeue() } -ParameterFilter { $Prompt -eq 'Number (Enter to quit)' }
        }

        It 'lists all, the checks and the tools in manifest order' {
            $TestAnswers.Enqueue('')

            & $build

            $first = $TestHostLines.IndexOf('Checks')
            $first | Should -BeGreaterOrEqual 0
            $TestHostLines[$first + 1] | Should -Be '   1  all      Every check below, then a summary'
            $TestHostLines[$first + 2] | Should -Be '   2  first    First check'
            $TestHostLines[$first + 7] | Should -Be '   7  last     Last check'
            $TestHostLines[$first + 8] | Should -Be 'Tools'
            $TestHostLines[$first + 9] | Should -Be '   8  tool     A tool'
            $TestHostLines[$first + 11] | Should -Be '  10  broken   A failing tool'
            $TestHostLines | Should -Contain 'Parameters: ./build.ps1 <name> [parameters]'
        }

        It 'runs the chosen check' {
            $TestAnswers.Enqueue(' 2 ')

            & $build

            $LASTEXITCODE | Should -Be 0
            Get-Content -Path $callLog | Should -Be @('first [] token=')
        }

        It 'runs every check from the all entry' {
            Mock gh { 'test-token' }
            $TestAnswers.Enqueue('1')

            & $build

            $LASTEXITCODE | Should -Be 1
            $TestHostLines | Should -Contain '3 passed, 1 failed, 2 skipped'
        }

        It 'runs the chosen tool without arguments' {
            $TestAnswers.Enqueue('9')

            $result = & $build

            $result.Value | Should -Be 'default'
            $result.WhatIf | Should -BeTrue
        }

        It 'runs nothing on an empty answer' {
            $TestAnswers.Enqueue('')

            & $build | Should -BeNullOrEmpty
            Test-Path -Path $callLog | Should -BeFalse
            Should -Invoke Read-Host -Times 1 -Exactly
        }

        It 'asks again until the answer is a number from the list' {
            foreach ($answer in 'x', '0', '11', '8') {
                $TestAnswers.Enqueue($answer)
            }

            $result = & $build

            $result.Value | Should -Be 'default'
            Should -Invoke Read-Host -Times 4 -Exactly
            $TestHostLines | Should -Contain 'Enter a number from 1 to 10, or press Enter to quit.'
        }

        It 'rejects parameters without a name, instead of dropping them' {
            { & $build -Force } | Should -Throw -ExpectedMessage 'Name the check or tool to pass parameters: ./build.ps1 <name> <parameters>.'
            Should -Invoke Read-Host -Times 0 -Exactly
        }
    }
}
