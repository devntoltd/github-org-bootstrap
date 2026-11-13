. (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/tests/PlanIndex.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/tests/ConfigError.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '../../shared/tests/GhFake.ps1')

function Get-TestGitHubOrgConfig {
    # A valid config with every field, as validation requires; a new object on every call, so tests can change it;
    # parsed from JSON like the real config.
    return @'
{
  "configVersion": "1.0",
  "organization": "contoso",
  "inventory": {
    "owners": ["octocat", "hubot"],
    "apps": [],
    "webhookHosts": [],
    "outsideCollaborators": []
  },
  "settings": {
    "default_repository_permission": "none",
    "members_can_create_repositories": false,
    "members_can_create_public_repositories": false,
    "members_can_create_private_repositories": false,
    "members_can_create_pages": false,
    "members_can_fork_private_repositories": false,
    "deploy_keys_enabled_for_repositories": false,
    "email": "security@contoso.com",
    "is_verified": true,
    "two_factor_requirement_enabled": true,
    "members_can_delete_repositories": false,
    "members_can_change_repo_visibility": false,
    "members_can_invite_outside_collaborators": false,
    "members_can_create_teams": false,
    "members_can_delete_issues": false,
    "readers_can_create_discussions": false,
    "members_can_create_public_pages": false,
    "members_can_create_private_pages": false,
    "display_commenter_full_name_setting_enabled": false,
    "web_commit_signoff_required": false,
    "default_repository_branch": "main",
    "has_organization_projects": true,
    "has_repository_projects": true,
    "members_can_view_dependency_insights": true,
    "secret_scanning_push_protection_custom_link": null,
    "secret_scanning_validity_checks_enabled": false
  },
  "authenticationSecurity": { "two_factor_secure_methods_required": true },
  "memberPrivileges": {
    "projects_base_permission": "none",
    "app_access_requests": "members_only",
    "members_can_install_github_apps": false,
    "members_can_rename_protected_branches": false
  },
  "repositoryDefaults": { "commit_comments": "enabled" },
  "projects": { "members_can_change_project_visibility": false },
  "actions": {
    "enabled_repositories": "all",
    "allowed_actions": "selected",
    "sha_pinning_required": true,
    "selected": {
      "github_owned_allowed": true,
      "verified_allowed": false,
      "patterns_allowed": ["azure/login@*", "octo-org/octo-action@*"]
    },
    "workflow": {
      "default_workflow_permissions": "read",
      "can_approve_pull_request_reviews": false
    },
    "selfHostedRunners": { "enabled_repositories": "none" },
    "forkPullRequests": { "approval_policy": "all_external_contributors" },
    "privateForkPullRequests": {
      "run_workflows_from_fork_pull_requests": false,
      "send_write_tokens_to_workflows": false,
      "send_secrets_and_variables": false,
      "require_approval_for_fork_pr_workflows": true
    },
    "retention": { "days": 30 },
    "cache": { "retention_days": 7, "size_limit_gb": 10 },
    "oidc": { "include_claim_keys": [], "use_immutable_subject": false }
  },
  "copilotCloudAgent": { "enabled_repositories": "none" },
  "copilot": {
    "policies": {
      "public_code_suggestions": "block",
      "ide_chat": "enabled",
      "platform_chat": "enabled",
      "cli": "unconfigured",
      "code_review": "enabled",
      "ai_credit_paid_usage": "enabled",
      "bill_reviews_to_organization": true,
      "reviews_without_license": false,
      "code_review_preview_features": false,
      "default_policy_new_features": "disabled",
      "feedback_collection": false,
      "cloud_preview_features": false,
      "metrics_api": "disabled",
      "metrics_industry_comparison": "disabled",
      "usage_metrics": "disabled",
      "mcp_servers": "disabled",
      "agent_mode_ide": "enabled",
      "editor_preview_features": "disabled",
      "github_desktop": "enabled",
      "copilot_app": "enabled",
      "cli_billed_to_organization": false,
      "cloud_sessions": "disabled",
      "web_search": "disabled",
      "model_native_search": "disabled",
      "external_semantic_indexing": "disabled",
      "spaces": "unconfigured",
      "spaces_individual_access": "unconfigured",
      "spaces_individual_sharing": "disabled",
      "commit_messages": "unconfigured",
      "user_memories": "unconfigured",
      "repository_memories": "none",
      "memory_retention_days": 90,
      "dreaming": "disabled",
      "bring_your_own_key": "disabled"
    },
    "models": { "default_availability": "disabled" },
    "codeReview": {
      "default_review_effort": null,
      "maximum_review_effort": "balanced",
      "approve_pull_requests": "disabled_everywhere",
      "block_external_license_reviews": true
    },
    "internetAccess": {
      "cloud_firewall": true,
      "cloud_recommended_allowlist": true,
      "cloud_repository_custom_rules": false,
      "code_review_firewall": true,
      "code_review_recommended_allowlist": true,
      "code_review_repository_custom_rules": false
    },
    "runnerType": {
      "code_review_runner_type": "standard",
      "code_review_allow_repository_customization": false,
      "cloud_agent_runner_type": "standard",
      "cloud_agent_allow_repository_customization": false
    },
    "automations": {
      "allow_automations": "none",
      "allow_shared_automations": false,
      "require_write_access": true,
      "update_triggering_resource_only": true,
      "require_workflow_approval": true
    },
    "partnerAgents": { "claude": false, "codex": false }
  },
  "codeSecurity": {
    "name": "baseline",
    "description": "Free features",
    "default_for_new_repos": "all",
    "enforcement": "enforced",
    "settings": {
      "dependency_graph": "enabled",
      "dependabot_alerts": "enabled",
      "dependabot_security_updates": "enabled",
      "private_vulnerability_reporting": "enabled"
    }
  },
  "ruleset": {
    "name": "default-branch",
    "enforcement": "active",
    "bypass": { "organizationAdmin": "pull_request" },
    "rules": {
      "deletion": true,
      "non_fast_forward": true,
      "pullRequest": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": true,
        "require_code_owner_review": true,
        "required_review_thread_resolution": true,
        "require_extra_approval_for_unattributed_changes": true,
        "allowed_merge_methods": ["merge"],
        "requiredReviewers": [
          {
            "team": "platform-admins",
            "minimum_approvals": 1,
            "file_patterns": [".github/workflows/**", ".github/actions/**", "**/CODEOWNERS", ".github/dependabot.yml"]
          }
        ]
      },
      "copilotCodeReview": {
        "enabled": true,
        "review_on_push": true,
        "review_draft_pull_requests": false
      },
      "workflows": [
        { "repository": ".github", "path": ".github/workflows/org-checks.yml", "sha": "0123456789abcdef0123456789abcdef01234567" }
      ]
    }
  },
  "budgets": [
    { "budget_type": "ProductPricing", "budget_product_sku": "actions", "budget_amount": 0, "prevent_further_usage": true },
    { "budget_type": "BundlePricing", "budget_product_sku": "ai_credits", "budget_amount": 50, "prevent_further_usage": true }
  ],
  "copilotSeats": { "selected_usernames": ["octocat"], "selected_teams": [] },
  "personalAccessTokens": { "fine_grained": "restrict", "classic": "restrict" },
  "oauthApps": { "policy": "restricted" },
  "codespaces": { "access": "disabled", "ownership": "user" },
  "packages": { "public_creation": false, "inherit_access": true },
  "discussions": { "enabled": false },
  "interactionLimits": { "limit": "none", "pull_request_cap_enabled": false },
  "immutableReleases": { "enforced_repositories": "all" },
  "dependabot": { "default_level": "public" },
  "advancedSecurity": { "agentic_autofix": false, "ai_scan_repositories": false, "ai_scan_pull_requests": "disabled", "scan_ai_applications": false, "code_quality": false },
  "exceptions": []
}
'@ | ConvertFrom-Json
}

