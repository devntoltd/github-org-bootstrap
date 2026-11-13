BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgWarning: inventory' {
    BeforeEach {
        $script:config = Get-TestGitHubOrgConfig
        $script:state = Get-MatchingTestGitHubOrgState
    }

    It 'warns about nothing when the inventory matches' {
        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -BeNullOrEmpty
    }

    It 'warns about a single owner even when it is the expected one' {
        $script:config.inventory.owners = @('octocat')
        $script:state.Inventory.Owners = [string[]]@('octocat')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "'contoso' has a single owner (octocat). If that account loses its second factor, nobody can recover the organization: add a second owner at https://github.com/orgs/contoso/people, and keep the two-factor recovery codes offline."
    }

    It 'reports no owner as missing owners, not as a single owner' {
        $script:state.Inventory.Owners = [string[]]@()

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings.Count | Should -Be 2
        $warnings[0] | Should -BeLike "'octocat' is in inventory.owners but not an owner of 'contoso'.*"
        $warnings[1] | Should -BeLike "'hubot' is in inventory.owners but not an owner of 'contoso'.*"
    }

    It 'warns about an owner not in the list' {
        $script:state.Inventory.Owners = [string[]]@('octocat', 'hubot', 'mallory')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "'mallory' is an owner of 'contoso' but not in inventory.owners. An unexpected owner is the usual way to keep access after a compromise: if you did not add them, remove them at https://github.com/orgs/contoso/people and review the audit log; if you did, add them to inventory.owners."
    }

    It 'warns about a listed owner who is not an owner' {
        $script:config.inventory.owners = @('octocat', 'hubot', 'monalisa')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "'monalisa' is in inventory.owners but not an owner of 'contoso'. Update the list, or make them an owner at https://github.com/orgs/contoso/people."
    }

    It 'warns about an outside collaborator not in the list' {
        $script:state.Inventory.OutsideCollaborators = [string[]]@('monalisa')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "'monalisa' is an outside collaborator of 'contoso' but not in inventory.outsideCollaborators. They reach repositories without being members, so neither the base permission nor a review of the members covers them: if they are not expected, remove them at https://github.com/orgs/contoso/outside-collaborators; if they are, add them to inventory.outsideCollaborators."
    }

    It 'warns about a listed outside collaborator who is not one' {
        $script:config.inventory.outsideCollaborators = @('monalisa')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "'monalisa' is in inventory.outsideCollaborators but not an outside collaborator of 'contoso'. Update the list."
    }

    It 'compares outside collaborators ignoring case' {
        $script:config.inventory.outsideCollaborators = @('MonaLisa')
        $script:state.Inventory.OutsideCollaborators = [string[]]@('monalisa')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -BeNullOrEmpty
    }

    It 'warns about every pending invitation, by login or by email' {
        $script:state.Inventory.Invitations = @(
            [pscustomobject]@{ Login = 'mallory'; Email = $null; Role = 'direct_member'; Inviter = 'octocat'; CreatedAt = '2026-09-30' }
            [pscustomobject]@{ Login = $null; Email = 'eve@example.com'; Role = 'admin'; Inviter = 'hubot'; CreatedAt = '2026-09-29' }
        )

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -Be @(
            "Pending invitation of 'mallory' to 'contoso' as direct_member, sent by octocat on 2026-09-30. An invitation is access waiting to be accepted, possibly by the wrong account: if it is not expected, cancel it at https://github.com/orgs/contoso/people/pending_invitations and review the audit log."
            "Pending invitation of 'eve@example.com' to 'contoso' as admin, sent by hubot on 2026-09-29. An invitation is access waiting to be accepted, possibly by the wrong account: if it is not expected, cancel it at https://github.com/orgs/contoso/people/pending_invitations and review the audit log."
        )
    }

    It 'warns about every repository invitation, marking expired ones' {
        $script:state.Inventory.RepositoryInvitations = @(
            [pscustomobject]@{ Repository = 'repo-a'; Login = 'mallory'; Permission = 'write'; Inviter = 'octocat'; CreatedAt = '2026-09-30'; Expired = $false }
            [pscustomobject]@{ Repository = 'repo-a'; Login = $null; Permission = 'admin'; Inviter = 'hubot'; CreatedAt = '2026-09-29'; Expired = $false }
            [pscustomobject]@{ Repository = 'repo-old'; Login = 'eve'; Permission = 'read'; Inviter = 'hubot'; CreatedAt = '2026-09-20'; Expired = $true }
        )

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -Be @(
            "Pending invitation of 'mallory' to repository 'contoso/repo-a' with write access, sent by octocat on 2026-09-30. Accepting it makes the account an outside collaborator: if it is not expected, cancel it at https://github.com/contoso/repo-a/settings/access and review the audit log."
            "Pending invitation of an account GitHub does not name to repository 'contoso/repo-a' with admin access, sent by hubot on 2026-09-29. Accepting it makes the account an outside collaborator: if it is not expected, cancel it at https://github.com/contoso/repo-a/settings/access and review the audit log."
            "Expired invitation of 'eve' to repository 'contoso/repo-old' with read access, sent by hubot on 2026-09-20. It can no longer be accepted, but an administrator of the repository can resend it: if it is not expected, cancel it at https://github.com/contoso/repo-old/settings/access."
        )
    }

    It 'compares owners and webhook hosts ignoring case' {
        $script:config.inventory.owners = @('OctoCat', 'HUBOT')
        $script:config.inventory.webhookHosts = @('Hooks.Example.com')
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/a'; Events = [string[]]@('push'); Active = $true; Https = $true; VerifiesTls = $true; HasSecret = $true })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -BeNullOrEmpty
    }

    It 'warns about an App not in the list, naming its access and permissions' {
        $script:state.Inventory.Apps = @([pscustomobject]@{ Slug = 'octo-app'; RepositorySelection = 'all'; Permissions = [ordered]@{ metadata = 'read'; contents = 'write' } })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "GitHub App 'octo-app' is installed with access to all repositories (permissions: contents: write, metadata: read) but not in inventory.apps. An app can read code and often change workflows: if it is not expected, uninstall it at https://github.com/organizations/contoso/settings/installations; if it is, add it to inventory.apps."
    }

    It 'names every difference of a listed App' {
        $script:config.inventory.apps = @('{ "slug": "octo-app", "repositorySelection": "selected", "permissions": { "contents": "read", "issues": "read", "metadata": "read" } }' | ConvertFrom-Json)
        $script:state.Inventory.Apps = @([pscustomobject]@{ Slug = 'octo-app'; RepositorySelection = 'all'; Permissions = [ordered]@{ contents = 'write'; metadata = 'read'; workflows = 'write' } })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "GitHub App 'octo-app' differs from inventory.apps: repository access: selected -> all; permissions: + workflows: write, contents: read -> write, - issues: read. If you did not approve this, review its access at https://github.com/organizations/contoso/settings/installations and the audit log; if you did, update inventory.apps."
    }

    It 'warns when a listed App narrows its access too' {
        $script:config.inventory.apps = @('{ "slug": "octo-app", "repositorySelection": "all", "permissions": { "metadata": "read" } }' | ConvertFrom-Json)
        $script:state.Inventory.Apps = @([pscustomobject]@{ Slug = 'octo-app'; RepositorySelection = 'selected'; Permissions = [ordered]@{ metadata = 'read' } })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -BeLike "GitHub App 'octo-app' differs from inventory.apps: repository access: all -> selected. *"
    }

    It 'matches a listed App whose permissions come in another order' {
        $script:config.inventory.apps = @('{ "slug": "octo-app", "repositorySelection": "selected", "permissions": { "metadata": "read", "contents": "write" } }' | ConvertFrom-Json)
        $script:state.Inventory.Apps = @([pscustomobject]@{ Slug = 'Octo-App'; RepositorySelection = 'selected'; Permissions = [ordered]@{ contents = 'write'; metadata = 'read' } })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -BeNullOrEmpty
    }

    It 'warns about a listed App that is not installed' {
        $script:config.inventory.apps = @('{ "slug": "octo-app", "repositorySelection": "all", "permissions": {} }' | ConvertFrom-Json)

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "GitHub App 'octo-app' is in inventory.apps but not installed in 'contoso'. Update the list, or install it again."
    }

    It 'warns about a webhook to a host not in the list' {
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/...'; Events = [string[]]@('push', 'member'); Active = $true; Https = $true; VerifiesTls = $true; HasSecret = $true })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "Organization webhook https://hooks.example.com/... (active; events: push, member) is not in inventory.webhookHosts. It sends organization events outside GitHub: if it is not expected, delete it at https://github.com/organizations/contoso/settings/hooks; if it is, add 'hooks.example.com' to inventory.webhookHosts."
    }

    It 'warns about a webhook without a readable URL without suggesting an empty host' {
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = ''; Url = ''; Events = [string[]]@('push'); Active = $false; Https = $false; VerifiesTls = $true; HasSecret = $true })

        # The second warning, about https, is the test below.
        $warning = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())[0]

        $warning | Should -BeLike 'Organization webhook without a readable URL (inactive; events: push) is not in inventory.webhookHosts.*'
        $warning | Should -BeLike '*settings/hooks.'
        $warning | Should -Not -BeLike "*add '*"
    }

    It 'accepts two webhooks to one listed host' {
        $script:config.inventory.webhookHosts = @('hooks.example.com')
        $script:state.Inventory.Webhooks = @(
            [pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/a'; Events = [string[]]@('push'); Active = $true; Https = $true; VerifiesTls = $true; HasSecret = $true }
            [pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/b'; Events = [string[]]@('member'); Active = $false; Https = $true; VerifiesTls = $true; HasSecret = $true }
        )

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() | Should -BeNullOrEmpty
    }

    It 'warns about a webhook that does not use https' {
        $script:config.inventory.webhookHosts = @('hooks.example.com')
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'http://hooks.example.com/...'; Events = [string[]]@('push'); Active = $true; Https = $false; VerifiesTls = $true; HasSecret = $true })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be 'Organization webhook http://hooks.example.com/... is not secure: its URL does not use https, so the organization events travel in clear text (use an https URL). Fix it at https://github.com/organizations/contoso/settings/hooks.'
    }

    It 'warns about a webhook with TLS verification off' {
        $script:config.inventory.webhookHosts = @('hooks.example.com')
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/...'; Events = [string[]]@('push'); Active = $true; Https = $true; VerifiesTls = $false; HasSecret = $true })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -BeLike '*: SSL verification is off, so anyone between GitHub and the receiver can read and answer the deliveries (enable SSL verification). *'
    }

    It 'warns that the TLS verification of a webhook is unknown, without calling it off' {
        $script:config.inventory.webhookHosts = @('hooks.example.com')
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/...'; Events = [string[]]@('push'); Active = $true; Https = $true; VerifiesTls = $null; HasSecret = $true })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be 'Organization webhook https://hooks.example.com/...: GitHub did not report whether SSL verification is on, so it could not be checked. Check it at https://github.com/organizations/contoso/settings/hooks.'
    }

    It 'does not ask about the TLS verification of a webhook without https' {
        $script:config.inventory.webhookHosts = @('hooks.example.com')
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'http://hooks.example.com/...'; Events = [string[]]@('push'); Active = $true; Https = $false; VerifiesTls = $null; HasSecret = $true })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike '*does not use https*'
    }

    It 'warns about a repository whose invitations could not be read' {
        $script:state.Inventory.SkippedRepositories = [string[]]@('repo-gone')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "Repository 'repo-gone' was listed, but its invitations could not be read: GitHub answered 404 (deleted, renamed or transferred during the run, or the gh account cannot see it). Pending invitations to it are not in this run; re-run to check it."
    }

    It 'warns about a webhook without a secret' {
        $script:config.inventory.webhookHosts = @('hooks.example.com')
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = 'hooks.example.com'; Url = 'https://hooks.example.com/...'; Events = [string[]]@('push'); Active = $true; Https = $true; VerifiesTls = $true; HasSecret = $false })

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -BeLike '*: it has no secret, so the receiver cannot tell its deliveries from forged ones (set a secret and check X-Hub-Signature-256 in the receiver). *'
    }

    It 'names every problem of an insecure webhook in one warning, listed or not' {
        $script:state.Inventory.Webhooks = @([pscustomobject]@{ Host = ''; Url = ''; Events = [string[]]@('push'); Active = $true; Https = $false; VerifiesTls = $true; HasSecret = $false })

        $warnings = @(Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @())

        $warnings.Count | Should -Be 2
        $warnings[1] | Should -BeLike '*without a readable URL*its URL does not use https*(use an https URL); it has no secret*'
    }

    It 'warns about a listed host without a webhook' {
        $script:config.inventory.webhookHosts = @('audit.example.com')

        Get-GitHubOrgWarning -Config $script:config -CurrentState $script:state -Plan @() |
            Should -Be "No organization webhook sends to 'audit.example.com', which is in inventory.webhookHosts. If it was deleted on purpose, update the list; otherwise check the audit log and add it again at https://github.com/organizations/contoso/settings/hooks."
    }
}
