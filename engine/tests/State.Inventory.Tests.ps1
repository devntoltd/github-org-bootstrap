BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgState: inventory' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Progress { }
        # Only the inventory: every read is one of the three below.
        $script:config = Get-TestGitHubOrgConfig
        $script:config.PSObject.Properties.Remove('settings')
        $script:config.PSObject.Properties.Remove('actions')
        $script:state = Get-MatchingTestGitHubOrgState
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'reads the owners, GitHub Apps and webhooks on every run' {
        $script:state.Inventory = [pscustomobject]@{
            Owners   = [string[]]@('octocat')
            Apps     = @([pscustomobject]@{ Slug = 'octo-app'; RepositorySelection = 'selected'; Permissions = [ordered]@{ contents = 'read'; metadata = 'read' } })
            Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/services/T000/B000'; Events = [string[]]@('push', 'member'); Active = $false; VerifiesTls = $true; HasSecret = $true })
        }
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        $inventory = (Get-GitHubOrgState -Config $script:config).Inventory

        @($inventory.Owners) | Should -Be @('octocat')
        @($inventory.Apps).Count | Should -Be 1
        $inventory.Apps[0].Slug | Should -Be 'octo-app'
        $inventory.Apps[0].RepositorySelection | Should -Be 'selected'
        $inventory.Apps[0].Permissions.contents | Should -Be 'read'
        @($inventory.Webhooks).Count | Should -Be 1
        $inventory.Webhooks[0].Host | Should -Be 'hooks.example.com'
        $inventory.Webhooks[0].Url | Should -Be 'https://hooks.example.com/...'
        ($inventory.Webhooks[0].Events -join ',') | Should -Be 'push,member'
        $inventory.Webhooks[0].Active | Should -BeFalse
        $inventory.Webhooks[0].Https | Should -BeTrue
        $inventory.Webhooks[0].VerifiesTls | Should -BeTrue
        $inventory.Webhooks[0].HasSecret | Should -BeTrue
    }

    It 'reads whether a webhook uses https, verifies TLS and has a secret, never the secret' {
        $routes = Get-TestGhRoute -State $script:state
        # insecure_ssl comes as a string or a number; a set secret comes masked, an unset one missing or null.
        $routes['GET orgs/contoso/hooks?per_page=100'] = Get-TestGhPagesResponse -Items @(
            [pscustomobject]@{ config = [pscustomobject]@{ url = 'http://hooks.example.com/a'; insecure_ssl = '0'; secret = '********' }; events = @('push'); active = $true }
            [pscustomobject]@{ config = [pscustomobject]@{ url = 'https://hooks.example.com/b'; insecure_ssl = 1; secret = $null }; events = @('push'); active = $true }
            [pscustomobject]@{ config = [pscustomobject]@{ url = 'https://hooks.example.com/c'; insecure_ssl = '1' }; events = @('push'); active = $true }
            [pscustomobject]@{ config = [pscustomobject]@{ url = 'https://hooks.example.com/d'; insecure_ssl = 0; secret = '********' }; events = @('push'); active = $true }
        )
        Register-TestGhRoute -Route $routes

        $webhooks = @((Get-GitHubOrgState -Config $script:config).Inventory.Webhooks)

        ($webhooks.Https -join ',') | Should -Be 'False,True,True,True'
        ($webhooks.VerifiesTls -join ',') | Should -Be 'True,False,False,True'
        ($webhooks.HasSecret -join ',') | Should -Be 'True,False,False,True'
        ($webhooks | ConvertTo-Json -Depth 5) | Should -Not -Match '\*\*\*\*'
    }

    It 'does not count a webhook as verifying TLS when GitHub leaves insecure_ssl out' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET orgs/contoso/hooks?per_page=100'] = Get-TestGhPagesResponse -Items @(
            [pscustomobject]@{ config = [pscustomobject]@{ url = 'https://hooks.example.com/a'; secret = '********' }; events = @('push'); active = $true }
        )
        Register-TestGhRoute -Route $routes

        $webhook = @((Get-GitHubOrgState -Config $script:config).Inventory.Webhooks)[0]

        $webhook.VerifiesTls | Should -Be $null
    }

    It 'reads the outside collaborators and the pending invitations' {
        $script:state.Inventory.OutsideCollaborators = [string[]]@('monalisa')
        $script:state.Inventory.Invitations = @(
            [pscustomobject]@{ Login = 'mallory'; Email = $null; Role = 'direct_member'; Inviter = 'octocat'; CreatedAt = '2026-09-30' }
            [pscustomobject]@{ Login = $null; Email = 'eve@example.com'; Role = 'admin'; Inviter = 'hubot'; CreatedAt = '2026-09-29' }
        )
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        $inventory = (Get-GitHubOrgState -Config $script:config).Inventory

        @($inventory.OutsideCollaborators) | Should -Be @('monalisa')
        @($inventory.Invitations).Count | Should -Be 2
        $inventory.Invitations[0].Login | Should -Be 'mallory'
        $inventory.Invitations[0].Email | Should -BeNullOrEmpty
        $inventory.Invitations[0].Role | Should -Be 'direct_member'
        $inventory.Invitations[0].Inviter | Should -Be 'octocat'
        # ConvertFrom-Json reads created_at as a date; only the UTC day is kept.
        $inventory.Invitations[0].CreatedAt | Should -Be '2026-09-30'
        $inventory.Invitations[1].Login | Should -BeNullOrEmpty
        $inventory.Invitations[1].Email | Should -Be 'eve@example.com'
    }

    It 'reads the invitations of every repository, archived ones and expired invitations included, on every page' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State $script:state) -PageSize 1 -Archived 'repo-old' -Repositories ([ordered]@{
                'repo-a'   = $null
                'repo-old' = $null
            }) -Invitations @{
            'repo-a'   = @(
                Get-TestRepositoryInvitation -Login 'mallory' -Permission 'write' -Inviter 'octocat' -CreatedAt '2026-09-30'
                Get-TestRepositoryInvitation -Login $null -Permission 'admin' -Inviter 'hubot' -CreatedAt '2026-09-29'
            )
            'repo-old' = @(Get-TestRepositoryInvitation -Login 'eve' -Permission 'read' -Inviter 'hubot' -CreatedAt '2026-09-20' -Expired)
        }
        Register-TestGhRoute -Route $routes

        $invitations = @((Get-GitHubOrgState -Config $script:config).Inventory.RepositoryInvitations)

        ($invitations.Repository -join ',') | Should -Be 'repo-a,repo-a,repo-old'
        $invitations[0].Login | Should -Be 'mallory'
        $invitations[0].Permission | Should -Be 'write'
        $invitations[0].Inviter | Should -Be 'octocat'
        $invitations[0].CreatedAt | Should -Be '2026-09-30'
        $invitations[0].Expired | Should -BeFalse
        $invitations[1].Login | Should -BeNullOrEmpty
        $invitations[2].Login | Should -Be 'eve'
        $invitations[2].Expired | Should -BeTrue
    }

    It 'reads the repository list once for the invitations and code security' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        Get-GitHubOrgState -Config $script:config | Out-Null

        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -eq 'orgs/contoso/repos?per_page=100' }).Count | Should -Be 1
    }

    It 'keeps a repository whose invitations answer 404 as skipped, and the invitations of the others' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State $script:state) -Repositories ([ordered]@{ 'repo-a' = $null }) -Vanished 'repo-gone' -Invitations @{
            'repo-a' = @(Get-TestRepositoryInvitation -Login 'mallory' -Permission 'write' -Inviter 'octocat' -CreatedAt '2026-09-30')
        }
        Register-TestGhRoute -Route $routes

        $inventory = (Get-GitHubOrgState -Config $script:config).Inventory

        @($inventory.SkippedRepositories) | Should -Be @('repo-gone')
        @($inventory.RepositoryInvitations.Repository) | Should -Be @('repo-a')
    }

    It 'stops when the invitations of a repository cannot be read otherwise' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET repos/contoso/repo-a/invitations?per_page=100'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*Cannot read repos/contoso/repo-a/invitations*HTTP 502*'
    }

    It 'reads an organization without Apps or webhooks as empty lists' {
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        $inventory = (Get-GitHubOrgState -Config $script:config).Inventory

        @($inventory.Owners) | Should -Be @('octocat', 'hubot')
        @($inventory.Apps).Count | Should -Be 0
        @($inventory.Webhooks).Count | Should -Be 0
        @($inventory.OutsideCollaborators).Count | Should -Be 0
        @($inventory.Invitations).Count | Should -Be 0
    }

    It 'reads the installations of every page' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET orgs/contoso/installations?per_page=100'] = Get-TestGhObjectPagesResponse -Property installations -PageSize 1 -Items @(
            [pscustomobject]@{ app_slug = 'octo-app'; repository_selection = 'all'; permissions = [pscustomobject]@{ metadata = 'read' } }
            [pscustomobject]@{ app_slug = 'other-app'; repository_selection = 'selected'; permissions = [pscustomobject]@{ issues = 'write' } }
        )
        Register-TestGhRoute -Route $routes

        $apps = @((Get-GitHubOrgState -Config $script:config).Inventory.Apps)

        ($apps.Slug -join ',') | Should -Be 'octo-app,other-app'
        $apps[1].Permissions.issues | Should -Be 'write'
    }

    It 'keeps only the scheme and host of a webhook URL, whose path can hold a secret' {
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://user:pass@hooks.example.com/services/T000/B000?token=x'; Events = [string[]]@('push'); Active = $true })
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        $webhook = @((Get-GitHubOrgState -Config $script:config).Inventory.Webhooks)[0]

        $webhook.Host | Should -Be 'hooks.example.com'
        $webhook.Url | Should -Be 'https://hooks.example.com/...'
    }

    It 'reads an internationalized webhook host in its ASCII form' {
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = ''; Url = "https://b$([char]0xFC)cher.example/hook"; Events = [string[]]@('push'); Active = $true })
        Register-TestGhRoute -Route (Get-TestGhRoute -State $script:state)

        $webhook = @((Get-GitHubOrgState -Config $script:config).Inventory.Webhooks)[0]

        $webhook.Host | Should -Be 'xn--bcher-kva.example'
        $webhook.Url | Should -Be 'https://xn--bcher-kva.example/...'
    }

    It 'reads a webhook without a URL and an App without permissions' {
        $routes = Get-TestGhRoute -State $script:state
        $routes['GET orgs/contoso/hooks?per_page=100'] = Get-TestGhPagesResponse -Items @(
            [pscustomobject]@{ config = [pscustomobject]@{ content_type = 'json' }; events = @('push'); active = $true }
        )
        $routes['GET orgs/contoso/installations?per_page=100'] = Get-TestGhObjectPagesResponse -Property installations -Items @(
            [pscustomobject]@{ app_slug = 'octo-app'; repository_selection = 'all' }
        )
        Register-TestGhRoute -Route $routes

        $inventory = (Get-GitHubOrgState -Config $script:config).Inventory

        $inventory.Webhooks[0].Host | Should -Be ''
        $inventory.Webhooks[0].Url | Should -Be ''
        $inventory.Apps[0].Slug | Should -Be 'octo-app'
        $inventory.Apps[0].Permissions.Count | Should -Be 0
    }

    It 'fails when the webhooks cannot be read' {
        $routes = Get-TestGhRoute -State $script:state
        $routes.Remove('GET orgs/contoso/hooks?per_page=100')
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*Cannot read orgs/contoso/hooks?per_page=100*HTTP 404*'
    }
}
