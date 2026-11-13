# The catalog of the settings pages of the organization. Pure: no GitHub calls.
#
# Every page under https://github.com/organizations/<org>/settings/, in the order of the settings menu. Status:
#   managed   - rows of $script:SettingDefinitions have it as their Page, or Area names the code that manages it;
#   unmanaged - the engine leaves it alone, Reason says why;
#   pending   - its controls are not catalogued yet (a later step fills it).
# Unmanaged: a control on a managed page that the engine leaves alone (UI label -> reason).
$script:SettingPages = @(
    @{ Path = 'profile'; Label = 'General'; Status = 'managed'; Unmanaged = @{ 'Display name' = 'identity of the organization, not a security setting'; 'Billing email' = 'private profile data'; 'Description' = 'public profile, not a security setting'; 'URL' = 'public profile, not a security setting'; 'Social accounts' = 'public profile, not a security setting'; 'Location' = 'public profile, not a security setting'; 'Profile picture' = 'public profile, not a security setting'; 'Gravatar email' = 'private profile data'; 'Sponsors update email' = 'private profile data'; 'Terms of service' = 'a contract of the organization, not a setting'; 'Rename organization' = 'an action on the organization, not a setting' }; ReviewedOn = '2026-11-09'; Order = @('settings.email') }
    @{ Path = 'policies/repositories'; Label = 'Repository > Policies'; Status = 'unmanaged'; Reason = 'repository policies are objects, none defined; the organization ruleset protects the default branch' }
    @{ Path = 'billing'; Label = 'Billing and licensing > Overview'; Status = 'unmanaged'; Reason = 'usage reports, not settings' }
    @{ Path = 'billing/usage'; Label = 'Billing and licensing > Usage'; Status = 'unmanaged'; Reason = 'usage reports, not settings' }
    @{ Path = 'billing/ai_usage'; Label = 'Billing and licensing > AI usage'; Status = 'unmanaged'; Reason = 'usage reports, not settings' }
    @{ Path = 'billing/budgets'; Label = 'Billing and licensing > Budgets and alerts'; Status = 'managed'; Area = 'budgets' }
    @{ Path = 'licensing'; Label = 'Billing and licensing > Licensing'; Status = 'unmanaged'; Reason = 'license and billing records, not settings' }
    @{ Path = 'billing/subscriptions'; Label = 'Billing and licensing > Additional billing details'; Status = 'unmanaged'; Reason = 'license and billing records, not settings' }
    @{ Path = 'billing/payment_information'; Label = 'Billing and licensing > Payment information'; Status = 'unmanaged'; Reason = 'payment data, never read' }
    @{ Path = 'org_roles'; Label = 'Access > Organization roles'; Status = 'unmanaged'; Reason = 'roles and who holds them are people and teams, managed outside this tool' }
    @{ Path = 'org_role_assignments'; Label = 'Access > Role assignments'; Status = 'unmanaged'; Reason = 'roles and who holds them are people and teams, managed outside this tool' }
    @{ Path = 'roles'; Label = 'Access > Repository roles'; Status = 'unmanaged'; Reason = 'roles and who holds them are people and teams, managed outside this tool' }
    @{ Path = 'member_privileges'; Label = 'Access > Member privileges'; Status = 'managed'; Unmanaged = @{ 'Repository invitations' = 'not shown on GitHub Team; the row settings.members_can_invite_outside_collaborators checks it' }; ReviewedOn = '2026-11-09'; Order = @('settings.default_repository_permission', 'settings.members_can_create_public_repositories', 'settings.members_can_create_private_repositories', 'settings.members_can_fork_private_repositories', 'settings.display_commenter_full_name_setting_enabled', 'settings.readers_can_create_discussions', 'memberPrivileges.projects_base_permission', 'settings.members_can_create_public_pages', 'settings.members_can_create_private_pages', 'memberPrivileges.app_access_requests', 'memberPrivileges.members_can_install_github_apps', 'settings.members_can_change_repo_visibility', 'settings.members_can_delete_repositories', 'settings.members_can_delete_issues', 'memberPrivileges.members_can_rename_protected_branches', 'settings.members_can_create_teams') }
    @{ Path = 'import-export'; Label = 'Access > Import/Export'; Status = 'unmanaged'; Reason = 'one-off data export, not a setting' }
    @{ Path = 'blocked_users'; Label = 'Moderation > Blocked users'; Status = 'unmanaged'; Reason = 'a list of accounts, not a setting' }
    @{ Path = 'interaction_limits'; Label = 'Moderation > Interaction limits'; Status = 'managed'; Unmanaged = @{ 'Exempt users based on account age' = 'no API; matters only while the pull request cap is enabled'; 'Exempt users based on merged pull requests' = 'no API; matters only while the pull request cap is enabled'; 'Maximum open pull requests per user' = 'no API; matters only while the pull request cap is enabled'; 'Count draft pull requests toward the limit' = 'no API; matters only while the pull request cap is enabled' }; ReviewedOn = '2026-11-09'; Order = @('interactionLimits.limit', 'interactionLimits.pull_request_cap_enabled') }
    @{ Path = 'code_review_limits'; Label = 'Moderation > Code review limits'; Status = 'unmanaged'; Reason = 'an action on every repository (limit or remove the review limits), not a setting the organization keeps' }
    @{ Path = 'moderators'; Label = 'Moderation > Moderators'; Status = 'unmanaged'; Reason = 'people and teams, managed outside this tool' }
    @{ Path = 'repository-defaults'; Label = 'Repository > General'; Status = 'managed'; Unmanaged = @{ 'Repository labels' = 'labels, objects rather than settings (outside this tool)' }; ReviewedOn = '2026-11-09'; Order = @('settings.default_repository_branch', 'settings.web_commit_signoff_required', 'repositoryDefaults.commit_comments', 'immutableReleases.enforced_repositories') }
    @{ Path = '/orgs/<org>/topics'; Label = 'Repository > Topics'; Status = 'unmanaged'; Reason = 'the topics of each repository, repository data (outside this tool)' }
    @{ Path = 'custom-properties'; Label = 'Repository > Custom properties'; Status = 'unmanaged'; Reason = 'repository properties are objects, none defined (outside this tool)' }
    @{ Path = 'rules'; Label = 'Repository > Rulesets'; Status = 'managed'; Area = 'ruleset' }
    @{ Path = 'rules/insights'; Label = 'Repository > Rule insights'; Status = 'unmanaged'; Reason = 'reports, not settings' }
    @{ Path = 'rules/dashboard'; Label = 'Repository > Rules dashboard'; Status = 'unmanaged'; Reason = 'reports, not settings' }
    @{ Path = 'codespaces'; Label = 'Codespaces > General'; Status = 'managed'; Unmanaged = @{ 'Access and security' = 'deprecated by GitHub; matters only while Codespaces is enabled' }; ReviewedOn = '2026-11-09'; Order = @('codespaces.access', 'codespaces.ownership') }
    @{ Path = 'codespaces/policies'; Label = 'Codespaces > Policies'; Status = 'unmanaged'; Reason = 'policies are objects, none defined; they apply only with organization ownership' }
    @{ Path = 'projects'; Label = 'Planning > Projects'; Status = 'managed'; Unmanaged = @{ 'Recommended templates' = 'project templates, objects rather than settings' }; ReviewedOn = '2026-11-09'; Order = @('settings.has_organization_projects', 'projects.members_can_change_project_visibility') }
    @{ Path = 'issue-types'; Label = 'Planning > Issue types'; Status = 'unmanaged'; Reason = 'issue types are objects, not settings' }
    @{ Path = 'issue-fields'; Label = 'Planning > Issue fields'; Status = 'unmanaged'; Reason = 'issue fields are objects, not settings' }
    @{ Path = 'copilot/seat_management'; Label = 'Copilot > Access'; Status = 'managed'; Area = 'copilotSeats' }
    @{ Path = 'copilot/policies'; Label = 'Copilot > Policies'; Status = 'managed'; Unmanaged = @{ 'MCP registry URL' = 'matters only while MCP servers are enabled'; 'Restrict MCP access to registry servers' = 'matters only while MCP servers are enabled' }; ReviewedOn = '2026-11-09'; Order = @('copilot.policies.ai_credit_paid_usage', 'copilot.policies.default_policy_new_features', 'copilot.policies.platform_chat', 'copilot.policies.feedback_collection', 'copilot.policies.cloud_preview_features', 'copilot.policies.metrics_api', 'copilot.policies.metrics_industry_comparison', 'copilot.policies.usage_metrics', 'copilot.policies.code_review', 'copilot.policies.bill_reviews_to_organization', 'copilot.policies.reviews_without_license', 'copilot.policies.code_review_preview_features', 'copilot.policies.mcp_servers', 'copilot.policies.ide_chat', 'copilot.policies.agent_mode_ide', 'copilot.policies.editor_preview_features', 'copilot.policies.github_desktop', 'copilot.policies.copilot_app', 'copilot.policies.cli', 'copilot.policies.cli_billed_to_organization', 'copilot.policies.cloud_sessions', 'copilot.policies.web_search', 'copilot.policies.model_native_search', 'copilot.policies.external_semantic_indexing', 'copilot.policies.spaces', 'copilot.policies.spaces_individual_access', 'copilot.policies.spaces_individual_sharing', 'copilot.policies.commit_messages', 'copilot.policies.user_memories', 'copilot.policies.repository_memories', 'copilot.policies.memory_retention_days', 'copilot.policies.dreaming', 'copilot.policies.bring_your_own_key', 'copilot.policies.public_code_suggestions') }
    @{ Path = 'copilot/models'; Label = 'Copilot > Models'; Status = 'managed'; Unmanaged = @{ 'Custom models' = 'a preview, none added'; 'Models' = 'the availability of each model; the default availability decides for new ones' }; ReviewedOn = '2026-11-09'; Order = @('copilot.models.default_availability') }
    @{ Path = 'copilot/custom_instructions'; Label = 'Copilot > Custom instructions'; Status = 'unmanaged'; Reason = 'free text instructions for Copilot, not a setting' }
    @{ Path = 'copilot/content_exclusion'; Label = 'Copilot > Content exclusion'; Status = 'unmanaged'; Reason = 'a list of paths Copilot must not read, none excluded' }
    @{ Path = 'copilot/code_review'; Label = 'Copilot > Code review'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('copilot.codeReview.default_review_effort', 'copilot.codeReview.maximum_review_effort', 'copilot.codeReview.approve_pull_requests', 'copilot.codeReview.block_external_license_reviews') }
    @{ Path = 'copilot/coding_agent'; Label = 'Copilot > Cloud'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('copilotCloudAgent.enabled_repositories', 'copilot.automations.allow_automations', 'copilot.automations.allow_shared_automations', 'copilot.automations.require_write_access', 'copilot.automations.update_triggering_resource_only', 'copilot.automations.require_workflow_approval', 'copilot.partnerAgents.claude', 'copilot.partnerAgents.codex') }
    @{ Path = 'copilot/internet_access'; Label = 'Copilot > Internet access'; Status = 'managed'; Unmanaged = @{ 'Organization custom allowlist' = 'a list of locations, none added' }; ReviewedOn = '2026-11-09'; Order = @('copilot.internetAccess.cloud_firewall', 'copilot.internetAccess.cloud_recommended_allowlist', 'copilot.internetAccess.cloud_repository_custom_rules', 'copilot.internetAccess.code_review_firewall', 'copilot.internetAccess.code_review_recommended_allowlist', 'copilot.internetAccess.code_review_repository_custom_rules') }
    @{ Path = 'copilot/runner_type'; Label = 'Copilot > Runner type'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('copilot.runnerType.cloud_agent_runner_type', 'copilot.runnerType.cloud_agent_allow_repository_customization', 'copilot.runnerType.code_review_runner_type', 'copilot.runnerType.code_review_allow_repository_customization') }
    @{ Path = 'actions'; Label = 'Actions > General'; Status = 'managed'; Unmanaged = @{ 'Custom images' = 'runners are not used'; 'Standard hosted runners' = 'the workflows run on the standard hosted runners, which stay enabled'; 'Allow live debugging on self-hosted runners' = 'runners are not used' }; ReviewedOn = '2026-11-09'; Order = @('actions.enabled_repositories', 'actions.allowed_actions', 'actions.selected.github_owned_allowed', 'actions.selected.verified_allowed', 'actions.selected.patterns_allowed', 'actions.sha_pinning_required', 'actions.selfHostedRunners.enabled_repositories', 'actions.retention.days', 'actions.cache.retention_days', 'actions.cache.size_limit_gb', 'actions.forkPullRequests.approval_policy', 'actions.privateForkPullRequests.run_workflows_from_fork_pull_requests', 'actions.privateForkPullRequests.send_write_tokens_to_workflows', 'actions.privateForkPullRequests.send_secrets_and_variables', 'actions.privateForkPullRequests.require_approval_for_fork_pr_workflows', 'actions.workflow.default_workflow_permissions', 'actions.workflow.can_approve_pull_request_reviews') }
    @{ Path = 'actions/rules'; Label = 'Actions > Rules'; Status = 'unmanaged'; Reason = 'Actions policies are objects, none defined; GitHub restricts pull_request_target on public repositories by default from 2026-12-02' }
    @{ Path = 'actions/rules/insights'; Label = 'Actions > Rule insights'; Status = 'unmanaged'; Reason = 'reports, not settings' }
    @{ Path = 'actions/runners'; Label = 'Actions > Runners'; Status = 'unmanaged'; Reason = 'runners are not used' }
    @{ Path = 'actions/runner-groups'; Label = 'Actions > Runner groups'; Status = 'unmanaged'; Reason = 'runners are not used' }
    @{ Path = 'actions/custom-images'; Label = 'Actions > Custom images'; Status = 'unmanaged'; Reason = 'runners are not used' }
    @{ Path = 'actions/caches'; Label = 'Actions > Caches'; Status = 'unmanaged'; Reason = 'cache storage of the workflows, not a setting' }
    @{ Path = 'actions/oidc-configuration'; Label = 'Actions > OIDC configuration'; Status = 'managed'; Unmanaged = @{ 'Custom property claims' = 'no custom properties are defined' }; ReviewedOn = '2026-11-09'; Order = @('actions.oidc.include_claim_keys', 'actions.oidc.use_immutable_subject') }
    @{ Path = 'hooks'; Label = 'Webhooks'; Status = 'managed'; Area = 'inventory' }
    @{ Path = 'discussions'; Label = 'Discussions'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('discussions.enabled') }
    @{ Path = 'packages'; Label = 'Packages'; Status = 'managed'; Unmanaged = @{ 'Deleted packages' = 'a list of deleted packages, not a setting'; 'Internal' = 'internal packages need an enterprise'; 'Private' = 'private packages stay visible to members with permission' }; ReviewedOn = '2026-11-09'; Order = @('packages.public_creation', 'packages.inherit_access') }
    @{ Path = 'pages'; Label = 'Pages'; Status = 'unmanaged'; Reason = 'verified domains for Pages, a list, none added' }
    @{ Path = 'network_configurations'; Label = 'Hosted compute networking'; Status = 'unmanaged'; Reason = 'runners are not used' }
    @{ Path = 'security_analysis'; Label = 'Advanced Security > Global settings'; Status = 'managed'; Unmanaged = @{ 'Copilot Autofix' = 'a suggested fix on an alert, no access or cost'; 'Custom patterns' = 'secret patterns, objects, none defined'; 'Dependabot rules' = 'alert rules, objects rather than settings'; 'Expand CodeQL analysis' = 'the libraries CodeQL knows, no access or cost'; 'Grouped security updates' = 'how Dependabot groups its pull requests, no access or cost'; 'Keep scheduled scans running every 30 days for inactive repositories' = 'scan schedule, no access or cost'; 'Pattern configurations' = 'the secret patterns of push protection, GitHub defaults'; 'Recommend the extended query suite for repositories enabling default setup' = 'the depth of code scanning, no access or cost'; 'Runner type' = 'the runner of Dependabot, the standard one'; 'Select additional repositories' = 'repositories added one by one to Dependabot access, none' }; ReviewedOn = '2026-11-09'; Order = @('advancedSecurity.agentic_autofix', 'advancedSecurity.ai_scan_repositories', 'advancedSecurity.ai_scan_pull_requests', 'advancedSecurity.scan_ai_applications', 'settings.secret_scanning_push_protection_custom_link', 'dependabot.default_level') }
    @{ Path = 'code-quality'; Label = 'Code quality'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('advancedSecurity.code_quality') }
    @{ Path = 'security'; Label = 'Authentication security'; Status = 'managed'; Unmanaged = @{ 'IP allow list' = 'GitHub Enterprise Cloud only'; 'SAML single sign-on' = 'GitHub Enterprise Cloud only'; 'SSH certificate authorities' = 'GitHub Enterprise Cloud only'; 'Team Synchronization' = 'GitHub Enterprise Cloud only' }; ReviewedOn = '2026-11-09'; Order = @('settings.two_factor_requirement_enabled', 'authenticationSecurity.two_factor_secure_methods_required') }
    @{ Path = 'security_products'; Label = 'Advanced Security > Configurations'; Status = 'managed'; Area = 'codeSecurity' }
    @{ Path = 'deploy_keys'; Label = 'Deploy keys'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('settings.deploy_keys_enabled_for_repositories') }
    @{ Path = 'compliance'; Label = 'Compliance'; Status = 'unmanaged'; Reason = 'compliance reports, not settings' }
    @{ Path = 'domains'; Label = 'Verified and approved domains'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('settings.is_verified') }
    @{ Path = 'secrets/actions'; Label = 'Secrets and variables > Actions'; Status = 'unmanaged'; Reason = 'secret values, never read' }
    @{ Path = 'secrets/codespaces'; Label = 'Secrets and variables > Codespaces'; Status = 'unmanaged'; Reason = 'secret values, never read' }
    @{ Path = 'secrets/dependabot'; Label = 'Secrets and variables > Dependabot'; Status = 'unmanaged'; Reason = 'secret values, never read' }
    @{ Path = 'secrets/private_registries'; Label = 'Secrets and variables > Private registries'; Status = 'unmanaged'; Reason = 'secret values, never read' }
    @{ Path = 'installations'; Label = 'GitHub Apps'; Status = 'managed'; Area = 'inventory' }
    @{ Path = 'oauth_application_policy'; Label = 'Third-party access > OAuth app policy'; Status = 'managed'; ReviewedOn = '2026-11-09'; Order = @('oauthApps.policy') }
    @{ Path = 'personal-access-tokens'; Label = 'Personal access tokens > Settings'; Status = 'managed'; Unmanaged = @{ 'Require administrator approval' = 'matters only while fine-grained tokens are allowed; the page disables it while they are restricted'; 'Fine-grained personal access tokens must expire' = 'matters only while fine-grained tokens are allowed; the page disables it while they are restricted'; 'Personal access tokens (classic) must expire' = 'matters only while classic tokens are allowed' }; ReviewedOn = '2026-11-09'; Order = @('personalAccessTokens.fine_grained', 'personalAccessTokens.classic') }
    @{ Path = 'personal-access-tokens/active'; Label = 'Personal access tokens > Active tokens'; Status = 'unmanaged'; Reason = 'lists of tokens and requests, not settings' }
    @{ Path = 'personal-access-token-requests'; Label = 'Personal access tokens > Pending requests'; Status = 'unmanaged'; Reason = 'lists of tokens and requests, not settings' }
    @{ Path = 'reminders'; Label = 'Scheduled reminders'; Status = 'unmanaged'; Reason = 'scheduled reminders are objects, none created' }
    @{ Path = 'applications'; Label = 'Developer settings > OAuth apps'; Status = 'unmanaged'; Reason = 'OAuth apps the organization owns, none' }
    @{ Path = 'apps'; Label = 'Developer settings > GitHub Apps'; Status = 'unmanaged'; Reason = 'GitHub Apps the organization owns, none, and their managers (people)' }
    @{ Path = 'publisher'; Label = 'Developer settings > Publisher verification'; Status = 'unmanaged'; Reason = 'publisher verification for Marketplace apps, none published' }
    @{ Path = 'sponsors-log'; Label = 'Logs > Sponsors log'; Status = 'unmanaged'; Reason = 'logs and lists; the audit log is read by hand (README, Manual verification)' }
    @{ Path = 'audit-log'; Label = 'Logs > Audit log'; Status = 'unmanaged'; Reason = 'logs and lists; the audit log is read by hand (README, Manual verification)' }
    @{ Path = 'deleted_repositories'; Label = 'Deleted repositories'; Status = 'unmanaged'; Reason = 'logs and lists; the audit log is read by hand (README, Manual verification)' }
)

