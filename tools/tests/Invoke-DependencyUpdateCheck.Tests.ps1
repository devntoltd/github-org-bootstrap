BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:checkScript = Join-Path -Path $script:root -ChildPath 'tools/Invoke-DependencyUpdateCheck.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    # A candidate as Find-DependencyUpdate.ps1 writes it.
    function Get-TestCandidate {
        param([string]$Name = 'Example.Base', [string]$Version = '5.6.0', [string]$Kind = 'Module', [string]$Until)

        $candidate = [ordered]@{
            Kind = $Kind; Name = $Name; File = 'modules.lock.psd1'; Locked = '5.5.3'; Version = $Version
            Published = '2026-09-25'; Notes = "https://example.test/$Name/$Version"
        }
        if ($Until) {
            $candidate.Until = $Until
        }
        $candidate
    }

    # An issue as 'gh issue list --json number,state,body' returns it, marked with the candidates.
    function Get-TestIssue {
        param([int]$Number, [string[]]$Marker, [string]$State = 'OPEN')

        [ordered]@{ number = $Number; state = $State; body = (($Marker | ForEach-Object { "<!-- dependency-update: $_ -->" }) -join "`n") + "`nReview." }
    }
}

Describe 'Invoke-DependencyUpdateCheck.ps1' {
    BeforeEach {
        $script:folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:template = Join-Path -Path $folder -ChildPath 'dependency-update.md'
        Set-Content -Path $template -Value (@(
                '---'
                'name: "Dependency update review"'
                'about: Review.'
                'title: "Review dependency updates"'
                'labels: [dependency-update, enhancement]'
                'assignees: [operator]'
                '---'
                ''
                '- [ ] Review it.'
            ) -join "`n")
        $script:candidatePath = Join-Path -Path $folder -ChildPath 'candidates.json'
        $script:summary = Join-Path -Path $folder -ChildPath 'summary.md'
        $env:GITHUB_STEP_SUMMARY = $summary

        $script:TestIssues = @()
        $script:TestLabels = @('enhancement')
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test: the fixtures are found by name (dynamic scoping), so their names
        # must not clash with variables of the script.
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            switch ($args[0..1] -join ' ') {
                'issue list' { ConvertTo-Json -InputObject @($TestIssues) -Depth 5 }
                'label list' { ConvertTo-Json -InputObject @($TestLabels | ForEach-Object { @{ name = $_ } }) }
                'issue create' { 'https://example.test/issues/9' }
            }
        }
        Mock Write-Host { }

        function Write-TestCandidate {
            param([object[]]$Candidate = @(), [object[]]$Quarantined = @())

            ConvertTo-Json -InputObject @{ Candidates = @($Candidate); Quarantined = @($Quarantined) } -Depth 5 | Set-Content -Path $script:candidatePath
        }
        $script:arguments = @{ CandidatePath = $candidatePath; TemplatePath = $template; TestResult = 'success'; RunUrl = 'https://example.test/runs/1' }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    It 'opens nothing without candidates' {
        Write-TestCandidate

        & $checkScript @arguments

        (Get-GhCall 'issue list').Count | Should -Be 0
        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-Content -Path $summary -Raw) | Should -Match 'Status: no updates'
    }

    It 'opens one issue with the markers, the table, the test result and its label' {
        Write-TestCandidate -Candidate @((Get-TestCandidate), (Get-TestCandidate -Name 'lychee' -Version '0.25.0' -Kind 'Tool')) -Quarantined @(Get-TestCandidate -Version '5.7.0' -Until '2026-10-09')

        & $checkScript @arguments

        (Get-GhCall 'label create')[0][2] | Should -Be 'dependency-update'
        $created = Get-GhCall 'issue create'
        $created.Count | Should -Be 1
        Get-GhOption -Call $created[0] -Name '--title' | Should -Be 'Review dependency updates'
        @(Get-GhOption -Call $created[0] -Name '--label') | Should -Be @('dependency-update', 'enhancement')
        @(Get-GhOption -Call $created[0] -Name '--assignee') | Should -Be @('operator')
        $body = Get-GhOption -Call $created[0] -Name '--body'
        $body | Should -Match '<!-- dependency-update: Example.Base 5\.6\.0 -->'
        $body | Should -Match '<!-- dependency-update: lychee 0\.25\.0 -->'
        $body | Should -Match '\| Example.Base \| module \| 5\.5\.3 \| 5\.6\.0 \| 2026-09-25 \| \[notes\]\(https://example\.test/Example.Base/5\.6\.0\) \|'
        $body | Should -Match 'Example.Base 5\.7\.0 is in quarantine until 2026-10-09'
        $body | Should -Match 'Tests and module imports on the new module versions: \*\*passed\*\* \(\[run\]\(https://example\.test/runs/1\)\)'
        $body | Should -Match '- \[ \] Review it\.'
        (Get-Content -Path $summary -Raw) | Should -Match 'Status: opened #9'
    }

    It 'reports failed tests' {
        Write-TestCandidate -Candidate @(Get-TestCandidate)

        & $checkScript @arguments -TestResult 'failure'

        Get-GhOption -Call (Get-GhCall 'issue create')[0] -Name '--body' | Should -Match 'Tests and module imports on the new module versions: \*\*failed\*\*'
    }

    It 'updates the open issue instead of opening another' {
        Write-TestCandidate -Candidate @(Get-TestCandidate)
        $script:TestIssues = @(Get-TestIssue -Number 4 -Marker 'Example.Base 5.5.9')

        & $checkScript @arguments

        (Get-GhCall 'issue create').Count | Should -Be 0
        $edited = Get-GhCall 'issue edit'
        $edited.Count | Should -Be 1
        $edited[0][2] | Should -Be '4'
        Get-GhOption -Call $edited[0] -Name '--body' | Should -Match 'dependency-update: Example.Base 5\.6\.0'
    }

    It 'opens nothing while a closed issue holds every candidate' {
        Write-TestCandidate -Candidate @(Get-TestCandidate)
        $script:TestIssues = @(Get-TestIssue -Number 3 -Marker 'Example.Base 5.6.0' -State 'CLOSED')

        & $checkScript @arguments

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'issue edit').Count | Should -Be 0
        (Get-Content -Path $summary -Raw) | Should -Match 'Status: closed #3'
    }

    It 'opens a new issue for a candidate no closed issue holds' {
        Write-TestCandidate -Candidate @((Get-TestCandidate), (Get-TestCandidate -Name 'Pester' -Version '6.3.0'))
        $script:TestIssues = @(Get-TestIssue -Number 3 -Marker 'Example.Base 5.6.0' -State 'CLOSED')

        & $checkScript @arguments

        (Get-GhCall 'issue create').Count | Should -Be 1
    }

    It 'says the tests did not run when there is no module candidate' {
        Write-TestCandidate -Candidate @(Get-TestCandidate -Name 'lychee' -Version '0.25.0' -Kind 'Tool')

        & $checkScript @arguments -TestResult 'skipped'

        Get-GhOption -Call (Get-GhCall 'issue create')[0] -Name '--body' | Should -Match 'Tests and module imports on the new module versions: \*\*not run\*\*'
    }

    It 'changes nothing with -WhatIf' {
        Write-TestCandidate -Candidate @(Get-TestCandidate)

        & $checkScript @arguments -WhatIf

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'label create').Count | Should -Be 0
        (Get-GhCall 'issue edit').Count | Should -Be 0
        (Get-Content -Path $summary -Raw) | Should -Match 'Status: new'
    }

    It 'changes nothing with -WhatIf when an issue is open' {
        Write-TestCandidate -Candidate @(Get-TestCandidate)
        $script:TestIssues = @(Get-TestIssue -Number 4 -Marker 'Example.Base 5.5.9')

        & $checkScript @arguments -WhatIf

        (Get-GhCall 'issue edit').Count | Should -Be 0
        (Get-Content -Path $summary -Raw) | Should -Match 'Status: open #4'
    }

    It 'finds the candidates itself without a candidate file' {
        Mock Find-PSResource { [pscustomobject]@{ Name = $Name; Version = [version]'0.0.1'; PublishedDate = [datetime]'2020-01-01'; Prerelease = '' } }
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            '[]'
        }

        & $checkScript -TemplatePath $template -WhatIf

        Should -Invoke Find-PSResource -Times 1 -ParameterFilter { $Name -eq 'Pester' }
        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-Content -Path $summary -Raw) | Should -Match 'Status: no updates'
    }
}
