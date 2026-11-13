BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../Bootstrap.Common.psm1') -Force
}

Describe 'Assert-GhVersion' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'GhStub.ps1')
    }

    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Host { }
        # The stub is a function, which Get-Command -CommandType Application does not find.
        Mock -ModuleName Bootstrap.Common Test-GhInstalled { $true }
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'prints the installed, minimum and latest gh versions and passes at or above the minimum: <Output>' -ForEach @(
        @{ Output = "gh version 2.101.0 (2026-09-15)`nhttps://github.com/cli/cli/releases/tag/v2.101.0"; Installed = '2.101.0' }
        @{ Output = 'gh version 2.48.0 (2024-04-17)'; Installed = '2.48.0' }
    ) {
        Register-TestGhRoute -Route @{
            '--version'                         = [pscustomobject]@{ ExitCode = 0; Output = $Output }
            'GET repos/cli/cli/releases/latest' = Get-TestGhResponse -Body @{ tag_name = "v$Installed" }
        }

        { Assert-GhVersion } | Should -Not -Throw

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Tools:' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter {
            $Object -eq ('  {0,-26} installed {1,-8} minimum {2,-8} latest {3}' -f 'gh', $Installed, '2.48.0', $Installed)
        }
    }

    It 'flags an available gh update' {
        Register-TestGhRoute -Route @{
            '--version'                         = [pscustomobject]@{ ExitCode = 0; Output = 'gh version 2.101.0 (2026-09-15)' }
            'GET repos/cli/cli/releases/latest' = Get-TestGhResponse -Body @{ tag_name = 'v2.102.0' }
        }

        Assert-GhVersion

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter {
            $Object -like '  gh *installed 2.101.0*latest 2.102.0  (update available)'
        }
    }

    It 'prints the pinned and latest GitHub REST API versions<Note>' -ForEach @(
        @{ Versions = @('2026-03-10', '2022-11-28'); Latest = '2026-03-10'; Note = '' }
        @{ Versions = @('2022-11-28', '2027-06-01', '2026-03-10'); Latest = '2027-06-01'; Note = '  (new version available)' }
    ) {
        Register-TestGhRoute -Route @{
            '--version'    = [pscustomobject]@{ ExitCode = 0; Output = 'gh version 2.101.0 (2026-09-15)' }
            'GET versions' = Get-TestGhListResponse -Items $Versions
        }

        Assert-GhVersion

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter {
            $Object -eq ('  {0,-26} pinned {1,-28} latest {2}{3}' -f 'GitHub REST API', '2026-03-10', $Latest, $Note)
        }
    }

    It 'shows latest unknown and passes when the latest versions cannot be read' {
        Register-TestGhRoute -Route @{ '--version' = [pscustomobject]@{ ExitCode = 0; Output = 'gh version 2.101.0 (2026-09-15)' } }

        { Assert-GhVersion } | Should -Not -Throw

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -like '  gh *installed 2.101.0*latest unknown' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -like '  GitHub REST API *pinned 2026-03-10*latest unknown' }
    }

    It 'skips the latest version lookups when asked' {
        Register-TestGhRoute -Route @{ '--version' = [pscustomobject]@{ ExitCode = 0; Output = 'gh version 2.101.0 (2026-09-15)' } }

        Assert-GhVersion -SkipLatestVersionCheck

        @(Get-TestGhCall | Where-Object { $_.Arguments[0] -eq 'api' }) | Should -BeNullOrEmpty
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -like '  gh *installed 2.101.0*latest skipped' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -like '  GitHub REST API *pinned 2026-03-10*latest skipped' }
    }

    It 'rejects a gh older than the minimum with an upgrade command, without calling the API' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = 'gh version 2.47.0 (2024-04-03)' } }

        { Assert-GhVersion } | Should -Throw '*gh 2.47.0 is older than 2.48.0*winget upgrade --id GitHub.cli -e*'
        @(Get-TestGhCall | Where-Object { $_.Arguments[0] -eq 'api' }) | Should -BeNullOrEmpty
    }

    It 'asks to install gh when it is missing, without calling it' {
        Mock -ModuleName Bootstrap.Common Test-GhInstalled { $false }
        Register-TestGhStub

        { Assert-GhVersion } | Should -Throw '*not installed*winget install --id GitHub.cli -e*gh auth login*'
        @(Get-TestGhCall).Count | Should -Be 0
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -like '  gh * installed missing *' }
    }

    It 'fails with the gh output when the version cannot be read' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = 'gh version DEV' } }

        { Assert-GhVersion } | Should -Throw "*Could not read the gh version*'gh version DEV'*"
    }
}

