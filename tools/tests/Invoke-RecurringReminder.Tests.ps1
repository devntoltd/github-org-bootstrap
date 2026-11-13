BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:reminderScript = Join-Path -Path $script:root -ChildPath 'tools/Invoke-RecurringReminder.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    # Writes an issue template with the given front matter lines into the fixture folder.
    function Write-TestTemplate {
        param([string]$Name, [string[]]$FrontMatter, [string]$Body = '- [ ] Do it.')

        $text = (@('---') + $FrontMatter + @('---', '', $Body)) -join "`n"
        Set-Content -Path (Join-Path -Path $script:templates -ChildPath $Name) -Value $text
    }

    function Write-TestInterval {
        param([string]$Text)

        Set-Content -Path $script:intervals -Value $Text
    }

    # An issue as 'gh issue list --json' returns it.
    function Get-TestIssue {
        param(
            [int]$Number,
            [string]$Operation = 'alpha',
            [string]$State = 'CLOSED',
            [string]$StateReason = 'COMPLETED',
            [string]$ClosedAt,
            [string]$CreatedAt = '2026-01-01T08:00:00Z',
            [string]$Title = 'A reminder'
        )
        [ordered]@{
            number      = $Number
            title       = $Title
            labels      = @(@{ name = 'recurring' }, @{ name = "recurring:$Operation" })
            state       = $State
            stateReason = if ($StateReason) { $StateReason } else { $null }
            closedAt    = if ($ClosedAt) { $ClosedAt } else { $null }
            createdAt   = $CreatedAt
            url         = "https://example.test/issues/$Number"
        }
    }
}

