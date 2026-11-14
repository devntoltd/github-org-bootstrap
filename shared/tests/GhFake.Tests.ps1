BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.Common.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'GhFake.ps1')
}

Describe 'Register-TestGhFake' {
    AfterEach {
        Unregister-TestGhFake
    }

    It 'answers a GET from the store' {
        Register-TestGhFake -Resource @{ 'orgs/contoso' = @{ login = 'contoso'; email = 'a@contoso.com' } }

        (Invoke-GhApi -Endpoint 'orgs/contoso').email | Should -Be 'a@contoso.com'
    }

    It 'answers like gh for an endpoint that is not in the store' {
        Register-TestGhFake -Resource @{}

        { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw '*HTTP 404*GET orgs/contoso*'
    }

    It 'answers 204 No Content for an endpoint stored as null' {
        Register-TestGhFake -Resource @{ 'repos/contoso/app/code-security-configuration' = $null }

        Invoke-GhApi -Endpoint 'repos/contoso/app/code-security-configuration' | Should -BeNullOrEmpty
    }

    It 'returns the items of a list read with -Paginate, ignoring per_page' {
        Register-TestGhFake -Resource @{ 'orgs/contoso/members?role=admin' = @(@{ login = 'octocat' }) }

        $members = @(Invoke-GhApi -Endpoint 'orgs/contoso/members?role=admin&per_page=100' -Paginate)

        $members.Count | Should -Be 1
        $members[0].login | Should -Be 'octocat'
    }

    It 'replaces the stored object on PUT' {
        Register-TestGhFake -Resource @{ 'orgs/contoso/actions/permissions/workflow' = @{ default_workflow_permissions = 'write'; can_approve_pull_request_reviews = $true } }

        Invoke-GhApi -Method PUT -Endpoint 'orgs/contoso/actions/permissions/workflow' -Body @{ default_workflow_permissions = 'read' } | Out-Null

        $stored = Get-TestGhFakeResource -Endpoint 'orgs/contoso/actions/permissions/workflow'
        $stored.default_workflow_permissions | Should -Be 'read'
        $stored.PSObject.Properties.Name | Should -Not -Contain 'can_approve_pull_request_reviews'
    }

    It 'merges the body into the stored object on PATCH' {
        Register-TestGhFake -Resource @{ 'orgs/contoso' = @{ login = 'contoso'; members_can_create_pages = $true } }

        Invoke-GhApi -Method PATCH -Endpoint 'orgs/contoso' -Body @{ members_can_create_pages = $false; email = 'a@contoso.com' } | Out-Null

        $stored = Get-TestGhFakeResource -Endpoint 'orgs/contoso'
        $stored.login | Should -Be 'contoso'
        $stored.members_can_create_pages | Should -BeFalse
        $stored.email | Should -Be 'a@contoso.com'
    }

    It 'rejects a PATCH of an endpoint that is not in the store' {
        Register-TestGhFake -Resource @{}

        { Invoke-GhApi -Method PATCH -Endpoint 'orgs/contoso' -Body @{ email = 'a@contoso.com' } } | Should -Throw '*HTTP 404*PATCH orgs/contoso*'
    }

    It 'rejects a POST without a handler' {
        Register-TestGhFake -Resource @{ 'orgs/contoso/things' = @() }

        { Invoke-GhApi -Method POST -Endpoint 'orgs/contoso/things' -Body @{ name = 'x' } } | Should -Throw '*HTTP 404*POST orgs/contoso/things*'
    }

    It 'lets a handler answer a request, with the store, the parsed body and the match' {
        $handler = @{
            '^POST orgs/(?<org>[^/]+)/things$' = {
                param($Store, $Request)
                $thing = [pscustomobject]@{ id = 7; name = $Request.Body.name; org = $Request.Match['org'] }
                $Store['orgs/contoso/things'] = @($Store['orgs/contoso/things']) + $thing
                $thing
            }
        }
        Register-TestGhFake -Resource @{ 'orgs/contoso/things' = @() } -Handler $handler

        $created = Invoke-GhApi -Method POST -Endpoint 'orgs/contoso/things' -Body @{ name = 'x' }

        $created.id | Should -Be 7
        $created.org | Should -Be 'contoso'
        @(Invoke-GhApi -Endpoint 'orgs/contoso/things?per_page=100' -Paginate).name | Should -Be @('x')
    }

    It 'falls back to the store when a handler returns nothing' {
        $handler = @{ '^GET orgs/contoso$' = { } }
        Register-TestGhFake -Resource @{ 'orgs/contoso' = @{ login = 'contoso' } } -Handler $handler

        (Invoke-GhApi -Endpoint 'orgs/contoso').login | Should -Be 'contoso'
    }

    It 'passes a gh response from a handler through, errors included' {
        $handler = @{ '^GET orgs/contoso$' = { Get-TestGhFakeError -Message 'gh: Conflict (HTTP 409)' } }
        Register-TestGhFake -Resource @{ 'orgs/contoso' = @{ login = 'contoso' } } -Handler $handler

        { Invoke-GhApi -Endpoint 'orgs/contoso' } | Should -Throw '*HTTP 409*'
    }

    It 'records every call like the stub' {
        Register-TestGhFake -Resource @{ 'orgs/contoso' = @{ login = 'contoso' } }

        Invoke-GhApi -Method PATCH -Endpoint 'orgs/contoso' -Body @{ email = 'a@contoso.com' } | Out-Null

        @(Get-TestGhCall | ForEach-Object { "$($_.Arguments[2]) $($_.Arguments[3])" }) | Should -Be @('PATCH orgs/contoso')
    }
}