# The areas of the engine that manage a page through their own code rather than rows (Area of a page).
$script:SettingAreas = @('inventory', 'codeSecurity', 'ruleset', 'budgets', 'copilotSeats')

function Get-SettingPage {
    # The page of $script:SettingPages with this path, or $null.
    param([Parameter(Mandatory)][string]$Path)

    return $script:SettingPages | Where-Object { $_.Path -eq $Path } | Select-Object -First 1
}

function Get-PageRow {
    # The rows of a page, top to bottom as the page shows them (its Order), then any row the Order does not list, in the
    # order of the definitions. A test keeps every Order complete; an area page has none.
    param([Parameter(Mandatory)][hashtable]$Page)

    $rows = @($script:SettingDefinitions | Where-Object { $_.Page -eq $Page.Path })
    $ordered = foreach ($path in @($Page.Order | Where-Object { $_ })) {
        $rows | Where-Object { (Get-SettingPath -Definition $_) -ceq $path }
    }
    $listed = @($Page.Order)
    $rest = @($rows | Where-Object { (Get-SettingPath -Definition $_) -cnotin $listed })
    return @(@($ordered) + $rest | Where-Object { $_ })
}

# A read that can answer "this feature does not exist for the organization", by the name a row gives as Absent. The
# answer is Status (an HTTP status) or Field = Value in a 200 answer; Message completes the warning "<n> checked
# settings are not checked: <Message>."
$script:AbsentCases = @{
    CopilotPlan = @{ Endpoint = '/orgs/{org}/copilot/billing'; Status = 404; Field = 'seat_management_setting'; Value = 'unconfigured'; Message = 'the organization has no Copilot plan' }
}