function Get-TestInventoryState {
    # What the inventory of Get-TestGitHubOrgConfig expects: two owners, no GitHub Apps, no webhooks, no outside
    # collaborators, and no pending invitations to the organization or its repositories.
    [pscustomobject]@{ Owners = [string[]]@('octocat', 'hubot'); Apps = @(); Webhooks = @(); OutsideCollaborators = [string[]]@(); Invitations = @(); RepositoryInvitations = @(); SkippedRepositories = [string[]]@() }
}

function Get-TestBudgetState {
    # A budget of the state, by default one Get-TestGitHubOrgConfig expects of a product.
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Sku,
        [string]$Type = 'ProductPricing',
        [string]$Scope = 'organization',
        [long]$Amount = 0,
        [bool]$PreventFurtherUsage = $true,
        [bool]$WillAlert = $true,
        [string[]]$Recipients = @('octocat', 'hubot')
    )
    [pscustomobject]@{ Id = $Id; Type = $Type; Sku = $Sku; Scope = $Scope; Amount = $Amount; PreventFurtherUsage = $PreventFurtherUsage; WillAlert = $WillAlert; Recipients = $Recipients }
}

function ConvertTo-TestBudgetResponse {
    # A budget of the state as GET /organizations/{org}/settings/billing/budgets lists it.
    param([Parameter(Mandatory)][object]$Budget)
    [pscustomobject]@{
        id                    = $Budget.Id
        budget_type           = $Budget.Type
        budget_product_sku    = $Budget.Sku
        budget_scope          = $Budget.Scope
        budget_amount         = $Budget.Amount
        prevent_further_usage = $Budget.PreventFurtherUsage
        budget_entity_name    = 'contoso'
        budget_alerting       = [pscustomobject]@{ will_alert = $Budget.WillAlert; alert_recipients = [string[]]$Budget.Recipients }
    }
}

function Get-TestCopilotSeat {
    # A seat of the state, by default one given directly and not being cancelled.
    param(
        [Parameter(Mandatory)][string]$Login,
        [string]$Team,
        [string]$PendingCancellation
    )
    [pscustomobject]@{ Login = $Login; Team = if ($Team) { $Team }; PendingCancellation = if ($PendingCancellation) { $PendingCancellation } }
}

function Get-TestCopilotSeatState {
    # The seats that match Get-TestGitHubOrgConfig: Copilot Business with selected members, one seat of octocat.
    param(
        [AllowEmptyCollection()][object[]]$Seats = @(Get-TestCopilotSeat -Login 'octocat'),
        [hashtable]$Teams = @{},
        [string]$SeatManagement = 'assign_selected'
    )
    [pscustomobject]@{ PlanType = 'business'; SeatManagement = $SeatManagement; Total = @($Seats).Count; Seats = [object[]]@($Seats); Teams = $Teams }
}

function Get-TestOrgCheckResource {
    # Endpoint -> answer of the reads of the check rows outside the sections and the Copilot plan, as the OpenAPI
    # description of 2026-03-10 documents them, with the values Get-TestGitHubOrgConfig expects. No interaction limit
    # is set, which GitHub answers with {}.
    @{
        'orgs/contoso/interaction-limits'                    = [pscustomobject]@{}
        'orgs/contoso/interaction-limits/pulls/creation-cap' = [pscustomobject]@{ enabled = $false; max_open_pull_requests = 1; include_drafts = $false }
        'orgs/contoso/settings/immutable-releases'           = [pscustomobject]@{ enforced_repositories = 'all' }
        'orgs/contoso/dependabot/repository-access'          = [pscustomobject]@{ default_level = 'public'; accessible_repositories = @() }
        'orgs/contoso/code-scanning/ai-scan'                 = [pscustomobject]@{ pr_scan = 'disabled' }
    }
}

function Get-TestCopilotPolicyResource {
    # Endpoint -> answer of the Copilot code review reads, as the OpenAPI description of 2026-03-10 documents them,
    # with the values Get-TestGitHubOrgConfig expects.
    @{
        'orgs/contoso/copilot/code-review/settings' = [pscustomobject]@{
            default_review_effort    = [pscustomobject]@{ configured = $null; effective = 'medium'; github_default = 'medium'; editable = $true; managed_by = 'organization' }
            available_review_efforts = @('low', 'medium', 'high')
        }
        'orgs/contoso/copilot/code-review/runner'   = [pscustomobject]@{ runner_type = 'standard'; runner_labels = @(); runner_group_name = $null; allow_repository_customization = $false; configured_by = 'code_review' }
        'orgs/contoso/copilot/policies/code-review' = [pscustomobject]@{ configured_state = 'enabled'; effective_state = 'enabled'; editable = $true; managed_by = 'organization' }
    }
}

function Get-TestCopilotSeatResource {
    # Endpoint -> response of the seat reads, as GitHub answers, from the state of the seats. A $null team has no
    # endpoint (GitHub answers 404).
    param([Parameter(Mandatory)][object]$CopilotSeats)

    $seats = @($CopilotSeats.Seats | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{
                assignee                  = [pscustomobject]@{ login = $_.Login; type = 'User' }
                assigning_team            = if ($_.Team) { [pscustomobject]@{ slug = $_.Team } }
                pending_cancellation_date = $_.PendingCancellation
                plan_type                 = $CopilotSeats.PlanType
            }
        })
    $billing = Get-TestCopilotBilling
    $billing.plan_type = $CopilotSeats.PlanType
    $billing.seat_management_setting = $CopilotSeats.SeatManagement
    $billing.seat_breakdown.total = $CopilotSeats.Total
    # The policies Get-TestGitHubOrgConfig expects.
    $billing.public_code_suggestions = 'block'
    $resource = @{
        'orgs/contoso/copilot/billing'       = $billing
        'orgs/contoso/copilot/billing/seats' = @{ total_seats = $seats.Count; seats = [object[]]$seats }
    }
    foreach ($endpoint in ($policies = Get-TestCopilotPolicyResource).Keys) {
        $resource[$endpoint] = $policies[$endpoint]
    }
    foreach ($team in $CopilotSeats.Teams.Keys) {
        if ($null -ne $CopilotSeats.Teams[$team]) {
            $resource["orgs/contoso/teams/$team/members"] = [object[]]@($CopilotSeats.Teams[$team] | ForEach-Object { [pscustomobject]@{ login = $_ } })
        }
    }
    return $resource
}

function Get-TestRepositoryInvitation {
    # An invitation as GET /repos/{owner}/{repo}/invitations returns it; no login is an invitee GitHub answers as null.
    param(
        [AllowNull()][string]$Login,
        [string]$Permission = 'write',
        [string]$Inviter = 'octocat',
        [string]$CreatedAt = '2026-09-30',
        [switch]$Expired
    )
    $invitee = $null
    if ($Login) {
        $invitee = [pscustomobject]@{ login = $Login }
    }
    [pscustomobject]@{
        invitee = $invitee; inviter = [pscustomobject]@{ login = $Inviter }; permissions = $Permission
        created_at = "$($CreatedAt)T08:15:00Z"; expired = [bool]$Expired
    }
}