Describe 'Invoke-GhApi' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'GhStub.ps1')
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'calls gh api with the method and endpoint and returns the parsed JSON' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '{"login":"contoso"}' } }

        $result = Invoke-GhApi -Endpoint 'orgs/contoso'

        $result.login | Should -Be 'contoso'
        (@(Get-TestGhCall)[0].Arguments -join ' ') | Should -Be 'api --method GET orgs/contoso'
    }

    It 'pins the REST API version on every call' {
        Register-TestGhStub

        Invoke-GhApi -Endpoint 'orgs/contoso' | Out-Null
        Invoke-GhApi -Method PATCH -Endpoint 'orgs/contoso' -Body @{ name = 'x' } | Out-Null
        Invoke-GhApi -Endpoint 'orgs/contoso/repos' -Paginate | Out-Null

        foreach ($call in @(Get-TestGhCall)) {
            $call.Headers | Should -Be 'X-GitHub-Api-Version: 2026-03-10'
        }
        @(Get-TestGhCall).Count | Should -Be 3
    }

    It 'sends the body as JSON on stdin' {
        Register-TestGhStub

        Invoke-GhApi -Method PATCH -Endpoint 'orgs/contoso' -Body ([ordered]@{ members_can_create_repositories = $false }) | Out-Null

        $call = @(Get-TestGhCall)[0]
        ($call.Arguments -join ' ') | Should -Be 'api --method PATCH orgs/contoso --input -'
        $call.Input | Should -Be '{"members_can_create_repositories":false}'
    }

    It 'sends a deeply nested body whole' {
        Register-TestGhStub
        # The nesting of an organization ruleset: rules -> rule -> parameters -> required_reviewers -> reviewer.
        $body = [ordered]@{ rules = @([ordered]@{ parameters = [ordered]@{ required_reviewers = @([ordered]@{ reviewer = [ordered]@{ id = 11 } }) } }) }

        Invoke-GhApi -Method PUT -Endpoint 'orgs/contoso/rulesets/7' -Body $body | Out-Null

        @(Get-TestGhCall)[0].Input | Should -Be '{"rules":[{"parameters":{"required_reviewers":[{"reviewer":{"id":11}}]}}]}'
    }

    It 'returns nothing for an empty response' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '' } }

        Invoke-GhApi -Method PUT -Endpoint 'orgs/contoso/actions/permissions' -Body @{ enabled_repositories = 'all' } | Should -BeNullOrEmpty
    }

    It 'with -Paginate asks gh for every page and returns the items of all pages' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '[[{"n":1},{"n":2}],[{"n":3}]]' } }

        $items = @(Invoke-GhApi -Endpoint 'orgs/contoso/repos?per_page=100' -Paginate)

        ($items.n -join ',') | Should -Be '1,2,3'
        (@(Get-TestGhCall)[0].Arguments -join ' ') | Should -Be 'api --method GET orgs/contoso/repos?per_page=100 --paginate --slurp'
    }

    It 'with -Paginate returns nothing for an empty list' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '[[]]' } }

        @(Invoke-GhApi -Endpoint 'orgs/contoso/repos?per_page=100' -Paginate).Count | Should -Be 0
    }

    It 'with -Paginate returns no item for an empty response' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '' } }

        @(Invoke-GhApi -Endpoint 'orgs/contoso/repos?per_page=100' -Paginate).Count | Should -Be 0
    }

    It 'without -Paginate returns a list response as it is, lists in it included' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '[["a","b"],["c"]]' } }

        $items = @(Invoke-GhApi -Endpoint 'orgs/contoso/lists')

        $items.Count | Should -Be 2
        $items[0] | Should -Be @('a', 'b')
    }

    It 'with -NoEnumerate returns the JSON root as it is: <Name>' -ForEach @(
        @{ Name = 'a single-item array'; Output = '[{"n":1}]'; Count = 1 }
        @{ Name = 'an empty array'; Output = '[]'; Count = 0 }
        @{ Name = 'an array of two'; Output = '[{"n":1},{"n":2}]'; Count = 2 }
    ) {
        $text = $Output
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = $text } }.GetNewClosure()

        $result = Invoke-GhApi -Endpoint 'orgs/contoso/lists' -NoEnumerate

        $result -is [array] | Should -BeTrue
        $result.Count | Should -Be $Count
    }

    It 'with -NoEnumerate returns an object as it is and nothing for an empty response' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '{"login":"contoso"}' } }
        $object = Invoke-GhApi -Endpoint 'orgs/contoso' -NoEnumerate
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        $empty = Invoke-GhApi -Endpoint 'orgs/contoso' -NoEnumerate

        $object | Should -BeOfType [System.Management.Automation.PSCustomObject]
        $object.login | Should -Be 'contoso'
        $null -eq $empty | Should -BeTrue
    }

    It 'fails with the endpoint, the gh output and the status: <Name>' -ForEach @(
        @{ Name = 'gh names it'; Output = 'gh: Not Found (HTTP 404)'; Status = 404 }
        # A proxy or CDN code that System.Net.HttpStatusCode has no name for.
        @{ Name = 'a code without a name'; Output = 'gh: Network Connect Timeout (HTTP 599)'; Status = 599 }
        # gh's message for a body that is not JSON, such as an error page of a proxy.
        @{ Name = 'a body that is not JSON'; Output = 'gh: HTTP 502'; Status = 502 }
        # What gh printed on 2026-09-29 for a 409: the error body, and a message without "HTTP 409".
        @{ Name = 'only the error body has it'; Output = @('{"message":"Conflict","errors":"All actions and workflows are allowed on this organization","status":"409"}', 'gh: All actions and workflows are allowed on this organization (Conflict)'); Status = 409 }
    ) {
        $script:output = $Output
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 1; Output = $script:output } }

        $thrown = { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -BeLike "gh api --method GET orgs/contoso failed (exit code 1): $(@($Output)[0])*"
        [int]$thrown.Exception.StatusCode | Should -Be $Status
        Test-GhStatus -ErrorRecord $thrown -StatusCode $Status | Should -BeTrue
        Test-GhStatus -ErrorRecord $thrown -StatusCode 500 | Should -BeFalse
    }

    It 'fails without a status when <Name>' -ForEach @(
        @{ Name = 'gh got no answer'; Output = 'error connecting to api.github.com'; Status = 404 }
        # Only an error body (an object) has a status; a list on stdout is not one.
        @{ Name = 'stdout has a list'; Output = '[{"status":"409"}]'; Status = 409 }
    ) {
        $script:output = $Output
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 1; Output = $script:output } }

        $thrown = { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw -PassThru

        $thrown.Exception.Message | Should -Be "gh api --method GET orgs/contoso failed (exit code 1): $Output"
        $thrown.Exception.StatusCode | Should -BeNullOrEmpty
        Test-GhStatus -ErrorRecord $thrown -StatusCode $Status | Should -BeFalse
    }

    It 'Test-GhStatus does not match <Name>' -ForEach @(
        @{ Name = 'another exception with that status code'; Exception = [System.InvalidOperationException]::new('Not Found') | Add-Member -NotePropertyName StatusCode -NotePropertyValue 404 -PassThru; Status = 404 }
        @{ Name = 'an error without a status as status 0'; Exception = [System.Net.Http.HttpRequestException]::new('error connecting to api.github.com'); Status = 0 }
    ) {
        $thrown = { throw $Exception } | Should -Throw -PassThru

        Test-GhStatus -ErrorRecord $thrown -StatusCode $Status | Should -BeFalse
    }

    It 'Test-GhStatus finds the status behind an error that wraps it' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 1; Output = 'gh: Not Found (HTTP 404)' } }
        $inner = { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw -PassThru

        $wrapped = { throw [System.Exception]::new('Cannot read orgs/contoso.', $inner.Exception) } | Should -Throw -PassThru

        Test-GhStatus -ErrorRecord $wrapped -StatusCode 404 | Should -BeTrue
    }

    It 'gives the HTTP status of a failed call, also behind a wrapping error' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 1; Output = 'gh: Forbidden (HTTP 403)' } }
        $inner = { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw -PassThru
        $wrapped = { throw [System.Exception]::new('Cannot read orgs/contoso.', $inner.Exception) } | Should -Throw -PassThru

        Get-GhStatus -ErrorRecord $inner | Should -Be 403
        Get-GhStatus -ErrorRecord $wrapped | Should -Be 403
    }

    It 'gives no status without an answer' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 1; Output = 'error connecting to api.github.com' } }
        $thrown = { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw -PassThru

        Get-GhStatus -ErrorRecord $thrown | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-GhApi with a native gh' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'NativeGh.ps1')
        $script:ghDirectory = Join-Path -Path $TestDrive -ChildPath 'gh'
        Register-TestNativeGh -Directory $script:ghDirectory
        # Cyrillic "Privet" from code points: the PowerShell files are ASCII-only.
        $script:text = -join ([char[]](0x041F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442))
    }

    AfterAll {
        Unregister-TestNativeGh
    }

    It 'decodes the output as UTF-8 whatever the console code page, and restores the code page' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{ 'GET orgs/contoso' = @{ ExitCode = 0; Output = "{`"description`":`"$script:text`"}" } }
        $previous = [Console]::OutputEncoding
        try {
            # The OEM code page of an English Windows console, which decodes gh's UTF-8 into box-drawing characters.
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)

            $result = Invoke-GhApi -Endpoint 'orgs/contoso'

            [Console]::OutputEncoding.CodePage | Should -Be 437
        }
        finally {
            [Console]::OutputEncoding = $previous
        }
        $result.description | Should -Be $script:text
    }

    It 'leaves a stderr line of a successful call out of the JSON' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{ 'GET orgs/contoso' = @{ ExitCode = 0; Output = '{"login":"contoso"}'; Error = 'A new release of gh is available' } }

        (Invoke-GhApi -Endpoint 'orgs/contoso').login | Should -Be 'contoso'
    }

    It 'sends the body on stdin as UTF-8' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{ 'PATCH orgs/contoso' = @{ ExitCode = 0; Output = '{}' } }

        Invoke-GhApi -Method PATCH -Endpoint 'orgs/contoso' -Body @{ description = $script:text } | Out-Null

        $call = @(Get-TestNativeGhCall -Directory $script:ghDirectory)[0]
        # Without a byte order mark: gh would read one as part of the JSON.
        $call.Input[0] | Should -Be '{'
        ($call.Input | ConvertFrom-Json).description | Should -Be $script:text
        $call.Arguments | Should -Contain 'X-GitHub-Api-Version: 2026-03-10'
    }

    It 'passes a query string with & as one argument' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{ 'GET orgs/contoso/members?role=admin&per_page=100' = @{ ExitCode = 0; Output = '[[{"login":"octocat"}]]' } }

        (Invoke-GhApi -Endpoint 'orgs/contoso/members?role=admin&per_page=100' -Paginate).login | Should -Be 'octocat'
    }

    It 'Assert-GhVersion finds gh on PATH and reads its version' {
        # Two lines, as gh prints them.
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{ '--version' = @{ ExitCode = 0; Output = "gh version 2.47.0 (2024-04-03)`nhttps://github.com/cli/cli/releases/tag/v2.47.0" } }
        Mock -ModuleName Bootstrap.Common Write-Host { }

        { Assert-GhVersion } | Should -Throw '*gh 2.47.0 is older than 2.48.0*'
    }

    It 'fails with the exit code and stderr of gh' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{ 'GET orgs/contoso' = @{ ExitCode = 4; Error = 'gh: Requires authentication (HTTP 401)' } }

        $thrown = { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw '*failed (exit code 4): gh: Requires authentication (HTTP 401)*' -PassThru
        [int]$thrown.Exception.StatusCode | Should -Be 401
    }

    It 'records an unknown call and answers it like gh answers an unknown endpoint' {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{}

        $thrown = { Invoke-GhApi -Endpoint 'orgs/contoso/missing' } | Should -Throw '*failed (exit code 1): gh: Not Found (HTTP 404): GET orgs/contoso/missing*' -PassThru
        [int]$thrown.Exception.StatusCode | Should -Be 404
        @(Get-TestNativeGhCall -Directory $script:ghDirectory).Count | Should -Be 1
    }

    # A smoke run of bootstrap.ps1 makes about 40 calls. A pwsh started per call took 0.8 to 1.2 s each on Windows, the
    # exe about 0.2 s.
    It 'answers a call in well under a second on Windows' -Skip:(-not $IsWindows) {
        Set-TestNativeGhRoute -Directory $script:ghDirectory -Route @{}
        gh --version | Out-Null

        $elapsed = Measure-Command { 1..10 | ForEach-Object { gh --version | Out-Null } }

        $elapsed.TotalSeconds | Should -BeLessThan 5
    }
}
