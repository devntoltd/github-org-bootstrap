BeforeAll {
    $script:root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    $script:checkScript = Join-Path -Path $script:root -ChildPath 'tools/Invoke-ApiEndpointCheck.ps1'
    # CI sets it for the whole job, and Invoke-Coverage.ps1 writes to it after the tests: restored after every test.
    $script:savedSummary = $env:GITHUB_STEP_SUMMARY
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhMock.ps1')

    # A field of GET /orgs/{org} that a row of the engine reads, so it is in neither Fields nor a difference: the rows
    # of the fake engine module the -Report tests import instead of the real one.
    $script:rowField = 'test_row_field'

    # The catalog of the tests: a read GET with Fields and a write PATCH with Body, a list endpoint, an operation
    # outside /orgs/{org} and fillers, so one removed operation stays above the 90% of the sanity check.
    function Get-TestCatalog {
        param([int]$Filler = 20)

        $paths = [ordered]@{
            '/orgs/{org}'           = [ordered]@{
                Category = 'orgs'
                GET      = [ordered]@{ Status = 'read'; Fields = [ordered]@{ login = 'profile data, not managed' } }
                PATCH    = [ordered]@{ Status = 'write'; Body = @('name', 'company') }
            }
            '/orgs/{org}/hooks'     = [ordered]@{
                Category = 'orgs'
                GET      = [ordered]@{ Status = 'read' }
                POST     = [ordered]@{ Status = 'unused'; Reason = 'webhooks are only read' }
            }
            '/repos/{owner}/{repo}' = [ordered]@{
                Category = 'repos'
                GET      = [ordered]@{ Status = 'read' }
            }
        }
        for ($i = 1; $i -le $Filler; $i++) {
            $paths["/orgs/{org}/filler/$i"] = [ordered]@{ Category = 'filler'; GET = [ordered]@{ Status = 'unused'; Reason = 'test filler' } }
        }
        [ordered]@{ ApiVersion = '2026-03-10'; ReviewedOn = '2026-11-08'; Paths = $paths }
    }

    # PowerShell data text of a catalog: strings, string arrays and nested hashtables.
    function ConvertTo-TestPsd1 {
        param([object]$Value)

        if ($Value -is [System.Collections.IDictionary]) {
            $entries = foreach ($key in $Value.Keys) { "'$key' = $(ConvertTo-TestPsd1 -Value $Value[$key])" }
            return "@{`n$($entries -join "`n")`n}"
        }
        if ($Value -is [array]) {
            return '@(' + (@($Value | ForEach-Object { "'$_'" }) -join ', ') + ')'
        }
        return "'$Value'"
    }

    # An operation of the description: summary, category and documentation link, as the OpenAPI description has them.
    function Get-TestOperation {
        param([string]$Summary, [string]$Category)

        [ordered]@{
            summary      = $Summary
            externalDocs = [ordered]@{ url = "https://docs.example.test/$Category" }
            'x-github'   = [ordered]@{ category = $Category }
        }
    }

    # The description that matches Get-TestCatalog: GET /orgs/{org} answers login and a row field through a $ref and
    # allOf, PATCH /orgs/{org} takes name and company the same way.
    function Get-TestDescription {
        param([int]$Filler = 20)

        $get = Get-TestOperation -Summary 'Get an organization' -Category 'orgs'
        $get.responses = [ordered]@{ '200' = [ordered]@{ content = [ordered]@{ 'application/json' = [ordered]@{ schema = [ordered]@{ '$ref' = '#/components/schemas/organization-full' } } } } }
        $patch = Get-TestOperation -Summary 'Update an organization' -Category 'orgs'
        $patch.requestBody = [ordered]@{ content = [ordered]@{ 'application/json' = [ordered]@{ schema = [ordered]@{
                        allOf = @(
                            [ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }
                            [ordered]@{ '$ref' = '#/components/schemas/company-body' }
                        )
                    }
                }
            }
        }
        $paths = [ordered]@{
            '/orgs/{org}'           = [ordered]@{ get = $get; patch = $patch; parameters = @() }
            '/orgs/{org}/hooks'     = [ordered]@{ get = (Get-TestOperation -Summary 'List webhooks' -Category 'orgs'); post = (Get-TestOperation -Summary 'Create a webhook' -Category 'orgs') }
            '/repos/{owner}/{repo}' = [ordered]@{ get = (Get-TestOperation -Summary 'Get a repository' -Category 'repos') }
        }
        for ($i = 1; $i -le $Filler; $i++) {
            $paths["/orgs/{org}/filler/$i"] = [ordered]@{ get = (Get-TestOperation -Summary "Filler $i" -Category 'filler') }
        }
        [ordered]@{
            openapi    = '3.0.3'
            paths      = $paths
            components = [ordered]@{
                schemas = [ordered]@{
                    'organization-full' = [ordered]@{
                        allOf = @(
                            [ordered]@{ properties = [ordered]@{ login = [ordered]@{ type = 'string' } } }
                            [ordered]@{ properties = [ordered]@{ $script:rowField = [ordered]@{ type = 'string' } } }
                        )
                    }
                    'company-body'      = [ordered]@{ properties = [ordered]@{ company = [ordered]@{ type = 'string' } } }
                }
            }
        }
    }

    # An issue as 'gh issue list --json number,state,body' returns it, opened by the check for one difference of an
    # operation, or by hand for the operation without -Difference.
    function Get-TestIssue {
        param([int]$Number, [string]$Operation, [string]$State = 'OPEN', [string]$Difference)

        $marker = if ($Difference) { "`n<!-- api-endpoint-difference: $Difference -->" } else { '' }
        [ordered]@{ number = $Number; state = $State; body = "<!-- api-endpoint: $Operation -->$marker`nDecide on it." }
    }

    # Writes the catalog and runs the check with the description; extra parameters go to the script.
    function Invoke-TestCheck {
        param([hashtable]$Parameter = @{})

        Set-Content -Path $script:catalogPath -Value (ConvertTo-TestPsd1 -Value $script:catalog)
        $script:TestDescriptionText = if ($script:description -is [string]) { $script:description } else { ConvertTo-Json -InputObject $script:description -Depth 30 }
        & $script:checkScript @paths @Parameter
    }

    function Get-TestCreatedTitle {
        @(foreach ($call in (Get-GhCall 'issue create')) { Get-GhOption -Call $call -Name '--title' })
    }
}