function Get-MatchingTestGitHubOrgState {
    # The state of an organization that already matches Get-TestGitHubOrgConfig.
    [pscustomobject]@{
        Settings                = [ordered]@{
            default_repository_permission               = 'none'
            members_can_create_repositories             = $false
            members_can_create_public_repositories      = $false
            members_can_create_private_repositories     = $false
            members_can_create_pages                    = $false
            members_can_fork_private_repositories       = $false
            deploy_keys_enabled_for_repositories        = $false
            email                                       = 'security@contoso.com'
            is_verified                                 = $true
            two_factor_requirement_enabled              = $true
            members_can_delete_repositories             = $false
            members_can_change_repo_visibility          = $false
            members_can_invite_outside_collaborators    = $false
            members_can_create_teams                    = $false
            members_can_delete_issues                   = $false
            readers_can_create_discussions              = $false
            members_can_create_public_pages             = $false
            members_can_create_private_pages            = $false
            display_commenter_full_name_setting_enabled = $false
            web_commit_signoff_required                 = $false
            default_repository_branch                   = 'main'
            has_organization_projects                   = $true
            has_repository_projects                     = $true
            members_can_view_dependency_insights        = $true
            secret_scanning_push_protection_custom_link = $null
            secret_scanning_validity_checks_enabled     = $false
        }
        Actions                 = [ordered]@{ enabled_repositories = 'all'; allowed_actions = 'selected'; sha_pinning_required = $true }
        SelectedActions         = [ordered]@{ github_owned_allowed = $true; verified_allowed = $false; patterns_allowed = [string[]]@('azure/login@*', 'octo-org/octo-action@*') }
        Workflow                = [ordered]@{ default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $false }
        SelfHostedRunners       = [ordered]@{ enabled_repositories = 'none' }
        ForkPullRequests        = [ordered]@{ approval_policy = 'all_external_contributors' }
        PrivateForkPullRequests = [ordered]@{ run_workflows_from_fork_pull_requests = $false; send_write_tokens_to_workflows = $false; send_secrets_and_variables = $false; require_approval_for_fork_pr_workflows = $true }
        Retention               = [ordered]@{ days = 30 }
        CopilotCloudAgent       = [ordered]@{ enabled_repositories = 'none' }
        Inventory               = Get-TestInventoryState
        CodeSecurity            = Get-MatchingTestCodeSecurityState
        Ruleset                 = Get-MatchingTestRulesetState
        Budgets                 = @(
            Get-TestBudgetState -Id 'budget-1' -Sku 'actions' -Amount 0
            Get-TestBudgetState -Id 'budget-2' -Type 'BundlePricing' -Sku 'ai_credits' -Amount 50
        )
        CopilotSeats            = Get-TestCopilotSeatState
    }
}

function Get-DefaultTestGitHubOrgState {
    # A new organization with permissive defaults: every field differs, there is no selection yet, no code security
    # configuration and no ruleset.
    [pscustomobject]@{
        Settings                = [ordered]@{
            default_repository_permission               = 'read'
            members_can_create_repositories             = $true
            members_can_create_public_repositories      = $true
            members_can_create_private_repositories     = $true
            members_can_create_pages                    = $true
            members_can_fork_private_repositories       = $true
            deploy_keys_enabled_for_repositories        = $true
            email                                       = $null
            is_verified                                 = $false
            two_factor_requirement_enabled              = $false
            members_can_delete_repositories             = $true
            members_can_change_repo_visibility          = $true
            members_can_invite_outside_collaborators    = $true
            members_can_create_teams                    = $true
            members_can_delete_issues                   = $true
            readers_can_create_discussions              = $true
            members_can_create_public_pages             = $false
            members_can_create_private_pages            = $false
            display_commenter_full_name_setting_enabled = $false
            web_commit_signoff_required                 = $false
            default_repository_branch                   = 'main'
            has_organization_projects                   = $true
            has_repository_projects                     = $true
            members_can_view_dependency_insights        = $true
            secret_scanning_push_protection_custom_link = $null
            secret_scanning_validity_checks_enabled     = $false
        }
        Actions                 = [ordered]@{ enabled_repositories = 'all'; allowed_actions = 'all'; sha_pinning_required = $false }
        SelectedActions         = $null
        Workflow                = [ordered]@{ default_workflow_permissions = 'write'; can_approve_pull_request_reviews = $true }
        SelfHostedRunners       = [ordered]@{ enabled_repositories = 'all' }
        ForkPullRequests        = [ordered]@{ approval_policy = 'first_time_contributors' }
        PrivateForkPullRequests = [ordered]@{ run_workflows_from_fork_pull_requests = $true; send_write_tokens_to_workflows = $true; send_secrets_and_variables = $true; require_approval_for_fork_pr_workflows = $false }
        Retention               = [ordered]@{ days = 90 }
        CopilotCloudAgent       = [ordered]@{ enabled_repositories = 'all' }
        Inventory               = Get-TestInventoryState
        CodeSecurity            = Get-EmptyTestCodeSecurityState
        Ruleset                 = Get-EmptyTestRulesetState
        Budgets                 = @()
        CopilotSeats            = Get-TestCopilotSeatState -Seats @()
    }
}

function Get-TestGhConflict {
    # What gh printed on 2026-09-29 for selected-actions while allowed_actions was 'all': 409, with no "HTTP 409" text.
    [pscustomobject]@{
        ExitCode = 1
        Output   = @(
            '{"message":"Conflict","errors":"All actions and workflows are allowed on this organization","status":"409"}'
            'gh: All actions and workflows are allowed on this organization (Conflict)'
        )
    }
}

