BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Get-GitHubOrgPlan: code security' {
    BeforeAll {
        function Get-TestCodeSecurityPlan {
            param([object]$Config = (Get-TestGitHubOrgConfig), [Parameter(Mandatory)][object]$CodeSecurity)
            $state = Get-MatchingTestGitHubOrgState
            $state.CodeSecurity = $CodeSecurity
            @(Get-GitHubOrgPlan -Config $Config -CurrentState $state)
        }
    }

    It 'creates, makes default and attaches a configuration that does not exist' {
        $config = Get-TestGitHubOrgConfig
        $config.codeSecurity.enforcement = 'unenforced'

        $plan = Get-TestCodeSecurityPlan -Config $config -CodeSecurity (Get-EmptyTestCodeSecurityState)

        ($plan.Action -join ',') | Should -Be 'CreateCodeSecurityConfiguration,SetCodeSecurityDefault,AttachCodeSecurityConfiguration'
        ($plan.Method -join ',') | Should -Be 'POST,PUT,POST'
        $plan.Endpoint | Should -Be @(
            'orgs/contoso/code-security/configurations'
            'orgs/contoso/code-security/configurations/{configuration_id}/defaults'
            'orgs/contoso/code-security/configurations/{configuration_id}/attach'
        )
        (@($plan[0].Body.Keys) -join ',') | Should -Be 'name,enforcement,description,dependency_graph,dependabot_alerts,dependabot_security_updates,private_vulnerability_reporting'
        $plan[0].Body.enforcement | Should -Be 'unenforced'
        $plan[0].Summary | Should -Be "+ create code security configuration 'baseline' (unenforced): dependency_graph: enabled, dependabot_alerts: enabled, dependabot_security_updates: enabled, private_vulnerability_reporting: enabled"
        $plan[1].Body.default_for_new_repos | Should -Be 'all'
        $plan[1].Summary | Should -Be "~ make code security configuration 'baseline' the default for new repositories: <none> -> all"
        $plan[2].Body.scope | Should -Be 'all_without_configurations'
        $plan[2].Summary | Should -Be "+ attach code security configuration 'baseline' to the repositories without one: repo-a, repo-b"
    }

    It 'updates the enforcement of an existing configuration' {
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Configuration.Enforcement = 'unenforced'

        $plan = Get-TestCodeSecurityPlan -CodeSecurity $codeSecurity

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'UpdateCodeSecurityConfiguration'
        (@($plan[0].Body.Keys) -join ',') | Should -Be 'enforcement'
        $plan[0].Summary | Should -Be "~ update code security configuration 'baseline': enforcement: unenforced -> enforced"
    }

    It 'plans nothing when the configuration matches and every repository has it' {
        @(Get-TestCodeSecurityPlan -CodeSecurity (Get-MatchingTestCodeSecurityState)).Count | Should -Be 0
    }

    It 'updates only the differing fields of an existing configuration' {
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Configuration.Settings.dependabot_security_updates = 'disabled'
        $codeSecurity.Configuration.Description = 'old'

        $plan = Get-TestCodeSecurityPlan -CodeSecurity $codeSecurity

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'UpdateCodeSecurityConfiguration'
        $plan[0].Method | Should -Be 'PATCH'
        $plan[0].Endpoint | Should -Be 'orgs/contoso/code-security/configurations/42'
        (@($plan[0].Body.Keys) -join ',') | Should -Be 'description,dependabot_security_updates'
        $plan[0].Summary | Should -Be "~ update code security configuration 'baseline': description: 'old' -> 'Free features'; dependabot_security_updates: disabled -> enabled"
    }

    It 'enables private vulnerability reporting in an existing configuration' {
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Configuration.Settings.private_vulnerability_reporting = 'disabled'

        $plan = Get-TestCodeSecurityPlan -CodeSecurity $codeSecurity

        @($plan[0].Body.Keys) | Should -Be @('private_vulnerability_reporting')
        $plan[0].Body.private_vulnerability_reporting | Should -Be 'enabled'
    }

    It 'names the configurations it replaces as default' {
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Default = $null
        $codeSecurity.OtherDefaults = @(
            [pscustomobject]@{ Name = 'legacy'; DefaultForNewRepos = 'private_and_internal' }
        )

        $plan = Get-TestCodeSecurityPlan -CodeSecurity $codeSecurity

        $plan[0].Action | Should -Be 'SetCodeSecurityDefault'
        $plan[0].Endpoint | Should -Be 'orgs/contoso/code-security/configurations/42/defaults'
        $plan[0].Summary | Should -BeLike "*: <none> -> all; replaces 'legacy' (private_and_internal)"
    }

    It 'does not name a default whose visibility does not overlap' {
        $config = Get-TestGitHubOrgConfig
        $config.codeSecurity.default_for_new_repos = 'public'
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Default = $null
        $codeSecurity.OtherDefaults = @([pscustomobject]@{ Name = 'legacy'; DefaultForNewRepos = 'private_and_internal' })

        $plan = Get-TestCodeSecurityPlan -Config $config -CodeSecurity $codeSecurity

        $plan[0].Summary | Should -BeLike '*: <none> -> public'
    }

    It 'treats a configuration that is not a default as none' {
        $config = Get-TestGitHubOrgConfig
        $config.codeSecurity.default_for_new_repos = 'none'
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Default = $null

        @(Get-TestCodeSecurityPlan -Config $config -CodeSecurity $codeSecurity).Count | Should -Be 0
    }

    It 'does not attach when every repository without our configuration has another one' {
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Repositories[1].ConfigurationId = 7
        $codeSecurity.Repositories[1].ConfigurationName = 'legacy'

        @(Get-TestCodeSecurityPlan -CodeSecurity $codeSecurity).Count | Should -Be 0
    }

    It 'attaches an existing configuration by its id' {
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Repositories[1].ConfigurationId = $null
        $codeSecurity.Repositories[1].ConfigurationName = $null

        $plan = Get-TestCodeSecurityPlan -CodeSecurity $codeSecurity

        $plan[0].Action | Should -Be 'AttachCodeSecurityConfiguration'
        $plan[0].Endpoint | Should -Be 'orgs/contoso/code-security/configurations/42/attach'
        $plan[0].Summary | Should -BeLike '*: repo-b'
    }
}

