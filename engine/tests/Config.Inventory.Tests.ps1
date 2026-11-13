BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Test-GitHubOrgConfig: inventory' {
    It 'rejects an inventory that is not an object' {
        $config = Get-TestGitHubOrgConfig
        $config.inventory = @('octocat')

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path 'inventory' -Part '["octocat"]' -Only
    }

    It 'requires every inventory list' {
        $config = Get-TestGitHubOrgConfig
        $config.inventory = [pscustomobject]@{ owners = 'octocat' }

        $errors = @(Test-GitHubOrgConfig -Config $config)

        $errors.Count | Should -Be 4
        Assert-ConfigError -Errors $errors -Path 'inventory.owners' -Part '"octocat"'
        foreach ($list in 'apps', 'webhookHosts', 'outsideCollaborators') {
            Assert-ConfigError -Errors $errors -Path "inventory.$list"
        }
    }

    It 'accepts an App entry' {
        $config = Get-TestGitHubOrgConfig
        $config.inventory.apps = @('{ "slug": "octo-app", "repositorySelection": "selected", "permissions": { "contents": "write", "metadata": "read" } }' | ConvertFrom-Json)

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'reports every inventory shape error together' {
        $config = Get-TestGitHubOrgConfig
        $config.inventory = @'
{
  "owners": ["octocat", "bad login"],
  "apps": [
    { "slug": "octo-app", "repositorySelection": "some", "permissions": { "contents": "own", "Pull-Requests": "read" }, "id": 1 },
    { "slug": "Octo-App", "repositorySelection": "all", "permissions": {} },
    { "slug": "other-app", "repositorySelection": "all", "permissions": "all" },
    "octo-app"
  ],
  "webhookHosts": ["hooks.example.com", "https://hooks.example.com/services/T000"],
  "outsideCollaborators": [],
  "teams": []
}
'@ | ConvertFrom-Json

        $errors = @(Test-GitHubOrgConfig -Config $config)

        Assert-ConfigError -Errors $errors -Path 'inventory.owners[1]' -Part @("'bad login'")
        Assert-ConfigError -Errors $errors -Path "inventory.apps['octo-app'].repositorySelection" -Part @('all, selected', "'some'")
        Assert-ConfigError -Errors $errors -Path "inventory.apps['octo-app'].permissions.contents" -Part @('read, write, admin', "'own'")
        Assert-ConfigError -Errors $errors -Path "inventory.apps['octo-app'].permissions" -Part @("'Pull-Requests'", "lower-case letters and '_'")
        Assert-ConfigError -Errors $errors -Path "inventory.apps['octo-app'].id"
        Assert-ConfigError -Errors $errors -Path "inventory.apps['Octo-App'].slug" -Part @("a slug of lower-case letters, digits and '-'", "'Octo-App'")
        Assert-ConfigError -Errors $errors -Path "inventory.apps['other-app'].permissions" -Part @('"all"')
        Assert-ConfigError -Errors $errors -Path 'inventory.apps[3]' -Part @('"octo-app"')
        Assert-ConfigError -Errors $errors -Path 'inventory.webhookHosts[1]' -Part @('a host name such as hooks.example.com, without scheme, path or port', "'https://hooks.example.com/services/T000'")
        Assert-ConfigError -Errors $errors -Path 'inventory.teams'
        Assert-ConfigError -Errors $errors -Path 'inventory.apps' -Part @("'Octo-App'")
        $errors.Count | Should -Be 11
    }

    It 'requires at least one owner' {
        $config = Get-TestGitHubOrgConfig
        $config.inventory.owners = @()

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path 'inventory.owners' -Only
    }
}
