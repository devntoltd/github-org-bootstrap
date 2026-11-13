BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')
    $script:helperPath = Join-Path -Path $PSScriptRoot -ChildPath '../GitHubIssue.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
}

Describe 'GitHubIssue.ps1' {
    BeforeEach {
        # Dot-sourced again for every test: the labels Add-MissingLabel read stay for the rest of a run.
        . $script:helperPath
        $folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:template = Join-Path -Path $folder -ChildPath 'review.md'
        Set-Content -Path $script:template -Value (@(
                '---'
                'name: "Review"'
                'about: Review something.'
                'title: "Review it"'
                'labels: [review, enhancement]'
                'assignees: [operator]'
                '---'
                ''
                '- [ ] Review it.'
            ) -join "`n")

        $script:TestIssues = @()
        $script:TestLabels = @('Enhancement')
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            switch ($args[0..1] -join ' ') {
                'issue list' { ConvertTo-Json -InputObject @($TestIssues) -Depth 5 }
                'label list' { ConvertTo-Json -InputObject @($TestLabels | ForEach-Object { @{ name = $_ } }) }
                'issue create' { "https://example.test/issues/7`n" }
            }
        }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    Context 'Assert-IssueTemplate' {
        It 'returns the title, labels, assignees and body of the template' {
            $result = Assert-IssueTemplate -Path $script:template -Label 'review'

            $result.Title | Should -Be 'Review it'
            $result.Labels | Should -Be @('review', 'enhancement')
            $result.Assignees | Should -Be @('operator')
            $result.Body | Should -Be '- [ ] Review it.'
        }

        It 'throws when the front matter has no title' {
            (Get-Content -Path $script:template) -notmatch '^title:' | Set-Content -Path $script:template

            { Assert-IssueTemplate -Path $script:template -Label 'review' } | Should -Throw 'review.md: the front matter has no title.'
        }

        It 'throws when the labels lack the one the issues are matched by' {
            { Assert-IssueTemplate -Path $script:template -Label 'other' } |
                Should -Throw "review.md: the labels must include 'other', which the issues are matched by."
        }
    }

    Context 'Get-LabeledIssue' {
        It 'returns the open and closed issues with the label, oldest first' {
            $script:TestIssues = @(
                @{ number = 9; state = 'OPEN'; body = 'b' }
                @{ number = 4; state = 'CLOSED'; body = 'a' }
            )

            $issues = @(Get-LabeledIssue -Label 'review')

            $issues.number | Should -Be @(4, 9)
            $call = (Get-GhCall 'issue list')[0]
            Get-GhOption -Call $call -Name '--label' | Should -Be 'review'
            Get-GhOption -Call $call -Name '--state' | Should -Be 'all'
            Get-GhOption -Call $call -Name '--json' | Should -Be 'number,state,body'
            Get-GhOption -Call $call -Name '--limit' | Should -Be '10000'
        }

        It 'throws rather than miss an issue when the list reaches the limit' {
            # gh returns at most --limit issues; the issues past it would be opened again as duplicates.
            $script:TestIssues = @(
                @{ number = 1; state = 'OPEN'; body = 'a' }
                @{ number = 2; state = 'CLOSED'; body = 'b' }
            )

            { Get-LabeledIssue -Label 'review' -Limit 2 } | Should -Throw "gh issue list returned 2 issues with the label 'review', its limit: some may be missing, so nothing was opened."
            Get-GhOption -Call (Get-GhCall 'issue list')[0] -Name '--limit' | Should -Be '2'
        }

        It 'returns nothing when no issue has the label' {
            @(Get-LabeledIssue -Label 'review').Count | Should -Be 0
        }
    }

    Context 'Find-IssueByMarker' {
        It 'returns the first issue whose body holds every marker' {
            $issues = @(
                [pscustomobject]@{ number = 2; body = '<!-- a -->' }
                [pscustomobject]@{ number = 3; body = "<!-- a -->`n<!-- b -->" }
                [pscustomobject]@{ number = 5; body = "<!-- b -->`n<!-- a -->" }
            )

            (Find-IssueByMarker -Issue $issues -Marker '<!-- a -->', '<!-- b -->').number | Should -Be 3
        }

        It 'returns nothing when no issue holds every marker' {
            $issues = @([pscustomobject]@{ number = 2; body = '<!-- a -->' }, [pscustomobject]@{ number = 3; body = $null })

            Find-IssueByMarker -Issue $issues -Marker '<!-- a -->', '<!-- b -->' | Should -BeNullOrEmpty
            Find-IssueByMarker -Issue @() -Marker '<!-- a -->' | Should -BeNullOrEmpty
        }
    }

    Context 'Add-MissingLabel' {
        It 'creates only the labels that do not exist, whatever their case' {
            Add-MissingLabel -Name 'review', 'enhancement' -Description 'Issue of a test'

            $created = Get-GhCall 'label create'
            $created.Count | Should -Be 1
            $created[0][2] | Should -Be 'review'
            Get-GhOption -Call $created[0] -Name '--description' | Should -Be 'Issue of a test'
        }

        It 'reads the labels once per run and creates none twice' {
            Add-MissingLabel -Name 'review' -Description 'Issue of a test'
            Add-MissingLabel -Name 'review', 'other' -Description 'Issue of a test'

            (Get-GhCall 'label list').Count | Should -Be 1
            @((Get-GhCall 'label create') | ForEach-Object { $_[2] }) | Should -Be @('review', 'other')
        }

        It 'creates nothing with -WhatIf' {
            Add-MissingLabel -Name 'review' -Description 'Issue of a test' -WhatIf

            (Get-GhCall 'label create').Count | Should -Be 0
        }
    }

    Context 'New-IssueFromTemplate' {
        BeforeEach {
            $script:issue = @{
                Title            = 'Review it 2027'
                Body             = 'The body.'
                Label            = @('review', 'enhancement')
                Assignee         = @('operator')
                Target           = '2027'
                LabelDescription = 'Issue of a test'
            }
        }

        It 'creates the missing labels first, then the issue, and returns its number' {
            $number = New-IssueFromTemplate @issue

            $number | Should -Be '7'
            ($script:TestGhCalls | ForEach-Object { $_[0..1] -join ' ' }) | Should -Be @('label list', 'label create', 'issue create')
            $created = (Get-GhCall 'issue create')[0]
            Get-GhOption -Call $created -Name '--title' | Should -Be 'Review it 2027'
            Get-GhOption -Call $created -Name '--body' | Should -Be 'The body.'
            @(Get-GhOption -Call $created -Name '--label') | Should -Be @('review', 'enhancement')
            @(Get-GhOption -Call $created -Name '--assignee') | Should -Be @('operator')
        }

        It 'creates nothing and returns nothing with -WhatIf' {
            New-IssueFromTemplate @issue -WhatIf | Should -BeNullOrEmpty

            $script:TestGhCalls.Count | Should -Be 0
        }
    }

    Context 'Add-StepSummary' {
        It 'appends the lines to the job summary, also in a dry run' {
            $env:GITHUB_STEP_SUMMARY = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid()).md"
            Set-Content -Path $env:GITHUB_STEP_SUMMARY -Value 'before'
            $WhatIfPreference = $true

            Add-StepSummary -Line '## Title', '', 'Status: ok'

            Get-Content -Path $env:GITHUB_STEP_SUMMARY | Should -Be @('before', '## Title', '', 'Status: ok')
        }

        It 'writes nothing outside GitHub Actions' {
            $env:GITHUB_STEP_SUMMARY = $null
            Mock Add-Content { }

            Add-StepSummary -Line 'Status: ok'

            Should -Invoke Add-Content -Times 0
        }
    }
}