Describe 'Get-GitHubOrgWarning: code security' {
    It 'reports a repository with another configuration' {
        $state = Get-MatchingTestGitHubOrgState
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Repositories[1].ConfigurationId = 7
        $codeSecurity.Repositories[1].ConfigurationName = 'legacy'
        $state.CodeSecurity = $codeSecurity

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @() |
            Should -Be "Repository 'repo-b' uses code security configuration 'legacy', not 'baseline'. The engine leaves it alone; to switch it, open https://github.com/organizations/contoso/settings/security_products and apply 'baseline' to the repository."
    }

    It 'reports a failed attachment' {
        $state = Get-MatchingTestGitHubOrgState
        $codeSecurity = Get-MatchingTestCodeSecurityState
        $codeSecurity.Repositories[0].Status = 'failed'
        $state.CodeSecurity = $codeSecurity

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @() |
            Should -Be "Attaching code security configuration 'baseline' to repository 'repo-a' failed. Open https://github.com/organizations/contoso/settings/security_products to see why, then re-run."
    }

    It 'reports a repository where the configuration is <Status>' -ForEach @(
        @{ Status = 'removed'; Meaning = 'a repository admin changed a setting it controls' }
        @{ Status = 'removed_by_enterprise'; Meaning = 'an enterprise configuration conflicts with it' }
        @{ Status = 'detached'; Meaning = 'the repository is detached from it' }
        @{ Status = 'some_new_status'; Meaning = 'GitHub reports the status some_new_status' }
    ) {
        $state = Get-MatchingTestGitHubOrgState
        $state.CodeSecurity.Repositories[0].Status = $Status

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @() |
            Should -Be "Code security configuration 'baseline' is not in effect on repository 'repo-a': $Meaning ($Status). The engine does not re-attach it; open https://github.com/organizations/contoso/settings/security_products and apply 'baseline' to the repository again."
    }

    It 'does not report a repository where the configuration is <_>' -ForEach @('attached', 'attaching', 'updating', 'enforced', 'enterprise_enforced') {
        $state = Get-MatchingTestGitHubOrgState
        $state.CodeSecurity.Repositories[0].Status = $_

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @() | Should -BeNullOrEmpty
    }

    It 'reports a repository that was gone before its configuration could be read' {
        $state = Get-MatchingTestGitHubOrgState
        $state.CodeSecurity.SkippedRepositories = @('repo-gone')

        Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @() |
            Should -Be "Repository 'repo-gone' was listed, but its code security configuration could not be read: GitHub answered 404 (deleted, renamed or transferred during the run, or the gh account cannot see it). It is left out of this run; re-run to check it."
    }

    It 'reports every attached repository as another configuration when ours does not exist yet' {
        $state = Get-MatchingTestGitHubOrgState
        $codeSecurity = Get-EmptyTestCodeSecurityState
        $codeSecurity.Repositories[0].ConfigurationId = 7
        $codeSecurity.Repositories[0].ConfigurationName = 'legacy'
        $state.CodeSecurity = $codeSecurity

        @(Get-GitHubOrgWarning -Config (Get-TestGitHubOrgConfig) -CurrentState $state -Plan @()).Count | Should -Be 1
    }
}