# Every operation of the REST API under /orgs/{org} and /organizations/{org} of the pinned version, and every other one
# the engine calls: path -> Category and method -> @{ Status; Reason; Fields; Body } (docs/architecture.md, "The endpoint
# catalog"). A data file, so tools/ and the tests read it without importing the engine.
$script:ApiCatalog = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../api-endpoints.psd1')

function Get-UnmanagedField {
    # The response fields of the GET of an endpoint (OpenAPI path) that no row reads, as Fields of the catalog lists
    # them; none for a GET without Fields or an endpoint the catalog does not list. None arrives as $null, as PowerShell
    # unrolls an empty array: callers wrap the call in @(), which a returned array object (return ,) would break.
    param([Parameter(Mandatory)][string]$Endpoint)

    $entry = $script:ApiCatalog.Paths[$Endpoint]
    if ($null -eq $entry -or $null -eq $entry.GET -or $null -eq $entry.GET.Fields) {
        return [string[]]@()
    }
    return [string[]]@($entry.GET.Fields.Keys)
}

function Get-GitHubOrgReadField {
    <#
    .SYNOPSIS
    Endpoint (OpenAPI path) -> the top-level field names the rows read from its GET.
    .DESCRIPTION
    For the endpoints a row reads (Get-SettingRead; 'a' of a nested read 'a.b'). tools/Invoke-ApiEndpointCheck.ps1
    -Report adds them to Fields to compare a GET with the description.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $fields = @{}
    foreach ($definition in $script:SettingDefinitions) {
        $read = Get-SettingRead -Definition $definition
        if ($read) {
            $fields[$read.Endpoint] = [string[]]@(@($fields[$read.Endpoint]) + $read.Field.Split('.')[0] | Where-Object { $_ } | Select-Object -Unique)
        }
    }
    return $fields
}