function Get-TestGhRoute {
    # Routes for every read of the engine, answering with the given state; no selection answers like GitHub (409).
    param([Parameter(Mandatory)][object]$State)

    $routes = @{
        'GET orgs/contoso'                                  = Get-TestGhResponse -Body $State.Settings
        'GET orgs/contoso/actions/permissions'              = Get-TestGhResponse -Body $State.Actions
        'GET orgs/contoso/actions/permissions/workflow'     = Get-TestGhResponse -Body $State.Workflow
        'GET orgs/contoso/copilot/coding-agent/permissions' = Get-TestGhResponse -Body $State.CopilotCloudAgent
    }
    $budgets = @($State.Budgets | Where-Object { $_ } | ForEach-Object { ConvertTo-TestBudgetResponse -Budget $_ })
    $routes['GET organizations/contoso/settings/billing/budgets?per_page=100'] = Get-TestGhObjectPagesResponse -Property budgets -Items $budgets
    foreach ($endpoint in ($checks = Get-TestOrgCheckResource).Keys) {
        $routes["GET $endpoint"] = Get-TestGhResponse -Body $checks[$endpoint]
    }
    if ($State.SelectedActions) {
        $routes['GET orgs/contoso/actions/permissions/selected-actions'] = Get-TestGhResponse -Body $State.SelectedActions
    }
    else {
        $routes['GET orgs/contoso/actions/permissions/selected-actions'] = Get-TestGhConflict
    }
    # The Actions policy reads.
    $policyPaths = [ordered]@{
        SelfHostedRunners       = 'self-hosted-runners'
        ForkPullRequests        = 'fork-pr-contributor-approval'
        PrivateForkPullRequests = 'fork-pr-workflows-private-repos'
        Retention               = 'artifact-and-log-retention'
    }
    foreach ($key in $policyPaths.Keys) {
        $routes["GET orgs/contoso/actions/permissions/$($policyPaths[$key])"] = Get-TestGhResponse -Body $State.$key
    }
    # The inventory reads, answering like GitHub from the state's inventory.
    if ($State.PSObject.Properties['Inventory'] -and $null -ne $State.Inventory) {
        $owners = @($State.Inventory.Owners | ForEach-Object { [pscustomobject]@{ login = $_ } })
        $routes['GET orgs/contoso/members?role=admin&per_page=100'] = Get-TestGhPagesResponse -Items $owners
        $installations = @($State.Inventory.Apps | ForEach-Object {
                [pscustomobject]@{ app_slug = $_.Slug; repository_selection = $_.RepositorySelection; permissions = [pscustomobject]$_.Permissions }
            })
        $routes['GET orgs/contoso/installations?per_page=100'] = Get-TestGhObjectPagesResponse -Property installations -Items $installations
        # A webhook without VerifiesTls or HasSecret is a safe one; GitHub masks a set secret.
        $hooks = @($State.Inventory.Webhooks | ForEach-Object {
                $hookConfig = [ordered]@{ url = $_.Url; content_type = 'json'; insecure_ssl = '0' }
                if ($_.PSObject.Properties['VerifiesTls'] -and -not $_.VerifiesTls) {
                    $hookConfig.insecure_ssl = '1'
                }
                if (-not $_.PSObject.Properties['HasSecret'] -or $_.HasSecret) {
                    $hookConfig.secret = '********'
                }
                [pscustomobject]@{ config = [pscustomobject]$hookConfig; events = [string[]]@($_.Events); active = $_.Active }
            })
        $routes['GET orgs/contoso/hooks?per_page=100'] = Get-TestGhPagesResponse -Items $hooks
        $collaborators = @($State.Inventory.OutsideCollaborators | ForEach-Object { [pscustomobject]@{ login = $_ } })
        $routes['GET orgs/contoso/outside_collaborators?per_page=100'] = Get-TestGhPagesResponse -Items $collaborators
        $invitations = @($State.Inventory.Invitations | ForEach-Object {
                [pscustomobject]@{ login = $_.Login; email = $_.Email; role = $_.Role; inviter = [pscustomobject]@{ login = $_.Inviter }; created_at = "$($_.CreatedAt)T08:15:00Z" }
            })
        $routes['GET orgs/contoso/invitations?per_page=100'] = Get-TestGhPagesResponse -Items $invitations
    }
    # Repository name -> the invitations of RepositoryInvitations, answered with the code security repository list.
    $repositoryInvitations = @{}
    if ($State.PSObject.Properties['Inventory'] -and $null -ne $State.Inventory -and $State.Inventory.PSObject.Properties['RepositoryInvitations']) {
        foreach ($invitation in @($State.Inventory.RepositoryInvitations)) {
            if (-not $repositoryInvitations.ContainsKey($invitation.Repository)) {
                $repositoryInvitations[$invitation.Repository] = [System.Collections.Generic.List[object]]::new()
            }
            $repositoryInvitations[$invitation.Repository].Add((Get-TestRepositoryInvitation -Login $invitation.Login -Permission $invitation.Permission -Inviter $invitation.Inviter -CreatedAt $invitation.CreatedAt -Expired:$invitation.Expired))
        }
    }
    # The code security reads, answering like GitHub from the state's code security.
    if ($State.PSObject.Properties['CodeSecurity'] -and $null -ne $State.CodeSecurity) {
        $codeSecurity = $State.CodeSecurity
        $configurations = @()
        $defaults = @()
        if ($codeSecurity.Configuration) {
            $own = $codeSecurity.Configuration
            $configuration = [pscustomobject]@{ id = $own.Id; name = $own.Name; target_type = 'organization'; description = $own.Description; enforcement = $own.Enforcement }
            foreach ($field in $own.Settings.Keys) {
                $configuration | Add-Member -NotePropertyName $field -NotePropertyValue $own.Settings[$field]
            }
            $configurations = @($configuration)
            if ($codeSecurity.Default) {
                $defaults = @([pscustomobject]@{ default_for_new_repos = $codeSecurity.Default; configuration = [pscustomobject]@{ id = $own.Id; name = $own.Name } })
            }
        }
        $repositories = [ordered]@{}
        foreach ($repository in @($codeSecurity.Repositories)) {
            $repositories[$repository.Name] = $null
            if ($null -ne $repository.ConfigurationId) {
                $repositories[$repository.Name] = [pscustomobject]@{ status = $repository.Status; configuration = [pscustomobject]@{ id = $repository.ConfigurationId; name = $repository.ConfigurationName } }
            }
        }
        $routes = Add-TestCodeSecurityRoute -Route $routes -Configurations $configurations -Defaults $defaults -Repositories $repositories -Invitations $repositoryInvitations
    }
    if ($State.PSObject.Properties['Ruleset'] -and $null -ne $State.Ruleset) {
        $routes = Add-TestRulesetRoute -Route $routes -Ruleset $State.Ruleset
    }
    if ($State.PSObject.Properties['CopilotSeats'] -and $null -ne $State.CopilotSeats) {
        $seats = Get-TestCopilotSeatResource -CopilotSeats $State.CopilotSeats
        $routes['GET orgs/contoso/copilot/billing'] = Get-TestGhResponse -Body $seats['orgs/contoso/copilot/billing']
        $routes['GET orgs/contoso/copilot/billing/seats?per_page=100'] = Get-TestGhObjectPagesResponse -Property seats -Items $seats['orgs/contoso/copilot/billing/seats'].seats
        foreach ($endpoint in ($policies = Get-TestCopilotPolicyResource).Keys) {
            $routes["GET $endpoint"] = Get-TestGhResponse -Body $policies[$endpoint]
        }
        foreach ($endpoint in @($seats.Keys | Where-Object { $_ -like '*/members' })) {
            $routes["GET ${endpoint}?per_page=100"] = Get-TestGhPagesResponse -Items $seats[$endpoint]
        }
    }
    return $routes
}

function Get-TestCodeSecurityConfiguration {
    # A configuration as GET /orgs/{org}/code-security/configurations returns it.
    param(
        [long]$Id = 42,
        [string]$Name = 'baseline',
        [string]$TargetType = 'organization',
        [string]$State = 'enabled'
    )
    [pscustomobject]@{
        id = $Id; name = $Name; target_type = $TargetType; description = 'Free features'
        dependency_graph = $State; dependabot_alerts = $State; dependabot_security_updates = $State; private_vulnerability_reporting = $State
        advanced_security = 'disabled'; enforcement = 'enforced'
    }
}

