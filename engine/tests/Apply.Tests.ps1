BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/GitHubOrg.Common.psm1') -Force
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestData.ps1')

    function Get-TestSettingsOnlyState {
        # Every setting differs, code security matches: no action needs the id of a configuration created in the run.
        $state = Get-DefaultTestGitHubOrgState
        $state.CodeSecurity = Get-MatchingTestCodeSecurityState
        $state
    }
}

Describe 'Invoke-GitHubOrgPlan' {
    BeforeEach {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
        $script:plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-TestSettingsOnlyState))
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'sends every action in plan order with its method, endpoint and body as planned' {
        # What each body holds is the plan's job (Plan.Tests.ps1) and is read back by the round trip; here only that
        # Apply sends it unchanged.
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState (Get-TestSettingsOnlyState))

        Invoke-GitHubOrgPlan -Plan $plan

        $calls = @(Get-TestGhCall)
        $calls.Count | Should -Be $plan.Count
        for ($i = 0; $i -lt $plan.Count; $i++) {
            "$($calls[$i].Arguments[2]) $($calls[$i].Arguments[3])" | Should -Be "$($plan[$i].Method) $($plan[$i].Endpoint)"
            $calls[$i].Input | Should -Be ($plan[$i].Body | ConvertTo-Json -Depth 10 -Compress)
        }
    }

    It 'sends a one-pattern list as a JSON array' {
        $config = Get-TestGitHubOrgConfig
        $config.actions.selected.patterns_allowed = @('azure/login@*')
        $plan = @(Get-GitHubOrgPlan -Config $config -CurrentState (Get-MatchingTestGitHubOrgState))

        Invoke-GitHubOrgPlan -Plan $plan

        @(Get-TestGhCall)[0].Input | Should -Match '"patterns_allowed":\["azure/login@\*"\]'
    }

    It 'stops at the first error' {
        Register-TestGhStub -Responder {
            param([string[]]$Arguments)
            if ($Arguments[2] -eq 'PUT') {
                return [pscustomobject]@{ ExitCode = 1; Output = 'gh: Validation Failed (HTTP 422)' }
            }
            [pscustomobject]@{ ExitCode = 0; Output = '' }
        }

        { Invoke-GitHubOrgPlan -Plan $script:plan } | Should -Throw '*PUT orgs/contoso/actions/permissions failed*HTTP 422*'
        @(Get-TestGhCall).Count | Should -Be 2
    }

    It 'shows a progress step for each action and clears the progress at the end' {
        # The step format belongs to Write-ApplyProgress (shared/tests); here only one step per action, by its summary.
        Invoke-GitHubOrgPlan -Plan $script:plan

        Should -Invoke Write-Progress -ModuleName GitHubOrg.Common -Times $script:plan.Count -Exactly -ParameterFilter { $Activity -eq 'Applying changes' -and -not $Completed }
        foreach ($action in $script:plan) {
            $summary = [WildcardPattern]::Escape($action.Summary)
            Should -Invoke Write-Progress -ModuleName GitHubOrg.Common -Times 1 -Exactly -ParameterFilter { $Status -like "*$summary" }
        }
        Should -Invoke Write-Progress -ModuleName GitHubOrg.Common -Times 1 -Exactly -ParameterFilter { $Activity -eq 'Applying changes' -and $Completed }
    }

    It 'clears the progress when an action fails' {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 1; Output = 'gh: Validation Failed (HTTP 422)' } }

        { Invoke-GitHubOrgPlan -Plan $script:plan } | Should -Throw '*HTTP 422*'
        Should -Invoke Write-Progress -ModuleName GitHubOrg.Common -Times 1 -Exactly -ParameterFilter { $Activity -eq 'Applying changes' -and $Completed }
    }

    It 'reports each applied action' {
        Invoke-GitHubOrgPlan -Plan $script:plan

        Should -Invoke Write-Host -ModuleName GitHubOrg -Times $script:plan.Count -Exactly -ParameterFilter { $Object -like '  done: *' }
        Should -Invoke Write-Host -ModuleName GitHubOrg -Times 1 -Exactly -ParameterFilter { $Object -like '  done: ~ set Actions permissions of contoso: *' }
    }
}