function Get-UnknownResponseField {
    # Endpoint (OpenAPI path) -> the field names of its answer that are neither a row's Read.Field for that endpoint
    # nor in Fields of its GET, for the endpoints with such fields, in the order of State.ResponseFields. Only a GET the
    # run called, that the catalog lists as read with Fields, is scanned; Body plays no part (spec 5.3, 5.4).
    param([Parameter(Mandatory)][object]$State)

    $unknown = [ordered]@{}
    $responseFields = $State.PSObject.Properties['ResponseFields'].Value
    if ($null -eq $responseFields) {
        return $unknown
    }
    $readFields = Get-GitHubOrgReadField
    foreach ($endpoint in $responseFields.Keys) {
        $entry = $script:ApiCatalog.Paths[$endpoint]
        if ($null -eq $entry -or $null -eq $entry.GET -or $entry.GET.Status -cne 'read' -or -not $entry.GET.ContainsKey('Fields')) {
            continue
        }
        $known = [System.Collections.Generic.HashSet[string]]::new([string[]]@($entry.GET.Fields.Keys), [StringComparer]::Ordinal)
        foreach ($field in $readFields[$endpoint]) {
            [void]$known.Add($field)
        }
        $fields = [string[]]@($responseFields[$endpoint] | Where-Object { -not $known.Contains($_) })
        if ($fields.Count -gt 0) {
            $unknown[$endpoint] = $fields
        }
    }
    return $unknown
}

