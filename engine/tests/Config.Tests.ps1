BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/Bootstrap.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')
}

Describe 'Test-GitHubOrgConfig' {
    It 'accepts a complete config' {
        Test-GitHubOrgConfig -Config (Get-TestGitHubOrgConfig) | Should -BeNullOrEmpty
    }

    It 'accepts an empty pattern list' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.selected.patterns_allowed = @()

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'requires the <Path> section' -ForEach @(
        @{ Path = 'organization' }
        @{ Path = 'inventory' }
        @{ Path = 'codeSecurity' }
        @{ Path = 'ruleset' }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.PSObject.Properties.Remove($Path)

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $Path -Only
    }

    It 'requires <Path>' -ForEach @(
        @{ Path = 'settings.email'; Remove = { param($c) $c.settings.PSObject.Properties.Remove('email') } }
        @{ Path = 'settings.members_can_invite_outside_collaborators'; Remove = { param($c) $c.settings.PSObject.Properties.Remove('members_can_invite_outside_collaborators') } }
        @{ Path = 'actions.enabled_repositories'; Remove = { param($c) $c.actions.PSObject.Properties.Remove('enabled_repositories') } }
        @{ Path = 'codeSecurity.description'; Remove = { param($c) $c.codeSecurity.PSObject.Properties.Remove('description') } }
        @{ Path = 'codeSecurity.settings.dependabot_alerts'; Remove = { param($c) $c.codeSecurity.settings.PSObject.Properties.Remove('dependabot_alerts') } }
    ) {
        $config = Get-TestGitHubOrgConfig
        & $Remove $config

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $Path -Only
    }

    It 'requires every endpoint section, since a section without setting rows would not be validated' {
        $sections = InModuleScope GitHubOrg { @($script:Sections.Keys) }

        foreach ($section in $sections) {
            $config = Get-TestGitHubOrgConfig
            $parent = $config
            $parts = $section.Split('.')
            foreach ($part in ($parts | Select-Object -SkipLast 1)) {
                $parent = $parent.$part
            }
            $parent.PSObject.Properties.Remove($parts[-1])

            Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $section -Only
        }
    }

    It 'puts every row in a section of the shape' {
        $bad = InModuleScope GitHubOrg {
            $fields = (Get-GitHubOrgConfigShape).Fields
            @($script:SettingDefinitions | Where-Object { -not $fields.Contains($_.Section.Split('.')[0]) } | ForEach-Object { Get-SettingPath -Definition $_ })
        }

        $bad | Should -BeNullOrEmpty
    }

    It 'describes why a row has no recommendation, after its own description' {
        $nodes = InModuleScope GitHubOrg {
            $rows = @{
                Described = @{ Section = 'settings'; Field = 'probe_a'; Type = 'boolean'; Mode = 'manual'; Description = 'A probe.'; NoRecommendation = 'Owner decides: a reason.' }
                Bare      = @{ Section = 'settings'; Field = 'probe_b'; Type = 'boolean'; Mode = 'manual'; NoRecommendation = 'Project data: a reason.' }
            }
            @{
                Described = ConvertTo-SettingNode -Definition $rows.Described
                Bare      = ConvertTo-SettingNode -Definition $rows.Bare
            }
        }

        $nodes.Described.Description | Should -Be 'A probe. Owner decides: a reason.'
        $nodes.Bare.Description | Should -Be 'Project data: a reason.'
        $nodes.Bare.Contains('Recommended') | Should -BeFalse
    }

    It 'adds a section by subject with its first row: <Section>' -ForEach @(
        @{ Section = 'probeSection' }
        @{ Section = 'probeSection.nested' }
    ) {
        $shape = InModuleScope GitHubOrg -Parameters @{ Section = $Section } {
            $saved = $script:SettingDefinitions
            $savedTop = $script:TopLevelSections
            $script:TopLevelSections = @($script:TopLevelSections) + 'probeSection'
            $script:SettingDefinitions = @($script:SettingDefinitions) + @(@{ Section = $Section; Field = 'probe'; Type = 'boolean'; Mode = 'manual'; Page = 'security'; UiGroup = 'Probe'; Why = 'A probe.' })
            $script:ConfigSections = @($script:SettingDefinitions | ForEach-Object { $_.Section } | Select-Object -Unique)
            try {
                $with = Get-GitHubOrgConfigShape
                $script:SettingDefinitions = $saved
                $script:ConfigSections = @($script:SettingDefinitions | ForEach-Object { $_.Section } | Select-Object -Unique)
                @{ With = $with; Without = Get-GitHubOrgConfigShape }
            }
            finally {
                $script:SettingDefinitions = $saved
                $script:TopLevelSections = $savedTop
                $script:ConfigSections = @($script:SettingDefinitions | ForEach-Object { $_.Section } | Select-Object -Unique)
            }
        }
        $top = $Section.Split('.')[0]

        $node = $shape.With.Fields[$top]
        foreach ($part in @($Section.Split('.') | Select-Object -Skip 1)) {
            $node = $node.Fields[$part]
        }
        $node.Fields['probe'].Type | Should -Be 'boolean'
        @($shape.With.Fields.Keys)[-1] | Should -Be 'exceptions'
        $shape.Without.Fields.Contains($top) | Should -BeFalse
    }

    It 'reports the same rule for an invalid login in every field' {
        $config = Get-TestGitHubOrgConfig
        $config.organization = 'bad name'
        $config.inventory.owners = @('octocat', 'bad login')

        $errors = @(Test-GitHubOrgConfig -Config $config)

        # The rule of the shared pattern, not the wording of the error: the test of Get-ConfigPatternNode.
        Assert-ConfigError -Errors $errors -Path 'organization' -Part "a GitHub login of letters, digits and '-'", "'bad name'"
        Assert-ConfigError -Errors $errors -Path 'inventory.owners[1]' -Part "a GitHub login of letters, digits and '-'", "'bad login'"
    }

    It 'reports every shape error together' {
        $config = Get-TestGitHubOrgConfig
        $config.organization = 'bad name'
        $config | Add-Member -NotePropertyName repositories -NotePropertyValue @()
        $config.settings | Add-Member -NotePropertyName members_can_create_internal_repositories -NotePropertyValue $false
        $config.settings.members_can_create_repositories = 'false'
        $config.settings.default_repository_permission = 'Read'
        $config.actions.enabled_repositories = 'selected'
        $config.actions.selected.patterns_allowed = @('azure/login@*', 'has space', '')
        $config.actions.workflow.can_approve_pull_request_reviews = 1

        $errors = @(Test-GitHubOrgConfig -Config $config)

        Assert-ConfigError -Errors $errors -Path 'organization' -Part @("'bad name'")
        Assert-ConfigError -Errors $errors -Path 'repositories'
        Assert-ConfigError -Errors $errors -Path 'settings.members_can_create_internal_repositories'
        Assert-ConfigError -Errors $errors -Path 'settings.members_can_create_repositories' -Part @('"false"')
        Assert-ConfigError -Errors $errors -Path 'settings.default_repository_permission' -Part @('read, write, admin, none', "'Read'")
        Assert-ConfigError -Errors $errors -Path 'actions.enabled_repositories' -Part @('all, none', "'selected'")
        Assert-ConfigError -Errors $errors -Path 'actions.selected.patterns_allowed[1]' -Part @('a non-empty string without whitespace', "'has space'")
        Assert-ConfigError -Errors $errors -Path 'actions.selected.patterns_allowed[2]' -Part @('a non-empty string without whitespace', "''")
        Assert-ConfigError -Errors $errors -Path 'actions.workflow.can_approve_pull_request_reviews' -Part @('1')
        $errors.Count | Should -Be 9
    }

    It 'accepts actions.selected as null when allowed_actions is not selected' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.allowed_actions = 'all'
        $config.actions.selected = $null

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'rejects a selection unless allowed_actions is selected' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.allowed_actions = 'all'

        Test-GitHubOrgConfig -Config $config | Should -Be "actions.selected must be null unless actions.allowed_actions is 'selected'; GitHub rejects the list otherwise."
    }

    It 'requires a selection when allowed_actions is selected' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.selected = $null

        Test-GitHubOrgConfig -Config $config | Should -Be "actions.selected must be an object when actions.allowed_actions is 'selected': it is the list of allowed actions, and GitHub keeps whatever list it has stored otherwise."
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a section that is not an object'; Mutate = { param($c) $c.actions = 'all' }; Path = 'actions'; Part = @('"all"') }
        @{ Name = 'a pattern list that is not a list'; Mutate = { param($c) $c.actions.selected.patterns_allowed = 'azure/login@*' }; Path = 'actions.selected.patterns_allowed'; Part = @('"azure/login@*"') }
        @{ Name = 'a nested section set to null'; Mutate = { param($c) $c.actions.workflow = $null }; Path = 'actions.workflow'; Part = @() }
        @{ Name = 'a top-level section set to null'; Mutate = { param($c) $c.settings = $null }; Path = 'settings'; Part = @() }
        @{ Name = 'an organization that is not a string'; Mutate = { param($c) $c.organization = @('contoso') }; Path = 'organization'; Part = @('["contoso"]') }
        @{ Name = 'a code security settings section set to null'; Mutate = { param($c) $c.codeSecurity.settings = $null }; Path = 'codeSecurity.settings'; Part = @() }
        @{ Name = 'an enforcement that is not known'; Mutate = { param($c) $c.codeSecurity.enforcement = 'strict' }; Path = 'codeSecurity.enforcement'; Part = @('enforced, unenforced', "'strict'") }
        @{ Name = 'a null code security name'; Mutate = { param($c) $c.codeSecurity.name = $null }; Path = 'codeSecurity.name'; Part = @() }
        @{ Name = 'an empty code security name'; Mutate = { param($c) $c.codeSecurity.name = '' }; Path = 'codeSecurity.name'; Part = @('a non-empty name without leading or trailing whitespace', "''") }
        @{ Name = 'a code security name with a leading space'; Mutate = { param($c) $c.codeSecurity.name = ' baseline' }; Path = 'codeSecurity.name'; Part = @('a non-empty name without leading or trailing whitespace', "' baseline'") }
    ) {
        $config = Get-TestGitHubOrgConfig
        & $Mutate $config

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $Path -Part $Part -Only
    }

    It 'accepts a null code security description' {
        $config = Get-TestGitHubOrgConfig
        $config.codeSecurity.description = $null

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'reports every code security error together' {
        $config = Get-TestGitHubOrgConfig
        $config.codeSecurity.default_for_new_repos = 'private'
        $config.codeSecurity.description = 5
        $config.codeSecurity | Add-Member -NotePropertyName secret_protection -NotePropertyValue 'enabled'
        $config.codeSecurity.settings.dependabot_alerts = 'on'
        $config.codeSecurity.settings | Add-Member -NotePropertyName secret_scanning -NotePropertyValue 'enabled'

        $errors = @(Test-GitHubOrgConfig -Config $config)

        Assert-ConfigError -Errors $errors -Path 'codeSecurity.default_for_new_repos' -Part @('all, none, private_and_internal, public', "'private'")
        Assert-ConfigError -Errors $errors -Path 'codeSecurity.description' -Part @('5')
        Assert-ConfigError -Errors $errors -Path 'codeSecurity.secret_protection'
        Assert-ConfigError -Errors $errors -Path 'codeSecurity.settings.dependabot_alerts' -Part @('enabled, disabled, not_set', "'on'")
        Assert-ConfigError -Errors $errors -Path 'codeSecurity.settings.secret_scanning'
        $errors.Count | Should -Be 5
    }

    It 'rejects a public email that is not an address: <Json>' -ForEach @(
        @{ Json = '"contoso.com"'; Path = 'settings.email'; Part = @('an email address such as security@example.com', "'contoso.com'") }
        @{ Json = '"security@contoso"'; Path = 'settings.email'; Part = @('an email address such as security@example.com', "'security@contoso'") }
        @{ Json = '"a b@contoso.com"'; Path = 'settings.email'; Part = @('an email address such as security@example.com', "'a b@contoso.com'") }
        @{ Json = '""'; Path = 'settings.email'; Part = @('an email address such as security@example.com', "''") }
        @{ Json = 'null'; Path = 'settings.email'; Part = @() }
        @{ Json = '42'; Path = 'settings.email'; Part = @('42') }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.settings.email = ConvertFrom-Json -InputObject $Json

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $Path -Part $Part -Only
    }

    It 'reports every Actions policy error together' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.deploy_keys_enabled_for_repositories = 'no'
        $config.actions.selfHostedRunners.enabled_repositories = 'selected'
        $config.actions.forkPullRequests.approval_policy = 'everyone'
        $config.actions.privateForkPullRequests.send_secrets_and_variables = 0
        $config.actions.retention | Add-Member -NotePropertyName maximum_allowed_days -NotePropertyValue 400

        $errors = @(Test-GitHubOrgConfig -Config $config)

        Assert-ConfigError -Errors $errors -Path 'settings.deploy_keys_enabled_for_repositories' -Part @('"no"')
        Assert-ConfigError -Errors $errors -Path 'actions.selfHostedRunners.enabled_repositories' -Part @('all, none', "'selected'")
        Assert-ConfigError -Errors $errors -Path 'actions.forkPullRequests.approval_policy' -Part @('first_time_contributors_new_to_github, first_time_contributors, all_external_contributors', "'everyone'")
        Assert-ConfigError -Errors $errors -Path 'actions.privateForkPullRequests.send_secrets_and_variables' -Part @('0')
        Assert-ConfigError -Errors $errors -Path 'actions.retention.maximum_allowed_days'
        $errors.Count | Should -Be 5
    }

    It 'requires a whole number of retention days of at least 1, not <Json>' -ForEach @(
        @{ Json = '"30"'; Path = 'actions.retention.days'; Part = @('"30"') }
        @{ Json = '30.0'; Path = 'actions.retention.days'; Part = @('30.0') }
        @{ Json = '1.5'; Path = 'actions.retention.days'; Part = @('1.5') }
        @{ Json = '0'; Path = 'actions.retention.days'; Part = @('0') }
        @{ Json = '-1'; Path = 'actions.retention.days'; Part = @('-1') }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.actions.retention = "{ `"days`": $Json }" | ConvertFrom-Json

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $Path -Part $Part -Only
    }

    It 'rejects a repository access of the Copilot cloud agent GitHub does not know' {
        $config = Get-TestGitHubOrgConfig
        $config.copilotCloudAgent.enabled_repositories = 'some'

        Assert-ConfigError -Errors (Test-GitHubOrgConfig -Config $config) -Path 'copilotCloudAgent.enabled_repositories' -Part @('all', 'selected', 'none') -Only
    }

    It 'rejects a budget of <Case>' -ForEach @(
        @{ Case = 'an unknown type'; Field = 'budget_type'; Value = 'Free'; Part = 'ProductPricing' }
        @{ Case = 'a product name with spaces'; Field = 'budget_product_sku'; Value = 'Git LFS'; Part = 'Git LFS' }
        @{ Case = 'a negative amount'; Field = 'budget_amount'; Value = -1; Part = '-1' }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.budgets[0].$Field = $Value

        @(Test-GitHubOrgConfig -Config $config | Where-Object { $_ -like "*$Field*" -and $_ -like "*$Part*" }).Count | Should -Be 1
    }

    It 'rejects two budgets of one product' {
        $config = Get-TestGitHubOrgConfig
        $config.budgets[1].budget_product_sku = 'actions'

        @(Test-GitHubOrgConfig -Config $config) | Should -Not -BeNullOrEmpty
    }

    It 'accepts a config without budgets to manage' {
        $config = Get-TestGitHubOrgConfig
        $config.budgets = @()

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'rejects a Copilot seat of <Case>' -ForEach @(
        @{ Case = 'a login with spaces'; Field = 'selected_usernames'; Value = 'not a login' }
        @{ Case = 'a team slug with spaces'; Field = 'selected_teams'; Value = 'not a team' }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.copilotSeats.$Field = @($Value)

        Assert-ConfigError -Errors (Test-GitHubOrgConfig -Config $config) -Path "copilotSeats.$Field[0]" -Part @($Value) -Only
    }

    It 'rejects a login listed twice for a Copilot seat, in any case' {
        $config = Get-TestGitHubOrgConfig
        $config.copilotSeats.selected_usernames = @('octocat', 'OctoCat')

        @(Test-GitHubOrgConfig -Config $config) | Should -Not -BeNullOrEmpty
    }

    It 'accepts a config without Copilot seats' {
        $config = Get-TestGitHubOrgConfig
        $config.copilotSeats.selected_usernames = @()

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'accepts the minimum of 1 retention day' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.retention = '{ "days": 1 }' | ConvertFrom-Json

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'reports every duplicate together, compared case-insensitively' {
        $config = Get-TestGitHubOrgConfig
        $config.inventory.owners = @('octocat', 'OctoCat')
        $config.inventory.outsideCollaborators = @('hubot', 'HUBOT')
        $config.inventory.webhookHosts = @('hooks.example.com', 'HOOKS.example.com')
        $config.inventory.apps = @(
            '{ "slug": "octo-app", "repositorySelection": "all", "permissions": {} }' | ConvertFrom-Json
            '{ "slug": "octo-app", "repositorySelection": "all", "permissions": {} }' | ConvertFrom-Json
        )
        $config.actions.selected.patterns_allowed = @('azure/login@*', 'Azure/Login@*')

        $errors = @(Test-GitHubOrgConfig -Config $config)

        $errors.Count | Should -Be 5
        Assert-ConfigError -Errors $errors -Path 'inventory.owners' -Part "'OctoCat'"
        Assert-ConfigError -Errors $errors -Path 'inventory.apps' -Part "'octo-app'"
        Assert-ConfigError -Errors $errors -Path 'inventory.webhookHosts' -Part "'HOOKS.example.com'"
        Assert-ConfigError -Errors $errors -Path 'inventory.outsideCollaborators' -Part "'HUBOT'"
        Assert-ConfigError -Errors $errors -Path 'actions.selected.patterns_allowed' -Part "'Azure/Login@*'"
    }

    Context 'exceptions' {
        BeforeAll {
            $script:today = [datetime]'2026-10-02'

            function Get-ConfigWithException {
                param([string]$Field = 'settings.members_can_invite_outside_collaborators', [string]$ExpiresOn = '2027-04-01')
                $config = Get-TestGitHubOrgConfig
                $config.settings.members_can_invite_outside_collaborators = $true
                $config.exceptions = @("{ `"field`": `"$Field`", `"category`": `"waiver`", `"reason`": `"Free plan`", `"expiresOn`": `"$ExpiresOn`", `"reference`": `"https://example.com/issues/1`" }" | ConvertFrom-Json)
                return $config
            }
        }

        It 'requires the exceptions list' {
            $config = Get-TestGitHubOrgConfig
            $config.PSObject.Properties.Remove('exceptions')

            Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config -Today $script:today) -Path 'exceptions' -Only
        }

        It 'accepts an exception for a field with a recommendation' {
            Test-GitHubOrgConfig -Config (Get-ConfigWithException) -Today $script:today | Should -BeNullOrEmpty
        }

        It 'rejects an exception for <Field>' -ForEach @(
            @{ Field = 'settings.email' }
            @{ Field = 'settings.unknown' }
        ) {
            $errors = @(Test-GitHubOrgConfig -Config (Get-ConfigWithException -Field $Field) -Today $script:today)

            Assert-ConfigError -Errors $errors -Path "exceptions['$Field']" -Part "'$Field' is not a field with a recommended value or a rule." -Only
        }

        It 'rejects an exception more than a year ahead' {
            $errors = @(Test-GitHubOrgConfig -Config (Get-ConfigWithException -ExpiresOn '2027-10-03') -Today $script:today)

            Assert-ConfigError -Errors $errors -Path "exceptions['settings.members_can_invite_outside_collaborators'].expiresOn" -Part '2027-10-02', "'2027-10-03'" -Only
        }

        It 'checks exceptions only once the shape is valid' {
            $config = Get-ConfigWithException -ExpiresOn '2027-10-03'
            $config.organization = 'bad name'

            @(Test-GitHubOrgConfig -Config $config -Today $script:today).Count | Should -Be 1
        }
    }

    Context 'ruleset' {
        It 'rejects <Name>' -ForEach @(
            @{ Name = 'a null ruleset'; Mutate = { param($c) $c.ruleset = $null }; Path = 'ruleset'; Part = @() }
            @{ Name = 'an empty name'; Mutate = { param($c) $c.ruleset.name = '' }; Path = 'ruleset.name'; Part = @('a non-empty name without leading or trailing whitespace', "''") }
            @{ Name = 'the enforcement evaluate'; Mutate = { param($c) $c.ruleset.enforcement = 'evaluate' }; Path = 'ruleset.enforcement'; Part = @('active, disabled', "'evaluate'") }
            @{ Name = 'an admin bypass always'; Mutate = { param($c) $c.ruleset.bypass.organizationAdmin = 'always' }; Path = 'ruleset.bypass.organizationAdmin'; Part = @('pull_request, none', "'always'") }
            @{ Name = 'a deletion rule that is not a boolean'; Mutate = { param($c) $c.ruleset.rules.deletion = 'true' }; Path = 'ruleset.rules.deletion'; Part = @('"true"') }
            @{ Name = 'more than 10 approvals'; Mutate = { param($c) $c.ruleset.rules.pullRequest.required_approving_review_count = 11 }; Path = 'ruleset.rules.pullRequest.required_approving_review_count'; Part = @('10', '11') }
            @{ Name = 'a negative number of approvals'; Mutate = { param($c) $c.ruleset.rules.pullRequest.required_approving_review_count = -1 }; Path = 'ruleset.rules.pullRequest.required_approving_review_count'; Part = @('0', '-1') }
            @{ Name = 'no merge method'; Mutate = { param($c) $c.ruleset.rules.pullRequest.allowed_merge_methods = @() }; Path = 'ruleset.rules.pullRequest.allowed_merge_methods'; Part = @() }
            @{ Name = 'an unknown merge method'; Mutate = { param($c) $c.ruleset.rules.pullRequest.allowed_merge_methods = @('merge', 'fast') }; Path = 'ruleset.rules.pullRequest.allowed_merge_methods[1]'; Part = @('merge, squash, rebase', "'fast'") }
            @{ Name = 'a repeated merge method'; Mutate = { param($c) $c.ruleset.rules.pullRequest.allowed_merge_methods = @('merge', 'merge') }; Path = 'ruleset.rules.pullRequest.allowed_merge_methods'; Part = @("'merge'") }
            @{ Name = 'a team listed twice in another case'; Mutate = { param($c) $c.ruleset.rules.pullRequest.requiredReviewers += ('{ "team": "Platform-Admins", "minimum_approvals": 1, "file_patterns": ["**"] }' | ConvertFrom-Json) }; Path = 'ruleset.rules.pullRequest.requiredReviewers'; Part = @("'Platform-Admins'") }
            @{ Name = 'a team that is not a slug'; Mutate = { param($c) $c.ruleset.rules.pullRequest.requiredReviewers[0].team = 'platform admins' }; Path = "ruleset.rules.pullRequest.requiredReviewers['platform admins'].team"; Part = @("'platform admins'") }
            @{ Name = 'more than 10 approvals of a team'; Mutate = { param($c) $c.ruleset.rules.pullRequest.requiredReviewers[0].minimum_approvals = 11 }; Path = "ruleset.rules.pullRequest.requiredReviewers['platform-admins'].minimum_approvals"; Part = @('10', '11') }
            @{ Name = 'no file pattern'; Mutate = { param($c) $c.ruleset.rules.pullRequest.requiredReviewers[0].file_patterns = @() }; Path = "ruleset.rules.pullRequest.requiredReviewers['platform-admins'].file_patterns"; Part = @() }
            @{ Name = 'an empty file pattern'; Mutate = { param($c) $c.ruleset.rules.pullRequest.requiredReviewers[0].file_patterns = @('**', '') }; Path = "ruleset.rules.pullRequest.requiredReviewers['platform-admins'].file_patterns[1]"; Part = @("''") }
            @{ Name = 'no central workflow'; Mutate = { param($c) $c.ruleset.rules.workflows = @() }; Path = 'ruleset.rules.workflows'; Part = @() }
            @{ Name = 'a commit SHA of 39 characters'; Mutate = { param($c) $c.ruleset.rules.workflows[0].sha = '0123456789abcdef0123456789abcdef0123456' }; Path = 'ruleset.rules.workflows[0].sha'; Part = @('40 lower-case hexadecimal characters') }
            @{ Name = 'an upper-case commit SHA'; Mutate = { param($c) $c.ruleset.rules.workflows[0].sha = '0123456789ABCDEF0123456789abcdef01234567' }; Path = 'ruleset.rules.workflows[0].sha'; Part = @('40 lower-case hexadecimal characters') }
            @{ Name = 'a workflow outside .github/workflows'; Mutate = { param($c) $c.ruleset.rules.workflows[0].path = 'workflows/x.yml' }; Path = 'ruleset.rules.workflows[0].path'; Part = @('a file under .github/workflows/', "'workflows/x.yml'") }
            @{ Name = 'a repository name with a slash'; Mutate = { param($c) $c.ruleset.rules.workflows[0].repository = 'contoso/.github' }; Path = 'ruleset.rules.workflows[0].repository'; Part = @("'contoso/.github'") }
            @{ Name = 'a null Copilot code review'; Mutate = { param($c) $c.ruleset.rules.copilotCodeReview = $null }; Path = 'ruleset.rules.copilotCodeReview'; Part = @() }
            @{ Name = 'a Copilot review on push that is not a boolean'; Mutate = { param($c) $c.ruleset.rules.copilotCodeReview.review_on_push = 'yes' }; Path = 'ruleset.rules.copilotCodeReview.review_on_push'; Part = @('"yes"') }
            @{ Name = 'a Copilot review without the draft setting'; Mutate = { param($c) $c.ruleset.rules.copilotCodeReview.PSObject.Properties.Remove('review_draft_pull_requests') }; Path = 'ruleset.rules.copilotCodeReview.review_draft_pull_requests'; Part = @() }
        ) {
            $config = Get-TestGitHubOrgConfig
            & $Mutate $config

            Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path $Path -Part $Part -Only
        }

        It 'accepts no required approval, which differs from the recommendation' {
            $config = Get-TestGitHubOrgConfig
            $config.ruleset.rules.pullRequest.required_approving_review_count = 0

            Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
            $warnings = @((Get-RecommendationReport -Config $config -Shape (Get-GitHubOrgConfigShape) -Today ([datetime]'2026-11-03')).Warnings)
            $warnings.Count | Should -Be 1
            $warnings[0] | Should -BeLike 'ruleset.rules.pullRequest.required_approving_review_count is 0; recommended 1: *'
        }

        It 'recommends <Path> = <Json>' -ForEach @(
            @{ Path = 'ruleset.enforcement'; Json = '"disabled"'; Mutate = { param($c) $c.ruleset.enforcement = 'disabled' } }
            @{ Path = 'ruleset.bypass.organizationAdmin'; Json = '"none"'; Mutate = { param($c) $c.ruleset.bypass.organizationAdmin = 'none' } }
            @{ Path = 'ruleset.rules.non_fast_forward'; Json = 'false'; Mutate = { param($c) $c.ruleset.rules.non_fast_forward = $false } }
            @{ Path = 'ruleset.rules.pullRequest.require_extra_approval_for_unattributed_changes'; Json = 'false'; Mutate = { param($c) $c.ruleset.rules.pullRequest.require_extra_approval_for_unattributed_changes = $false } }
            @{ Path = 'ruleset.rules.pullRequest.allowed_merge_methods'; Json = '["merge","squash"]'; Mutate = { param($c) $c.ruleset.rules.pullRequest.allowed_merge_methods = @('merge', 'squash') } }
            @{ Path = 'ruleset.rules.copilotCodeReview.enabled'; Json = 'false'; Mutate = { param($c) $c.ruleset.rules.copilotCodeReview.enabled = $false } }
            @{ Path = 'ruleset.rules.copilotCodeReview.review_on_push'; Json = 'false'; Mutate = { param($c) $c.ruleset.rules.copilotCodeReview.review_on_push = $false } }
            @{ Path = 'ruleset.rules.copilotCodeReview.review_draft_pull_requests'; Json = 'true'; Mutate = { param($c) $c.ruleset.rules.copilotCodeReview.review_draft_pull_requests = $true } }
        ) {
            $config = Get-TestGitHubOrgConfig
            & $Mutate $config

            $warnings = @((Get-RecommendationReport -Config $config -Shape (Get-GitHubOrgConfigShape) -Today ([datetime]'2026-11-03')).Warnings)

            $warnings.Count | Should -Be 1
            $warnings[0] | Should -BeLike "$([WildcardPattern]::Escape("$Path is $Json; recommended "))*"
        }

        It 'reports a central workflow listed twice' {
            $config = Get-TestGitHubOrgConfig
            $config.ruleset.rules.workflows += ('{ "repository": ".GitHub", "path": ".github/workflows/org-checks.yml", "sha": "89abcdef0123456789abcdef0123456789abcdef" }' | ConvertFrom-Json)

            Test-GitHubOrgConfig -Config $config | Should -Be "ruleset.rules.workflows: '.GitHub/.github/workflows/org-checks.yml' is listed more than once."
        }

        It 'accepts two workflows of one repository whose paths differ in case' {
            $config = Get-TestGitHubOrgConfig
            $config.ruleset.rules.workflows += ('{ "repository": ".github", "path": ".github/workflows/Org-checks.yml", "sha": "89abcdef0123456789abcdef0123456789abcdef" }' | ConvertFrom-Json)

            Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
        }
    }

    It 'takes exceptions for the recommended fields only' {
        $fields = @((Get-GitHubOrgConfigShape).Fields['exceptions'].Items.Fields['field'].SchemaEnum)

        $fields | Should -Contain 'settings.members_can_invite_outside_collaborators'
        $fields | Should -Contain 'actions.selected.verified_allowed'
        $fields | Should -Contain 'codeSecurity.settings.dependabot_alerts'
        $fields | Should -Not -Contain 'settings.email'
        $fields | Should -Not -Contain 'actions.retention.days'
        $fields | Should -Contain 'actions.privateForkPullRequests.require_approval_for_fork_pr_workflows'
        $fields | Should -Not -Contain 'copilot.policies.ide_chat'
        $fields | Should -Contain 'ruleset.rules.pullRequest.allowed_merge_methods'
        $fields | Should -Not -Contain 'ruleset.rules.workflows'
        # Not a value but a rule: the required reviewers of the workflows (Get-WorkflowReviewerReport).
        $fields | Should -Contain 'ruleset.rules.pullRequest.requiredReviewers'
        $fields | Should -Contain 'ruleset.rules.copilotCodeReview.enabled'
        $fields | Should -Contain 'copilot.policies.cli_billed_to_organization'
        $fields.Count | Should -Be 112
    }

    It 'recommends the values of the complete test config' {
        # The fixture is the baseline: any recommendation that differs from it is a typo in the table.
        (Get-RecommendationReport -Config (Get-TestGitHubOrgConfig) -Shape (Get-GitHubOrgConfigShape) -Today ([datetime]'2026-10-02')).Warnings |
            Should -BeNullOrEmpty
    }

    It 'warns about a setting that differs from its recommendation' {
        $config = Get-TestGitHubOrgConfig
        $config.settings.members_can_create_pages = $true

        $warnings = @((Get-RecommendationReport -Config $config -Shape (Get-GitHubOrgConfigShape) -Today ([datetime]'2026-10-02')).Warnings)

        $warnings.Count | Should -Be 1
        $warnings[0] | Should -BeLike 'settings.members_can_create_pages is true; recommended false: *'
    }
}

