BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../Bootstrap.Common.psm1') -Force
}

Describe 'Write-BootstrapPlan' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Host { }
    }

    It 'says there are no changes for an empty plan' {
        Write-BootstrapPlan -Plan @()

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'No changes: everything matches the config.' }
    }

    It 'prints every action summary' {
        Write-BootstrapPlan -Plan @([pscustomobject]@{ Summary = '+ a' }, [pscustomobject]@{ Summary = '~ b' })

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Planned changes (2):' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq '  + a' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq '  ~ b' }
    }

    It 'prints the details of an action under its summary' {
        Write-BootstrapPlan -Plan @([pscustomobject]@{ Summary = '~ x'; Details = @('UI:    a', 'Read:  b') })

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq '  ~ x' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq '      UI:    a' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq '      Read:  b' }
    }
}

Describe 'Write-BootstrapSummary' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Host { }
    }

    It 'reports applied changes and objects that were already up to date' {
        Write-BootstrapSummary -Applied @([pscustomobject]@{ Summary = '+ a' }) -Unchanged @('mg-root', 'sub-dev')

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Done. Applied 1 change(s).' }
        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Already up to date: mg-root, sub-dev' }
    }

    It 'reports a single object that was already up to date' {
        Write-BootstrapSummary -Applied @() -Unchanged @('mg-root')

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Already up to date: mg-root' }
    }

    It 'reports no up-to-date line when nothing was unchanged' {
        Write-BootstrapSummary -Applied @([pscustomobject]@{ Summary = '+ a' }) -Unchanged @()

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 0 -Exactly -ParameterFilter { $Object -like 'Already up to date*' }
    }
}

Describe 'Write-BootstrapRecommendation' {
    BeforeEach {
        $script:printed = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Bootstrap.Common Write-Host { $script:printed.Add([string]$Object) }
        $script:rendering = $PSStyle.OutputRendering
    }

    AfterEach {
        $PSStyle.OutputRendering = $script:rendering
    }

    It 'prints a blank line, the cyan label with the message, and the command on its own line' {
        $PSStyle.OutputRendering = 'Ansi'

        Write-BootstrapRecommendation -Message 'remove the scopes:' -Command 'gh auth refresh -r x'

        $script:printed.ToArray() | Should -Be @(
            ''
            "$($PSStyle.Foreground.Cyan)Recommended:$($PSStyle.Reset) remove the scopes:"
            '  gh auth refresh -r x'
        )
    }

    It 'prints no color when output is plain text' {
        $PSStyle.OutputRendering = 'PlainText'

        Write-BootstrapRecommendation -Message 'remove the scopes:' -Command 'gh auth refresh -r x'

        $script:printed.ToArray() | Should -Be @('', 'Recommended: remove the scopes:', '  gh auth refresh -r x')
    }
}

Describe 'Confirm-BootstrapPlan' {
    BeforeAll {
        # A stage stand-in: Confirm-BootstrapPlan calls ShouldProcess on the cmdlet it is given.
        function Invoke-TestStage {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Confirm-BootstrapPlan calls ShouldProcess on this cmdlet.')]
            [CmdletBinding(SupportsShouldProcess)]
            param([AllowEmptyCollection()][object[]]$Plan, [switch]$Force)

            Confirm-BootstrapPlan -Plan $Plan -Target 'tenant t1' -Cmdlet $PSCmdlet -Force:$Force
        }

        $script:twoActions = @([pscustomobject]@{ Summary = 'a' }, [pscustomobject]@{ Summary = 'b' })
    }

    BeforeEach {
        Mock -ModuleName Bootstrap.Common Read-Host { 'y' }
    }

    It 'asks with the number of changes and the target, and applies on yes' {
        Invoke-TestStage -Plan $script:twoActions | Should -BeTrue

        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Prompt -eq 'Apply 2 change(s) to tenant t1? [y/N]' }
    }

    It 'applies on the answer <Answer>' -ForEach @(
        @{ Answer = 'y' }
        @{ Answer = 'yes' }
        @{ Answer = ' Y ' }
    ) {
        $script:answer = $Answer
        Mock -ModuleName Bootstrap.Common Read-Host { $script:answer }

        Invoke-TestStage -Plan $script:twoActions | Should -BeTrue
    }

    It 'aborts on the answer <Name>' -ForEach @(
        @{ Name = 'n'; Answer = 'n' }
        @{ Name = 'Enter alone'; Answer = '' }
        @{ Name = 'yes, please'; Answer = 'yes, please' }
    ) {
        $script:answer = $Answer
        Mock -ModuleName Bootstrap.Common Read-Host { $script:answer }

        { Invoke-TestStage -Plan $script:twoActions } | Should -Throw '*Aborted by operator*'
    }

    It 'does not ask for an empty plan' {
        Invoke-TestStage -Plan @() | Should -BeFalse

        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
    }

    It 'does not ask with -Force' {
        Invoke-TestStage -Plan $script:twoActions -Force | Should -BeTrue

        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
    }

    It 'neither asks nor applies with -WhatIf, also with -Force' -ForEach @(
        @{ Force = $false }
        @{ Force = $true }
    ) {
        Invoke-TestStage -Plan $script:twoActions -Force:$Force -WhatIf | Should -BeFalse

        Should -Invoke Read-Host -ModuleName Bootstrap.Common -Times 0 -Exactly
    }
}

Describe 'Progress helpers' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Progress { }
    }

    It 'Write-StateProgress shows which read runs' {
        Write-StateProgress -Status 'management groups'

        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter {
            $Activity -eq 'Reading current state' -and $Status -eq 'management groups'
        }
    }

    It 'Write-ApplyProgress shows the action number, its summary and the share done before it' {
        Write-ApplyProgress -Index 1 -Total 4 -Summary '+ create group'

        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter {
            $Activity -eq 'Applying changes' -and $Status -eq '2/4: + create group' -and $PercentComplete -eq 25
        }
    }

    It 'Complete-BootstrapProgress clears both progress bars' {
        Complete-BootstrapProgress

        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Activity -eq 'Reading current state' -and $Completed }
        Should -Invoke Write-Progress -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter { $Activity -eq 'Applying changes' -and $Completed }
    }
}