Describe 'Invoke-ApiEndpointCheck.ps1' {
    BeforeEach {
        $folder = (New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()))).FullName
        $script:module = Join-Path -Path $folder -ChildPath 'Common.psm1'
        Set-Content -Path $script:module -Value "`$ErrorActionPreference = 'Stop'`n`$script:GitHubApiVersion = '2026-03-10'"
        $script:template = Join-Path -Path $folder -ChildPath 'api-endpoint.md'
        Set-Content -Path $script:template -Value (@(
                '---'
                'name: "API endpoint"'
                'about: Decide on an API operation.'
                'title: "Review the API endpoint"'
                'labels: [api-endpoint, enhancement]'
                'assignees: [operator]'
                '---'
                ''
                '- [ ] Decide on it.'
            ) -join "`n")
        $script:catalogPath = Join-Path -Path $folder -ChildPath 'api-endpoints.psd1'
        # The engine module of -Report: only the rows' read fields, so no test depends on a real row.
        $script:engineModule = Join-Path -Path $folder -ChildPath 'TestEndpointEngine.psm1'
        Set-Content -Path $script:engineModule -Value "function Get-GitHubOrgReadField { @{ '/orgs/{org}' = @('$script:rowField') } }`nExport-ModuleMember -Function Get-GitHubOrgReadField"
        $script:paths = @{ ModulePath = $script:module; TemplatePath = $script:template; CatalogPath = $script:catalogPath; EngineModulePath = $script:engineModule }
        $script:summary = Join-Path -Path $folder -ChildPath 'summary.md'
        $env:GITHUB_STEP_SUMMARY = $script:summary

        $script:catalog = Get-TestCatalog
        $script:description = Get-TestDescription
        $script:TestApiExit = 0
        $script:TestIssueListExit = 0
        $script:TestIssues = @()
        $script:TestLabels = @('enhancement')
        $script:TestOutput = [System.Collections.Generic.List[string]]::new()
        $script:TestGhCalls = [System.Collections.Generic.List[string[]]]::new()
        # The mock runs inside the script under test: the fixtures are found by name (dynamic scoping), so their names
        # must not clash with variables of the script.
        Mock gh {
            $TestGhCalls.Add([string[]]$args)
            $global:LASTEXITCODE = 0
            switch ($args[0..1] -join ' ') {
                'api --header' {
                    $global:LASTEXITCODE = $TestApiExit
                    if ($TestApiExit -eq 0) { $TestDescriptionText }
                }
                'issue list' {
                    $global:LASTEXITCODE = $TestIssueListExit
                    ConvertTo-Json -InputObject @($TestIssues) -Depth 5
                }
                'label list' { ConvertTo-Json -InputObject @($TestLabels | ForEach-Object { @{ name = $_ } }) }
                # Numbered from 7 in the order they are opened.
                'issue create' { "https://example.test/issues/$(6 + @($TestGhCalls | Where-Object { ($_[0..1] -join ' ') -eq 'issue create' }).Count)" }
            }
        }
        Mock Write-Host { $TestOutput.Add([string]$Object) }
    }

    AfterEach {
        $env:GITHUB_STEP_SUMMARY = $script:savedSummary
        Remove-Module -Name TestEndpointEngine -ErrorAction Ignore
    }

    It 'opens nothing when the description matches' {
        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'issue list').Count | Should -Be 0
        ($script:TestOutput -join "`n") | Should -BeLike '*no change*'
        (Get-Content -Path $script:summary -Raw) | Should -BeLike '*no change*'
    }

    It 'downloads the description of -Version with the pinned API version' {
        Invoke-TestCheck -Parameter @{ Version = '2027-06-01' }

        $download = (Get-GhCall 'api --header')[0]
        @(Get-GhOption -Call $download -Name '--header') | Should -Be @('Accept: application/vnd.github.raw', 'X-GitHub-Api-Version: 2026-03-10')
        $download[-1] | Should -Be 'repos/github/rest-api-description/contents/descriptions/api.github.com/api.github.com.2027-06-01.json'
    }

    It 'opens one issue for <Case>' -ForEach @(
        @{ Case = 'a new path'; Operation = 'GET /orgs/{org}/new-feature'; Kind = 'new operation'; Change = { $description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') } } }
        @{ Case = 'a new method of a listed path'; Operation = 'DELETE /orgs/{org}/hooks'; Kind = 'new operation'; Change = { $description.paths['/orgs/{org}/hooks'].delete = (Get-TestOperation -Summary 'Delete webhooks' -Category 'orgs') } }
        @{ Case = 'a removed operation'; Operation = 'POST /orgs/{org}/hooks'; Kind = 'removed operation'; Change = { $description.paths['/orgs/{org}/hooks'].Remove('post') } }
        @{ Case = 'a new body field of a write operation'; Operation = 'PATCH /orgs/{org}'; Kind = 'request body fields'; Change = { $description.components.schemas['company-body'].properties.new_policy = [ordered]@{ type = 'boolean' } } }
    ) {
        & $Change

        Invoke-TestCheck

        (Get-GhCall 'label create').Count | Should -Be 1
        (Get-GhCall 'label create')[0][2] | Should -Be 'api-endpoint'
        $created = Get-GhCall 'issue create'
        $created.Count | Should -Be 1
        Get-GhOption -Call $created[0] -Name '--title' | Should -Be "Review the API endpoint $Operation"
        @(Get-GhOption -Call $created[0] -Name '--label') | Should -Be @('api-endpoint', 'enhancement')
        @(Get-GhOption -Call $created[0] -Name '--assignee') | Should -Be @('operator')
        $body = Get-GhOption -Call $created[0] -Name '--body'
        $body | Should -BeLike "<!-- api-endpoint: $Operation -->`n<!-- api-endpoint-difference: $Kind*-->*"
        $body | Should -BeLike "*$Kind*"
        $body | Should -BeLike '*- `[ `] Decide on it.'
        (Get-Content -Path $script:summary -Raw) | Should -BeLike "*$Operation*$Kind*opened #7*"
    }

    It 'names the summary, category and documentation of a new operation, and every differing body field' {
        $description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
        $description.components.schemas['company-body'].properties.new_policy = [ordered]@{ type = 'boolean' }
        $description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema.allOf = @(@{ '$ref' = '#/components/schemas/company-body' })

        Invoke-TestCheck

        $bodies = @(foreach ($call in (Get-GhCall 'issue create')) { Get-GhOption -Call $call -Name '--body' })
        $new = @($bodies | Where-Object { $_ -like '*GET /orgs/{org}/new-feature*' })[0]
        $new | Should -BeLike '*Get a new feature*'
        $new | Should -BeLike '*features*'
        $new | Should -BeLike '*https://docs.example.test/features*'
        $patch = @($bodies | Where-Object { $_ -like '*PATCH /orgs/{org}*' })[0]
        $patch | Should -Match ([regex]::Escape('not in `Body`: `new_policy`.'))
        $patch | Should -Match ([regex]::Escape('no longer in the description: `name`.'))
        $patch | Should -BeLike '*Update an organization*'
        $patch | Should -Match ([regex]::Escape('(category `orgs`'))
        $patch | Should -BeLike '*https://docs.example.test/orgs*'
    }

    It 'asks a person opening an issue by hand for the marker line, not the title' {
        $text = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../.github/ISSUE_TEMPLATE/api-endpoint.md') -Raw

        $text | Should -BeLike '*<!-- api-endpoint: <METHOD> <path> -->*'
        $text | Should -Not -BeLike '*put `<METHOD> <path>` in the title*'
    }

    It 'tells that a renamed path parameter opens two issues' {
        $text = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../.github/ISSUE_TEMPLATE/api-endpoint.md') -Raw

        $text | Should -BeLike '*renamed path parameter*a removed and a new operation*'
    }

    It 'opens an issue for a body difference that no issue of the operation records, unless one is open' {
        # A year on, a new field of PATCH /orgs/{org}: the closed issue recorded the decision on another difference.
        $description.components.schemas['company-body'].properties.new_policy = [ordered]@{ type = 'boolean' }
        $script:TestIssues = @(Get-TestIssue -Number 5 -Operation 'PATCH /orgs/{org}' -State 'CLOSED' -Difference 'request body fields: +old_policy')

        Invoke-TestCheck

        $created = Get-GhCall 'issue create'
        $created.Count | Should -Be 1
        Get-GhOption -Call $created[0] -Name '--body' | Should -BeLike '*<!-- api-endpoint-difference: request body fields: +new_policy -->*'

        $script:TestGhCalls.Clear()
        $script:TestIssues = @(Get-TestIssue -Number 5 -Operation 'PATCH /orgs/{org}' -Difference 'request body fields: +old_policy')

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -BeLike '*PATCH /orgs/{org}*open #5*'
    }

    It 'counts an issue opened by hand from the real template as covering the operation' {
        # The template explains the difference line in its text; only a line of its own is a marker.
        . (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubIssue.ps1')
        $template = Read-IssueTemplate -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../.github/ISSUE_TEMPLATE/api-endpoint.md')
        $description.components.schemas['company-body'].properties.new_policy = [ordered]@{ type = 'boolean' }
        $script:TestIssues = @([ordered]@{ number = 5; state = 'CLOSED'; body = "<!-- api-endpoint: PATCH /orgs/{org} -->`n$($template.Body)" })

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -BeLike '*PATCH /orgs/{org}*closed #5*'
    }

    It 'names the differing body fields in a marker that does not depend on the order of Body' {
        $script:catalog.Paths['/orgs/{org}'].PATCH.Body = @('name', 'company', 'zeta', 'alpha')
        $script:TestIssues = @(Get-TestIssue -Number 5 -Operation 'PATCH /orgs/{org}' -State 'CLOSED' -Difference 'request body fields: -alpha -zeta')

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
    }

    It 'visits a schema shared by many variants once' {
        # Each schema refers to the next one twice: without a cache, 2^24 visits.
        for ($i = 0; $i -lt 24; $i++) {
            $next = [ordered]@{ '$ref' = "#/components/schemas/chain-$($i + 1)" }
            $description.components.schemas["chain-$i"] = [ordered]@{ anyOf = @($next, $next) }
        }
        $description.components.schemas['chain-24'] = [ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }
        $description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ '$ref' = '#/components/schemas/chain-0' }

        $elapsed = Measure-Command { Invoke-TestCheck }

        $elapsed.TotalSeconds | Should -BeLessThan 30
        ($script:TestOutput -join "`n") | Should -BeLike '*PATCH /orgs/{org}, request body not comparable*'
    }

    It 'lists the fields of a schema shared by many allOf parts once' {
        # Each schema is an allOf of the next twice: comparable, and without a visited set 2^24 visits.
        for ($i = 0; $i -lt 24; $i++) {
            $next = [ordered]@{ '$ref' = "#/components/schemas/diamond-$($i + 1)" }
            $description.components.schemas["diamond-$i"] = [ordered]@{ allOf = @($next, $next) }
        }
        $description.components.schemas['diamond-24'] = [ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' }; company = [ordered]@{ type = 'string' } } }
        $description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ '$ref' = '#/components/schemas/diamond-0' }

        $elapsed = Measure-Command { Invoke-TestCheck }

        $elapsed.TotalSeconds | Should -BeLessThan 30
        ($script:TestOutput -join "`n") | Should -BeLike '*no change*'
    }

    It 'reports both bodies of an allOf cycle as not comparable, whichever is visited first' {
        # cycle-a = allOf(cycle-b, oneOf), cycle-b = allOf(cycle-a); PATCH /orgs/{org} is visited before PUT .../zz.
        $description.components.schemas['cycle-a'] = [ordered]@{ allOf = @([ordered]@{ '$ref' = '#/components/schemas/cycle-b' }, [ordered]@{ oneOf = @([ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }) }) }
        $description.components.schemas['cycle-b'] = [ordered]@{ allOf = @([ordered]@{ '$ref' = '#/components/schemas/cycle-a' }) }
        $description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ '$ref' = '#/components/schemas/cycle-a' }
        $put = Get-TestOperation -Summary 'Set zz' -Category 'orgs'
        $put.requestBody = [ordered]@{ content = [ordered]@{ 'application/json' = [ordered]@{ schema = [ordered]@{ '$ref' = '#/components/schemas/cycle-b' } } } }
        $description.paths['/orgs/{org}/zz'] = [ordered]@{ put = $put }
        $script:catalog.Paths['/orgs/{org}/zz'] = [ordered]@{ Category = 'orgs'; PUT = [ordered]@{ Status = 'write'; Body = @('name') } }

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        $text = $script:TestOutput -join "`n"
        $text | Should -BeLike '*PATCH /orgs/{org}, request body not comparable*'
        $text | Should -BeLike '*PUT /orgs/{org}/zz, request body not comparable*'
    }

    It 'opens no issue for a difference that a closed issue records, and lists it in the summary' {
        $description.components.schemas['company-body'].properties.new_policy = [ordered]@{ type = 'boolean' }
        $script:TestIssues = @(Get-TestIssue -Number 5 -Operation 'PATCH /orgs/{org}' -State 'CLOSED' -Difference 'request body fields: +new_policy')

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -BeLike '*Closed without a catalog change*#5*PATCH /orgs/{org}*'
    }

    It 'reports a request body it cannot compare (<Case>) and opens no issue' -ForEach @(
        @{ Case = 'oneOf'; Reason = '*oneOf or anyOf*'; Change = {
                $description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ oneOf = @([ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }) }
            }
        }
        @{ Case = 'anyOf in an allOf part'; Reason = '*oneOf or anyOf*'; Change = {
                $description.components.schemas['company-body'] = [ordered]@{ anyOf = @([ordered]@{ properties = [ordered]@{ company = [ordered]@{ type = 'string' } } }) }
            }
        }
        @{ Case = 'not JSON'; Reason = '*not JSON (application/x-www-form-urlencoded)*'; Change = {
                $body = $description.paths['/orgs/{org}'].patch.requestBody
                $body.content = [ordered]@{ 'application/x-www-form-urlencoded' = $body.content['application/json'] }
            }
        }
    ) {
        & $Change

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'issue list').Count | Should -Be 0
        $text = $script:TestOutput -join "`n"
        $text | Should -BeLike "*PATCH /orgs/{org}, request body not comparable: $Reason*report only*"
        $text | Should -Not -BeLike '*request body fields*'
        (Get-Content -Path $script:summary -Raw) | Should -BeLike '*PATCH /orgs/{org}*request body not comparable*report only*'
    }

    It 'opens one issue per operation, two for two new methods of a path' {
        $description.paths['/orgs/{org}/hooks'].patch = Get-TestOperation -Summary 'Update webhooks' -Category 'orgs'
        $description.paths['/orgs/{org}/hooks'].delete = Get-TestOperation -Summary 'Delete webhooks' -Category 'orgs'

        Invoke-TestCheck

        Get-TestCreatedTitle | Should -Be @('Review the API endpoint PATCH /orgs/{org}/hooks', 'Review the API endpoint DELETE /orgs/{org}/hooks')
        (Get-GhCall 'issue list').Count | Should -Be 1
    }

    It 'opens no second issue for an operation with one, open or closed' {
        $description.paths['/orgs/{org}/hooks'].delete = Get-TestOperation -Summary 'Delete webhooks' -Category 'orgs'
        $description.paths['/orgs/{org}/hooks'].Remove('post')
        $script:TestLabels = @('enhancement', 'api-endpoint')
        $script:TestIssues = @(
            Get-TestIssue -Number 4 -Operation 'DELETE /orgs/{org}/hooks'
            Get-TestIssue -Number 5 -Operation 'POST /orgs/{org}/hooks' -State 'CLOSED'
        )

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'label create').Count | Should -Be 0
        $text = Get-Content -Path $script:summary -Raw
        $text | Should -BeLike '*DELETE /orgs/{org}/hooks*open #4*'
        $text | Should -BeLike '*POST /orgs/{org}/hooks*closed #5*'
    }

    It 'lists an operation closed without being catalogued in the summary' {
        $description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
        $script:TestIssues = @(Get-TestIssue -Number 5 -Operation 'GET /orgs/{org}/new-feature' -State 'CLOSED')

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        $text = Get-Content -Path $script:summary -Raw
        $text | Should -BeLike '*Closed without a catalog change*'
        $text | Should -BeLike '*#5*GET /orgs/{org}/new-feature*'
    }

    It 'fails and opens nothing when <Case>' -ForEach @(
        @{ Case = 'the download fails'; Message = '*Downloading the description of 2026-03-10 failed*'; Change = { $script:TestApiExit = 1 } }
        @{ Case = 'the answer is not JSON'; Message = '*description of 2026-03-10 is not JSON*'; Change = { $script:description = '<html>Not found</html>' } }
        @{ Case = 'it has no paths'; Message = '*description of 2026-03-10 has no paths*'; Change = { $script:description = '{"openapi":"3.0.3"}' } }
        @{ Case = 'no /orgs/{org} operation'; Message = '*description of 2026-03-10 has no operation under /orgs/{org}*'; Change = { $script:description = '{"paths":{"/repos/{owner}/{repo}":{"get":{}}}}' } }
        @{ Case = 'under 90% of the listed operations'; Message = '*Only 22 of 25 operations of the catalog*90%*'; Change = {
                foreach ($i in 1..3) { $script:description.paths.Remove("/orgs/{org}/filler/$i") }
            }
        }
        @{ Case = 'more than 10 listed operations missing'; Message = '*11 operations of the catalog are missing*GET /orgs/{org}/filler/1*'; Change = {
                $script:catalog = Get-TestCatalog -Filler 120
                $script:description = Get-TestDescription -Filler 120
                foreach ($i in 1..11) { $script:description.paths.Remove("/orgs/{org}/filler/$i") }
            }
        }
        # Every operation is still there, but the request body of PATCH /orgs/{org} would lose company.
        @{ Case = 'a reference is not defined'; Message = "*description of 2026-03-10 has a reference it does not resolve: '#/components/schemas/company-body'*"; Change = {
                $script:description.components.schemas.Remove('company-body')
            }
        }
        @{ Case = 'a reference is not local'; Message = "*description of 2026-03-10 has a reference it does not resolve: 'other.json#/components/schemas/company-body'*"; Change = {
                $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema.allOf[1]['$ref'] = 'other.json#/components/schemas/company-body'
            }
        }
        # A variant first must not skip the reference after it, while a new operation would open an issue.
        @{ Case = 'a reference after a variant is not defined'; Message = "*description of 2026-03-10 has a reference it does not resolve: '#/components/schemas/missing'*"; Change = {
                $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema.allOf = @(
                    [ordered]@{ oneOf = @([ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }) }
                    [ordered]@{ '$ref' = '#/components/schemas/missing' }
                )
                $script:description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
            }
        }
        @{ Case = 'a reference in a variant is not defined'; Message = "*description of 2026-03-10 has a reference it does not resolve: '#/components/schemas/missing'*"; Change = {
                $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ oneOf = @([ordered]@{ '$ref' = '#/components/schemas/missing' }) }
                $script:description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
            }
        }
        # Read as comparable, a variant schema past the limit would report every Body field removed.
        @{ Case = 'schemas nest deeper than 32 levels'; Message = "*description of 2026-03-10 nests schemas deeper than 32 levels at '#/components/schemas/deep-33'*"; Change = {
                for ($i = 0; $i -lt 34; $i++) {
                    $script:description.components.schemas["deep-$i"] = [ordered]@{ allOf = @([ordered]@{ '$ref' = "#/components/schemas/deep-$($i + 1)" }) }
                }
                $script:description.components.schemas['deep-34'] = [ordered]@{ anyOf = @([ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }) }
                $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ '$ref' = '#/components/schemas/deep-0' }
                $script:description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
            }
        }
        # One body reaches deep-0 at depth 0 and the other at depth 10; the catalog is a hashtable, so the two cases swap
        # the bodies and one of them visits the shallow one first: the deeper one still throws.
        @{ Case = 'a schema another body shares nests deeper than 32 levels (PATCH deeper)'; Message = '*description of 2026-03-10 nests schemas deeper than 32 levels*'; Change = {
                for ($i = 0; $i -lt 25; $i++) {
                    $script:description.components.schemas["deep-$i"] = [ordered]@{ allOf = @([ordered]@{ '$ref' = "#/components/schemas/deep-$($i + 1)" }) }
                }
                $script:description.components.schemas['deep-25'] = [ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' }; company = [ordered]@{ type = 'string' } } }
                for ($i = 0; $i -lt 10; $i++) {
                    $next = if ($i -eq 9) { 'deep-0' } else { "wide-$($i + 1)" }
                    $script:description.components.schemas["wide-$i"] = [ordered]@{ allOf = @([ordered]@{ '$ref' = "#/components/schemas/$next" }) }
                }
                $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ '$ref' = '#/components/schemas/wide-0' }
                $put = Get-TestOperation -Summary 'Set zz' -Category 'orgs'
                $put.requestBody = [ordered]@{ content = [ordered]@{ 'application/json' = [ordered]@{ schema = [ordered]@{ '$ref' = '#/components/schemas/deep-0' } } } }
                $script:description.paths['/orgs/{org}/zz'] = [ordered]@{ put = $put }
                $script:catalog.Paths['/orgs/{org}/zz'] = [ordered]@{ Category = 'orgs'; PUT = [ordered]@{ Status = 'write'; Body = @('name', 'company') } }
            }
        }
        @{ Case = 'a schema another body shares nests deeper than 32 levels (PUT deeper)'; Message = '*description of 2026-03-10 nests schemas deeper than 32 levels*'; Change = {
                for ($i = 0; $i -lt 25; $i++) {
                    $script:description.components.schemas["deep-$i"] = [ordered]@{ allOf = @([ordered]@{ '$ref' = "#/components/schemas/deep-$($i + 1)" }) }
                }
                $script:description.components.schemas['deep-25'] = [ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' }; company = [ordered]@{ type = 'string' } } }
                for ($i = 0; $i -lt 10; $i++) {
                    $next = if ($i -eq 9) { 'deep-0' } else { "wide-$($i + 1)" }
                    $script:description.components.schemas["wide-$i"] = [ordered]@{ allOf = @([ordered]@{ '$ref' = "#/components/schemas/$next" }) }
                }
                $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = [ordered]@{ '$ref' = '#/components/schemas/deep-0' }
                $put = Get-TestOperation -Summary 'Set zz' -Category 'orgs'
                $put.requestBody = [ordered]@{ content = [ordered]@{ 'application/json' = [ordered]@{ schema = [ordered]@{ '$ref' = '#/components/schemas/wide-0' } } } }
                $script:description.paths['/orgs/{org}/zz'] = [ordered]@{ put = $put }
                $script:catalog.Paths['/orgs/{org}/zz'] = [ordered]@{ Category = 'orgs'; PUT = [ordered]@{ Status = 'write'; Body = @('name', 'company') } }
            }
        }
        # A variant 40 levels down, shared with a body that reaches it 30 levels down: cached from either body first, the
        # deeper one still throws. The two cases swap the bodies, since the order of the catalog is not fixed.
        foreach ($deeper in 'PATCH', 'PUT') {
            @{ Case = "a variant schema another body shares nests deeper than 32 levels ($deeper deeper)"; Deeper = $deeper; Message = '*description of 2026-03-10 nests schemas deeper than 32 levels*'; Change = {
                    for ($i = 0; $i -lt 40; $i++) {
                        $script:description.components.schemas["vdeep-$i"] = [ordered]@{ allOf = @([ordered]@{ '$ref' = "#/components/schemas/vdeep-$($i + 1)" }) }
                    }
                    $script:description.components.schemas['vdeep-40'] = [ordered]@{ oneOf = @([ordered]@{ properties = [ordered]@{ name = [ordered]@{ type = 'string' } } }) }
                    $deep = [ordered]@{ '$ref' = '#/components/schemas/vdeep-0' }
                    $shallow = [ordered]@{ '$ref' = '#/components/schemas/vdeep-10' }
                    $patch, $zz = if ($Deeper -eq 'PATCH') { $deep, $shallow } else { $shallow, $deep }
                    $script:description.paths['/orgs/{org}'].patch.requestBody.content['application/json'].schema = $patch
                    $put = Get-TestOperation -Summary 'Set zz' -Category 'orgs'
                    $put.requestBody = [ordered]@{ content = [ordered]@{ 'application/json' = [ordered]@{ schema = $zz } } }
                    $script:description.paths['/orgs/{org}/zz'] = [ordered]@{ put = $put }
                    $script:catalog.Paths['/orgs/{org}/zz'] = [ordered]@{ Category = 'orgs'; PUT = [ordered]@{ Status = 'write'; Body = @('name') } }
                }
            }
        }
        @{ Case = 'the issue list fails'; Message = '*gh issue list failed*'; Change = {
                $script:description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
                $script:TestIssueListExit = 1
            }
        }
    ) {
        & $Change

        { Invoke-TestCheck } | Should -Throw $Message
        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'label create').Count | Should -Be 0
    }

    It 'with -Report opens nothing and lists body and response field differences' {
        $description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }
        $description.components.schemas['company-body'].properties.new_policy = [ordered]@{ type = 'boolean' }
        $description.components.schemas['organization-full'].allOf += @([ordered]@{ properties = [ordered]@{ new_setting = [ordered]@{ type = 'boolean' } } })

        Invoke-TestCheck -Parameter @{ Report = $true }

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'issue list').Count | Should -Be 0
        $text = $script:TestOutput -join "`n"
        $text | Should -BeLike '*GET /orgs/{org}/new-feature*new operation*'
        $text | Should -BeLike '*PATCH /orgs/{org}*request body fields*new_policy*'
        $text | Should -BeLike '*GET /orgs/{org}*response fields*new_setting*'
        $text | Should -Not -BeLike "*$script:rowField*"
        $text | Should -Not -BeLike '*login*'
    }

    It 'opens no issue for a response field difference' {
        $description.components.schemas['organization-full'].allOf += @([ordered]@{ properties = [ordered]@{ new_setting = [ordered]@{ type = 'boolean' } } })

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0
        ($script:TestOutput -join "`n") | Should -BeLike '*no change*'
    }

    It 'with -WhatIf opens nothing' {
        $description.paths['/orgs/{org}/new-feature'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get a new feature' -Category 'features') }

        Invoke-TestCheck -Parameter @{ WhatIf = $true }

        (Get-GhCall 'issue create').Count | Should -Be 0
        (Get-GhCall 'label create').Count | Should -Be 0
        (Get-Content -Path $script:summary -Raw) | Should -BeLike '*GET /orgs/{org}/new-feature*new operation*| new |*'
    }

    It 'reports an operation outside /orgs/{org} only when it disappears' {
        $description.paths['/repos/{owner}/{repo}/topics'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get topics' -Category 'repos') }
        $description.paths['/user'] = [ordered]@{ get = (Get-TestOperation -Summary 'Get the user' -Category 'users') }

        Invoke-TestCheck

        (Get-GhCall 'issue create').Count | Should -Be 0

        $description.paths.Remove('/repos/{owner}/{repo}')

        Invoke-TestCheck

        Get-TestCreatedTitle | Should -Be @('Review the API endpoint GET /repos/{owner}/{repo}')
    }

    It 'fails before any gh call when the template lacks the label the issues are matched by' {
        (Get-Content -Path $script:template -Raw) -replace 'api-endpoint, ', '' | Set-Content -Path $script:template

        { Invoke-TestCheck } | Should -Throw "*api-endpoint.md*'api-endpoint'*"
        $script:TestGhCalls.Count | Should -Be 0
    }
}