function Add-TestCodeSecurityRoute {
    # Adds the code security reads to routes from Get-TestGhRoute. Repositories: ordered name -> the attached
    # configuration response ({ status; configuration }) or $null for none (GitHub answers 204, gh prints nothing).
    # A repository attached to an organization or global configuration of Configurations is in its list; it
    # gets a route of its own only with the status 'detached', like every other repository. Vanished: repositories in
    # the repository list whose own reads answer 404 (deleted, renamed or transferred meanwhile). Invitations:
    # repository name -> its pending invitations (Get-TestRepositoryInvitation); every other repository has none.
    # Visibility: repository name -> its visibility; every other repository is private.
    # Lists come as gh --paginate --slurp prints them, split into pages of PageSize.
    param(
        [Parameter(Mandatory)][hashtable]$Route,
        [AllowEmptyCollection()][object[]]$Configurations = @(),
        [AllowEmptyCollection()][object[]]$Defaults = @(),
        [System.Collections.IDictionary]$Repositories = [ordered]@{},
        [string[]]$Archived = @(),
        [string[]]$Vanished = @(),
        [hashtable]$Invitations = @{},
        [hashtable]$Visibility = @{},
        [int]$PageSize = 100
    )

    $Route['GET orgs/contoso/code-security/configurations?per_page=100'] = Get-TestGhPagesResponse -Items $Configurations -PageSize $PageSize
    $Route['GET orgs/contoso/code-security/configurations/defaults'] = Get-TestGhListResponse -Items $Defaults
    $names = @($Repositories.Keys) + @($Vanished)
    $repositoryItems = @($names | ForEach-Object {
            $repositoryVisibility = if ($Visibility.ContainsKey($_)) { $Visibility[$_] } else { 'private' }
            [pscustomobject]@{ name = $_; archived = ($_ -in $Archived); visibility = $repositoryVisibility }
        })
    $Route['GET orgs/contoso/repos?per_page=100'] = Get-TestGhPagesResponse -Items $repositoryItems -PageSize $PageSize
    foreach ($name in $Repositories.Keys) {
        $Route["GET repos/contoso/$name/invitations?per_page=100"] = Get-TestGhPagesResponse -Items @($Invitations[$name] | Where-Object { $null -ne $_ }) -PageSize $PageSize
    }
    $listed = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($configuration in @($Configurations | Where-Object { $_.target_type -in 'organization', 'global' })) {
        $items = @(foreach ($name in $Repositories.Keys) {
                $attached = $Repositories[$name]
                if ($null -ne $attached -and [long]$attached.configuration.id -eq [long]$configuration.id) {
                    [pscustomobject]@{ status = $attached.status; repository = [pscustomobject]@{ name = $name } }
                    if ($attached.status -ne 'detached') {
                        $listed.Add($name) | Out-Null
                    }
                }
            })
        $Route["GET orgs/contoso/code-security/configurations/$($configuration.id)/repositories?per_page=100"] = Get-TestGhPagesResponse -Items $items -PageSize $PageSize
    }
    foreach ($name in @($Repositories.Keys | Where-Object { -not $listed.Contains($_) })) {
        if ($null -eq $Repositories[$name]) {
            $Route["GET repos/contoso/$name/code-security-configuration"] = [pscustomobject]@{ ExitCode = 0; Output = '' }
        }
        else {
            $Route["GET repos/contoso/$name/code-security-configuration"] = Get-TestGhResponse -Body $Repositories[$name]
        }
    }
    return $Route
}

function Get-MatchingTestCodeSecurityState {
    # The code security state that matches Get-TestGitHubOrgConfig: configuration 42, default for all, attached.
    [pscustomobject]@{
        Configuration       = [pscustomobject]@{
            Id          = 42
            Name        = 'baseline'
            Description = 'Free features'
            Enforcement = 'enforced'
            Settings    = [ordered]@{ dependency_graph = 'enabled'; dependabot_alerts = 'enabled'; dependabot_security_updates = 'enabled'; private_vulnerability_reporting = 'enabled' }
        }
        Default             = 'all'
        OtherDefaults       = @()
        Repositories        = @(
            [pscustomobject]@{ Name = 'repo-a'; ConfigurationId = 42; ConfigurationName = 'baseline'; Status = 'attached' }
            [pscustomobject]@{ Name = 'repo-b'; ConfigurationId = 42; ConfigurationName = 'baseline'; Status = 'attaching' }
        )
        SkippedRepositories = @()
    }
}

function Get-EmptyTestCodeSecurityState {
    # No configuration, no default, two repositories without a configuration.
    [pscustomobject]@{
        Configuration       = $null
        Default             = $null
        OtherDefaults       = @()
        Repositories        = @(
            [pscustomobject]@{ Name = 'repo-a'; ConfigurationId = $null; ConfigurationName = $null; Status = $null }
            [pscustomobject]@{ Name = 'repo-b'; ConfigurationId = $null; ConfigurationName = $null; Status = $null }
        )
        SkippedRepositories = @()
    }
}

function Get-TestRulesetDetail {
    # A ruleset as GET /orgs/{org}/rulesets/{id} returns it, matching the ruleset of Get-TestGitHubOrgConfig: team
    # 'platform-admins' is id 11, repository '.github' id 21. GitHub adds fields the engine never sends.
    param(
        [long]$Id = 7,
        [string]$Name = 'default-branch',
        [string]$Enforcement = 'active'
    )
    [pscustomobject]@{
        id                      = $Id
        name                    = $Name
        target                  = 'branch'
        source_type             = 'Organization'
        source                  = 'contoso'
        enforcement             = $Enforcement
        conditions              = [pscustomobject]@{
            ref_name        = [pscustomobject]@{ include = @('~DEFAULT_BRANCH'); exclude = @() }
            repository_name = [pscustomobject]@{ include = @('~ALL'); exclude = @(); protected = $false }
        }
        bypass_actors           = @([pscustomobject]@{ actor_id = $null; actor_type = 'OrganizationAdmin'; bypass_mode = 'pull_request' })
        rules                   = @(
            [pscustomobject]@{ type = 'deletion' }
            [pscustomobject]@{ type = 'non_fast_forward' }
            [pscustomobject]@{
                type       = 'pull_request'
                parameters = [pscustomobject]@{
                    required_approving_review_count                 = 1
                    dismiss_stale_reviews_on_push                   = $true
                    require_last_push_approval                      = $true
                    require_code_owner_review                       = $true
                    required_review_thread_resolution               = $true
                    require_extra_approval_for_unattributed_changes = $true
                    allowed_merge_methods                           = @('merge')
                    required_reviewers                              = @([pscustomobject]@{
                            minimum_approvals = 1
                            file_patterns     = @('.github/workflows/**', '.github/actions/**', '**/CODEOWNERS', '.github/dependabot.yml')
                            reviewer          = [pscustomobject]@{ id = 11; type = 'Team' }
                        })
                }
            }
            [pscustomobject]@{
                type       = 'copilot_code_review'
                parameters = [pscustomobject]@{ review_on_push = $true; review_draft_pull_requests = $false }
            }
            [pscustomobject]@{
                type       = 'workflows'
                parameters = [pscustomobject]@{
                    do_not_enforce_on_create = $true
                    workflows                = @([pscustomobject]@{ repository_id = 21; path = '.github/workflows/org-checks.yml'; sha = '0123456789abcdef0123456789abcdef01234567' })
                }
            }
        )
        node_id                 = 'RRS_lACqUmVwb3NpdG9yec4AAAAH'
        created_at              = '2026-11-03T08:15:00Z'
        updated_at              = '2026-11-03T08:15:00Z'
        current_user_can_bypass = 'pull_requests_only'
        _links                  = [pscustomobject]@{ self = [pscustomobject]@{ href = "https://api.github.com/orgs/contoso/rulesets/$Id" } }
    }
}

function Get-TestRulesetReference {
    # The text of engine/examples/org-checks.yml, the reference copy of the central workflow.
    Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../examples/org-checks.yml') -Raw
}

function Get-MatchingTestRulesetState {
    # The ruleset state that matches Get-TestGitHubOrgConfig: the ruleset exists, the team has write access to every
    # repository, the private .github repository shares the reference copy at the configured commit, and the
    # organization has Copilot Business with one seat.
    $teams = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    $teams['platform-admins'] = [pscustomobject]@{ Id = 11; Slug = 'platform-admins'; HasRepositoryWrite = $true }
    [pscustomobject]@{
        Current                = Get-TestRulesetDetail
        OtherRulesets          = @()
        Teams                  = $teams
        WorkflowSources        = @{
            '.github/.github/workflows/org-checks.yml@0123456789abcdef0123456789abcdef01234567' = [pscustomobject]@{
                RepositoryId = 21; Visibility = 'private'; AccessLevel = 'organization'; Content = Get-TestRulesetReference
            }
        }
        RepositoryVisibilities = [string[]]@('private')
        References             = @{ 'org-checks.yml' = Get-TestRulesetReference }
        Copilot                = [pscustomobject]@{ PlanType = 'business'; Seats = 1 }
    }
}