Describe 'configVersion' {
    It 'accepts the config format of the engine' {
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = '1.0'

        Test-GitHubOrgConfig -Config $config | Should -BeNullOrEmpty
    }

    It 'rejects <Version>, a format the engine does not read' -ForEach @(
        @{ Version = '1.1' }
        @{ Version = '2.0' }
        @{ Version = '0.9' }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = $Version

        Test-GitHubOrgConfig -Config $config |
            Should -Be "configVersion '$Version': this version of the engine reads config formats 1.0 to 1.0. Update the engine or the config as the notes of the format say."
    }

    It 'reports only the format, not the fields, of a config of another format' {
        # A config of another major differs in its keys: those errors would hide the one that explains them.
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = '2.0'
        $config.PSObject.Properties.Remove('inventory')
        $config | Add-Member -NotePropertyName 'renamedSection' -NotePropertyValue @{}

        Test-GitHubOrgConfig -Config $config | Should -BeLike "configVersion '2.0': *"
    }

    It 'rejects <Version>, which is not major.minor' -ForEach @(
        @{ Version = '1' }
        @{ Version = '01.0' }
        @{ Version = '1.0.0' }
        @{ Version = '99999999999.0' }
        @{ Version = "2.0`n" }
    ) {
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = $Version

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path 'configVersion' -Part $Version -Only
    }

    It 'rejects a number' {
        $config = Get-TestGitHubOrgConfig
        $config.configVersion = 1.0

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path 'configVersion' -Only
    }

    It 'is required' {
        $config = Get-TestGitHubOrgConfig
        $config.PSObject.Properties.Remove('configVersion')

        Assert-ConfigError -Errors @(Test-GitHubOrgConfig -Config $config) -Path 'configVersion' -Only
    }
}

