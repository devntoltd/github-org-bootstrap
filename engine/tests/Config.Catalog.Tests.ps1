BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Setting catalog' {
    It 'gives every row a page of the settings menu, or none with NoUi' {
        $bad = InModuleScope GitHubOrg {
            @($script:SettingDefinitions | Where-Object {
                    if ($_.NoUi) { $null -ne $_.Page } else { -not $_.Page -or -not (Get-SettingPage -Path $_.Page) }
                } | ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'lists every page once, in menu order' {
        $paths = InModuleScope GitHubOrg { @($script:SettingPages | ForEach-Object { $_.Path }) }

        $paths.Count | Should -BeGreaterThan 0
        @($paths | Select-Object -Unique).Count | Should -Be $paths.Count
        $paths[0] | Should -Be 'profile'
    }

    It 'marks a page managed exactly when rows or an area cover it' {
        $bad = InModuleScope GitHubOrg {
            $covered = @($script:SettingDefinitions | Where-Object { $_.Page } | ForEach-Object { $_.Page })
            foreach ($page in $script:SettingPages) {
                $has = $covered -contains $page.Path -or [bool]$page.Area
                switch ($page.Status) {
                    'managed' { if (-not $has) { "$($page.Path): managed without rows or area" } }
                    'unmanaged' { if ($has -or -not $page.Reason) { "$($page.Path): unmanaged needs a reason and no rows" } }
                    'pending' { if ($has -or $page.Reason) { "$($page.Path): pending has rows or a reason" } }
                    default { "$($page.Path): unknown status" }
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'reads and writes every apply row of an endpoint section' {
        $bad = InModuleScope GitHubOrg {
            @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'apply' -and $script:Sections.Contains($_.Section) } |
                    Where-Object { -not (Get-SettingRead -Definition $_) -or -not (Get-SettingWrite -Definition $_) } |
                    ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'gives every row a recommendation with its reason, or the reason it has none' {
        # Every value of github.json has a reason: a recommended value and why, or why the engine takes no side
        # (project data, or the owner decides), never both and never neither.
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in $script:SettingDefinitions) {
                $path = Get-SettingPath -Definition $definition
                $recommended = $definition.ContainsKey('Recommended')
                if ($recommended -and $definition.ContainsKey('NoRecommendation')) { "${path}: both" }
                elseif ($recommended -and -not $definition.Why) { "${path}: Recommended without Why" }
                elseif (-not $recommended -and -not $definition.NoRecommendation) { "${path}: neither" }
                elseif ($definition.NoRecommendation -and $definition.NoRecommendation -notmatch '^(Project data|Owner decides): \S') { "${path}: NoRecommendation names neither project data nor the owner" }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'gives every manual row a page, a group and a reason' {
        # A setting without an API and without a page does not exist, so a manual row is never NoUi.
        $bad = InModuleScope GitHubOrg {
            @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'manual' } |
                    Where-Object { $_.NoUi -or -not $_.Page -or -not $_.UiGroup -or -not $_.Why } | ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'uses only row keys the engine knows' {
        # A misspelled key (Option, AbsentValues) would be ignored without a word.
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in $script:SettingDefinitions) {
                foreach ($key in $definition.Keys) {
                    if ($key -cnotin $script:SettingRowKeys) { "$(Get-SettingPath -Definition $definition): $key" }
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'makes a row depend only on a boolean apply row of its own section' {
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.DependsOn })) {
                $target = @(Get-SettingDefinition -Section $definition.Section | Where-Object { $_.Field -ceq $definition.DependsOn })
                if ($definition.Mode -ne 'apply' -or $target.Count -ne 1 -or $target[0].Type -ne 'boolean' -or $target[0].Mode -ne 'apply') {
                    "$(Get-SettingPath -Definition $definition): $($definition.DependsOn)"
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'gives a check row a Write exactly when the write of its section takes the field' {
        # Otherwise the warning would claim "GitHub has no API to change it" for a field the PATCH takes, or the reverse.
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'check' -and $script:Sections.Contains($_.Section) })) {
                $section = $script:Sections[$definition.Section]
                $body = @($script:ApiCatalog.Paths['/orgs/{org}' + $section.Path][$section.Method].Body)
                $writable = (Get-SettingRead -Definition $definition).Field -cin $body
                if ($writable -ne [bool]$definition.Write) { "$(Get-SettingPath -Definition $definition): in Body $writable, Write $([bool]$definition.Write)" }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'names options only for values of the row' {
        # A boolean without a control label of its own (two radios, a menu) names its options as true and false.
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.Options })) {
                $values = if ($definition.Type -eq 'boolean') { @('true', 'false') } else { @($definition['Values']) }
                foreach ($key in $definition.Options.Keys) {
                    if ($key -cnotin $values -or -not $definition.Options[$key]) { "$(Get-SettingPath -Definition $definition): $key" }
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }
}

Describe 'Setting catalog: UI metadata of the page walk' {
    BeforeAll {
        # The rows the walk shows one by one: with a page that no area manages.
        $script:walkRows = InModuleScope GitHubOrg {
            $areaPages = @($script:SettingPages | Where-Object { $_.Area } | ForEach-Object { $_.Path })
            , @($script:SettingDefinitions | Where-Object { $_.Page -and $_.Page -notin $areaPages })
        }
    }

    It 'lists every row of a page once in its Order' {
        $bad = InModuleScope GitHubOrg {
            foreach ($page in $script:SettingPages) {
                $rows = @($script:SettingDefinitions | Where-Object { $_.Page -eq $page.Path } | ForEach-Object { Get-SettingPath -Definition $_ })
                if ($page.Area) {
                    if ($page.ContainsKey('Order')) { "$($page.Path): an area page has no Order" }
                    continue
                }
                $expected = @($rows | Sort-Object)
                $actual = @($page.Order | Sort-Object)
                if (($expected -join '|') -cne ($actual -join '|')) { "$($page.Path): Order [$($actual -join ', ')] rows [$($expected -join ', ')]" }
                if ($page.Order -and @($page.Order | Select-Object -Unique).Count -ne @($page.Order).Count) { "$($page.Path): Order repeats a row" }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'dates the UI metadata of every page with rows' {
        $bad = InModuleScope GitHubOrg {
            $today = [datetime]::UtcNow.Date
            foreach ($page in $script:SettingPages) {
                # An area page shows its actions and warnings, not its rows: nothing of it was compared with the page.
                $hasRows = -not $page.Area -and @($script:SettingDefinitions | Where-Object { $_.Page -eq $page.Path }).Count -gt 0
                if (-not $hasRows) {
                    if ($page.ContainsKey('ReviewedOn')) { "$($page.Path): ReviewedOn without rows" }
                    continue
                }
                $date = [datetime]::MinValue
                if ($page.ReviewedOn -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not [datetime]::TryParseExact($page.ReviewedOn, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, 'None', [ref]$date) -or $date -gt $today) {
                    "$($page.Path): ReviewedOn '$($page.ReviewedOn)'"
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'names the group of every row with a page' {
        $bad = @($script:walkRows | Where-Object { -not $_.UiGroup } | ForEach-Object { "$($_.Section).$($_.Field)" })

        $bad | Should -BeNullOrEmpty
    }

    It 'names the control of every row with a page' {
        # An enum is found by its options; a boolean by its label, or by its two options when it has no label; any
        # other type by its label. A hint adds to them and never stands in for them.
        $bad = @(foreach ($row in $script:walkRows) {
                $ok = switch ($row.Type) {
                    'enum' { [bool]$row.Options }
                    'boolean' { [bool]$row.UiLabel -or ($row.Options -and $row.Options.Count -eq 2) }
                    default { [bool]$row.UiLabel }
                }
                if (-not $ok) { "$($row.Section).$($row.Field)" }
            })

        $bad | Should -BeNullOrEmpty
    }

    It 'tells the controls of a page apart' {
        # Rows without a label are told apart by their options.
        $keys = @($script:walkRows | ForEach-Object {
                $control = if ($_.UiLabel) { $_.UiLabel } else { ($_.Options.Values | Sort-Object) -join '/' }
                "$($_.Page)|$($_.UiGroup)|$control"
            })

        @($keys | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) | Should -BeNullOrEmpty
    }

    It 'never uses the field name as a UI name' {
        $bad = @($script:walkRows | Where-Object {
                $path = "$($_.Section).$($_.Field)"
                $_.UiGroup -cin @($_.Field, $path) -or $_.UiLabel -cin @($_.Field, $path)
            } | ForEach-Object { "$($_.Section).$($_.Field)" })

        $bad | Should -BeNullOrEmpty
    }

    It 'names the option <Name> expects, or gives a hint' -ForEach @(
        @{ Name = 'examples/github.json'; Path = '../examples/github.json' }
    ) {
        # Project data: the expected value of the config, which unconfigured and null have no option for on most pages.
        $config = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath $Path) | ConvertFrom-Json
        $bad = @(foreach ($row in @($script:walkRows | Where-Object { $_.Type -eq 'enum' })) {
                $value = $config
                foreach ($part in @($row.Section -split '\.') + $row.Field) { $value = $value.$part }
                if (-not $row.Hint -and ($null -eq $value -or -not $row.Options.ContainsKey([string]$value))) { "$($row.Section).$($row.Field): $value" }
            })

        $bad | Should -BeNullOrEmpty
    }

    It 'gives the code security page its area' {
        InModuleScope GitHubOrg { (Get-SettingPage -Path 'security_products').Area } | Should -Be 'codeSecurity'
    }

    It 'gives the rows of a page in its Order' {
        $rows = InModuleScope GitHubOrg {
            $page = @{ Path = 'probe'; Order = @('settings.b', 'settings.a') }
            $script:SavedDefinitions = $script:SettingDefinitions
            try {
                $script:SettingDefinitions = @(
                    @{ Section = 'settings'; Field = 'a'; Page = 'probe' }
                    @{ Section = 'settings'; Field = 'b'; Page = 'probe' }
                )
                @(Get-PageRow -Page $page | ForEach-Object { $_.Field })
            }
            finally {
                $script:SettingDefinitions = $script:SavedDefinitions
            }
        }

        $rows | Should -Be @('b', 'a')
    }
}

Describe 'Setting catalog: rows' {

    It 'keeps the hint of a manual row true for every value of the row' {
        # The checklist prints the hint before the value the config expects: a hint that names one choice contradicts
        # the others. An enum names its choice through Options after the value; a boolean hint says what true means.
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'manual' -and $_.Hint })) {
                $path = Get-SettingPath -Definition $definition
                if ($definition.Type -eq 'boolean' -and $definition.Hint -notmatch '\btrue is\b') { "${path}: says not what true means" }
                # ['Values']: .Values of a hashtable is its own values.
                foreach ($value in @($definition['Values'] | Where-Object { $_ })) {
                    if ($definition.Hint -match "\b$([regex]::Escape($value))\b") { "${path}: names $value" }
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'leaves no page pending' {
        $pending = InModuleScope GitHubOrg { @($script:SettingPages | Where-Object { $_.Status -eq 'pending' } | ForEach-Object { $_.Path }) }

        $pending | Should -BeNullOrEmpty
    }

    It 'names a known area on every page with an Area' {
        $bad = InModuleScope GitHubOrg {
            @($script:SettingPages | Where-Object { $_.Area -and $_.Area -notin $script:SettingAreas } | ForEach-Object { "$($_.Path): $($_.Area)" })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'reads every check row' {
        $bad = InModuleScope GitHubOrg {
            @($script:SettingDefinitions | Where-Object { $_.Mode -eq 'check' } |
                    Where-Object { -not (Get-SettingRead -Definition $_) } | ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'never reads a manual row' {
        InModuleScope GitHubOrg {
            $row = @{ Section = 'settings'; Field = 'x_manual'; Type = 'boolean'; Mode = 'manual'; Page = 'security' }

            Get-SettingRead -Definition $row | Should -BeNullOrEmpty
            Get-SettingWrite -Definition $row | Should -BeNullOrEmpty
        }
    }

    It 'never makes a row with a read manual' {
        $bad = InModuleScope GitHubOrg {
            @($script:SettingDefinitions | Where-Object { $_.ContainsKey('Read') -and $_.Mode -notin 'apply', 'check' } | ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'reads every row of an endpoint section from that endpoint, so none is manual' {
        # An endpoint section is one request and one plan action; a manual row goes into the section of its page or
        # subject instead.
        $bad = InModuleScope GitHubOrg {
            @($script:SettingDefinitions | Where-Object { $script:Sections.Contains($_.Section) } | Where-Object {
                    $read = Get-SettingRead -Definition $_
                    -not $read -or $read.Endpoint -ne ('/orgs/{org}' + $script:Sections[$_.Section].Path)
                } | ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'defaults the read of an apply row to its section endpoint and field' {
        InModuleScope GitHubOrg {
            $row = $script:SettingDefinitions | Where-Object { $_.Section -eq 'actions.workflow' -and $_.Field -eq 'default_workflow_permissions' }

            $read = Get-SettingRead -Definition $row
            $write = Get-SettingWrite -Definition $row

            $read.Endpoint | Should -Be '/orgs/{org}/actions/permissions/workflow'
            $read.Field | Should -Be 'default_workflow_permissions'
            $write.Method | Should -Be 'PUT'
            $write.Endpoint | Should -Be '/orgs/{org}/actions/permissions/workflow'
            Get-SettingPath -Definition $row | Should -Be 'actions.workflow.default_workflow_permissions'
        }
    }

    It 'gives the settings of the workflow permissions their group on the Actions page' {
        InModuleScope GitHubOrg {
            $rows = @($script:SettingDefinitions | Where-Object { $_.Section -eq 'actions.workflow' })

            $rows.Count | Should -Be 2
            $rows | ForEach-Object { $_.UiGroup | Should -Be 'Workflow permissions' }
        }
    }

    It 'finds a page by path, and none for an unknown path' {
        InModuleScope GitHubOrg {
            (Get-SettingPage -Path 'member_privileges').Status | Should -Be 'managed'
            Get-SettingPage -Path 'no/such/page' | Should -BeNullOrEmpty
        }
    }
}

Describe 'API catalog' {
    BeforeAll {
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg.Common Write-Progress { }

        $script:catalog = InModuleScope GitHubOrg { $script:ApiCatalog }

        function ConvertTo-TestCatalogPath {
            # The catalog path of a call: 'orgs/contoso/members?role=admin&per_page=100' -> '/orgs/{org}/members'. A
            # '{name}' segment takes one segment ('{path}' the rest); of the matching paths the one with the most
            # literal segments wins. $null when none matches.
            param(
                [Parameter(Mandatory)][string]$Endpoint,
                [Parameter(Mandatory)][string[]]$Path
            )

            $segments = @($Endpoint.Split('?')[0].Trim('/').Split('/'))
            $best = $null
            $bestLiterals = -1
            foreach ($candidate in $Path) {
                $parts = @($candidate.Trim('/').Split('/'))
                $literals = 0
                $matched = $true
                for ($i = 0; $i -lt $parts.Count; $i++) {
                    if ($parts[$i] -eq '{path}' -and $i -eq $parts.Count - 1) {
                        $matched = $segments.Count -gt $i
                        $i = $parts.Count
                        break
                    }
                    if ($i -ge $segments.Count) {
                        $matched = $false
                        break
                    }
                    if ($parts[$i] -match '^\{[^}]+\}$') {
                        continue
                    }
                    if ($parts[$i] -cne $segments[$i]) {
                        $matched = $false
                        break
                    }
                    $literals++
                }
                if ($matched -and ($parts[-1] -eq '{path}' -or $parts.Count -eq $segments.Count) -and $literals -gt $bestLiterals) {
                    $best = $candidate
                    $bestLiterals = $literals
                }
            }
            return $best
        }

        function Get-TestNameSet {
            # A case-sensitive set of names: field names and '<METHOD> <path>' keys.
            param([AllowNull()][object]$Value)
            return , [System.Collections.Generic.HashSet[string]]::new([string[]]@($Value | Where-Object { $null -ne $_ }), [StringComparer]::Ordinal)
        }

        function Get-TestCatalogCall {
            # The gh calls recorded so far, each with its method, catalog path and parsed body.
            param([Parameter(Mandatory)][string[]]$Path)

            foreach ($call in @(Get-TestGhCall)) {
                $body = $null
                if ($call.Input) {
                    $body = $call.Input | ConvertFrom-Json -AsHashtable
                }
                [pscustomobject]@{ Method = $call.Arguments[2]; Endpoint = $call.Arguments[3]; Path = ConvertTo-TestCatalogPath -Endpoint $call.Arguments[3] -Path $Path; Body = $body }
            }
        }

        function Invoke-TestRoundTrip {
            # Reads the fake, plans, applies and plans again, as a run and a second run do; returns the first plan.
            param([Parameter(Mandatory)][object]$Config)

            $plan = @(Get-GitHubOrgPlan -Config $Config -CurrentState (Get-GitHubOrgState -Config $Config))
            Invoke-GitHubOrgPlan -Plan $plan
            @(Get-GitHubOrgPlan -Config $Config -CurrentState (Get-GitHubOrgState -Config $Config)) | Should -BeNullOrEmpty
            $plan
        }

        $paths = [string[]]@($script:catalog.Paths.Keys)
        $calls = [System.Collections.Generic.List[object]]::new()

        # The context check and a run on an organization that matches.
        $resource = Get-MatchingTestGitHubOrgResource
        $resource['user/memberships/orgs/contoso'] = @{ state = 'active'; role = 'admin'; user = @{ login = 'octocat' } }
        Register-TestGitHubOrgFake -Resource $resource
        Assert-GitHubOrgContext -Organization 'contoso'
        Invoke-TestRoundTrip -Config (Get-TestGitHubOrgConfig) | Out-Null
        $calls.AddRange(@(Get-TestCatalogCall -Path $paths))
        Unregister-TestGhFake

        # The first run: everything is created.
        Register-TestGitHubOrgFake -Resource (Get-PermissiveTestGitHubOrgResource)
        Invoke-TestRoundTrip -Config (Get-TestGitHubOrgConfig) | Out-Null
        $calls.AddRange(@(Get-TestCatalogCall -Path $paths))
        Unregister-TestGhFake

        # The updates: one organization setting, the ruleset, a budget and the code security configuration differ,
        # and a team of the config has a member without a Copilot seat.
        $config = Get-TestGitHubOrgConfig
        $config.copilotSeats.selected_teams = @('reviewers')
        $resource = Get-MatchingTestGitHubOrgResource
        $resource['orgs/contoso'].members_can_create_pages = $true
        $resource['orgs/contoso/rulesets/7'].enforcement = 'disabled'
        $resource['organizations/contoso/settings/billing/budgets'].budgets[0].budget_amount = 5
        $resource['orgs/contoso/code-security/configurations'][1] = Get-TestCodeSecurityConfiguration -Id 42 -State 'disabled'
        $resource['orgs/contoso/teams/reviewers/members'] = @(@{ login = 'hubot' })
        Register-TestGitHubOrgFake -Resource $resource
        $script:updatePlan = Invoke-TestRoundTrip -Config $config
        $calls.AddRange(@(Get-TestCatalogCall -Path $paths))
        Unregister-TestGhFake

        $script:calls = $calls.ToArray()
    }

    It 'gives the Read and Write of every row the catalog status of its call<Case>' -ForEach @(
        @{ Case = '' }
        @{ Case = ', a named Read included'; Row = @{ Section = 'testCheck'; Field = 'level'; Type = 'string'; Mode = 'check'; Page = 'security'; UiGroup = 'Level'; Read = @{ Endpoint = '/orgs/{org}/copilot/billing'; Field = 'cli' }; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/codespaces/access' } } }
    ) {
        # A Read is a GET the engine calls; the Write of an apply row is a call of Apply; the Write of a manual row is a
        # call the engine never makes. A check row the engine does not apply yet may share a write of apply rows (the
        # PATCH of the organization), so its Write only has to be a listed operation.
        $bad = InModuleScope GitHubOrg -Parameters @{ Row = $Row } {
            $rows = @($script:SettingDefinitions)
            if ($Row) {
                $rows += $Row
            }
            foreach ($definition in $rows) {
                $read = Get-SettingRead -Definition $definition
                if ($read -and $script:ApiCatalog.Paths[$read.Endpoint].GET.Status -cne 'read') {
                    "$(Get-SettingPath -Definition $definition): GET $($read.Endpoint) is not read"
                }
                $write = Get-SettingWrite -Definition $definition
                $expected = switch ($definition.Mode) { 'apply' { 'write' } 'manual' { 'unused' } default { $null } }
                $status = if ($write) { $script:ApiCatalog.Paths[$write.Endpoint][$write.Method].Status }
                if ($write -and ($null -eq $status -or ($expected -and $status -cne $expected))) {
                    "$(Get-SettingPath -Definition $definition): $($write.Method) $($write.Endpoint) is not $expected"
                }
            }
        }
        # Not vacuous: rows of the catalog name a Read and a Write of their own, of check and manual rows alike.
        $named = InModuleScope GitHubOrg {
            @{
                Read        = @($script:SettingDefinitions | Where-Object { $_.ContainsKey('Read') }).Count
                Write       = @($script:SettingDefinitions | Where-Object { $_.ContainsKey('Write') -and $_.Mode -eq 'check' }).Count
                ManualWrite = @($script:SettingDefinitions | Where-Object { $_.ContainsKey('Write') -and $_.Mode -eq 'manual' }).Count
            }
        }

        $bad | Should -BeNullOrEmpty
        $named.Read | Should -BeGreaterThan 0
        $named.Write | Should -BeGreaterThan 0
        $named.ManualWrite | Should -BeGreaterThan 0
    }

    It 'checks every setting field of the organization answer' {
        $pending = @($script:catalog.Paths['/orgs/{org}'].GET.Fields.GetEnumerator() | Where-Object { $_.Value -like '*pending*' } | ForEach-Object { $_.Key })

        $pending | Should -BeNullOrEmpty
    }

    It 'tracks the response fields of every GET a row reads' {
        # Without Fields the run never warns about a field of its answer that nobody looked at (spec 3.1).
        $bad = InModuleScope GitHubOrg {
            foreach ($endpoint in @((Get-GitHubOrgReadField).Keys)) {
                if (-not $script:ApiCatalog.Paths[$endpoint].GET.ContainsKey('Fields')) {
                    $endpoint
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'is reviewed against the pinned API version' {
        $pinned = & (Get-Module GitHubOrg.Common) { $script:GitHubApiVersion }

        $script:catalog.ApiVersion | Should -Be $pinned
        $script:catalog.ReviewedOn | Should -Match '^\d{4}-\d{2}-\d{2}$'
    }

    It 'maps a call with a query string to its catalog path' {
        $paths = [string[]]@($script:catalog.Paths.Keys)

        ConvertTo-TestCatalogPath -Endpoint 'orgs/contoso/members?role=admin&per_page=100' -Path $paths | Should -Be '/orgs/{org}/members'
        ConvertTo-TestCatalogPath -Endpoint 'orgs/contoso' -Path $paths | Should -Be '/orgs/{org}'
        ConvertTo-TestCatalogPath -Endpoint 'orgs/contoso/code-security/configurations/defaults' -Path $paths | Should -Be '/orgs/{org}/code-security/configurations/defaults'
        ConvertTo-TestCatalogPath -Endpoint 'orgs/contoso/code-security/configurations/42' -Path $paths | Should -Be '/orgs/{org}/code-security/configurations/{configuration_id}'
        ConvertTo-TestCatalogPath -Endpoint 'repos/contoso/.github/contents/.github/workflows/org-checks.yml?ref=0123' -Path $paths | Should -Be '/repos/{owner}/{repo}/contents/{path}'
        ConvertTo-TestCatalogPath -Endpoint 'orgs/contoso/no/such/endpoint' -Path $paths | Should -BeNullOrEmpty
    }

    It 'lists every call of the engine with its status' {
        $script:calls.Count | Should -BeGreaterThan 0
        $bad = foreach ($call in $script:calls) {
            $expected = if ($call.Method -eq 'GET') { 'read' } else { 'write' }
            $operation = if ($call.Path) { $script:catalog.Paths[$call.Path][$call.Method] }
            if ($null -eq $operation -or $operation.Status -ne $expected) {
                "$($call.Method) $($call.Endpoint) ($($call.Path)) is not $expected"
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'calls every read and write operation it lists' {
        $called = Get-TestNameSet -Value @($script:calls | ForEach-Object { "$($_.Method) $($_.Path)" })
        $script:updatePlan.Action | Should -Contain 'UpdateRuleset'
        $script:updatePlan.Action | Should -Contain 'UpdateBudget'
        $script:updatePlan.Action | Should -Contain 'UpdateCodeSecurityConfiguration'

        $bad = foreach ($path in $script:catalog.Paths.Keys) {
            foreach ($method in @($script:catalog.Paths[$path].Keys | Where-Object { $_ -ne 'Category' })) {
                if ($script:catalog.Paths[$path][$method].Status -in 'read', 'write' -and -not $called.Contains("$method $path")) {
                    "$method $path"
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'lists a field once: a row reads it or Fields names it' {
        $bad = InModuleScope GitHubOrg {
            foreach ($definition in $script:SettingDefinitions) {
                $read = Get-SettingRead -Definition $definition
                if ($read -and $read.Field -in @(Get-UnmanagedField -Endpoint $read.Endpoint)) {
                    "$($read.Endpoint) $($read.Field)"
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'gives every unused operation a reason' {
        $bad = foreach ($path in $script:catalog.Paths.Keys) {
            $entry = $script:catalog.Paths[$path]
            if (-not $entry.Category) {
                "$path has no category"
            }
            foreach ($method in @($entry.Keys | Where-Object { $_ -ne 'Category' })) {
                $operation = $entry[$method]
                if ($method -notin 'GET', 'PUT', 'POST', 'PATCH', 'DELETE' -or $operation.Status -notin 'read', 'write', 'unused') {
                    "$method $path has the status '$($operation.Status)'"
                }
                elseif ($operation.Status -eq 'unused' -and -not $operation.Reason) {
                    "$method $path is unused without a reason"
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'sends exactly the Body of a PUT section' {
        $sections = InModuleScope GitHubOrg {
            foreach ($key in $script:Sections.Keys) {
                $section = $script:Sections[$key]
                if ($section.Method -eq 'PUT') {
                    $rows = @(Get-SettingDefinition -Section $key)
                    [pscustomobject]@{
                        Path   = '/orgs/{org}' + $section.Path
                        Apply  = [string[]]@($rows | Where-Object { $_.Mode -eq 'apply' } | ForEach-Object { $_.Field })
                        Others = [string[]]@($rows | Where-Object { $_.Mode -ne 'apply' } | ForEach-Object { Get-SettingPath -Definition $_ })
                    }
                }
            }
        }

        $sections.Count | Should -BeGreaterThan 0
        foreach ($section in $sections) {
            $body = [string[]]$script:catalog.Paths[$section.Path].PUT.Body
            (Get-TestNameSet -Value $body).SetEquals($section.Apply) | Should -BeTrue -Because "PUT $($section.Path) has the body fields $($body -join ', ')"
            $section.Others | Should -BeNullOrEmpty -Because "PUT $($section.Path) replaces the section"
            $puts = @($script:calls | Where-Object { $_.Method -eq 'PUT' -and $_.Path -eq $section.Path })
            $puts.Count | Should -BeGreaterThan 0 -Because "the round trip sets $($section.Path)"
            foreach ($put in $puts) {
                (Get-TestNameSet -Value $body).SetEquals([string[]]@($put.Body.Keys)) | Should -BeTrue -Because "PUT $($put.Endpoint) sends $(@($put.Body.Keys) -join ', ')"
            }
        }
    }

    It 'allows every apply field of a PATCH section in its Body' {
        $sections = InModuleScope GitHubOrg {
            foreach ($key in $script:Sections.Keys) {
                $section = $script:Sections[$key]
                if ($section.Method -eq 'PATCH') {
                    [pscustomobject]@{ Path = '/orgs/{org}' + $section.Path; Apply = [string[]]@(Get-SettingDefinition -Section $key | Where-Object { $_.Mode -eq 'apply' } | ForEach-Object { $_.Field }) }
                }
            }
        }

        @($sections).Path | Should -Be '/orgs/{org}'
        foreach ($section in $sections) {
            $body = [string[]]$script:catalog.Paths[$section.Path].PATCH.Body
            $section.Apply | Where-Object { $_ -notin $body } | Should -BeNullOrEmpty
        }
    }

    It 'sends only Body fields with a PATCH, never all of them' {
        # And with a PUT that is not a section (the ruleset, the code security default): spec 5.5 covers sections only.
        $sectionPaths = InModuleScope GitHubOrg { @($script:Sections.Values | ForEach-Object { '/orgs/{org}' + $_.Path }) }
        $writes = @($script:calls | Where-Object { $_.Method -eq 'PATCH' -or ($_.Method -eq 'PUT' -and $_.Path -notin $sectionPaths) })

        @($writes.Path | Select-Object -Unique) | Should -Contain '/orgs/{org}'
        @($writes.Path | Select-Object -Unique) | Should -Contain '/orgs/{org}/rulesets/{ruleset_id}'
        foreach ($write in $writes) {
            $body = [string[]]$script:catalog.Paths[$write.Path][$write.Method].Body
            @($write.Body.Keys | Where-Object { $_ -notin $body }) | Should -BeNullOrEmpty -Because "$($write.Method) $($write.Endpoint) sends only fields of its Body"
        }
        $settings = Get-PlanAction -Plan $script:updatePlan -Action 'UpdateOrganizationSettings'
        @($settings.Body.Keys) | Should -Be @('members_can_create_pages')
        @($settings.Body.Keys).Count | Should -BeLessThan @($script:catalog.Paths['/orgs/{org}'].PATCH.Body).Count
    }

    It 'tracks response fields only on GETs it reads' {
        $sectionPaths = InModuleScope GitHubOrg { @($script:Sections.Values | ForEach-Object { '/orgs/{org}' + $_.Path }) }

        $bad = foreach ($path in $script:catalog.Paths.Keys) {
            foreach ($method in @($script:catalog.Paths[$path].Keys | Where-Object { $_ -ne 'Category' })) {
                $operation = $script:catalog.Paths[$path][$method]
                $tracked = $operation.ContainsKey('Fields')
                if ($tracked -and ($method -ne 'GET' -or $operation.Status -ne 'read')) {
                    "$method $path has Fields"
                }
                # The section endpoints track their fields; other reads may (the endpoints rows read, the Copilot billing).
                if ($method -eq 'GET' -and $path -in $sectionPaths -and -not $tracked) {
                    "GET $path tracks fields: $tracked"
                }
                if ($operation.ContainsKey('Body') -and ($operation.Status -ne 'write' -or $method -notin 'PUT', 'PATCH')) {
                    "$method $path has a Body"
                }
            }
        }

        $bad | Should -BeNullOrEmpty
    }
}

Describe 'Get-UnmanagedField' {
    It 'lists the response fields no row reads, and none for a GET without Fields' {
        InModuleScope GitHubOrg {
            Get-UnmanagedField -Endpoint '/orgs/{org}' | Should -Contain 'login'
            Get-UnmanagedField -Endpoint '/orgs/{org}' | Should -Not -Contain 'default_repository_permission'
            @(Get-UnmanagedField -Endpoint '/orgs/{org}/code-security/configurations').Count | Should -Be 0
            @(Get-UnmanagedField -Endpoint '/no/such/path').Count | Should -Be 0
        }
    }
}

Describe 'Get-UnknownResponseField: nested reads' {
    It 'knows the top-level field of a nested read' {
        $unknown = InModuleScope GitHubOrg {
            $saved = $script:SettingDefinitions
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(@{ Section = 'testCheck'; Field = 'effort'; Type = 'string'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}'; Field = 'default_x.configured' }; Page = 'security'; UiGroup = 'Effort' })
            try {
                Get-UnknownResponseField -State ([pscustomobject]@{ ResponseFields = [ordered]@{ '/orgs/{org}' = [string[]]@('login', 'default_x', 'other_y') } })
            }
            finally {
                $script:SettingDefinitions = $saved
            }
        }

        $unknown['/orgs/{org}'] | Should -Be @('other_y')
    }
}

Describe 'Get-GitHubOrgReadField' {
    It 'lists the fields the rows read, by endpoint, and never a field Fields names' {
        $read = Get-GitHubOrgReadField

        $read['/orgs/{org}'] | Should -Contain 'default_repository_permission'
        $read['/orgs/{org}'] | Should -Not -Contain 'login'
        $read['/orgs/{org}/actions/permissions'] | Should -Contain 'enabled_repositories'
        $read.Contains('/no/such/path') | Should -BeFalse
    }
}

Describe 'ConvertTo-FieldMap' {
    BeforeEach {
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
    }

    AfterEach {
        Unregister-TestGhFake
        InModuleScope GitHubOrg { $script:SettingDefinitions = @($script:SettingDefinitions | Where-Object { $_.Field -notin 'x_manual', 'x_config_name' }) }
    }

    It 'maps only the rows that read the endpoint, never a manual row' {
        Register-TestGitHubOrgFake -Resource (Get-PermissiveTestGitHubOrgResource)
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(@{ Section = 'settings'; Field = 'x_manual'; Type = 'boolean'; Mode = 'manual'; Page = 'security' })
        }

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Settings.Contains('x_manual') | Should -BeFalse
        $state.Settings.Contains('default_repository_permission') | Should -BeTrue
    }

    It 'reads a row by its Read.Field and keeps the config field as the key' {
        $resource = Get-PermissiveTestGitHubOrgResource
        $resource['orgs/contoso']['x_api_name'] = 'from-api'
        Register-TestGitHubOrgFake -Resource $resource
        InModuleScope GitHubOrg {
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(@{ Section = 'settings'; Field = 'x_config_name'; Type = 'string'; Mode = 'check'; Page = 'security'; Read = @{ Endpoint = '/orgs/{org}'; Field = 'x_api_name' } })
        }

        $state = Get-GitHubOrgState -Config (Get-TestGitHubOrgConfig)

        $state.Settings['x_config_name'] | Should -Be 'from-api'
        $state.Settings.Contains('x_api_name') | Should -BeFalse
    }
}

Describe 'Get-GitHubOrgSettingReference' {
    BeforeAll {
        $script:reference = Get-GitHubOrgSettingReference
    }

    It 'is generated from the catalog (run tools/Build-SettingReference.ps1 after changing it)' {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../settings.md'
        $committed = [System.IO.File]::ReadAllText($path)

        $committed | Should -BeExactly $script:reference
        $script:reference | Should -Not -Match "`r"
    }

    It 'keeps UI and API coverage in separate parts' {
        $text = $script:reference
        $ui = $text.IndexOf("`n## UI coverage`n")
        $api = $text.IndexOf("`n## API coverage`n")

        $ui | Should -BeGreaterThan 0
        $api | Should -BeGreaterThan $ui
        $text.IndexOf("`n### Fields without a page`n") | Should -BeLessThan $api
        # no total or percentage across the parts: no heading, row or line that starts with a total (a reason may say "total")
        $text | Should -Not -Match '\d+\s*%'
        $text | Should -Not -Match '(?im)^[|#*\s]*total\b'
        # a row appears in the UI part under its page and in the API part as a field of its endpoint
        $text.Substring($ui, $api - $ui).Contains(([char]96 + 'settings.two_factor_requirement_enabled' + [char]96)) | Should -BeTrue
        $text.Substring($api) | Should -BeLike '*two_factor_requirement_enabled (row: settings.two_factor_requirement_enabled)*'
    }

    It 'names a row with a group and no label or hint by its group, never by its field: <Field>' -ForEach @(
        @{ Field = 'default_workflow_permissions' }
    ) {
        $path = [char]96 + "actions.workflow.$Field" + [char]96
        $line = @($script:reference -split "`n" | Where-Object { $_.Contains($path) })[0]

        $line.StartsWith("| Workflow permissions | $path | ") | Should -BeTrue -Because $line
    }

    It 'keeps the hint after the label of a row with both' {
        $path = [char]96 + 'copilot.policies.bill_reviews_to_organization' + [char]96
        $line = @($script:reference -split "`n" | Where-Object { $_.Contains($path) })[0]

        $line | Should -BeLike '| Copilot code review > Choose how members with a Copilot license are billed (under "Choose how members with a Copilot license are billed", true is "Organization") | *'
    }

    It 'escapes the angle brackets of a UI label, which Markdown would read as HTML' {
        $path = [char]96 + 'settings.two_factor_requirement_enabled' + [char]96
        $line = @($script:reference -split "`n" | Where-Object { $_.Contains($path) })[0]

        $line | Should -BeLike '*everyone in the \<organization> organization.*'
    }

    It 'links a field without a page to its category' {
        $reference = InModuleScope GitHubOrg {
            $saved = $script:SettingDefinitions
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(@{ Section = 'settings'; Field = 'x_no_ui'; Type = 'boolean'; Mode = 'check'; NoUi = $true; Page = $null })
            try {
                Get-GitHubOrgSettingReference
            }
            finally {
                $script:SettingDefinitions = $saved
            }
        }
        $line = @($reference -split "`n" | Where-Object { $_.StartsWith('| `settings.x_no_ui`') })[0]

        $line.EndsWith('| `GET orgs/{org} .x_no_ui` | - | [orgs](#orgs) |') | Should -BeTrue -Because $line
    }

    It 'builds a category anchor as GitHub does: <Text>' -ForEach @(
        @{ Text = 'orgs'; Anchor = 'orgs' }
        @{ Text = 'code-security'; Anchor = 'code-security' }
        @{ Text = 'Private Registries'; Anchor = 'private-registries' }
        @{ Text = 'a.b/c_d'; Anchor = 'abc_d' }
    ) {
        InModuleScope GitHubOrg -Parameters @{ Text = $Text } { ConvertTo-ReferenceAnchor -Text $Text } | Should -BeExactly $Anchor
    }

    It 'ends the reason of an unmanaged page with one full stop: <Reason>' -ForEach @(
        @{ Reason = 'usage reports, not settings' }
        @{ Reason = 'usage reports, not settings.' }
    ) {
        $reference = InModuleScope GitHubOrg -Parameters @{ Reason = $Reason } {
            $saved = $script:SettingPages
            $script:SettingPages = @($script:SettingPages) + @(@{ Path = 'probe-page'; Label = 'Probe page'; Status = 'unmanaged'; Reason = $Reason })
            try {
                Get-GitHubOrgSettingReference
            }
            finally {
                $script:SettingPages = $saved
            }
        }
        $section = ($reference -split '(?m)^### ') | Where-Object { $_ -like 'Probe page *' }

        $section | Should -Match '(?m)^Not managed: usage reports, not settings\.$'
    }

    It 'says a pending page is not covered yet' {
        # No page of the menu is pending now; a page the review finds is (spec 6).
        $reference = InModuleScope GitHubOrg {
            $saved = $script:SettingPages
            $script:SettingPages = @($script:SettingPages) + @(@{ Path = 'probe-page'; Label = 'Probe page'; Status = 'pending' })
            try {
                Get-GitHubOrgSettingReference
            }
            finally {
                $script:SettingPages = $saved
            }
        }
        $section = ($reference -split '(?m)^### ') | Where-Object { $_ -like 'Probe page *' }

        $section | Should -BeLike '*not covered yet*'
    }
}
