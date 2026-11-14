BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:checkScript = Join-Path -Path $script:root -ChildPath 'tools/Invoke-GitHubApiVersionCheck.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    # An issue as 'gh issue list --json number,state,body' returns it, opened by the check for $Version.
    function Get-TestIssue {
        param([int]$Number, [string]$Version, [string]$State = 'OPEN')

        [ordered]@{ number = $Number; state = $State; body = "<!-- github-api-version: $Version -->`nReview it." }
    }
}

Describe 'Invoke-GitHubApiVersionCheck.ps1' {
    BeforeEach {
        $folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:module = Join-Path -Path $folder -ChildPath 'Common.psm1'
        Set-Content -Path $script:module -Value "`$ErrorActionPreference = 'Stop'`n`$script:GitHubApiVersion = '2026-03-10'"
        $script:template = Join-Path -Path $folder -ChildPath 'api-version.md'
        Set-Content -Path $script:template -Value (@(
                '---'
                'name: "API version"'
                'about: Review a newer API version.'
                'title: "Review the API version"'
                'labels: [github-api-version, enhancement]'
                'assignees: [operator]'
                '---'
                ''
                '- [ ] Review it.'
            ) -join "`n")
        $script:paths = @{ ModulePath = $script:module; TemplatePath = $script:template }
        $script:summary = Join-Path -Path $folder -ChildPath 'summary.md'
        $env:GITHUB_STEP_SUMMARY = $script:summary

        $script:TestVersions = @('2026-03-10', '2022-11-28')
        $script:TestIssues = @()
        $script:TestLabels = @('enhancement')
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test: the fixtures are found by name (dynamic scoping), so their names
        # must not clash with variables of the script.
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            switch ($args[0..1] -join ' ') {
                'api versions' { ConvertTo-Json -InputObject @($TestVersions) }
                'issue list' { ConvertTo-Json -InputObject @($TestIssues) -Depth 5 }
                'label list' { ConvertTo-Json -InputObject @($TestLabels | ForEach-Object { @{ name = $_ } }) }
                'issue create' { 'https://example.test/issues/7' }
            }
        }
        Mock Write-Host { }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    It 'opens nothing while the pinned version is the latest' {
        & $script:checkScript @paths

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'issue list').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -Match '\| 2026-03-10 \| 2026-03-10 \| ok \|'
    }

    It 'opens one review issue, with its label, for a newer version' {
        $script:TestVersions = @('2026-03-10', '2027-06-01', '2022-11-28')
        $script:TestIssues = @(Get-TestIssue -Number 3 -Version '2026-03-10' -State 'CLOSED')

        & $script:checkScript @paths

        (Get-GhCall 'label create').Count | Should -Be 1
        (Get-GhCall 'label create')[0][2] | Should -Be 'github-api-version'
        $created = Get-GhCall 'issue create'
        $created.Count | Should -Be 1
        Get-GhOption -Call $created[0] -Name '--title' | Should -Be 'Review the API version 2027-06-01'
        @(Get-GhOption -Call $created[0] -Name '--label') | Should -Be @('github-api-version', 'enhancement')
        @(Get-GhOption -Call $created[0] -Name '--assignee') | Should -Be @('operator')
        $body = Get-GhOption -Call $created[0] -Name '--body'
        $body | Should -BeLike '<!-- github-api-version: 2027-06-01 -->*'
        $body | Should -Match ([regex]::Escape('version `2027-06-01`; the engine pins `2026-03-10`'))
        $body | Should -BeLike '*- `[ `] Review it.'
        (Get-Content -Path $script:summary -Raw) | Should -Match '\| 2026-03-10 \| 2027-06-01 \| opened #7 \|'
    }

    It 'opens no second issue for a version that has one: <State>' -ForEach @(
        @{ State = 'OPEN'; Status = 'open #5' }
        @{ State = 'CLOSED'; Status = 'closed #5' }
    ) {
        $script:TestVersions = @('2027-06-01', '2026-03-10')
        $script:TestLabels = @('enhancement', 'github-api-version')
        $script:TestIssues = @(Get-TestIssue -Number 5 -Version '2027-06-01' -State $State)

        & $script:checkScript @paths

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'label create').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -Match "\| 2026-03-10 \| 2027-06-01 \| $Status \|"
    }

    It 'with -WhatIf reports a newer version without creating anything' {
        $script:TestVersions = @('2027-06-01', '2026-03-10')

        & $script:checkScript @paths -WhatIf

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'label create').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -Match '\| 2026-03-10 \| 2027-06-01 \| new \|'
    }

    It 'reads the pinned version of the shared module and the issue template of the repository by default' {
        $script:TestVersions = @('9999-12-31')

        & $script:checkScript

        $created = Get-GhCall 'issue create'
        $created.Count | Should -Be 1
        Get-GhOption -Call $created[0] -Name '--title' | Should -BeLike '* 9999-12-31'
        @(Get-GhOption -Call $created[0] -Name '--label') | Should -Contain 'github-api-version'
        @(Get-GhOption -Call $created[0] -Name '--assignee') | Should -Not -BeNullOrEmpty
        (Get-Content -Path $script:summary -Raw) | Should -Match '\| \d{4}-\d{2}-\d{2} \| 9999-12-31 \| opened #7 \|'
    }

    It 'fails before any gh call when the template lacks the label the issues are matched by' {
        (Get-Content -Path $script:template -Raw) -replace 'github-api-version, ', '' | Set-Content -Path $script:template

        { & $script:checkScript @paths } | Should -Throw "*api-version.md*'github-api-version'*"
        $script:TestGhCalls.Count | Should -Be 0
    }

    It 'fails before any gh call when the module pins no version' {
        Set-Content -Path $script:module -Value "`$ErrorActionPreference = 'Stop'"

        { & $script:checkScript @paths } | Should -Throw '*GitHubApiVersion*'
        $script:TestGhCalls.Count | Should -Be 0
    }
}