# The endpoints some apply work depends on: a failed read there stops the run (a plan without the current value would
# send every field as a change). Any other endpoint is read for check rows only and its failure is an observation.
$script:ApplyReadEndpoints = @(@($script:Sections.Values | ForEach-Object { '/orgs/{org}' + $_.Path }) + '/orgs/{org}/copilot/billing')

function ConvertTo-ReferenceAnchor {
    # The anchor GitHub (and lychee) give a heading: lower case, spaces to '-', characters other than letters, digits,
    # '-' and '_' dropped.
    param([Parameter(Mandatory)][string]$Text)

    return ($Text.ToLowerInvariant() -replace '[^a-z0-9 _-]', '' -replace ' ', '-')
}

function Format-ReferenceCell {
    # One Markdown table cell: pipes and angle brackets escaped (a UI label's <organization> is not HTML), line breaks
    # flattened; '-' for an empty value.
    param([AllowNull()][object]$Value)

    $text = if ($null -eq $Value) { '' } else { ([string]$Value) -replace '\r?\n', ' ' -replace '\|', '\|' -replace '<', '\<' }
    if ($text.Trim() -eq '') {
        return '-'
    }
    return $text
}

function Format-ReferenceValue {
    # A recommended value for the reference, in code style; '-' when the row has none.
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return '-'
    }
    $text = if ($Value -is [bool]) { $Value.ToString().ToLowerInvariant() } elseif ($Value -is [array]) { @($Value) -join ', ' } else { [string]$Value }
    return '`' + (Format-ReferenceCell -Value $text) + '`'
}

