@{
    # The engine module. ModuleVersion is the release; a test keeps it equal to the latest release of CHANGELOG.md.
    RootModule        = 'GitHubOrg.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5c0f2b8e-7d4a-4f36-9b1e-3a6d8c2e4f71'
    Author            = 'Devnto'
    CompanyName       = 'Devnto'
    Copyright         = 'Copyright 2026 Devnto. Licensed under the Apache License, Version 2.0.'
    Description       = 'Keeps the settings of a GitHub organization in line with a config file: reads the organization, plans the difference, asks once and applies.'
    PowerShellVersion = '7.6'
    # GitHubOrg.Common (shared/) is imported by the caller first, never nested: see docs/architecture.md.
    FunctionsToExport = @(
        'Test-GitHubOrgConfig', 'Get-GitHubOrgConfigShape', 'Get-GitHubOrgSettingReference', 'Get-GitHubOrgReadField',
        'Get-WorkflowReviewerReport', 'Assert-GitHubOrgContext', 'Get-GitHubOrgState', 'Get-GitHubOrgPlan',
        'Get-GitHubOrgWarning', 'Invoke-GitHubOrgPlan', 'Invoke-GitHubOrgBootstrap'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('GitHub', 'Organization', 'Settings', 'Governance', 'Security')
            LicenseUri   = 'https://github.com/devntoltd/github-org-bootstrap/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/devntoltd/github-org-bootstrap'
            ReleaseNotes = 'https://github.com/devntoltd/github-org-bootstrap/blob/main/CHANGELOG.md'
        }
    }
}