Describe 'Invoke-RecurringReminder.ps1' {
    BeforeEach {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        $script:templates = (New-Item -ItemType Directory -Path (Join-Path -Path $folder -ChildPath 'ISSUE_TEMPLATE')).FullName
        $script:intervals = Join-Path -Path $folder -ChildPath 'recurring-operations.psd1'
        $script:summary = Join-Path -Path $folder -ChildPath 'summary.md'
        $env:GITHUB_STEP_SUMMARY = $script:summary

        Write-TestTemplate -Name 'recurring-alpha.md' -FrontMatter @(
            'name: "Recurring: Alpha"'
            'about: Do alpha.'
            'title: "[Recurring] Do alpha"'
            'labels: [recurring, "recurring:alpha"]'
            'assignees: [operator]'
        )
        Write-TestInterval "@{ 'recurring-alpha.md' = @{ IntervalDays = 90 } }"

        $script:TestIssues = @()
        $script:TestLabels = @('recurring', 'recurring:alpha')
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test, where $script: is that script's scope: the fixtures are found by
        # name (dynamic scoping), so their names must not clash with variables of the script.
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            switch ($args[0..1] -join ' ') {
                'issue list' { ConvertTo-Json -InputObject @($TestIssues) -Depth 5 }
                'label list' { ConvertTo-Json -InputObject @($TestLabels | ForEach-Object { @{ name = $_ } }) }
                'issue create' { 'https://example.test/issues/99' }
            }
        }
        Mock Get-Date { [datetime]::new(2026, 10, 5, 12, 0, 0, [DateTimeKind]::Utc) }
        Mock Write-Host { }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    Context 'validation' {
        It 'reports every problem at once, before any call to gh' {
            Write-TestTemplate -Name 'recurring-beta.md' -FrontMatter @('labels: [recurring, "recurring:gamma"]')
            Write-TestTemplate -Name 'plain.md' -FrontMatter @('title: Plain', 'labels: [bug]')
            Write-TestInterval ("@{ 'recurring-alpha.md' = @{ IntervalDays = 0 }; " +
                "'recurring-ghost.md' = @{ IntervalDays = 30 }; 'plain.md' = @{ IntervalDays = 30 } }")

            $message = ({ & $script:reminderScript -TemplatePath $script:templates -IntervalPath $script:intervals } |
                    Should -Throw -PassThru).Exception.Message

            $message | Should -BeLike "*recurring-alpha.md: IntervalDays in recurring-operations.psd1 must be a whole number above 0, got '0'.*"
            $message | Should -BeLike "*recurring-operations.psd1: 'recurring-ghost.md' is not a template in *"
            $message | Should -BeLike "*recurring-operations.psd1: 'plain.md' has no label 'recurring'.*"
            $message | Should -BeLike '*recurring-beta.md: no interval in recurring-operations.psd1.*'
            $message | Should -BeLike '*recurring-beta.md: the front matter has no title.*'
            $message | Should -BeLike "*recurring-beta.md: the labels must include 'recurring:beta'*"
            Should -Invoke gh -Times 0
        }

        It 'ignores templates without the label recurring and issue forms' {
            Write-TestTemplate -Name 'bug.md' -FrontMatter @('title: Bug', 'labels: [bug]')
            Set-Content -Path (Join-Path -Path $script:templates -ChildPath 'feature.yml') -Value 'name: Feature'

            { & $script:reminderScript -TemplatePath $script:templates -IntervalPath $script:intervals -WhatIf } |
                Should -Not -Throw

            $summary = Get-Content -Path $script:summary
            $summary | Should -Contain '| Do alpha | 90 days | never | 2026-10-05 | due |'
            $summary | Where-Object { $_ -like '*Bug*' -or $_ -like '*Feature*' } | Should -BeNullOrEmpty
        }
    }

    Context 'reminders' {
        BeforeAll {
            function Invoke-TestReminder {
                & $script:reminderScript -TemplatePath $script:templates -IntervalPath $script:intervals @args
            }
        }

        It 'opens a reminder for an operation never done' {
            Invoke-TestReminder

            $create = Get-GhCall -Command 'issue create'
            $create.Count | Should -Be 1
            Get-GhOption -Call $create[0] -Name '--title' | Should -Be '[Recurring] Do alpha (due 2026-10-05)'
            Get-GhOption -Call $create[0] -Name '--label' | Should -Be @('recurring', 'recurring:alpha')
            Get-GhOption -Call $create[0] -Name '--assignee' | Should -Be 'operator'
            Get-GhOption -Call $create[0] -Name '--body' | Should -Be "Every 90 days; never done before.`n`n- [ ] Do it."
            Get-Content -Path $script:summary | Should -Contain '| Do alpha | 90 days | never | 2026-10-05 | opened #99 |'
        }

        It 'counts the interval from the last completion (closed <ClosedAt>)' -ForEach @(
            @{ ClosedAt = '2026-07-08T10:00:00Z'; Created = 0; Row = '| Do alpha | 90 days | 2026-07-08 (#5) | 2026-10-06 | ok |' }
            @{ ClosedAt = '2026-07-07T23:00:00Z'; Created = 1; Row = '| Do alpha | 90 days | 2026-07-07 (#5) | 2026-10-05 | opened #99 |' }
        ) {
            $script:TestIssues = @(Get-TestIssue -Number 5 -ClosedAt $ClosedAt)

            Invoke-TestReminder

            (Get-GhCall -Command 'issue create').Count | Should -Be $Created
            Get-Content -Path $script:summary | Should -Contain $Row
        }

        It 'ignores a reminder closed as not planned' {
            $script:TestIssues = @(
                Get-TestIssue -Number 3 -ClosedAt '2026-01-01T09:00:00Z'
                Get-TestIssue -Number 4 -ClosedAt '2026-09-30T09:00:00Z' -StateReason 'NOT_PLANNED'
            )

            Invoke-TestReminder

            $create = Get-GhCall -Command 'issue create'
            Get-GhOption -Call $create[0] -Name '--title' | Should -Be '[Recurring] Do alpha (due 2026-04-01)'
            Get-GhOption -Call $create[0] -Name '--body' | Should -BeLike 'Every 90 days; last done 2026-01-01 in #3.*'
        }

        It 'finds the history by the operation label, whatever the title' {
            $script:TestIssues = @(
                Get-TestIssue -Number 5 -ClosedAt '2026-09-01T10:00:00Z' -Title 'Renamed by hand'
                Get-TestIssue -Number 6 -Operation 'beta' -State 'OPEN' -StateReason '' -CreatedAt '2026-10-01T00:00:00Z'
                Get-TestIssue -Number 8 -Operation 'beta' -ClosedAt '2026-10-04T10:00:00Z'
            )

            Invoke-TestReminder

            (Get-GhCall -Command 'issue create').Count | Should -Be 0
            Get-Content -Path $script:summary | Should -Contain '| Do alpha | 90 days | 2026-09-01 (#5) | 2026-11-30 | ok |'
        }

        It 'never duplicates an open reminder (<Case>)' -ForEach @(
            @{
                Case   = 'overdue since the last completion'
                Issues = @(
                    @{ Number = 2; ClosedAt = '2026-06-01T10:00:00Z' }
                    @{ Number = 7; State = 'OPEN'; StateReason = ''; CreatedAt = '2026-09-01T06:17:00Z' }
                )
                Row    = '| Do alpha | 90 days | 2026-06-01 (#2) | 2026-08-30 | open #7, overdue by 36 days |'
            }
            @{
                Case   = 'never done, opened weeks ago'
                Issues = @(@{ Number = 7; State = 'OPEN'; StateReason = ''; CreatedAt = '2026-09-01T06:17:00Z' })
                Row    = '| Do alpha | 90 days | never | 2026-09-01 | open #7, overdue by 34 days |'
            }
            @{
                Case   = 'never done, opened today'
                Issues = @(@{ Number = 7; State = 'OPEN'; StateReason = ''; CreatedAt = '2026-10-05T06:17:00Z' })
                Row    = '| Do alpha | 90 days | never | 2026-10-05 | open #7 |'
            }
        ) {
            $script:TestIssues = @($Issues | ForEach-Object { Get-TestIssue @_ })

            Invoke-TestReminder

            (Get-GhCall -Command 'issue create').Count | Should -Be 0
            Get-Content -Path $script:summary | Should -Contain $Row
        }

        It 'creates the missing labels only' {
            $script:TestLabels = @('recurring')

            Invoke-TestReminder

            $created = Get-GhCall -Command 'label create'
            $created.Count | Should -Be 1
            $created[0][2] | Should -Be 'recurring:alpha'
        }

        It 'creates another missing label of the template with the reminder, reading the labels once' {
            Write-TestTemplate -Name 'recurring-alpha.md' -FrontMatter @(
                'title: "[Recurring] Do alpha"'
                'labels: [recurring, "recurring:alpha", ops]'
            )

            Invoke-TestReminder

            $created = Get-GhCall -Command 'label create'
            @($created | ForEach-Object { $_[2] }) | Should -Be @('ops')
            Get-GhOption -Call $created[0] -Name '--description' | Should -Be 'Reminder of a recurring operation (tools/Invoke-RecurringReminder.ps1)'
            (Get-GhCall -Command 'label list').Count | Should -Be 1
            Get-GhOption -Call (Get-GhCall -Command 'issue create')[0] -Name '--label' | Should -Be @('recurring', 'recurring:alpha', 'ops')
        }

        It 'changes nothing with -WhatIf, but still writes the summary' {
            $script:TestLabels = @()

            Invoke-TestReminder -WhatIf

            (Get-GhCall -Command 'issue create').Count | Should -Be 0
            (Get-GhCall -Command 'label create').Count | Should -Be 0
            Get-Content -Path $script:summary | Should -Contain '| Do alpha | 90 days | never | 2026-10-05 | due |'
        }

        It 'writes the job summary only when GITHUB_STEP_SUMMARY is set' {
            $env:GITHUB_STEP_SUMMARY = $null

            Invoke-TestReminder -WhatIf

            Test-Path -Path $script:summary | Should -BeFalse
            Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*Do alpha*' }
        }

        It 'keeps every column on the host, whatever its width' {
            $title = '[Recurring] ' + ('Do a very long operation ' * 5).Trim()
            Write-TestTemplate -Name 'recurring-alpha.md' -FrontMatter @(
                "title: `"$title`""
                'labels: [recurring, "recurring:alpha"]'
            )
            $script:TestIssues = @(Get-TestIssue -Number 7 -State 'OPEN' -StateReason '' -CreatedAt '2026-09-01T06:17:00Z')

            Invoke-TestReminder

            Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*open #7, overdue by 34 days*' }
        }

        It 'creates no empty label when there is no recurring operation' {
            Remove-Item -Path (Join-Path -Path $script:templates -ChildPath 'recurring-alpha.md')
            Write-TestInterval '@{}'
            $script:TestLabels = @()

            Invoke-TestReminder

            (Get-GhCall -Command 'label create').ForEach({ $_[2] }) | Should -Be @('recurring')
        }

        It 'throws when gh fails' {
            Mock gh { $global:LASTEXITCODE = 1 }

            { Invoke-TestReminder } | Should -Throw '*gh issue list failed with exit code 1*'
        }
    }
}

Describe 'recurring operations of this repository' {
    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
    }

    It 'has valid templates and intervals, and lists every operation' {
        $env:GITHUB_STEP_SUMMARY = $null
        $script:TestPrinted = [System.Collections.Generic.List[string]]::new()
        Mock gh { $global:LASTEXITCODE = 0; '[]' }
        Mock Write-Host { $TestPrinted.Add("$Object") }

        { & $script:reminderScript -WhatIf } | Should -Not -Throw

        $templates = @(Get-ChildItem -Path (Join-Path -Path $script:root -ChildPath '.github/ISSUE_TEMPLATE') -Filter 'recurring-*.md')
        $templates | Should -Not -BeNullOrEmpty
        foreach ($template in $templates) {
            $title = ((Get-Content -Path $template.FullName -Raw) -split "`n" | Where-Object { $_ -match '^title:\s*"\[Recurring\] (?<action>.+)"' } | ForEach-Object { $Matches.action })
            $title | Should -Not -BeNullOrEmpty -Because "$($template.Name) has a title"
            ($script:TestPrinted -join "`n") | Should -BeLike "*$([WildcardPattern]::Escape($title))*" -Because "$($template.Name) is listed"
        }
    }
}