function Format-ReferenceRead {
    # '`GET <endpoint> .<field>`' for a read, '-' for none.
    param([AllowNull()][object]$Read)

    if (-not $Read) {
        return '-'
    }
    return '`GET ' + $Read.Endpoint.TrimStart('/') + ' .' + $Read.Field + '`'
}

function Format-ReferenceWrite {
    # '`<METHOD> <endpoint>`' for a write, or the fallback text.
    param(
        [AllowNull()][object]$Write,
        [Parameter(Mandatory)][string]$Fallback
    )

    if (-not $Write) {
        return $Fallback
    }
    return '`' + $Write.Method + ' ' + $Write.Endpoint.TrimStart('/') + '`'
}

function Get-ReferenceUiRow {
    # One table row of the UI part for a setting row.
    param([Parameter(Mandatory)][hashtable]$Definition)

    $read = Get-SettingRead -Definition $Definition
    $write = Get-SettingWrite -Definition $Definition
    # The label, with the hint after it as the checklist shows it.
    $setting = if ($Definition.UiLabel -and $Definition.Hint) {
        "$($Definition.UiLabel) ($($Definition.Hint))"
    }
    elseif ($Definition.UiLabel) {
        $Definition.UiLabel
    }
    elseif ($Definition.Hint) {
        $Definition.Hint
    }
    # The group locates the control on the page, whatever names it; a row without a label or hint (its options are the
    # control) is named by its group alone, never by the API field, which no page shows.
    if ($Definition.UiGroup -and $setting) {
        $setting = "$($Definition.UiGroup) > $setting"
    }
    elseif ($Definition.UiGroup) {
        $setting = $Definition.UiGroup
    }
    elseif (-not $setting) {
        $setting = $Definition.Field
    }
    $api = if ($read -and $write) { 'read and write' } elseif ($read) { 'read only' } elseif ($write) { 'write only' } elseif ($Definition.Mode -eq 'manual') { 'UI only' } else { 'by area' }
    $fallback = if ($Definition.Mode -eq 'apply') { 'by the engine' } else { 'on the page' }
    $cells = @(
        (Format-ReferenceCell -Value $setting)
        '`' + (Get-SettingPath -Definition $Definition) + '`'
        (Format-ReferenceValue -Value $Definition.Recommended)
        (Format-ReferenceCell -Value $Definition.Mode)
        $api
        (Format-ReferenceRead -Read $read)
        (Format-ReferenceWrite -Write $write -Fallback $fallback)
    )
    return '| ' + ($cells -join ' | ') + ' |'
}

