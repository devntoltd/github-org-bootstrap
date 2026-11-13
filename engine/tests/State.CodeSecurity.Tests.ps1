BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgState: code security' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Progress { }
        $script:config = Get-TestGitHubOrgConfig
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'matches the organization configuration by its exact name, ignoring global configurations' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 17 -Name 'baseline' -TargetType 'global'
            Get-TestCodeSecurityConfiguration -Id 42 -Name 'baseline'
        )
        Register-TestGhRoute -Route $routes

        $codeSecurity = (Get-GitHubOrgState -Config $script:config).CodeSecurity

        $codeSecurity.Configuration.Id | Should -Be 42
        $codeSecurity.Configuration.Description | Should -Be 'Free features'
        $codeSecurity.Configuration.Enforcement | Should -Be 'enforced'
        $codeSecurity.Configuration.Settings.dependabot_alerts | Should -Be 'enabled'
        $codeSecurity.Configuration.Settings.Contains('advanced_security') | Should -BeFalse
    }

    It 'stops when an organization configuration differs from the name only in case' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 42 -Name 'Baseline'
        )
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } |
            Should -Throw "*code security configuration 'Baseline' of 'contoso' differs from codeSecurity.name 'baseline' only in case; use the same spelling in the config, or rename the configuration at https://github.com/organizations/contoso/settings/security_products*"
    }

    It 'stops when the name belongs to <Kind> configuration' -ForEach @(
        @{ Kind = 'a built-in GitHub'; TargetType = 'global'; Name = 'Baseline' }
        @{ Kind = 'an enterprise'; TargetType = 'enterprise'; Name = 'baseline' }
    ) {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 17 -Name $Name -TargetType $TargetType
        )
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } |
            Should -Throw "*'baseline' is the name of $Kind code security configuration; choose another codeSecurity.name*"
    }

    It 'finds the configuration on a later page' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -PageSize 1 -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 17 -Name 'GitHub recommended' -TargetType 'global'
            Get-TestCodeSecurityConfiguration -Id 42
        )
        Register-TestGhRoute -Route $routes

        (Get-GitHubOrgState -Config $script:config).CodeSecurity.Configuration.Id | Should -Be 42
    }

    It 'leaves archived repositories out' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Archived 'repo-old' -Repositories ([ordered]@{
                'repo-a'   = $null
                'repo-old' = $null
            })
        Register-TestGhRoute -Route $routes

        (@((Get-GitHubOrgState -Config $script:config).CodeSecurity.Repositories).Name -join ',') | Should -Be 'repo-a'
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -like 'repos/contoso/repo-old/code-security*' }).Count | Should -Be 0
    }

    It 'reads the default of the matched configuration and the other defaults' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 42
        ) -Defaults @(
            [pscustomobject]@{ default_for_new_repos = 'public'; configuration = (Get-TestCodeSecurityConfiguration -Id 42) }
            [pscustomobject]@{ default_for_new_repos = 'private_and_internal'; configuration = (Get-TestCodeSecurityConfiguration -Id 7 -Name 'legacy') }
        )
        Register-TestGhRoute -Route $routes

        $codeSecurity = (Get-GitHubOrgState -Config $script:config).CodeSecurity

        $codeSecurity.Default | Should -Be 'public'
        @($codeSecurity.OtherDefaults).Count | Should -Be 1
        $codeSecurity.OtherDefaults[0].Name | Should -Be 'legacy'
        $codeSecurity.OtherDefaults[0].DefaultForNewRepos | Should -Be 'private_and_internal'
    }

    It 'reads the repositories of organization and global configurations from their lists, the others one by one' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 17 -Name 'GitHub recommended' -TargetType 'global'
            Get-TestCodeSecurityConfiguration -Id 42
            Get-TestCodeSecurityConfiguration -Id 7 -Name 'legacy'
            Get-TestCodeSecurityConfiguration -Id 99 -Name 'enterprise baseline' -TargetType 'enterprise'
        ) -Repositories ([ordered]@{
                'repo-a' = [pscustomobject]@{ status = 'attaching'; configuration = (Get-TestCodeSecurityConfiguration -Id 42) }
                'repo-b' = $null
                'repo-c' = [pscustomobject]@{ status = 'attached'; configuration = (Get-TestCodeSecurityConfiguration -Id 17 -Name 'GitHub recommended' -TargetType 'global') }
                'repo-d' = [pscustomobject]@{ status = 'removed'; configuration = (Get-TestCodeSecurityConfiguration -Id 7 -Name 'legacy') }
                'repo-e' = [pscustomobject]@{ status = 'enforced'; configuration = (Get-TestCodeSecurityConfiguration -Id 99 -Name 'enterprise baseline' -TargetType 'enterprise') }
            })
        Register-TestGhRoute -Route $routes

        $codeSecurity = (Get-GitHubOrgState -Config $script:config).CodeSecurity

        $repositories = @{}
        foreach ($repository in $codeSecurity.Repositories) {
            $repositories[$repository.Name] = '{0}/{1}/{2}' -f $repository.ConfigurationId, $repository.ConfigurationName, $repository.Status
        }
        $repositories.Count | Should -Be 5
        $repositories['repo-a'] | Should -Be '42/baseline/attaching'
        $repositories['repo-b'] | Should -Be '//'
        $repositories['repo-c'] | Should -Be '17/GitHub recommended/attached'
        $repositories['repo-d'] | Should -Be '7/legacy/removed'
        $repositories['repo-e'] | Should -Be '99/enterprise baseline/enforced'
        # Only the repositories no list answers are read one by one; enterprise configurations are not asked for a list.
        @(Get-TestGhCall | ForEach-Object { $_.Arguments[3] } | Where-Object { $_ -like 'repos/contoso/*/code-security*' }) | Sort-Object |
            Should -Be @('repos/contoso/repo-b/code-security-configuration', 'repos/contoso/repo-e/code-security-configuration')
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -like '*/configurations/99/repositories*' }).Count | Should -Be 0
        @($codeSecurity.SkippedRepositories).Count | Should -Be 0
    }

    It 'reads a repository on its own when its list shows it detached' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Configurations @(
            Get-TestCodeSecurityConfiguration -Id 42
        ) -Repositories ([ordered]@{
                'repo-a' = [pscustomobject]@{ status = 'detached'; configuration = (Get-TestCodeSecurityConfiguration -Id 42) }
            })
        Register-TestGhRoute -Route $routes

        $repository = @((Get-GitHubOrgState -Config $script:config).CodeSecurity.Repositories)[0]

        $repository.Status | Should -Be 'detached'
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -eq 'repos/contoso/repo-a/code-security-configuration' }).Count | Should -Be 1
    }

    It 'skips a repository that is gone by the time its own read runs' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Repositories ([ordered]@{
                'repo-a' = $null
            }) -Vanished 'repo-gone'
        Register-TestGhRoute -Route $routes

        $codeSecurity = (Get-GitHubOrgState -Config $script:config).CodeSecurity

        @($codeSecurity.Repositories).Name | Should -Be @('repo-a')
        @($codeSecurity.SkippedRepositories) | Should -Be @('repo-gone')
    }

    It 'stops when the own read of a repository fails otherwise' {
        $routes = Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Repositories ([ordered]@{
                'repo-a' = $null
            })
        $routes['GET repos/contoso/repo-a/code-security-configuration'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*Cannot read repos/contoso/repo-a/code-security-configuration*HTTP 502*'
    }

    It 'reads every page of the repositories of a configuration' {
        $repositories = [ordered]@{}
        foreach ($i in 1..3) {
            $repositories["repo-$i"] = [pscustomobject]@{ status = 'attached'; configuration = (Get-TestCodeSecurityConfiguration -Id 42) }
        }
        Register-TestGhRoute -Route (Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -PageSize 2 -Configurations @(
                Get-TestCodeSecurityConfiguration -Id 42
            ) -Repositories $repositories)

        @((Get-GitHubOrgState -Config $script:config).CodeSecurity.Repositories | Where-Object { $_.ConfigurationId -eq 42 }).Count | Should -Be 3
    }

    It 'reads every page of repositories' {
        $repositories = [ordered]@{}
        foreach ($i in 1..101) {
            $repositories["repo-$i"] = $null
        }
        Register-TestGhRoute -Route (Add-TestCodeSecurityRoute -Route (Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)) -Repositories $repositories)

        @((Get-GitHubOrgState -Config $script:config).CodeSecurity.Repositories).Count | Should -Be 101
    }

}
