BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    function Get-TestRulesetListItem {
        # A ruleset as GET /orgs/{org}/rulesets lists it (no rules).
        param(
            [Parameter(Mandatory)][long]$Id,
            [Parameter(Mandatory)][string]$Name,
            [string]$SourceType = 'Organization',
            [string]$Target = 'branch',
            [string]$Enforcement = 'active'
        )
        [pscustomobject]@{ id = $Id; name = $Name; target = $Target; source_type = $SourceType; source = 'contoso'; enforcement = $Enforcement }
    }

    function Get-TestRulesetCallCount {
        # How often gh was asked for the endpoint.
        param([Parameter(Mandatory)][string]$Endpoint)
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -eq $Endpoint }).Count
    }
}

Describe 'Get-GitHubOrgState: ruleset' {
    BeforeEach {
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
        $script:config = Get-TestGitHubOrgConfig
        $script:routes = Get-TestGhRoute -State (Get-MatchingTestGitHubOrgState)
        $script:sha = '0123456789abcdef0123456789abcdef01234567'
        $script:sourceKey = ".github/.github/workflows/org-checks.yml@$script:sha"
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'reads the details of the organization ruleset with the configured name once and lists the other organization rulesets' {
        $script:routes['GET orgs/contoso/rulesets?per_page=100'] = Get-TestGhPagesResponse -PageSize 1 -Items @(
            Get-TestRulesetListItem -Id 3 -Name 'default-branch' -SourceType 'Enterprise'
            Get-TestRulesetListItem -Id 7 -Name 'default-branch'
            Get-TestRulesetListItem -Id 9 -Name 'tags' -Target 'tag' -Enforcement 'disabled'
        )
        Register-TestGhRoute -Route $script:routes

        $ruleset = (Get-GitHubOrgState -Config $script:config).Ruleset

        $ruleset.Current.id | Should -Be 7
        $ruleset.Current.rules.type | Should -Contain 'workflows'
        Get-TestRulesetCallCount -Endpoint 'orgs/contoso/rulesets/7' | Should -Be 1
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -match '^orgs/contoso/rulesets/\d+$' }).Count | Should -Be 1
        # The enterprise ruleset is neither the match nor an organization ruleset.
        @($ruleset.OtherRulesets).Count | Should -Be 1
        ($ruleset.OtherRulesets | ForEach-Object { '{0}/{1}/{2}/{3}' -f $_.Id, $_.Name, $_.Target, $_.Enforcement }) |
            Should -Be @('9/tags/tag/disabled')
    }

    It 'has no current ruleset when none has the name' {
        $script:routes['GET orgs/contoso/rulesets?per_page=100'] = Get-TestGhPagesResponse -Items @(Get-TestRulesetListItem -Id 9 -Name 'legacy')
        Register-TestGhRoute -Route $script:routes

        $ruleset = (Get-GitHubOrgState -Config $script:config).Ruleset

        $ruleset.Current | Should -BeNullOrEmpty
        @($ruleset.OtherRulesets).Name | Should -Be @('legacy')
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -match '^orgs/contoso/rulesets/\d+$' }).Count | Should -Be 0
    }

    It 'stops when an organization ruleset differs from the name only in case' {
        $script:routes['GET orgs/contoso/rulesets?per_page=100'] = Get-TestGhPagesResponse -Items @(Get-TestRulesetListItem -Id 7 -Name 'Default-Branch')
        Register-TestGhRoute -Route $script:routes

        { Get-GitHubOrgState -Config $script:config } |
            Should -Throw "The ruleset 'Default-Branch' of 'contoso' differs from ruleset.name 'default-branch' only in case; use the same spelling in the config, or rename the ruleset at https://github.com/organizations/contoso/settings/rules."
    }

    It 'reads a team by its slug and finds its write access under <Role>' -ForEach @(
        @{ Role = 'all_repo_write'; Id = 3 }
        @{ Role = 'all_repo_maintain'; Id = 4 }
        @{ Role = 'all_repo_admin'; Id = 5 }
    ) {
        $script:routes['GET orgs/contoso/organization-roles/3/teams?per_page=100'] = Get-TestGhPagesResponse -Items @()
        $script:routes["GET orgs/contoso/organization-roles/$Id/teams?per_page=100"] = Get-TestGhPagesResponse -Items @([pscustomobject]@{ id = 11; slug = 'platform-admins' })
        Register-TestGhRoute -Route $script:routes

        $team = (Get-GitHubOrgState -Config $script:config).Ruleset.Teams['platform-admins']

        $team.Id | Should -Be 11
        $team.Slug | Should -Be 'platform-admins'
        $team.HasRepositoryWrite | Should -BeTrue
    }

    It 'reads a team without write access to every repository' {
        $script:routes['GET orgs/contoso/organization-roles/3/teams?per_page=100'] = Get-TestGhPagesResponse -Items @([pscustomobject]@{ id = 12; slug = 'developers' })
        $script:routes['GET orgs/contoso/organization-roles/1/teams?per_page=100'] = Get-TestGhPagesResponse -Items @([pscustomobject]@{ id = 11; slug = 'platform-admins' })
        Register-TestGhRoute -Route $script:routes

        (Get-GitHubOrgState -Config $script:config).Ruleset.Teams['platform-admins'].HasRepositoryWrite | Should -BeFalse
    }

    It 'keeps a missing team as $null and reads no organization roles for it' {
        $script:routes.Remove('GET orgs/contoso/teams/platform-admins')
        Register-TestGhRoute -Route $script:routes

        $teams = (Get-GitHubOrgState -Config $script:config).Ruleset.Teams

        $teams.ContainsKey('platform-admins') | Should -BeTrue
        $teams['platform-admins'] | Should -BeNullOrEmpty
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -like 'orgs/contoso/organization-roles*' }).Count | Should -Be 0
    }

    It 'finds a team whose slug the config spells in another case' {
        $script:config.ruleset.rules.pullRequest.requiredReviewers[0].team = 'Platform-Admins'
        Register-TestGhRoute -Route $script:routes

        $teams = (Get-GitHubOrgState -Config $script:config).Ruleset.Teams

        $teams['Platform-Admins'].Id | Should -Be 11
        $teams['platform-admins'].Id | Should -Be 11
        $teams['platform-admins'].HasRepositoryWrite | Should -BeTrue
    }

    It 'stops when a team read fails otherwise' {
        $script:routes['GET orgs/contoso/teams/platform-admins'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $script:routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*Cannot read orgs/contoso/teams/platform-admins*HTTP 502*'
    }

    It 'reads the repository, the Actions access level and the file of a workflow source at its commit' {
        $text = "name: checks`n# caf$([char]0xE9)`n"
        $script:routes['GET repos/contoso/.github'] = Get-TestGhResponse -Body @{ id = 21; name = '.github'; visibility = 'internal' }
        $script:routes['GET repos/contoso/.github/actions/permissions/access'] = Get-TestGhResponse -Body @{ access_level = 'enterprise' }
        $script:routes["GET repos/contoso/.github/contents/.github/workflows/org-checks.yml?ref=$script:sha"] = Get-TestGhResponse -Body (Get-TestGhContent -Path '.github/workflows/org-checks.yml' -Text $text)
        Register-TestGhRoute -Route $script:routes

        $source = (Get-GitHubOrgState -Config $script:config).Ruleset.WorkflowSources[$script:sourceKey]

        $source.RepositoryId | Should -Be 21
        $source.Visibility | Should -Be 'internal'
        $source.AccessLevel | Should -Be 'enterprise'
        $source.Content | Should -BeExactly $text
    }

    It 'keeps a workflow source of a missing repository as $null and reads nothing else of it' {
        $script:routes.Remove('GET repos/contoso/.github')
        Register-TestGhRoute -Route $script:routes

        $sources = (Get-GitHubOrgState -Config $script:config).Ruleset.WorkflowSources

        $sources.ContainsKey($script:sourceKey) | Should -BeTrue
        $sources[$script:sourceKey] | Should -BeNullOrEmpty
        @(Get-TestGhCall | Where-Object { $_.Arguments[3] -like 'repos/contoso/.github/*' }).Count | Should -Be 0
    }

    It 'reads no content for a workflow file that is not there at the commit' {
        $script:routes.Remove("GET repos/contoso/.github/contents/.github/workflows/org-checks.yml?ref=$script:sha")
        Register-TestGhRoute -Route $script:routes

        $source = (Get-GitHubOrgState -Config $script:config).Ruleset.WorkflowSources[$script:sourceKey]

        $source.RepositoryId | Should -Be 21
        $source.Content | Should -BeNullOrEmpty
    }

    It 'reads no Actions access level of a public workflow repository' {
        $script:routes['GET repos/contoso/.github'] = Get-TestGhResponse -Body @{ id = 21; name = '.github'; visibility = 'public' }
        Register-TestGhRoute -Route $script:routes

        $source = (Get-GitHubOrgState -Config $script:config).Ruleset.WorkflowSources[$script:sourceKey]

        $source.Visibility | Should -Be 'public'
        $source.AccessLevel | Should -BeNullOrEmpty
        Get-TestRulesetCallCount -Endpoint 'repos/contoso/.github/actions/permissions/access' | Should -Be 0
        $source.Content | Should -Not -BeNullOrEmpty
    }

    It 'reads no content when the path is a directory at the commit' {
        $script:routes["GET repos/contoso/.github/contents/.github/workflows/org-checks.yml?ref=$script:sha"] = Get-TestGhListResponse -Items @(
            [pscustomobject]@{ type = 'file'; name = 'ci.yml'; path = '.github/workflows/org-checks.yml/ci.yml' }
        )
        Register-TestGhRoute -Route $script:routes

        $source = (Get-GitHubOrgState -Config $script:config).Ruleset.WorkflowSources[$script:sourceKey]

        $null -eq $source.Content | Should -BeTrue
    }

    It 'lists the visibilities of the repositories that are not archived' {
        $script:routes = Add-TestCodeSecurityRoute -Route $script:routes -Archived 'repo-old' -Repositories ([ordered]@{
                'repo-a'   = $null
                'repo-b'   = $null
                'repo-c'   = $null
                'repo-old' = $null
            }) -Visibility @{ 'repo-b' = 'internal'; 'repo-old' = 'public' }
        Register-TestGhRoute -Route $script:routes

        (Get-GitHubOrgState -Config $script:config).Ruleset.RepositoryVisibilities | Should -Be @('internal', 'private')
    }

    It 'reads the Copilot plan and its seats' {
        Register-TestGhRoute -Route $script:routes

        $copilot = (Get-GitHubOrgState -Config $script:config).Ruleset.Copilot

        $copilot.PlanType | Should -Be 'business'
        $copilot.Seats | Should -Be 1
    }

    It 'has no Copilot plan when GitHub answers 404' {
        $script:routes.Remove('GET orgs/contoso/copilot/billing')
        Register-TestGhRoute -Route $script:routes

        (Get-GitHubOrgState -Config $script:config).Ruleset.Copilot | Should -BeNullOrEmpty
    }

    It 'has no Copilot plan when GitHub answers an unconfigured seat management, as for an organization that never bought it' {
        $script:routes['GET orgs/contoso/copilot/billing'] = Get-TestGhResponse -Body (Get-TestCopilotBilling)
        Register-TestGhRoute -Route $script:routes

        (Get-GitHubOrgState -Config $script:config).Ruleset.Copilot | Should -BeNullOrEmpty
    }

    It 'stops when the Copilot plan read fails otherwise' {
        $script:routes['GET orgs/contoso/copilot/billing'] = [pscustomobject]@{ ExitCode = 1; Output = 'gh: Server Error (HTTP 502)' }
        Register-TestGhRoute -Route $script:routes

        { Get-GitHubOrgState -Config $script:config } | Should -Throw '*Cannot read orgs/contoso/copilot/billing*HTTP 502*'
    }

    It 'keeps no Copilot plan while Copilot code review is disabled' {
        $script:config.ruleset.rules.copilotCodeReview.enabled = $false
        Register-TestGhRoute -Route $script:routes

        (Get-GitHubOrgState -Config $script:config).Ruleset.Copilot | Should -BeNullOrEmpty
    }

    It 'reads the Copilot plan once for the ruleset and the seats' {
        Register-TestGhRoute -Route $script:routes

        Get-GitHubOrgState -Config $script:config | Out-Null

        Get-TestRulesetCallCount -Endpoint 'orgs/contoso/copilot/billing' | Should -Be 1
    }

    It 'holds the reference copy of each required workflow found beside the config' {
        Register-TestGhRoute -Route $script:routes
        $directory = Join-Path -Path $TestDrive -ChildPath 'with-reference'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $directory -ChildPath 'org-checks.yml') -Value "name: reference`n" -NoNewline

        $references = (Get-GitHubOrgState -Config $script:config -ConfigDirectory $directory).Ruleset.References

        $references.Keys | Should -Be @('org-checks.yml')
        $references['org-checks.yml'] | Should -BeExactly "name: reference`n"
    }

    It 'holds no reference without a file of that name beside the config' {
        Register-TestGhRoute -Route $script:routes
        $directory = Join-Path -Path $TestDrive -ChildPath 'without-reference'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null

        (Get-GitHubOrgState -Config $script:config -ConfigDirectory $directory).Ruleset.References.Count | Should -Be 0
    }

    It 'shows a progress status for each ruleset read' {
        Register-TestGhRoute -Route $script:routes

        Get-GitHubOrgState -Config $script:config | Out-Null

        # One status per gh call: the organization roles are one list and the teams of three roles, the workflow
        # repository three reads.
        $expected = [ordered]@{
            'rulesets'                      = 1
            "ruleset 'default-branch'"      = 1
            "team 'platform-admins'"        = 1
            'organization roles'            = 4
            "workflow repository '.github'" = 3
            'Copilot plan'                  = 1
        }
        foreach ($expectedStatus in $expected.Keys) {
            Should -Invoke Write-Progress -ModuleName GitHubOrg.Common -Times $expected[$expectedStatus] -Exactly -ParameterFilter { $Status -eq $expectedStatus }
        }
    }
}