function Get-EmptyTestRulesetState {
    # No ruleset yet; the team and the central workflow are in place.
    $state = Get-MatchingTestRulesetState
    $state.Current = $null
    $state
}

function Get-TestCopilotBilling {
    # GET /orgs/{org}/copilot/billing of an organization on GitHub Team that never bought Copilot, as GitHub answered
    # it on 2026-11-03: 200, plan_type business, no seats, seat management unconfigured.
    [pscustomobject]@{
        seat_breakdown          = [pscustomobject]@{ pending_invitation = 0; pending_cancellation = 0; added_this_cycle = 0; total = 0; active_this_cycle = 0; inactive_this_cycle = 0 }
        seat_management_setting = 'unconfigured'
        plan_type               = 'business'
        public_code_suggestions = 'allow'
        ide_chat                = 'enabled'
        cli                     = 'unconfigured'
        platform_chat           = 'enabled'
    }
}

function Get-TestRulesetResource {
    # Endpoint -> response of every ruleset read, answering like GitHub from a ruleset state; a key with per_page is
    # a list read with --paginate. A $null team or workflow source has no endpoint (GitHub answers 404), and so has
    # the file of a source without Content. A $null Copilot answers like an organization that never bought it
    # (Get-TestCopilotBilling). Organization roles: ids 1..5 for the predefined ones; a team with HasRepositoryWrite is
    # listed under all_repo_write.
    param([Parameter(Mandatory)][object]$Ruleset)

    $listed = @()
    if ($Ruleset.Current) {
        $current = $Ruleset.Current
        $listed = @([pscustomobject]@{ id = $current.id; name = $current.name; target = $current.target; source_type = $current.source_type; source = $current.source; enforcement = $current.enforcement })
    }
    $others = @($Ruleset.OtherRulesets | ForEach-Object {
            [pscustomobject]@{ id = $_.Id; name = $_.Name; target = $_.Target; source_type = 'Organization'; source = 'contoso'; enforcement = $_.Enforcement }
        })
    $resource = @{
        'orgs/contoso/rulesets?per_page=100' = [object[]]($listed + $others)
    }
    if ($Ruleset.Current) {
        $resource["orgs/contoso/rulesets/$($Ruleset.Current.id)"] = $Ruleset.Current
    }
    $writers = @()
    foreach ($slug in $Ruleset.Teams.Keys) {
        $team = $Ruleset.Teams[$slug]
        if ($null -ne $team) {
            $resource["orgs/contoso/teams/$($team.Slug)"] = [pscustomobject]@{ id = $team.Id; slug = $team.Slug; name = $team.Slug }
            if ($team.HasRepositoryWrite) {
                $writers += [pscustomobject]@{ id = $team.Id; slug = $team.Slug; assignment = 'direct' }
            }
        }
    }
    $roles = @('all_repo_read', 'all_repo_triage', 'all_repo_write', 'all_repo_maintain', 'all_repo_admin')
    $resource['orgs/contoso/organization-roles'] = [pscustomobject]@{
        total_count = $roles.Count
        roles       = @(for ($i = 0; $i -lt $roles.Count; $i++) { [pscustomobject]@{ id = $i + 1; name = $roles[$i]; source = 'Predefined' } })
    }
    for ($i = 0; $i -lt $roles.Count; $i++) {
        $teams = @()
        if ($roles[$i] -eq 'all_repo_write') {
            $teams = $writers
        }
        $resource["orgs/contoso/organization-roles/$($i + 1)/teams?per_page=100"] = [object[]]$teams
    }
    $resource['orgs/contoso/copilot/billing'] = Get-TestCopilotBilling
    if ($null -ne $Ruleset.Copilot) {
        $resource['orgs/contoso/copilot/billing'] = [pscustomobject]@{
            seat_breakdown          = [pscustomobject]@{ total = $Ruleset.Copilot.Seats; added_this_cycle = 0; pending_cancellation = 0; pending_invitation = 0; active_this_cycle = $Ruleset.Copilot.Seats; inactive_this_cycle = 0 }
            seat_management_setting = 'assign_selected'
            plan_type               = $Ruleset.Copilot.PlanType
            public_code_suggestions = 'block'
            ide_chat                = 'enabled'
            platform_chat           = 'enabled'
            cli                     = 'enabled'
        }
    }
    foreach ($key in $Ruleset.WorkflowSources.Keys) {
        $source = $Ruleset.WorkflowSources[$key]
        if ($null -eq $source) {
            continue
        }
        # "<repository>/<path>@<sha>"; a repository name has no slash.
        $repository, $rest = $key.Split('/', 2)
        $path, $sha = $rest.Split('@', 2)
        $resource["repos/contoso/$repository"] = [pscustomobject]@{ id = $source.RepositoryId; name = $repository; visibility = $source.Visibility }
        $resource["repos/contoso/$repository/actions/permissions/access"] = [pscustomobject]@{ access_level = $source.AccessLevel }
        if ($null -ne $source.Content) {
            $resource["repos/contoso/$repository/contents/$($path)?ref=$sha"] = Get-TestGhContent -Path $path -Text $source.Content
        }
    }
    return $resource
}

function Get-TestGhContent {
    # A file as GET /repos/{owner}/{repo}/contents/{path} returns it: base64 of the UTF-8 bytes in lines of 60.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
    $lines = for ($start = 0; $start -lt $base64.Length; $start += 60) { $base64.Substring($start, [Math]::Min(60, $base64.Length - $start)) }
    [pscustomobject]@{ type = 'file'; encoding = 'base64'; path = $Path; name = (Split-Path -Path $Path -Leaf); content = (@($lines) -join "`n") + "`n" }
}

function Add-TestRulesetRoute {
    # Adds the ruleset reads of a ruleset state to routes from Get-TestGhRoute.
    param(
        [Parameter(Mandatory)][hashtable]$Route,
        [Parameter(Mandatory)][object]$Ruleset
    )
    $resource = Get-TestRulesetResource -Ruleset $Ruleset
    foreach ($endpoint in $resource.Keys) {
        if ($endpoint -like '*per_page=*') {
            $Route["GET $endpoint"] = Get-TestGhPagesResponse -Items @($resource[$endpoint])
        }
        else {
            $Route["GET $endpoint"] = Get-TestGhResponse -Body $resource[$endpoint]
        }
    }
    return $Route
}