Describe 'Invoke-GitHubOrgPlan: code security' {
    BeforeEach {
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
        $state = Get-MatchingTestGitHubOrgState
        $state.CodeSecurity = Get-EmptyTestCodeSecurityState
        $script:plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'uses the id of the configuration it created in the later calls' {
        Register-TestGhRoute -Route @{
            'POST orgs/contoso/code-security/configurations'            = Get-TestGhResponse -Body @{ id = 99; name = 'baseline' }
            'PUT orgs/contoso/code-security/configurations/99/defaults' = Get-TestGhResponse -Body @{ default_for_new_repos = 'all' }
            'POST orgs/contoso/code-security/configurations/99/attach'  = [pscustomobject]@{ ExitCode = 0; Output = '{}' }
        }

        Invoke-GitHubOrgPlan -Plan $script:plan

        (@(Get-TestGhCall) | ForEach-Object { "$($_.Arguments[2]) $($_.Arguments[3])" }) | Should -Be @(
            'POST orgs/contoso/code-security/configurations'
            'PUT orgs/contoso/code-security/configurations/99/defaults'
            'POST orgs/contoso/code-security/configurations/99/attach'
        )
        (@(Get-TestGhCall)[0].Input | ConvertFrom-Json).dependabot_alerts | Should -Be 'enabled'
    }

    It 'stops before calling GitHub with an unresolved id' {
        Register-TestGhRoute -Route @{
            'POST orgs/contoso/code-security/configurations' = [pscustomobject]@{ ExitCode = 0; Output = '{}' }
        }

        { Invoke-GitHubOrgPlan -Plan $script:plan } | Should -Throw '*needs the id of the code security configuration created in this run, but the create response had none*'
        @(Get-TestGhCall).Count | Should -Be 1
    }
}

Describe 'Invoke-GitHubOrgPlan: ruleset' {
    BeforeEach {
        Register-TestGhStub -Responder { [pscustomobject]@{ ExitCode = 0; Output = '{}' } }
        Mock -ModuleName GitHubOrg Write-Host { }
        Mock -ModuleName GitHubOrg.Common Write-Progress { }
    }

    AfterEach {
        Unregister-TestGhStub
    }

    It 'sends <Action> with its method, endpoint and whole body' -ForEach @(
        @{ Action = 'CreateRuleset'; Change = { param($r) $r.Current = $null }; Expected = 'POST orgs/contoso/rulesets' }
        @{ Action = 'UpdateRuleset'; Change = { param($r) $r.Current.enforcement = 'disabled' }; Expected = 'PUT orgs/contoso/rulesets/7' }
    ) {
        $state = Get-MatchingTestGitHubOrgState
        & $Change $state.Ruleset
        $plan = @(Get-GitHubOrgPlan -Config (Get-TestGitHubOrgConfig) -CurrentState $state)
        $plan.Action | Should -Be $Action

        Invoke-GitHubOrgPlan -Plan $plan

        $call = @(Get-TestGhCall)[0]
        "$($call.Arguments[2]) $($call.Arguments[3])" | Should -Be $Expected
        $call.Input | Should -Be ($plan[0].Body | ConvertTo-Json -Depth 10 -Compress)
        # One-item lists stay arrays at every depth.
        $sent = $call.Input | ConvertFrom-Json -NoEnumerate
        $pullRequest = @($sent.rules | Where-Object type -EQ 'pull_request')[0].parameters
        $workflows = @($sent.rules | Where-Object type -EQ 'workflows')[0].parameters.workflows
        , $sent.bypass_actors | Should -BeOfType [object[]]
        , $pullRequest.allowed_merge_methods | Should -BeOfType [object[]]
        , $pullRequest.required_reviewers | Should -BeOfType [object[]]
        $pullRequest.required_reviewers[0].reviewer.id | Should -Be 11
        $pullRequest.required_reviewers[0].file_patterns | Should -HaveCount 4
        , $workflows | Should -BeOfType [object[]]
        $workflows[0].repository_id | Should -Be 21
        , $sent.conditions.ref_name.include | Should -BeOfType [object[]]
    }
}