Describe 'Get-WorkflowReviewerReport' {
    BeforeAll {
        $script:today = [datetime]'2026-11-03'

        function Get-ConfigWithReviewerPattern {
            param([string[]]$Pattern, [int]$MinimumApprovals = 1)
            $config = Get-TestGitHubOrgConfig
            $config.ruleset.rules.pullRequest.requiredReviewers[0].file_patterns = $Pattern
            $config.ruleset.rules.pullRequest.requiredReviewers[0].minimum_approvals = $MinimumApprovals
            return $config
        }

        function Add-ReviewerException {
            param([object]$Config)
            $Config.exceptions = @('{ "field": "ruleset.rules.pullRequest.requiredReviewers", "category": "waiver", "reason": "No team yet", "expiresOn": "2027-05-01", "reference": null }' | ConvertFrom-Json)
        }
    }

    It 'finds nothing for the test config' {
        $report = Get-WorkflowReviewerReport -Config (Get-TestGitHubOrgConfig) -Today $script:today

        $report.NotWaived | Should -BeNullOrEmpty
        $report.Warnings | Should -BeNullOrEmpty
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'is a config error when no team must approve changes to the workflows' {
        Test-GitHubOrgConfig -Config (Get-ConfigWithReviewerPattern -Pattern 'src/**') -Today $script:today |
            Should -Be 'ruleset.rules.pullRequest.requiredReviewers: no team must approve changes to .github/workflows/**, so anyone with write access and one approval changes the workflows of every repository. Add a requiredReviewers entry with minimum_approvals of at least 1 whose file_patterns include .github/workflows/**. To keep it, add an entry to exceptions.'
    }

    It 'does not count <Name> as covering the workflows' -ForEach @(
        @{ Name = 'an entry without approvals'; Pattern = @('.github/workflows/**'); MinimumApprovals = 0 }
        @{ Name = 'an entry that excludes .github/workflows'; Pattern = @('.github/**', '!.github/workflows/**'); MinimumApprovals = 1 }
        @{ Name = 'an entry that excludes .github'; Pattern = @('**', '!.github/**'); MinimumApprovals = 1 }
        @{ Name = 'a pattern in another case'; Pattern = @('.GitHub/workflows/**'); MinimumApprovals = 1 }
    ) {
        $errors = @(Test-GitHubOrgConfig -Config (Get-ConfigWithReviewerPattern -Pattern $Pattern -MinimumApprovals $MinimumApprovals) -Today $script:today)

        $errors.Count | Should -Be 1
        $errors[0] | Should -BeLike 'ruleset.rules.pullRequest.requiredReviewers: no team must approve changes to .github/workflows/*'
    }

    It 'counts the pattern <Pattern> as covering the workflows' -ForEach @(
        @{ Pattern = '**' }
        @{ Pattern = '.github/**' }
        @{ Pattern = '.github/workflows/**' }
    ) {
        Test-GitHubOrgConfig -Config (Get-ConfigWithReviewerPattern -Pattern 'src/**', $Pattern) -Today $script:today | Should -BeNullOrEmpty
    }

    It 'accepts a config without such a reviewer while an exception is in force, and reports the waiver' {
        $config = Get-ConfigWithReviewerPattern -Pattern 'src/**'
        Add-ReviewerException -Config $config

        Test-GitHubOrgConfig -Config $config -Today $script:today | Should -BeNullOrEmpty
        $report = Get-WorkflowReviewerReport -Config $config -Today $script:today
        $report.NotWaived | Should -BeNullOrEmpty
        @($report.Waivers).Count | Should -Be 1
    }

    It 'warns about an exception the reviewers make unneeded' {
        $config = Get-TestGitHubOrgConfig
        Add-ReviewerException -Config $config

        $report = Get-WorkflowReviewerReport -Config $config -Today $script:today

        $report.NotWaived | Should -BeNullOrEmpty
        $report.Warnings | Should -BeLike '*: a team must approve changes to .github/workflows/`*`*. Remove it.'
    }
}

Describe 'github.schema.json' {
    BeforeAll {
        $script:schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../github.schema.json'
    }

    It 'is generated from the shape (run tools/Build-ConfigSchema.ps1 after changing it)' {
        $expected = ConvertTo-ConfigSchema -Shape (Get-GitHubOrgConfigShape) -Title 'github-org-bootstrap config'

        (Get-Content -LiteralPath $script:schemaPath -Raw) -replace "`r`n", "`n" | Should -BeExactly $expected
    }

    It 'accepts <Name>, which references it' -ForEach @(
        @{ Name = 'examples/github.json'; Path = '../examples/github.json'; Schema = '../github.schema.json' }
    ) {
        $configText = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath $Path) -Raw

        ($configText | ConvertFrom-Json).'$schema' | Should -Be $Schema
        $configText | Test-Json -Schema (Get-Content -LiteralPath $script:schemaPath -Raw) | Should -BeTrue
    }
}