function ConvertTo-TestGitHubOrgResource {
    # The fake store of an organization in the given state, as GitHub answers, with the given extra settings and
    # code security endpoints and the ruleset of the state; the inventory is the one Get-TestGitHubOrgConfig expects.
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][hashtable]$CodeSecurity
    )

    $organization = [ordered]@{ login = 'contoso'; id = 1001; plan = [ordered]@{ name = 'team' } }
    foreach ($source in $Settings, $State.Settings) {
        foreach ($field in $source.Keys) {
            $organization[$field] = $source[$field]
        }
    }
    $resource = @{
        'orgs/contoso'                                                     = $organization
        'orgs/contoso/actions/permissions'                                 = $State.Actions
        'orgs/contoso/actions/permissions/workflow'                        = $State.Workflow
        'orgs/contoso/actions/permissions/self-hosted-runners'             = $State.SelfHostedRunners
        'orgs/contoso/actions/permissions/fork-pr-contributor-approval'    = $State.ForkPullRequests
        'orgs/contoso/actions/permissions/fork-pr-workflows-private-repos' = $State.PrivateForkPullRequests
        'orgs/contoso/actions/permissions/artifact-and-log-retention'      = $State.Retention
        'orgs/contoso/copilot/coding-agent/permissions'                    = $State.CopilotCloudAgent
        'organizations/contoso/settings/billing/budgets'                   = @{ budgets = @($State.Budgets | Where-Object { $_ } | ForEach-Object { ConvertTo-TestBudgetResponse -Budget $_ }); has_next_page = $false; total_count = @($State.Budgets | Where-Object { $_ }).Count }
        'orgs/contoso/members?role=admin'                                  = @($State.Inventory.Owners | ForEach-Object { @{ login = $_ } })
        'orgs/contoso/installations'                                       = @{ total_count = 0; installations = @() }
        'orgs/contoso/hooks'                                               = @()
        'orgs/contoso/outside_collaborators'                               = @()
        'orgs/contoso/invitations'                                         = @()
        'orgs/contoso/repos'                                               = @(
            @{ name = 'repo-a'; archived = $false; visibility = 'private' }
            @{ name = 'repo-b'; archived = $false; visibility = 'private' }
            @{ name = 'old-repo'; archived = $true; visibility = 'private' }
        )
        'repos/contoso/repo-a/invitations'                                 = @()
        'repos/contoso/repo-b/invitations'                                 = @()
        'repos/contoso/old-repo/invitations'                               = @()
    }
    # GitHub keeps a selection while allowed_actions is not 'selected' and answers 409 for it (Register-TestGitHubOrgFake).
    $resource['orgs/contoso/actions/permissions/selected-actions'] = $State.SelectedActions
    if ($null -eq $State.SelectedActions) {
        $resource['orgs/contoso/actions/permissions/selected-actions'] = @{ github_owned_allowed = $false; verified_allowed = $true; patterns_allowed = @() }
    }
    foreach ($key in $CodeSecurity.Keys) {
        $resource[$key] = $CodeSecurity[$key]
    }
    $ruleset = Get-TestRulesetResource -Ruleset $State.Ruleset
    foreach ($key in $ruleset.Keys) {
        $resource[$key] = $ruleset[$key]
    }
    $seats = Get-TestCopilotSeatResource -CopilotSeats $State.CopilotSeats
    foreach ($key in $seats.Keys) {
        $resource[$key] = $seats[$key]
    }
    $checks = Get-TestOrgCheckResource
    foreach ($key in $checks.Keys) {
        $resource[$key] = $checks[$key]
    }
    return $resource
}

function Get-PermissiveTestGitHubOrgResource {
    # The fake store of an organization that differs from Get-TestGitHubOrgConfig in every apply field:
    # Get-DefaultTestGitHubOrgState, no email, only GitHub's built-in code security configuration, and two
    # repositories without a configuration besides an archived one.
    ConvertTo-TestGitHubOrgResource -State (Get-DefaultTestGitHubOrgState) -Settings @{ email = $null; is_verified = $false } -CodeSecurity @{
        'orgs/contoso/code-security/configurations'          = @(Get-TestCodeSecurityConfiguration -Id 17 -Name 'GitHub recommended' -TargetType 'global')
        'orgs/contoso/code-security/configurations/defaults' = @()
        'repos/contoso/repo-a/code-security-configuration'   = $null
        'repos/contoso/repo-b/code-security-configuration'   = $null
    }
}

function Get-MatchingTestGitHubOrgResource {
    # The fake store of an organization that already matches Get-TestGitHubOrgConfig.
    $attached = @{ status = 'attached'; configuration = @{ id = 42; name = 'baseline' } }
    ConvertTo-TestGitHubOrgResource -State (Get-MatchingTestGitHubOrgState) -Settings @{ email = 'security@contoso.com'; is_verified = $true } -CodeSecurity @{
        'orgs/contoso/code-security/configurations'          = @(
            Get-TestCodeSecurityConfiguration -Id 17 -Name 'GitHub recommended' -TargetType 'global'
            Get-TestCodeSecurityConfiguration -Id 42
        )
        'orgs/contoso/code-security/configurations/defaults' = @(@{ default_for_new_repos = 'all'; configuration = @{ id = 42; name = 'baseline' } })
        'repos/contoso/repo-a/code-security-configuration'   = $attached
        'repos/contoso/repo-b/code-security-configuration'   = $attached
    }
}

function Find-TestCodeSecurityConfiguration {
    # The configuration with the id in the store of the fake, or $null.
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][long]$Id
    )
    @($Store["orgs/$Organization/code-security/configurations"]) | Where-Object { [long]$_.id -eq $Id } | Select-Object -First 1
}

function Save-TestRulesetFakeEntry {
    # Stores a ruleset of a create or update request in the store of the fake as GitHub keeps it: the details with
    # the fields GitHub adds and the rules in another order, and its entry in the list of rulesets. Returns the details.
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][long]$Id,
        [Parameter(Mandatory)][object]$Body
    )

    $detail = [pscustomobject]@{ id = $Id; source_type = 'Organization'; source = $Organization }
    foreach ($property in $Body.PSObject.Properties) {
        $detail | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }
    $rules = @($detail.rules)
    [array]::Reverse($rules)
    $detail.rules = $rules
    $detail | Add-Member -NotePropertyName node_id -NotePropertyValue "RRS_$Id"
    $detail | Add-Member -NotePropertyName created_at -NotePropertyValue '2026-11-03T08:15:00Z'
    $detail | Add-Member -NotePropertyName updated_at -NotePropertyValue '2026-11-03T09:30:00Z'
    $detail | Add-Member -NotePropertyName current_user_can_bypass -NotePropertyValue 'pull_requests_only'
    $detail | Add-Member -NotePropertyName _links -NotePropertyValue ([pscustomobject]@{ self = [pscustomobject]@{ href = "https://api.github.com/orgs/$Organization/rulesets/$Id" } })
    $Store["orgs/$Organization/rulesets/$Id"] = $detail

    $key = "orgs/$Organization/rulesets"
    $entry = [pscustomobject]@{ id = $Id; name = $detail.name; target = $detail.target; enforcement = $detail.enforcement; source_type = 'Organization'; source = $Organization }
    $others = @($Store[$key] | Where-Object { $null -ne $_ -and [long]$_.id -ne $Id })
    $Store[$key] = [object[]]($others + $entry)
    $detail
}

