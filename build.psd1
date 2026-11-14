@{
    # The checks of .github/workflows/ci.yml, in the order './build.ps1 all' runs them: fast first, tests last.
    # Command runs from the repository root with Arguments. CiStep is the name of the matching step in ci.yml (a test
    # keeps both lists equal). Install is what to install when Command is missing (default: ./tools/Install-DevTools.ps1,
    # so a test keeps every other command in dev-tools.psd1). GitHubToken sets GH_TOKEN from 'gh auth token' for the
    # check when it is not set.
    Checks = @(
        @{ Name = 'lint'; Description = 'PSScriptAnalyzer, every rule'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'tools/Invoke-Lint.ps1'); CiStep = 'Lint' }
        @{ Name = 'editorconfig'; Description = 'Every file against .editorconfig'; Command = 'editorconfig-checker'; Arguments = @(); CiStep = 'EditorConfig' }
        @{ Name = 'markdownlint'; Description = 'Markdown lint'; Command = 'npx'; Arguments = @('--yes', 'markdownlint-cli2@0.23.3'); Install = 'Node.js'; CiStep = 'Markdown lint' }
        @{ Name = 'links'; Description = 'Links and anchors between the docs'; Command = 'lychee'; Arguments = @('--offline', '--include-fragments', '--no-progress', '--exclude-path=decisions.\d{4}-', './**/*.md'); CiStep = 'Markdown links' }
        @{ Name = 'shellcheck'; Description = 'The pre-commit hook'; Command = 'shellcheck'; Arguments = @('.githooks/pre-commit'); CiStep = 'shellcheck' }
        @{ Name = 'actionlint'; Description = 'Workflow correctness'; Command = 'actionlint'; Arguments = @('.github/workflows/ci.yml', '.github/workflows/recurring.yml', 'engine/examples/org-checks.yml'); CiStep = 'actionlint' }
        @{ Name = 'zizmor'; Description = 'Workflow security, online audits'; Command = 'zizmor'; Arguments = @('--persona=pedantic', '.', 'engine/examples/org-checks.yml'); GitHubToken = $true; CiStep = 'zizmor' }
        @{ Name = 'secrets'; Description = 'Betterleaks over the full git history'; Command = 'betterleaks'; Arguments = @('git', '--redact', '--verbose', '--no-banner', '.'); CiStep = 'Betterleaks' }
        @{ Name = 'tests'; Description = 'All tests with coverage'; Command = 'pwsh'; Arguments = @('-NoProfile', '-File', 'tools/Invoke-Coverage.ps1'); CiStep = 'Test and coverage' }
    )
    # The scripts of tools/ that are not checks, run with Parameters (splatted by name) first. The ones that write to
    # GitHub without asking run with -WhatIf only: the real run is recurring.yml's (ci.yml's for the release). A hashtable, not an array: a
    # '-WhatIf' string in a splatted array binds as a positional value, not as the switch.
    Tools  = @(
        @{ Name = 'schemas'; Description = 'Regenerate the config schemas'; Script = 'tools/Build-ConfigSchema.ps1'; Parameters = @{} }
        @{ Name = 'reference'; Description = 'Regenerate the settings reference'; Script = 'tools/Build-SettingReference.ps1'; Parameters = @{} }
        @{ Name = 'install'; Description = 'Install the dev tools and modules'; Script = 'tools/Install-DevTools.ps1'; Parameters = @{} }
        @{ Name = 'reminders'; Description = 'Recurring operations: status only'; Script = 'tools/Invoke-RecurringReminder.ps1'; Parameters = @{ WhatIf = $true } }
        @{ Name = 'api-version'; Description = 'GitHub REST API version: status only'; Script = 'tools/Invoke-GitHubApiVersionCheck.ps1'; Parameters = @{ WhatIf = $true } }
        @{ Name = 'endpoints'; Description = 'API endpoint catalog: status only'; Script = 'tools/Invoke-ApiEndpointCheck.ps1'; Parameters = @{ WhatIf = $true } }
        @{ Name = 'updates'; Description = 'Module and tool versions newer than the lock'; Script = 'tools/Find-DependencyUpdate.ps1'; Parameters = @{} }
        @{ Name = 'dependencies'; Description = 'Dependency update issue: status only'; Script = 'tools/Invoke-DependencyUpdateCheck.ps1'; Parameters = @{ WhatIf = $true } }
        @{ Name = 'release'; Description = 'Release of ModuleVersion: status only'; Script = 'tools/Publish-Release.ps1'; Parameters = @{ WhatIf = $true } }
    )
}