function Get-GitHubOrgSettingReference {
    <#
    .SYNOPSIS
    The Markdown of engine/settings.md (LF endings), from $script:SettingPages, the rows and $script:ApiCatalog.
    .DESCRIPTION
    Two parts that never mix, and no total across them: the settings pages with their rows (UI coverage) and the
    endpoints with their fields (API coverage). tools/Build-SettingReference.ps1 writes it; a test fails while the
    committed file differs.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Settings reference')
    $lines.Add('')
    $lines.Add('Generated by `tools/Build-SettingReference.ps1` from the settings pages and the rows of `engine/src` and from `engine/api-endpoints.psd1`; do not edit it. Run the script after changing a row, a page or the endpoint catalog (a test fails while this file is stale).')
    $lines.Add('')
    $lines.Add('It has two parts that are never added together: which settings pages and controls are known (UI coverage), and which API endpoints and response fields are known (API coverage). A row of the config appears in both: under its page, and as a field of its endpoint.')
    $lines.Add('')
    $lines.Add('## UI coverage')
    $lines.Add('')
    $lines.Add('Every page of the organization settings menu, in menu order. Addresses are relative to `https://github.com/organizations/<org>/settings/`.')
    $lines.Add('')

    $rows = @($script:SettingDefinitions)
    foreach ($page in $script:SettingPages) {
        $lines.Add('### ' + $page.Label + ' (`' + $page.Path + '`)')
        $lines.Add('')
        $pageRows = @(Get-PageRow -Page $page)
        switch ($page.Status) {
            'unmanaged' {
                $lines.Add('Not managed: ' + (Format-ReferenceCell -Value ([string]$page.Reason).TrimEnd('.')) + '.')
                $lines.Add('')
            }
            'pending' {
                $lines.Add('Not covered yet: the controls of this page are not catalogued, so nothing says which of them the engine manages.')
                $lines.Add('')
            }
            default {
                if ($page.Area) {
                    $lines.Add('Managed by the area `' + $page.Area + '` of the engine (see the [engine reference](README.md)).')
                    $lines.Add('')
                }
                if ($page.ReviewedOn) {
                    $lines.Add('Rows in the order of the page; UI read on ' + $page.ReviewedOn + '.')
                    $lines.Add('')
                }
                if ($pageRows.Count -gt 0 -or $page.Unmanaged) {
                    $lines.Add('| Setting | Config | Recommended | Mode | API | Read | Change |')
                    $lines.Add('| --- | --- | --- | --- | --- | --- | --- |')
                    foreach ($row in $pageRows) {
                        $lines.Add((Get-ReferenceUiRow -Definition $row))
                    }
                    if ($page.Unmanaged) {
                        foreach ($label in ($page.Unmanaged.Keys | Sort-Object -CaseSensitive)) {
                            $lines.Add('| ' + (Format-ReferenceCell -Value $label) + ' | - | - | not managed | - | - | ' + (Format-ReferenceCell -Value $page.Unmanaged[$label]) + ' |')
                        }
                    }
                    $lines.Add('')
                }
            }
        }
    }

    $lines.Add('### Fields without a page')
    $lines.Add('')
    $noUi = @($rows | Where-Object { $_.NoUi })
    if ($noUi.Count -eq 0) {
        $lines.Add('None: every row of the config has a page.')
    }
    else {
        $lines.Add('Rows with no settings page (the web UI does not show them). Their endpoints are in the API part.')
        $lines.Add('')
        $lines.Add('| Config | Recommended | Mode | Read | Change | Category |')
        $lines.Add('| --- | --- | --- | --- | --- | --- |')
        foreach ($row in $noUi) {
            $read = Get-SettingRead -Definition $row
            $entry = if ($read) { $script:ApiCatalog.Paths[$read.Endpoint] } else { $null }
            $category = if ($entry) { '[' + $entry.Category + '](#' + (ConvertTo-ReferenceAnchor -Text $entry.Category) + ')' } else { '-' }
            $cells = @(
                '`' + (Get-SettingPath -Definition $row) + '`'
                (Format-ReferenceValue -Value $row.Recommended)
                (Format-ReferenceCell -Value $row.Mode)
                (Format-ReferenceRead -Read $read)
                (Format-ReferenceWrite -Write (Get-SettingWrite -Definition $row) -Fallback '-')
                $category
            )
            $lines.Add('| ' + ($cells -join ' | ') + ' |')
        }
    }
    $lines.Add('')

    $lines.Add('## API coverage')
    $lines.Add('')
    $lines.Add('Every operation under `/orgs/{org}` and `/organizations/{org}` of REST API version `' + $script:ApiCatalog.ApiVersion + '` (reviewed on ' + $script:ApiCatalog.ReviewedOn + ') and every other one the engine calls. `read` means the engine calls the GET, not that every setting of its answer is managed: the fields column shows that. `write` is a call of the engine that changes something (`Body` lists the request fields); `unused` is not called, with the reason.')
    $lines.Add('')
    $methodOrder = @('GET', 'POST', 'PUT', 'PATCH', 'DELETE')
    $paths = $script:ApiCatalog.Paths
    $categories = @($paths.Keys | ForEach-Object { $paths[$_].Category } | Sort-Object -Unique -CaseSensitive)
    foreach ($category in $categories) {
        $lines.Add('### ' + $category)
        $lines.Add('')
        $lines.Add('| Method | Path | Status | Fields or reason |')
        $lines.Add('| --- | --- | --- | --- |')
        foreach ($path in ($paths.Keys | Where-Object { $paths[$_].Category -eq $category } | Sort-Object -CaseSensitive)) {
            $entry = $paths[$path]
            foreach ($method in ($entry.Keys | Where-Object { $_ -ne 'Category' } | Sort-Object { $methodOrder.IndexOf($_) })) {
                $operation = $entry[$method]
                $detail = switch ($operation.Status) {
                    'unused' { Format-ReferenceCell -Value $operation.Reason }
                    'write' { if ($operation.Body) { 'Body: ' + ((@($operation.Body) | ForEach-Object { '`' + $_ + '`' }) -join ', ') } else { '-' } }
                    default {
                        $parts = [System.Collections.Generic.List[string]]::new()
                        if ($method -eq 'GET') {
                            foreach ($row in ($rows | Sort-Object { Get-SettingPath -Definition $_ })) {
                                $read = Get-SettingRead -Definition $row
                                if ($read -and $read.Endpoint -eq $path) {
                                    $parts.Add('`' + $read.Field + ' (row: ' + (Get-SettingPath -Definition $row) + ')`')
                                }
                            }
                            if ($operation.Fields) {
                                foreach ($field in ($operation.Fields.Keys | Sort-Object -CaseSensitive)) {
                                    $parts.Add('`' + $field + '`: ' + (Format-ReferenceCell -Value $operation.Fields[$field]))
                                }
                            }
                        }
                        if ($parts.Count -gt 0) { $parts -join '; ' } else { '-' }
                    }
                }
                $lines.Add('| ' + $method + ' | `' + $path + '` | ' + $operation.Status + ' | ' + $detail + ' |')
            }
        }
        $lines.Add('')
    }

    return (($lines -join "`n").TrimEnd("`n") + "`n")
}