function Register-TestGitHubOrgFake {
    # The fake GitHub API with what the generic rules of Register-TestGhFake do not cover: the selection of actions
    # answers 409 while allowed_actions is not 'selected', and code security configurations are created, changed,
    # made the default and attached as GitHub documents it, and the organization ruleset is created and replaced.
    param([Parameter(Mandatory)][hashtable]$Resource)

    $handler = [ordered]@{
        '^POST orgs/(?<org>[^/]+)/copilot/billing/selected_users$'                      = {
            param($Store, $Request)
            $key = "orgs/$($Request.Match.org)/copilot/billing/seats"
            $added = @($Request.Body.selected_usernames | ForEach-Object { [pscustomobject]@{ assignee = [pscustomobject]@{ login = $_; type = 'User' }; assigning_team = $null; pending_cancellation_date = $null } })
            $Store[$key].seats = [object[]](@($Store[$key].seats | Where-Object { $_ }) + $added)
            $Store[$key].total_seats = @($Store[$key].seats).Count
            $Store["orgs/$($Request.Match.org)/copilot/billing"].seat_breakdown.total = @($Store[$key].seats).Count
            [pscustomobject]@{ seats_created = $added.Count }
        }
        '^POST orgs/(?<org>[^/]+)/copilot/billing/selected_teams$'                      = {
            # A seat for each member of each team, assigned through the team; a member who holds a seat already, or got
            # one through an earlier team of the request, gets no second one.
            param($Store, $Request)
            $key = "orgs/$($Request.Match.org)/copilot/billing/seats"
            $holders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($seat in @($Store[$key].seats | Where-Object { $_ })) {
                $null = $holders.Add($seat.assignee.login)
            }
            $added = @(foreach ($team in @($Request.Body.selected_teams)) {
                    foreach ($member in @($Store["orgs/$($Request.Match.org)/teams/$team/members"] | Where-Object { $_ })) {
                        if ($holders.Add($member.login)) {
                            [pscustomobject]@{ assignee = [pscustomobject]@{ login = $member.login; type = 'User' }; assigning_team = [pscustomobject]@{ slug = $team }; pending_cancellation_date = $null }
                        }
                    }
                })
            $Store[$key].seats = [object[]](@($Store[$key].seats | Where-Object { $_ }) + $added)
            $Store[$key].total_seats = @($Store[$key].seats).Count
            $Store["orgs/$($Request.Match.org)/copilot/billing"].seat_breakdown.total = @($Store[$key].seats).Count
            [pscustomobject]@{ seats_created = $added.Count }
        }
        '^POST organizations/(?<org>[^/]+)/settings/billing/budgets$'                   = {
            param($Store, $Request)
            $key = "organizations/$($Request.Match.org)/settings/billing/budgets"
            $budgets = @($Store[$key].budgets | Where-Object { $_ })
            $created = [pscustomobject]@{ id = "budget-$($budgets.Count + 1)"; budget_entity_name = $Request.Match.org }
            foreach ($property in $Request.Body.PSObject.Properties) {
                $created | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
            $Store[$key].budgets = [object[]]($budgets + $created)
            [pscustomobject]@{ message = 'Budget successfully created.'; budget = $created }
        }
        '^PATCH organizations/(?<org>[^/]+)/settings/billing/budgets/(?<id>[^/]+)$'     = {
            param($Store, $Request)
            $budget = @($Store["organizations/$($Request.Match.org)/settings/billing/budgets"].budgets | Where-Object { $_.id -eq $Request.Match.id }) | Select-Object -First 1
            if (-not $budget) {
                return Get-TestGhFakeError -Message "gh: Not Found (HTTP 404): $($Request.Endpoint)"
            }
            foreach ($property in $Request.Body.PSObject.Properties) {
                $budget | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
            $budget
        }
        '^(GET|PUT) orgs/(?<org>[^/]+)/actions/permissions/selected-actions$'           = {
            param($Store, $Request)
            if ($Store["orgs/$($Request.Match.org)/actions/permissions"].allowed_actions -ne 'selected') {
                Get-TestGhFakeError -Message ((Get-TestGhConflict).Output -join "`n")
            }
        }
        '^POST orgs/(?<org>[^/]+)/code-security/configurations$'                        = {
            param($Store, $Request)
            $key = "orgs/$($Request.Match.org)/code-security/configurations"
            $configurations = @($Store[$key])
            # GitHub's defaults for what the request leaves out.
            $created = [pscustomobject]@{
                id = 1 + [long](($configurations | Measure-Object -Property id -Maximum).Maximum); target_type = 'organization'
                description = ''; enforcement = 'enforced'; advanced_security = 'disabled'
                dependency_graph = 'enabled'; dependabot_alerts = 'disabled'; dependabot_security_updates = 'disabled'; private_vulnerability_reporting = 'disabled'
            }
            foreach ($property in $Request.Body.PSObject.Properties) {
                $created | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
            $Store[$key] = [object[]]($configurations + $created)
            $created
        }
        '^PATCH orgs/(?<org>[^/]+)/code-security/configurations/(?<id>\d+)$'            = {
            param($Store, $Request)
            $configuration = Find-TestCodeSecurityConfiguration -Store $Store -Organization $Request.Match.org -Id $Request.Match.id
            if (-not $configuration) {
                return Get-TestGhFakeError -Message "gh: Not Found (HTTP 404): $($Request.Endpoint)"
            }
            foreach ($property in $Request.Body.PSObject.Properties) {
                $configuration | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
            $configuration
        }
        '^PUT orgs/(?<org>[^/]+)/code-security/configurations/(?<id>\d+)/defaults$'     = {
            param($Store, $Request)
            $configuration = Find-TestCodeSecurityConfiguration -Store $Store -Organization $Request.Match.org -Id $Request.Match.id
            if (-not $configuration) {
                return Get-TestGhFakeError -Message "gh: Not Found (HTTP 404): $($Request.Endpoint)"
            }
            $key = "orgs/$($Request.Match.org)/code-security/configurations/defaults"
            $entry = [pscustomobject]@{ default_for_new_repos = $Request.Body.default_for_new_repos; configuration = $configuration }
            $others = @($Store[$key] | Where-Object { [long]$_.configuration.id -ne $configuration.id })
            $Store[$key] = [object[]]($others + $entry)
            $entry
        }
        '^GET orgs/(?<org>[^/]+)/code-security/configurations/(?<id>\d+)/repositories$' = {
            # The repositories whose own read names the configuration, as one page of gh --paginate --slurp.
            param($Store, $Request)
            $organization = $Request.Match.org
            $items = @(foreach ($repository in @($Store["orgs/$organization/repos"])) {
                    $attached = $Store["repos/$organization/$($repository.name)/code-security-configuration"]
                    if ($null -ne $attached -and [long]$attached.configuration.id -eq [long]$Request.Match.id) {
                        [pscustomobject]@{ status = $attached.status; repository = [pscustomobject]@{ name = $repository.name } }
                    }
                })
            Get-TestGhFakeResponse -Output (ConvertTo-Json -InputObject @(, $items) -Depth 5 -Compress)
        }
        '^POST orgs/(?<org>[^/]+)/code-security/configurations/(?<id>\d+)/attach$'      = {
            param($Store, $Request)
            $organization = $Request.Match.org
            $configuration = Find-TestCodeSecurityConfiguration -Store $Store -Organization $organization -Id $Request.Match.id
            if (-not $configuration -or $Request.Body.scope -ne 'all_without_configurations') {
                return Get-TestGhFakeError -Message "gh: Validation Failed (HTTP 422): $($Request.Endpoint)"
            }
            foreach ($repository in @($Store["orgs/$organization/repos"] | Where-Object { -not $_.archived })) {
                $key = "repos/$organization/$($repository.name)/code-security-configuration"
                if ($null -eq $Store[$key]) {
                    $Store[$key] = [pscustomobject]@{ status = 'attaching'; configuration = [pscustomobject]@{ id = $configuration.id; name = $configuration.name } }
                }
            }
            # 202 Accepted, no body.
            Get-TestGhFakeResponse
        }
        '^POST orgs/(?<org>[^/]+)/rulesets$'                                            = {
            param($Store, $Request)
            $key = "orgs/$($Request.Match.org)/rulesets"
            $rulesets = @($Store[$key] | Where-Object { $null -ne $_ })
            $id = 1 + [long](($rulesets | Measure-Object -Property id -Maximum).Maximum)
            Save-TestRulesetFakeEntry -Store $Store -Organization $Request.Match.org -Id $id -Body $Request.Body
        }
        '^PUT orgs/(?<org>[^/]+)/rulesets/(?<id>\d+)$'                                  = {
            param($Store, $Request)
            $id = [long]$Request.Match.id
            if (-not @($Store["orgs/$($Request.Match.org)/rulesets"] | Where-Object { $null -ne $_ -and [long]$_.id -eq $id })) {
                return Get-TestGhFakeError -Message "gh: Not Found (HTTP 404): $($Request.Endpoint)"
            }
            Save-TestRulesetFakeEntry -Store $Store -Organization $Request.Match.org -Id $id -Body $Request.Body
        }
    }
    Register-TestGhFake -Resource $Resource -Handler $handler
}
