# The supported settings and config validation. Pure: no GitHub calls.

# Not a full address grammar: enough to catch a domain, a missing part or a stray space before GitHub does.
$script:EmailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
$script:TeamSlugPattern = '^[A-Za-z0-9_.-]+$'
$script:TeamSlugRule = "a team slug of letters, digits, '.', '_' and '-'"
# Config section -> endpoint path under orgs/<org>, plan action, HTTP method of the write, state property, the
# summary label (lower case: the plan puts '~ ' before it), the progress status while reading it and whether the section may be null (actions.selected exists
# only while allowed_actions is 'selected'). The order is the order of the actions: GitHub rejects a selection until allowed_actions is 'selected'.
$script:Sections = [ordered]@{
    'settings'                        = @{ Path = ''; Action = 'UpdateOrganizationSettings'; Method = 'PATCH'; StateKey = 'Settings'; Label = 'update organization settings'; Reading = 'organization settings' }
    'actions'                         = @{ Path = '/actions/permissions'; Action = 'SetActionsPermissions'; Method = 'PUT'; StateKey = 'Actions'; Label = 'set Actions permissions'; Reading = 'Actions permissions' }
    'actions.selected'                = @{ Path = '/actions/permissions/selected-actions'; Action = 'SetSelectedActions'; Method = 'PUT'; StateKey = 'SelectedActions'; Label = 'set allowed actions'; Reading = 'allowed actions'; Nullable = $true }
    'actions.workflow'                = @{ Path = '/actions/permissions/workflow'; Action = 'SetWorkflowPermissions'; Method = 'PUT'; StateKey = 'Workflow'; Label = 'set workflow permissions'; Reading = 'workflow permissions' }
    'actions.selfHostedRunners'       = @{ Path = '/actions/permissions/self-hosted-runners'; Action = 'SetSelfHostedRunners'; Method = 'PUT'; StateKey = 'SelfHostedRunners'; Label = 'set self-hosted runner access'; Reading = 'self-hosted runners' }
    'actions.forkPullRequests'        = @{ Path = '/actions/permissions/fork-pr-contributor-approval'; Action = 'SetForkPullRequestApproval'; Method = 'PUT'; StateKey = 'ForkPullRequests'; Label = 'set fork pull request approval'; Reading = 'fork pull request approval' }
    'actions.privateForkPullRequests' = @{ Path = '/actions/permissions/fork-pr-workflows-private-repos'; Action = 'SetPrivateForkPullRequestWorkflows'; Method = 'PUT'; StateKey = 'PrivateForkPullRequests'; Label = 'set private repository fork pull request workflows'; Reading = 'private repository fork pull request workflows' }
    'actions.retention'               = @{ Path = '/actions/permissions/artifact-and-log-retention'; Action = 'SetArtifactAndLogRetention'; Method = 'PUT'; StateKey = 'Retention'; Label = 'set artifact and log retention'; Reading = 'artifact and log retention' }
    # In public preview in the REST API. 'selected' keeps the repository list of the settings page, which the engine does not manage.
    'copilotCloudAgent'               = @{ Path = '/copilot/coding-agent/permissions'; Action = 'SetCopilotCloudAgentAccess'; Method = 'PUT'; StateKey = 'CopilotCloudAgent'; Label = 'set Copilot cloud agent repository access'; Reading = 'Copilot cloud agent repository access' }
}

# Every field the engine knows, under GitHub's own name. Mode 'apply': the engine sets it. Mode 'check': GitHub's API
# cannot change it, so a mismatch is a warning that tells an owner where to change it. The UI keys, spelled as the web UI
# shows them: Page, the page that holds the
# control; UiGroup, the visible heading of its group; UiLabel, the control's own words (left out for a choice whose only
# name is the heading); Options, value -> the option label the page shows (true/false for a boolean without a label);
# Hint, extra words on what to do, never the only name of the control. A <organization> in a label stands for the name
# the page shows there. The checklist prints the Hint of a manual row before the value the config expects, so it holds
# for every value: an enum names its choice through Options, a boolean says what true means (tests in
# Config.Catalog.Tests.ps1). The order of the rows of a page is its Order in $script:SettingPages.
$script:SettingDefinitions = @(
    @{ Section = 'settings'; Field = 'default_repository_permission'; Type = 'enum'; Values = @('read', 'write', 'admin', 'none'); Mode = 'apply'; Page = 'member_privileges'; UiGroup = 'Base permissions'; Options = @{ none = 'No permission'; read = 'Read'; write = 'Write'; admin = 'Admin' }; Recommended = 'none'; Why = 'Members see only the repositories they are given; a base permission opens every private repository to every member, a compromised account included.' }
    @{ Section = 'settings'; Field = 'members_can_create_repositories'; Type = 'boolean'; Mode = 'apply'; NoUi = $true; Recommended = $false; Why = 'Owners create repositories, so each one is deliberate and gets the organization settings.' }
    @{ Section = 'settings'; Field = 'members_can_create_public_repositories'; Type = 'boolean'; Mode = 'apply'; Page = 'member_privileges'; UiGroup = 'Repository creation'; UiLabel = 'Public'; Recommended = $false; Why = 'A public repository created by mistake publishes its code and history to everyone.' }
    @{ Section = 'settings'; Field = 'members_can_create_private_repositories'; Type = 'boolean'; Mode = 'apply'; Page = 'member_privileges'; UiGroup = 'Repository creation'; UiLabel = 'Private'; Recommended = $false; Why = 'Owners create repositories, so each one is deliberate and gets the organization settings.' }
    @{ Section = 'settings'; Field = 'members_can_create_pages'; Type = 'boolean'; Mode = 'apply'; NoUi = $true; Recommended = $false; Why = 'A Pages site publishes repository content to the internet, from private repositories too.' }
    @{ Section = 'settings'; Field = 'members_can_fork_private_repositories'; Type = 'boolean'; Mode = 'apply'; Page = 'member_privileges'; UiGroup = 'Repository forking'; UiLabel = 'Allow forking of private repositories'; Recommended = $false; Why = 'A fork of a private repository keeps its code in a personal account, outside the organization.' }
    @{ Section = 'settings'; Field = 'deploy_keys_enabled_for_repositories'; Type = 'boolean'; Mode = 'apply'; Page = 'deploy_keys'; UiGroup = 'Deploy keys'; Options = @{ 'true' = 'Enabled'; 'false' = 'Disabled' }; Recommended = $false; Why = 'A deploy key is a repository credential that belongs to no person and never expires; turning this off also disables existing keys.' }
    @{ Section = 'settings'; Field = 'email'; Type = 'email'; Mode = 'apply'; Page = 'profile'; UiGroup = 'General'; UiLabel = 'Email (will be public)'; Description = 'Public contact address on the organization page, where security reports go.'; NoRecommendation = 'Project data: the contact address of the organization.' }
    @{ Section = 'settings'; Field = 'is_verified'; Type = 'boolean'; Mode = 'check'; Page = 'domains'; UiGroup = 'Verified & approved domains'; UiLabel = 'Add a domain'; Hint = 'add a domain the organization owns and verify it with the DNS TXT record GitHub shows'; Recommended = $true; Why = 'A verified domain shows people that this is the real organization.' }
    @{ Section = 'settings'; Field = 'two_factor_requirement_enabled'; Type = 'boolean'; Mode = 'check'; Page = 'security'; UiLabel = 'Require two-factor authentication for everyone in the <organization> organization.'; UiGroup = 'Two-factor authentication'; Recommended = $true; Why = 'A stolen password alone must not be enough to act as a member.' }
    @{ Section = 'settings'; Field = 'members_can_delete_repositories'; Type = 'boolean'; Mode = 'check'; Page = 'member_privileges'; UiGroup = 'Repository deletion and transfer'; UiLabel = 'Allow members to delete or transfer repositories for this organization'; Recommended = $false; Why = 'Deleting or transferring a repository loses its code and history; only owners should.' }
    @{ Section = 'settings'; Field = 'members_can_change_repo_visibility'; Type = 'boolean'; Mode = 'check'; Page = 'member_privileges'; UiGroup = 'Repository visibility change'; UiLabel = 'Allow members to change repository visibilities for this organization'; Recommended = $false; Why = 'Making a private repository public publishes it; only owners should decide.' }
    @{ Section = 'settings'; Field = 'members_can_invite_outside_collaborators'; Type = 'boolean'; Mode = 'check'; NoUi = $true; Recommended = $false; Why = 'Outside collaborators get repository access without being members, so nobody reviews them with the members. Only GitHub Enterprise Cloud can restrict it: on other plans, keep true with an exception.' }
    @{ Section = 'settings'; Field = 'members_can_create_teams'; Type = 'boolean'; Mode = 'check'; Page = 'member_privileges'; UiGroup = 'Team creation rules'; UiLabel = 'Allow members to create teams'; Recommended = $false; Why = 'Teams grant repository access; only owners should create them.' }
    @{ Section = 'settings'; Field = 'members_can_delete_issues'; Type = 'boolean'; Mode = 'check'; Page = 'member_privileges'; UiGroup = 'Issue deletion'; UiLabel = 'Allow repository administrators to delete issues for this organization'; Recommended = $false; Why = 'Deleting an issue removes its record for good.' }
    @{ Section = 'settings'; Field = 'readers_can_create_discussions'; Type = 'boolean'; Mode = 'check'; Page = 'member_privileges'; UiGroup = 'Repository discussions'; UiLabel = 'Allow users with read access to create discussions'; Recommended = $false; Why = 'Read access is for reading; starting discussions needs write access.' }
    # Read from GET orgs/{org} and checked; the PATCH writes those with a Write, which a later issue each applies.
    @{ Section = 'settings'; Field = 'members_can_create_public_pages'; Type = 'boolean'; Mode = 'check'; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}' }; Page = 'member_privileges'; UiGroup = 'Pages creation'; UiLabel = 'Public'; Recommended = $false; Why = 'A public Pages site publishes repository content to everyone.' }
    @{ Section = 'settings'; Field = 'members_can_create_private_pages'; Type = 'boolean'; Mode = 'check'; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}' }; PlanRestriction = 'Private Pages sites need GitHub Enterprise Cloud'; Page = 'member_privileges'; UiGroup = 'Pages creation'; UiLabel = 'Private'; Recommended = $false; Why = 'A Pages site publishes repository content beyond the repository, with or without access control.' }
    @{ Section = 'settings'; Field = 'display_commenter_full_name_setting_enabled'; Type = 'boolean'; Mode = 'check'; Page = 'member_privileges'; UiGroup = 'Repository comments'; UiLabel = 'Allow members to see comment author''s profile name in private repositories'; Description = 'Shows the profile name of a comment author in the pull requests of private repositories.'; NoRecommendation = 'Owner decides: who sees profile names is a matter of privacy within the organization, not of security.' }
    @{ Section = 'settings'; Field = 'web_commit_signoff_required'; Type = 'boolean'; Mode = 'check'; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}' }; Page = 'repository-defaults'; UiGroup = 'Commit signoff'; Options = @{ 'true' = 'All repositories'; 'false' = 'No policy' }; Hint = 'under "Commit signoff" choose the policy'; Description = 'Contributors sign off the commits they make in the web interface, such as for a Developer Certificate of Origin; the page shows false as "No policy".'; NoRecommendation = 'Owner decides: a sign-off policy, such as a Developer Certificate of Origin, is a legal process, not a security setting.' }
    @{ Section = 'settings'; Field = 'default_repository_branch'; Type = 'string'; Pattern = '^\S+$'; Rule = 'a branch name without whitespace'; Mode = 'check'; Page = 'repository-defaults'; UiGroup = 'Repository default branch'; UiLabel = 'Default branch name'; Hint = 'under "Repository default branch" set "Default branch name" and select Update'; Description = 'The default branch of new repositories.'; NoRecommendation = 'Project data: the branch name the projects use.' }
    @{ Section = 'settings'; Field = 'has_organization_projects'; Type = 'boolean'; Mode = 'check'; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}' }; Page = 'projects'; UiGroup = 'Projects'; UiLabel = 'Enable Projects for the organization'; Description = 'Members can create projects of the organization.'; NoRecommendation = 'Owner decides: whether the organization plans its work in GitHub Projects.' }
    @{ Section = 'settings'; Field = 'has_repository_projects'; Type = 'boolean'; Mode = 'check'; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}' }; NoUi = $true; Page = $null; Description = 'Repositories of the organization can have projects; no settings page shows it.'; NoRecommendation = 'Owner decides: whether the organization plans its work in GitHub Projects.' }
    @{ Section = 'settings'; Field = 'members_can_view_dependency_insights'; Type = 'boolean'; Mode = 'check'; NoUi = $true; Page = $null; Description = 'Members can see the dependency insights of the organization; no settings page of GitHub Team shows it.'; NoRecommendation = 'Owner decides: GitHub Team shows no page and has no API to change it, so a recommendation could only be waived.' }
    @{ Section = 'settings'; Field = 'secret_scanning_push_protection_custom_link'; Type = 'string'; Pattern = '^https://\S+$'; Rule = 'an https:// link'; Nullable = $true; Mode = 'check'; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}' }; Page = 'security_analysis'; UiLabel = 'Add a resource link in the CLI and web UI when a commit is blocked'; UiGroup = 'Push protection'; Hint = 'under "Push protection" set or clear "Add a resource link in the CLI and web UI when a commit is blocked" and its link, as the config expects'; Description = 'A link shown when push protection blocks a commit, or null.'; NoRecommendation = 'Project data: a link to the organization''s own guidance, where it has one.' }
    @{ Section = 'settings'; Field = 'secret_scanning_validity_checks_enabled'; Type = 'boolean'; Mode = 'check'; NoUi = $true; Description = 'GitHub checks whether a found secret is still valid; it needs Secret Protection, which budgets stop.'; NoRecommendation = 'Owner decides: it needs Secret Protection, a paid product the budgets stop; buying it is a decision of its own.' }
    @{ Section = 'actions'; Field = 'enabled_repositories'; Type = 'enum'; Values = @('all', 'none'); Mode = 'apply'; Page = 'actions'; UiGroup = 'Policies'; Options = @{ all = 'All repositories'; none = 'Disabled' }; Recommended = 'all'; Why = 'Every repository may run workflows; the policies below limit what they run. none turns Actions off.' }
    @{ Section = 'actions'; Field = 'allowed_actions'; Type = 'enum'; Values = @('all', 'local_only', 'selected'); Mode = 'apply'; Page = 'actions'; UiGroup = 'Policies'; Options = @{ all = 'Allow all actions and reusable workflows'; local_only = 'Allow <organization> actions and reusable workflows'; selected = 'Allow <organization>, and select non-<organization>, actions and reusable workflows' }; Recommended = 'selected'; Why = 'Only GitHub actions and the listed ones run, so a new third-party action needs a deliberate change here.' }
    @{ Section = 'actions'; Field = 'sha_pinning_required'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Policies'; UiLabel = 'Require actions to be pinned to a full-length commit SHA'; Recommended = $true; Why = 'A tag or branch can be moved by the action owner after review; a full commit SHA cannot.' }
    @{ Section = 'actions.selected'; Field = 'github_owned_allowed'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Policies'; UiLabel = 'Allow actions created by GitHub'; Recommended = $true; Why = 'Actions published by GitHub are trusted like the platform itself.' }
    @{ Section = 'actions.selected'; Field = 'verified_allowed'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Policies'; UiLabel = 'Allow actions by Marketplace verified creators'; Recommended = $false; Why = 'A verified creator is not a reviewed action; list third-party actions one by one in patterns_allowed.' }
    @{ Section = 'actions.selected'; Field = 'patterns_allowed'; Type = 'list'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Policies'; UiLabel = 'Allow or block specified actions and reusable workflows'; Description = 'Actions allowed besides the GitHub-owned ones, such as azure/login@*. Add an action here and re-run before a workflow starts using it.'; NoRecommendation = 'Project data: the actions the workflows of the organization use.' }
    @{ Section = 'actions.workflow'; Field = 'default_workflow_permissions'; Type = 'enum'; Values = @('read', 'write'); Mode = 'apply'; Page = 'actions'; UiGroup = 'Workflow permissions'; Options = @{ write = 'Read and write permissions'; read = 'Read repository contents and packages permissions' }; Recommended = 'read'; Why = 'A workflow token only reads unless the workflow asks for more, which limits what a compromised step can do.' }
    @{ Section = 'actions.workflow'; Field = 'can_approve_pull_request_reviews'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Workflow permissions'; UiLabel = 'Allow GitHub Actions to create and approve pull requests'; Recommended = $false; Why = 'A workflow that approves pull requests bypasses human review.' }
    @{ Section = 'actions.selfHostedRunners'; Field = 'enabled_repositories'; Type = 'enum'; Values = @('all', 'none'); Mode = 'apply'; Page = 'actions'; UiGroup = 'Runners'; UiLabel = 'Repository self-hosted runners'; Options = @{ all = 'All repositories'; none = 'Disabled' }; Recommended = 'none'; Why = 'A self-hosted runner runs repository code on your own machine and keeps state between jobs; GitHub-hosted runners are discarded after each job.' }
    @{ Section = 'actions.forkPullRequests'; Field = 'approval_policy'; Type = 'enum'; Values = @('first_time_contributors_new_to_github', 'first_time_contributors', 'all_external_contributors'); Mode = 'apply'; Page = 'actions'; UiGroup = 'Approval for running fork pull request workflows from contributors'; Options = @{ first_time_contributors_new_to_github = 'Require approval for first-time contributors who are new to GitHub'; first_time_contributors = 'Require approval for first-time contributors'; all_external_contributors = 'Require approval for all external contributors' }; Recommended = 'all_external_contributors'; Why = 'A workflow from a fork runs someone else''s code; a maintainer approves it first for every outside contributor.' }
    @{ Section = 'actions.privateForkPullRequests'; Field = 'run_workflows_from_fork_pull_requests'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Fork pull request workflows in private and internal repositories'; UiLabel = 'Run workflows from fork pull requests'; Recommended = $false; Why = 'Workflows from forks of private repositories run code nobody has reviewed.' }
    @{ Section = 'actions.privateForkPullRequests'; Field = 'send_write_tokens_to_workflows'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Fork pull request workflows in private and internal repositories'; UiLabel = 'Send write tokens to workflows from fork pull requests.'; Recommended = $false; Why = 'A workflow from a fork must not get a token that writes to the repository.' }
    @{ Section = 'actions.privateForkPullRequests'; Field = 'send_secrets_and_variables'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Fork pull request workflows in private and internal repositories'; UiLabel = 'Send secrets and variables to workflows from fork pull requests.'; Recommended = $false; Why = 'A workflow from a fork must not see the repository secrets.' }
    @{ Section = 'actions.privateForkPullRequests'; Field = 'require_approval_for_fork_pr_workflows'; Type = 'boolean'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Fork pull request workflows in private and internal repositories'; UiLabel = 'Require approval for fork pull request workflows.'; DependsOn = 'run_workflows_from_fork_pull_requests'; Description = 'Only matters while run_workflows_from_fork_pull_requests is true; until then GitHub keeps it false and the plan leaves it alone.'; Recommended = $true; Why = 'Should workflows of fork pull requests ever run, a person approves each run before code from a fork gets the repository''s token or secrets.' }
    @{ Section = 'actions.retention'; Field = 'days'; Type = 'integer'; Mode = 'apply'; Page = 'actions'; UiGroup = 'Check, workflow run, status, artifact and log retention'; UiLabel = 'Check, workflow run, status, artifact and log retention'; Description = 'How long artifacts and logs are kept: 1 to the organization maximum (400 for private repositories).'; NoRecommendation = 'Project data: how long the organization needs workflow artifacts and logs.' }
    @{ Section = 'actions.cache'; Field = 'retention_days'; Type = 'integer'; Minimum = 1; Maximum = 365; Mode = 'manual'; Page = 'actions'; UiGroup = 'Cache'; UiLabel = 'Cache retention'; Why = 'How long an unused cache of a workflow is kept; repositories can set less, never more.'; NoRecommendation = 'Project data: GitHub''s default suits most projects; a longer retention keeps more cache, billed as storage.' }
    @{ Section = 'actions.cache'; Field = 'size_limit_gb'; Type = 'integer'; Minimum = 1; Mode = 'manual'; Page = 'actions'; UiGroup = 'Cache'; UiLabel = 'Cache size eviction limit'; Why = 'The cache storage of a repository before GitHub evicts the oldest caches; storage beyond the included amount is charged.'; NoRecommendation = 'Project data: GitHub''s default suits most projects; a larger cache is billed as storage.' }
    @{ Section = 'copilotCloudAgent'; Field = 'enabled_repositories'; Type = 'enum'; Values = @('all', 'selected', 'none'); Mode = 'apply'; Page = 'copilot/coding_agent'; UiGroup = 'Repository access'; Options = @{ none = 'No repositories' }; Recommended = 'none'; Why = 'The cloud agent changes code and opens pull requests from tasks: it works only where it is needed.' }
    @{ Section = 'codeSecurity'; Field = 'name'; Type = 'string'; Mode = 'apply'; Page = 'security_products'; Pattern = '^\S(.*\S)?$'; Rule = 'a non-empty name without leading or trailing whitespace'; Description = 'Name of the code security configuration the engine manages.'; NoRecommendation = 'Project data: the name of the configuration.' }
    @{ Section = 'codeSecurity'; Field = 'description'; Type = 'string'; Mode = 'apply'; Page = 'security_products'; Nullable = $true; Description = 'Description of the configuration, or null.'; NoRecommendation = 'Project data: the description of the configuration.' }
    @{ Section = 'codeSecurity'; Field = 'default_for_new_repos'; Type = 'enum'; Values = @('all', 'none', 'private_and_internal', 'public'); Mode = 'apply'; Page = 'security_products'; Recommended = 'all'; Why = 'Every new repository gets the configuration without anyone remembering to attach it.' }
    @{ Section = 'codeSecurity'; Field = 'enforcement'; Type = 'enum'; Values = @('enforced', 'unenforced'); Mode = 'apply'; Page = 'security_products'; Recommended = 'enforced'; Why = 'Repository admins cannot turn the features off.' }
    @{ Section = 'codeSecurity.settings'; Field = 'dependency_graph'; Type = 'enum'; Values = @('enabled', 'disabled', 'not_set'); Mode = 'apply'; Page = 'security_products'; Recommended = 'enabled'; Why = 'Dependabot needs the dependency graph to know what a repository uses.' }
    @{ Section = 'codeSecurity.settings'; Field = 'dependabot_alerts'; Type = 'enum'; Values = @('enabled', 'disabled', 'not_set'); Mode = 'apply'; Page = 'security_products'; Recommended = 'enabled'; Why = 'Known vulnerabilities in dependencies are reported.' }
    @{ Section = 'codeSecurity.settings'; Field = 'dependabot_security_updates'; Type = 'enum'; Values = @('enabled', 'disabled', 'not_set'); Mode = 'apply'; Page = 'security_products'; Recommended = 'enabled'; Why = 'Dependabot opens pull requests that fix vulnerable dependencies.' }
    @{ Section = 'codeSecurity.settings'; Field = 'private_vulnerability_reporting'; Type = 'enum'; Values = @('enabled', 'disabled', 'not_set'); Mode = 'apply'; Page = 'security_products'; Recommended = 'enabled'; Why = 'A researcher can report a vulnerability of a public repository privately instead of in a public issue.' }
    @{ Section = 'ruleset'; Field = 'name'; Type = 'string'; Mode = 'apply'; Page = 'rules'; Pattern = '^\S(.*\S)?$'; Rule = 'a non-empty name without leading or trailing whitespace'; Description = 'Name of the organization ruleset the engine manages; it protects the default branch of every repository.'; NoRecommendation = 'Project data: the name of the ruleset.' }
    @{ Section = 'ruleset'; Field = 'enforcement'; Type = 'enum'; Values = @('active', 'disabled'); Mode = 'apply'; Page = 'rules'; Recommended = 'active'; Why = 'A disabled ruleset protects no branch.' }
    @{ Section = 'ruleset.bypass'; Field = 'organizationAdmin'; Type = 'enum'; Values = @('pull_request', 'none'); Mode = 'apply'; Page = 'rules'; Recommended = 'pull_request'; Why = 'An organization owner can merge a pull request without the approvals, which GitHub records, but never push to a default branch directly; none leaves no way past the rules.' }
    @{ Section = 'ruleset.rules'; Field = 'deletion'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'Nobody can delete the default branch of a repository.' }
    @{ Section = 'ruleset.rules'; Field = 'non_fast_forward'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'Nobody can force-push to a default branch and rewrite its reviewed history.' }
    @{
        Section = 'ruleset.rules'; Field = 'workflows'; Type = 'objectList'; Mode = 'apply'; Page = 'rules'; MinItems = 1; NoRecommendation = 'Project data: the central workflows of the organization.'
        Description = 'Central workflows every pull request of every repository must pass, each pinned to a commit of a repository of the organization, so write access to that repository alone cannot change a check.'
        Item        = [ordered]@{
            repository = @{ Type = 'string'; Pattern = '^[A-Za-z0-9._-]+$'; Rule = "a repository name of letters, digits, '.', '_' and '-'"; Description = 'Name of the repository of the organization that holds the workflow, such as .github.' }
            path       = @{ Type = 'string'; Pattern = '^\.github/workflows/[^/]+\.ya?ml$'; Rule = 'a file under .github/workflows/'; Description = 'Path of the workflow file in that repository.' }
            sha        = @{ Type = 'string'; Pattern = '^[0-9a-f]{40}$'; Rule = '40 lower-case hexadecimal characters'; Description = 'Full commit SHA of the workflow file to run.' }
        }
    }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'required_approving_review_count'; Type = 'integer'; Minimum = 0; Maximum = 10; Mode = 'apply'; Page = 'rules'; Recommended = 1; Why = 'Every change to a default branch is approved by someone other than its author.' }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'dismiss_stale_reviews_on_push'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'A commit pushed after an approval needs a new approval, so no unreviewed code joins an approved pull request.' }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'require_last_push_approval'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'Someone other than the person who pushed last approves, so nobody approves their own last change.' }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'require_code_owner_review'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'A change to files with code owners needs the approval of one of them; it has no effect in a repository without a CODEOWNERS file.' }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'required_review_thread_resolution'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'Every review comment is resolved before the merge, so none is lost.' }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'require_extra_approval_for_unattributed_changes'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'A change GitHub cannot attribute to a person, such as one made by Copilot, needs one more approval.' }
    @{ Section = 'ruleset.rules.pullRequest'; Field = 'allowed_merge_methods'; Type = 'enumList'; Values = @('merge', 'squash', 'rebase'); Mode = 'apply'; Page = 'rules'; Recommended = @('merge'); Why = 'Reviewed and tested commits reach the default branch with the same SHAs; the ruleset does not turn off the other methods in the repository settings.' }
    @{
        Section = 'ruleset.rules.pullRequest'; Field = 'requiredReviewers'; Type = 'objectList'; Mode = 'apply'; Page = 'rules'; ItemKey = 'team'; RuleExceptions = $true; NoRecommendation = 'Project data: the teams of the organization; the entry that covers the workflows is a rule of its own.'
        Description = 'Teams that must approve changes to some files in every repository. A team counts only where it has write access. One entry with minimum_approvals of at least 1 must cover .github/workflows/**, unless an exception names this field.'
        Item        = [ordered]@{
            team              = @{ Type = 'string'; Pattern = $script:TeamSlugPattern; Rule = $script:TeamSlugRule; Description = 'Slug of the team of the organization.' }
            minimum_approvals = @{ Type = 'integer'; Minimum = 0; Maximum = 10; Description = 'How many members of the team must approve, 0 to 10.' }
            file_patterns     = @{ Type = 'array'; Unique = $true; MinItems = 1; Items = @{ Type = 'string'; Pattern = '^\S(.*\S)?$'; Rule = 'a non-empty file pattern without leading or trailing whitespace' }; Description = 'File patterns, as in CODEOWNERS, whose changes the team must approve.' }
        }
    }
    @{ Section = 'ruleset.rules.copilotCodeReview'; Field = 'enabled'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'Copilot reviews every pull request, and its comments are resolved before the merge; false leaves the rule out of the ruleset. It needs Copilot Business.' }
    @{ Section = 'ruleset.rules.copilotCodeReview'; Field = 'review_on_push'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $true; Why = 'Copilot reviews every new push too, so the changes made after its review are reviewed as well; each review costs AI credits.' }
    @{ Section = 'ruleset.rules.copilotCodeReview'; Field = 'review_draft_pull_requests'; Type = 'boolean'; Mode = 'apply'; Page = 'rules'; Recommended = $false; Why = 'Copilot reviews a pull request once it is ready for review, so a draft that still changes costs no AI credits.' }
    # Copilot policies the API reads (from copilot/billing and the code review endpoints); without a Copilot plan they
    # do not apply. Read and checked, never applied: the API writes some, each a later issue.
    @{ Section = 'copilot.policies'; Field = 'public_code_suggestions'; Type = 'enum'; Values = @('allow', 'block', 'unconfigured'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/billing'; Field = 'public_code_suggestions' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Duplicate Detection Filter'; UiLabel = 'Suggestions matching public code'; Options = @{ unconfigured = 'Unconfigured'; allow = 'Allowed'; block = 'Blocked' }; Recommended = 'block'; Why = 'Less risk of code under someone else''s license.' }
    @{ Section = 'copilot.policies'; Field = 'ide_chat'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/billing'; Field = 'ide_chat' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Editors'; UiLabel = 'Copilot Chat in the IDE'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Description = 'Copilot Chat in the editors of the members.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'platform_chat'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/billing'; Field = 'platform_chat' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Copilot in the cloud'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Description = 'Copilot on GitHub.com and GitHub Mobile; the page names it Copilot in the cloud, which replaced Copilot Chat in GitHub.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'cli'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/billing'; Field = 'cli' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Desktop & terminal'; UiLabel = 'Copilot CLI'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Description = 'Copilot CLI in the terminal; it also governs the GitHub Copilot app before its version 1.1.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'code_review'; Type = 'enum'; Values = @('enabled', 'disabled'); Nullable = $true; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/policies/code-review'; Field = 'configured_state' }; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/copilot/policies/code-review' }; Absent = 'CopilotPlan'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Copilot code review'; Options = @{ enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'enabled'; Why = 'The ruleset asks Copilot to review every pull request; null is a policy the organization never configured.' }
    @{ Section = 'copilot.codeReview'; Field = 'default_review_effort'; Type = 'string'; Pattern = '^\S+$'; Rule = 'an effort GitHub offers, such as medium'; Nullable = $true; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/code-review/settings'; Field = 'default_review_effort.configured' }; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}/copilot/code-review/settings' }; Absent = 'CopilotPlan'; Page = 'copilot/code_review'; UiLabel = 'Default review effort level'; UiGroup = 'General'; Hint = 'under "General" set "Default review effort level"'; Description = 'The review effort stored for the organization; null inherits the default, which the page shows as "Default (Balanced)". A deeper effort costs more AI credits per review.'; NoRecommendation = 'Owner decides: a deeper review costs more AI credits per review.' }
    @{ Section = 'copilot.runnerType'; Field = 'code_review_runner_type'; Type = 'enum'; Values = @('standard', 'labeled'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/code-review/runner'; Field = 'runner_type' }; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/copilot/code-review/runner' }; Absent = 'CopilotPlan'; Page = 'copilot/runner_type'; UiGroup = 'Copilot code review'; UiLabel = 'Runner type configuration'; Options = @{ standard = 'Standard GitHub runner' }; Recommended = 'standard'; Why = 'Reviews run on the standard GitHub runner; a custom runner costs more and is another place the code runs.' }
    # Other settings the API reads and the engine checks; each Write is applied by a later issue.
    @{ Section = 'interactionLimits'; Field = 'limit'; Type = 'enum'; Values = @('none', 'existing_users', 'contributors_only', 'collaborators_only'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/interaction-limits'; Field = 'limit' }; AbsentValue = 'none'; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/interaction-limits' }; Page = 'interaction_limits'; UiGroup = 'Temporary interaction limits'; Options = @{ existing_users = 'Limit to existing users'; contributors_only = 'Limit to prior contributors'; collaborators_only = 'Limit to repository collaborators' }; Hint = 'enable the temporary limit the config names, or none'; Description = 'A temporary limit on who can interact with the public repositories; none while no limit is set (GitHub answers {}). A limit expires on its own.'; NoRecommendation = 'Owner decides: a temporary measure during an incident on a public repository, which expires on its own.' }
    @{ Section = 'interactionLimits'; Field = 'pull_request_cap_enabled'; Type = 'boolean'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/interaction-limits/pulls/creation-cap'; Field = 'enabled' }; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}/interaction-limits/pulls/creation-cap' }; Page = 'interaction_limits'; UiGroup = 'Pull request limits'; UiLabel = 'Limit open pull requests from users without write access'; Description = 'A cap on the open pull requests of a user without write access in each public repository.'; NoRecommendation = 'Owner decides: a spam measure for public repositories, which matters once they receive outside pull requests.' }
    @{ Section = 'immutableReleases'; Field = 'enforced_repositories'; Type = 'enum'; Values = @('all', 'none', 'selected'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/settings/immutable-releases'; Field = 'enforced_repositories' }; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/settings/immutable-releases' }; Page = 'repository-defaults'; UiGroup = 'Releases'; Options = @{ all = 'All repositories'; selected = 'Selected repositories'; none = 'No policy' }; Hint = 'under "Releases" choose the policy'; Recommended = 'all'; Why = 'Once published, a release cannot have its assets changed or its tag moved, so what a workflow downloaded by tag stays what was reviewed.' }
    @{ Section = 'actions.oidc'; Field = 'include_claim_keys'; Type = 'list'; Mode = 'manual'; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/actions/oidc/customization/sub' }; Page = 'actions/oidc-configuration'; UiGroup = 'Subject claim'; UiLabel = 'Subject claim template'; Why = 'The claims of the subject of the OIDC token; an empty template keeps the default subject that existing cloud identities trust, and a change breaks the sign-in of every federated credential until the identities are updated. GET actions/oidc/customization/sub answered 404 to the owner on 2026-11-08, so only the page shows it.'; NoRecommendation = 'Project data: follows the OIDC subjects the cloud identities of the organization trust.' }
    @{ Section = 'actions.oidc'; Field = 'use_immutable_subject'; Type = 'boolean'; Mode = 'manual'; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/actions/oidc/customization/sub' }; Page = 'actions/oidc-configuration'; UiGroup = 'Subject claim'; UiLabel = 'Use immutable subject claim'; Why = 'The subject carries the ids of the repository and the organization, so a renamed or recreated one cannot take over a trust; a change breaks the sign-in of every federated credential until the identities are updated.'; NoRecommendation = 'Project data: follows the OIDC subjects the cloud identities of the organization trust.' }
    @{ Section = 'dependabot'; Field = 'default_level'; Type = 'enum'; Values = @('public', 'internal'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/dependabot/repository-access'; Field = 'default_level' }; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/dependabot/repository-access/default-level' }; Page = 'security_analysis'; UiGroup = 'Grant Dependabot access to repositories'; UiLabel = 'Repository access'; Options = @{ public = 'Public repositories only' }; Recommended = 'public'; Why = 'What Dependabot reads in a repository becomes visible to every member through its updates, so it reads only public repositories unless one is added on purpose.' }
    @{ Section = 'copilot.runnerType'; Field = 'code_review_allow_repository_customization'; Type = 'boolean'; Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/copilot/code-review/runner'; Field = 'allow_repository_customization' }; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/copilot/code-review/runner' }; Absent = 'CopilotPlan'; Page = 'copilot/runner_type'; UiGroup = 'Copilot code review'; UiLabel = 'Allow repositories to customize the runner type'; Recommended = $false; Why = 'A repository cannot move its reviews to a runner of its own.' }
    # Settings without an API read: only a person can check them (-WhatIf -ManualChecklist lists them).
    # Values are the options of the page in lower case; names and options as the pages showed them on 2026-11-08.
    @{ Section = 'authenticationSecurity'; Field = 'two_factor_secure_methods_required'; Type = 'boolean'; Mode = 'manual'; Page = 'security'; UiGroup = 'Two-factor authentication'; UiLabel = 'Only allow secure two-factor methods'; Recommended = $true; Why = 'SMS codes can be intercepted; passkeys, security keys and apps cannot.' }
    @{ Section = 'memberPrivileges'; Field = 'projects_base_permission'; Type = 'enum'; Values = @('none', 'read', 'write', 'admin'); Mode = 'manual'; Page = 'member_privileges'; UiGroup = 'Projects base permissions'; Hint = 'choose the role'; Options = @{ none = 'No access'; read = 'Read'; write = 'Write'; admin = 'Admin' }; Recommended = 'none'; Why = 'A project shows the issues and pull requests it tracks; members see only the projects they are given.' }
    @{ Section = 'memberPrivileges'; Field = 'app_access_requests'; Type = 'enum'; Values = @('members_and_outside_collaborators', 'members_only', 'disabled'); Mode = 'manual'; Page = 'member_privileges'; UiGroup = 'App access requests'; Hint = 'choose who can request apps'; Options = @{ members_and_outside_collaborators = 'Members and outside collaborators'; members_only = 'Members only'; disabled = 'Disable app access requests' }; Recommended = 'members_only'; Why = 'An outside collaborator cannot ask for an app that reaches the code of the organization.' }
    @{ Section = 'memberPrivileges'; Field = 'members_can_install_github_apps'; Type = 'boolean'; Mode = 'manual'; Page = 'member_privileges'; UiGroup = 'GitHub Apps'; UiLabel = 'Allow repository admins to install GitHub Apps for their repositories.'; Recommended = $false; Why = 'An app gets access to code and often to workflows, so only owners install them.' }
    @{ Section = 'memberPrivileges'; Field = 'members_can_rename_protected_branches'; Type = 'boolean'; Mode = 'manual'; Page = 'member_privileges'; UiGroup = 'Branch renames'; UiLabel = 'Allow repository administrators to rename branches protected by organization rules'; Recommended = $false; Why = 'Only owners rename a branch the organization ruleset protects.' }
    @{ Section = 'projects'; Field = 'members_can_change_project_visibility'; Type = 'boolean'; Mode = 'manual'; Page = 'projects'; UiGroup = 'Projects'; UiLabel = 'Allow members to change project visibilities for this organization'; Recommended = $false; Why = 'Making a project public publishes what it tracks; only owners should decide.' }
    @{ Section = 'repositoryDefaults'; Field = 'commit_comments'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'manual'; Page = 'repository-defaults'; UiGroup = 'Commit comments'; Hint = 'choose the default'; Options = @{ enabled = 'Enabled by default'; disabled = 'Disabled by default' }; Why = 'Whether new repositories take comments on commits; repositories can override it.'; NoRecommendation = 'Owner decides: a collaboration feature, not a security setting.' }
    @{ Section = 'personalAccessTokens'; Field = 'fine_grained'; Type = 'enum'; Values = @('allow', 'restrict'); Mode = 'manual'; Page = 'personal-access-tokens'; UiGroup = 'Fine-grained tokens'; Hint = 'choose the access'; Options = @{ allow = 'Allow access via fine-grained personal access tokens'; restrict = 'Restrict access via fine-grained personal access tokens' }; Recommended = 'restrict'; Why = 'A forgotten token keeps write access to main, and so to the deployment, until it expires; allow it only while someone needs one.' }
    @{ Section = 'personalAccessTokens'; Field = 'classic'; Type = 'enum'; Values = @('allow', 'restrict'); Mode = 'manual'; Page = 'personal-access-tokens'; UiGroup = 'Tokens (classic)'; Hint = 'choose the access'; Options = @{ allow = 'Allow access via personal access tokens (classic)'; restrict = 'Restrict access via personal access tokens (classic)' }; Recommended = 'restrict'; Why = 'A classic token with repo reaches every repository and cannot be limited; gh auth login uses an OAuth token, not a classic one.' }
    @{ Section = 'oauthApps'; Field = 'policy'; Type = 'enum'; Values = @('restricted', 'unrestricted'); Mode = 'manual'; Page = 'oauth_application_policy'; UiGroup = 'Third-party application access policy'; UiLabel = 'Policy'; Hint = 'the page asks for sudo mode; check the policy'; Options = @{ restricted = 'Access restricted' }; Recommended = 'restricted'; Why = 'Without it, every OAuth app a member authorized reads the private repositories.' }
    @{ Section = 'codespaces'; Field = 'access'; Type = 'enum'; Values = @('disabled', 'selected_members', 'all_members', 'all_members_and_outside_collaborators'); Mode = 'manual'; Write = @{ Method = 'PUT'; Endpoint = '/orgs/{org}/codespaces/access' }; Page = 'codespaces'; UiGroup = 'Codespaces access'; Hint = 'choose who can use Codespaces'; Options = @{ disabled = 'Disabled'; selected_members = 'Enable for specific members or teams'; all_members = 'Enable for all members'; all_members_and_outside_collaborators = 'Enable for all members and outside collaborators' }; Recommended = 'disabled'; Why = 'One less place where the code and its secrets run. The API writes it but cannot read it back, so only a person can check it.' }
    @{ Section = 'codespaces'; Field = 'ownership'; Type = 'enum'; Values = @('organization', 'user'); Mode = 'manual'; Page = 'codespaces'; UiGroup = 'Codespace ownership'; Hint = 'choose who owns the codespaces'; Options = @{ organization = 'Organization ownership'; user = 'User ownership' }; Why = 'Who pays for a codespace and whose policies apply; matters once Codespaces is enabled.'; NoRecommendation = 'Owner decides: it matters only while Codespaces are enabled (codespaces.access), and then decides who pays.' }
    @{ Section = 'packages'; Field = 'public_creation'; Type = 'boolean'; Mode = 'manual'; Page = 'packages'; UiGroup = 'Package creation'; UiLabel = 'Public'; Recommended = $false; Why = 'No public package or container is published by mistake.' }
    @{ Section = 'packages'; Field = 'inherit_access'; Type = 'boolean'; Mode = 'manual'; Page = 'packages'; UiGroup = 'Default package settings'; UiLabel = 'Inherit access from source repository'; Recommended = $true; Why = 'A new package is visible to whoever sees its repository, nobody else.' }
    @{ Section = 'discussions'; Field = 'enabled'; Type = 'boolean'; Mode = 'manual'; Page = 'discussions'; UiGroup = 'Discussions for your organization'; UiLabel = 'Enable discussions for this organization'; Why = 'A place for posts of the whole organization; the engine does not use it.'; NoRecommendation = 'Owner decides: a collaboration feature, not a security setting.' }
    @{ Section = 'advancedSecurity'; Field = 'agentic_autofix'; Type = 'boolean'; Mode = 'manual'; Page = 'security_analysis'; UiGroup = 'Code scanning'; UiLabel = 'Agentic autofix'; Recommended = $false; Why = 'Copilot opens fix pull requests for alerts and consumes AI credits for each.' }
    @{ Section = 'advancedSecurity'; Field = 'ai_scan_repositories'; Type = 'boolean'; Mode = 'manual'; Page = 'security_analysis'; UiGroup = 'AI Scan'; UiLabel = 'AI Scan for repositories'; Recommended = $false; Why = 'A preview that scans default branches with AI at a cost; turn it on deliberately.' }
    @{ Section = 'advancedSecurity'; Field = 'ai_scan_pull_requests'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'check'; Read = @{ Endpoint = '/orgs/{org}/code-scanning/ai-scan'; Field = 'pr_scan' }; Write = @{ Method = 'PATCH'; Endpoint = '/orgs/{org}/code-scanning/ai-scan' }; Page = 'security_analysis'; UiGroup = 'AI Scan'; UiLabel = 'AI Scan for pull requests'; Options = @{ enabled = 'On'; disabled = 'Off' }; Recommended = 'disabled'; Why = 'Each scan of a pull request costs AI credits; turn it on deliberately.' }
    @{ Section = 'advancedSecurity'; Field = 'scan_ai_applications'; Type = 'boolean'; Mode = 'manual'; Page = 'security_analysis'; UiGroup = 'AI Scan'; UiLabel = 'Scan for AI applications'; Recommended = $false; Why = 'A preview that scans pull requests with AI at a cost; turn it on deliberately.' }
    @{ Section = 'advancedSecurity'; Field = 'code_quality'; Type = 'boolean'; Mode = 'manual'; Page = 'code-quality'; UiLabel = 'Enable Code Quality'; UiGroup = 'Code quality'; Hint = 'true is "Enable Code Quality" selected'; Recommended = $false; Why = 'Code quality scanning charges Actions minutes, which the budgets stop at 0.' }
    # Copilot pages; a policy shows Enabled, Disabled or Unconfigured (never set). Current values, recommendations only
    # where data or money is at stake (decided 2026-11-08).
    @{ Section = 'copilot.policies'; Field = 'ai_credit_paid_usage'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Billing'; UiLabel = 'AI credit paid usage'; Options = @{ enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Usage beyond the included AI credits is charged; the ai_credits budget caps it.'; NoRecommendation = 'Owner decides: paid usage beyond the included credits is a cost decision, capped by the ai_credits budget.' }
    @{ Section = 'copilot.policies'; Field = 'bill_reviews_to_organization'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/policies'; UiLabel = 'Choose how members with a Copilot license are billed'; UiGroup = 'Copilot code review'; Hint = 'under "Choose how members with a Copilot license are billed", true is "Organization"'; Recommended = $true; Why = 'Reviews count against ai_credits of budgets, not the quota of the member; billed to the member, a review fails with insufficient remaining quota.' }
    @{ Section = 'copilot.policies'; Field = 'reviews_without_license'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Copilot code review'; UiLabel = 'Allow reviews without a Copilot license'; Recommended = $false; Why = 'The organization does not pay for reviews of Dependabot and outside contributors.' }
    @{ Section = 'copilot.policies'; Field = 'code_review_preview_features'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Copilot code review'; UiLabel = 'Opt in to preview features'; Recommended = $false; Why = 'Preview features of code review fall under the pre-release terms.' }
    @{ Section = 'copilot.policies'; Field = 'default_policy_new_features'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Features'; UiLabel = 'Default policy for new features and clients'; Options = @{ enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'A new Copilot feature starts only after someone decides on it.' }
    @{ Section = 'copilot.policies'; Field = 'feedback_collection'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Opt in to free text user feedback collection'; Recommended = $false; Why = 'The feedback may include sensitive information.' }
    @{ Section = 'copilot.policies'; Field = 'cloud_preview_features'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Opt in to preview features'; Recommended = $false; Why = 'Preview features fall under the pre-release terms.' }
    @{ Section = 'copilot.policies'; Field = 'metrics_api'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Copilot metrics API'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Owners can query Copilot usage through the API.'; NoRecommendation = 'Owner decides: metrics of Copilot use stay within GitHub; whether to collect them is a decision of the organization.' }
    @{ Section = 'copilot.policies'; Field = 'metrics_industry_comparison'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Copilot metrics industry comparison'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'Enabled, the organization contributes its aggregated metrics to comparisons with other organizations.' }
    @{ Section = 'copilot.policies'; Field = 'usage_metrics'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'Copilot usage metrics'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Admins and authorized users can read Copilot usage through the API.'; NoRecommendation = 'Owner decides: metrics of Copilot use stay within GitHub; whether to collect them is a decision of the organization.' }
    @{ Section = 'copilot.policies'; Field = 'mcp_servers'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Web & mobile'; UiLabel = 'MCP servers in Copilot'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'No third-party server is connected to Copilot.' }
    @{ Section = 'copilot.policies'; Field = 'agent_mode_ide'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Editors'; UiLabel = 'Copilot Agent Mode in IDE Chat'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Copilot plans and changes code from the editor of a member.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'editor_preview_features'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Editors'; UiLabel = 'Editor preview features'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'Preview features of the editors, MCP servers among them, fall under the pre-release terms.' }
    @{ Section = 'copilot.policies'; Field = 'github_desktop'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Desktop & terminal'; UiLabel = 'Copilot in GitHub Desktop'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Copilot assistance in GitHub Desktop.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'copilot_app'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Desktop & terminal'; UiLabel = 'GitHub Copilot app'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'The GitHub Copilot app; before its version 1.1 the Copilot CLI policy governs it.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'cli_billed_to_organization'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Desktop & terminal'; UiLabel = 'Allow use of Copilot CLI billed to the organization'; Recommended = $false; Why = 'The Copilot CLI of automations that no member runs would spend the AI credits of the organization.' }
    @{ Section = 'copilot.policies'; Field = 'cloud_sessions'; Type = 'enum'; Values = @('disabled', 'view_from_cloud', 'view_and_control'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Desktop & terminal'; UiLabel = 'Store local sessions in the Cloud'; Options = @{ disabled = 'Disabled'; view_from_cloud = 'View from cloud'; view_and_control = 'View and control' }; Recommended = 'disabled'; Why = 'The CLI and VS Code sessions of members are stored on GitHub; with control, whoever holds a member''s account steers the agent on the member''s machine from github.com.' }
    @{ Section = 'copilot.policies'; Field = 'web_search'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Search & context'; UiLabel = 'Copilot can search the web'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'A web search sends parts of the question, and so of the code, to Bing.' }
    @{ Section = 'copilot.policies'; Field = 'model_native_search'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Search & context'; UiLabel = 'Copilot can search the web using model native search'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'The search of a model sends parts of the question to the search of its provider.' }
    @{ Section = 'copilot.policies'; Field = 'external_semantic_indexing'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Search & context'; UiLabel = 'Semantic indexing for Non-GitHub Repositories'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'Members would upload code from outside GitHub for indexing.' }
    @{ Section = 'copilot.policies'; Field = 'spaces'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Search & context'; UiLabel = 'Copilot Spaces'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Members can view and create Copilot Spaces.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'spaces_individual_access'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Search & context'; UiLabel = 'Copilot Spaces Individual Access'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Members can create Spaces of their own.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'spaces_individual_sharing'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Search & context'; UiLabel = 'Copilot Spaces Individual Sharing'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'A Space of a member, with what it holds of the code, could be shared with others.' }
    @{ Section = 'copilot.policies'; Field = 'commit_messages'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Creation & suggestions'; UiLabel = 'Copilot-generated commit messages'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Copilot suggests commit messages on GitHub.com.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'user_memories'; Type = 'enum'; Values = @('enabled', 'disabled', 'unconfigured'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Memory'; UiLabel = 'User memories'; Options = @{ unconfigured = 'Unconfigured'; enabled = 'Enabled'; disabled = 'Disabled' }; Why = 'Copilot keeps personal preferences of members for later sessions.'; NoRecommendation = 'Owner decides: a Copilot feature the seats are bought for; whether members use it is a decision of the organization, not a security setting.' }
    @{ Section = 'copilot.policies'; Field = 'repository_memories'; Type = 'enum'; Values = @('none', 'all', 'selected'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Memory'; UiLabel = 'Repository memories'; Options = @{ none = 'No repositories' }; Recommended = 'none'; Why = 'Copilot keeps no facts about private repositories while nobody needs them.' }
    @{ Section = 'copilot.policies'; Field = 'memory_retention_days'; Type = 'integer'; Minimum = 7; Maximum = 180; Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Memory > Copilot memory retention'; UiLabel = 'Retention period (days)'; Why = 'How long Copilot keeps a memory after its last update; the GitHub default while User memories are enabled.'; NoRecommendation = 'Owner decides: how long Copilot keeps memories, a trade-off between usefulness and the data kept.' }
    @{ Section = 'copilot.policies'; Field = 'dreaming'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Memory'; UiLabel = 'Dreaming'; Options = @{ enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'A preview that changes memories without approval and proposes changes to files of the repositories.' }
    @{ Section = 'copilot.policies'; Field = 'bring_your_own_key'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'manual'; Page = 'copilot/policies'; UiGroup = 'Data & model controls'; UiLabel = 'Bring Your Own Language Model Key in Select IDEs'; Options = @{ enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'Code does not go to a third-party model outside the control of the organization.' }
    @{ Section = 'copilot.models'; Field = 'default_availability'; Type = 'enum'; Values = @('enabled', 'disabled'); Mode = 'manual'; Page = 'copilot/models'; UiGroup = 'Default models'; UiLabel = 'Default availability for released models'; Options = @{ enabled = 'Enabled'; disabled = 'Disabled' }; Recommended = 'disabled'; Why = 'A new model, possibly with other data retention terms (the page notes one for Claude Fable 5), becomes available only after someone decides on it.' }
    @{ Section = 'copilot.codeReview'; Field = 'maximum_review_effort'; Type = 'string'; Pattern = '^\S(.*\S)?$'; Rule = 'an effort the page offers, such as balanced'; Mode = 'manual'; Page = 'copilot/code_review'; UiLabel = 'Maximum review effort'; UiGroup = 'General'; Hint = 'under "General" choose "Maximum review effort"'; Recommended = 'balanced'; Why = 'Nobody requests Max reviews (about $10 each, in preview).' }
    @{ Section = 'copilot.codeReview'; Field = 'approve_pull_requests'; Type = 'string'; Pattern = '^\S(.*\S)?$'; Rule = 'the option of the page in lower case with underscores, such as disabled_everywhere'; Mode = 'manual'; Page = 'copilot/code_review'; UiGroup = 'Approvals'; UiLabel = 'Allow Copilot to approve pull requests'; Recommended = 'disabled_everywhere'; Why = 'An approval by Copilot would satisfy the required approval of the ruleset, and a pull request would merge without a person.' }
    @{ Section = 'copilot.codeReview'; Field = 'block_external_license_reviews'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/code_review'; UiGroup = 'Access and licensing'; UiLabel = 'Block reviews requested with an external Copilot license'; Recommended = $true; Why = 'Only licenses of the organization request reviews; the automatic reviews of the ruleset still run.' }
    @{ Section = 'copilot.internetAccess'; Field = 'cloud_firewall'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/internet_access'; UiGroup = 'Copilot in the cloud'; UiLabel = 'Enable firewall'; Recommended = $true; Why = 'An agent that reads the code reaches only the allowlisted locations.' }
    @{ Section = 'copilot.internetAccess'; Field = 'cloud_recommended_allowlist'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/internet_access'; UiGroup = 'Copilot in the cloud'; UiLabel = 'Recommended allowlist'; Recommended = $true; Why = 'The agent installs packages and tools only from the locations GitHub recommends.' }
    @{ Section = 'copilot.internetAccess'; Field = 'cloud_repository_custom_rules'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/internet_access'; UiGroup = 'Copilot in the cloud'; UiLabel = 'Allow repository custom rules'; Recommended = $false; Why = 'A repository admin cannot open more network access than the organization allows.' }
    @{ Section = 'copilot.internetAccess'; Field = 'code_review_firewall'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/internet_access'; UiGroup = 'Copilot code review'; UiLabel = 'Enable firewall'; Recommended = $true; Why = 'A reviewer that reads the code reaches only the allowlisted locations.' }
    @{ Section = 'copilot.internetAccess'; Field = 'code_review_recommended_allowlist'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/internet_access'; UiGroup = 'Copilot code review'; UiLabel = 'Recommended allowlist'; Recommended = $true; Why = 'The reviewer installs packages and tools only from the locations GitHub recommends.' }
    @{ Section = 'copilot.internetAccess'; Field = 'code_review_repository_custom_rules'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/internet_access'; UiGroup = 'Copilot code review'; UiLabel = 'Allow repository custom rules'; Recommended = $false; Why = 'A repository admin cannot open more network access than the organization allows.' }
    @{ Section = 'copilot.runnerType'; Field = 'cloud_agent_runner_type'; Type = 'enum'; Values = @('standard', 'labeled'); Mode = 'manual'; Page = 'copilot/runner_type'; UiGroup = 'Copilot cloud agent'; UiLabel = 'Runner type configuration'; Hint = 'choose the runner type'; Options = @{ standard = 'Standard GitHub runner' }; Recommended = 'standard'; Why = 'The cloud agent runs on the standard GitHub runner; a custom runner costs more and is another place the code runs.' }
    @{ Section = 'copilot.runnerType'; Field = 'cloud_agent_allow_repository_customization'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/runner_type'; UiGroup = 'Copilot cloud agent'; UiLabel = 'Allow repositories to customize the runner type'; Recommended = $false; Why = 'A repository cannot move the cloud agent to a runner of its own.' }
    @{ Section = 'copilot.automations'; Field = 'allow_automations'; Type = 'enum'; Values = @('none', 'all', 'selected'); Mode = 'manual'; Page = 'copilot/coding_agent'; UiGroup = 'Automations'; UiLabel = 'Allow automations'; Options = @{ none = 'No repositories' }; Recommended = 'none'; Why = 'The cloud agent is not used, and a repository cannot turn automations on by itself.' }
    @{ Section = 'copilot.automations'; Field = 'allow_shared_automations'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/coding_agent'; UiGroup = 'Automations'; UiLabel = 'Allow shared automations'; Recommended = $false; Why = 'Shared automations run as the organization and are billed to it.' }
    @{ Section = 'copilot.automations'; Field = 'require_write_access'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/coding_agent'; UiGroup = 'Automations'; UiLabel = 'Require write access to trigger automations'; Recommended = $true; Why = 'Someone without write access cannot start an automation.' }
    @{ Section = 'copilot.automations'; Field = 'update_triggering_resource_only'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/coding_agent'; UiGroup = 'Automations'; UiLabel = 'Only allow automations to update the resource that triggered them'; Recommended = $true; Why = 'An automation changes only what started it.' }
    @{ Section = 'copilot.automations'; Field = 'require_workflow_approval'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/coding_agent'; UiLabel = 'Require approval for workflows on automation pull requests'; UiGroup = 'Automations'; Hint = 'under "Require approval for workflows on automation pull requests", true is "Enabled in all repositories"'; Recommended = $true; Why = 'The workflows of its pull requests wait for a person.' }
    @{ Section = 'copilot.partnerAgents'; Field = 'claude'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/coding_agent'; UiGroup = 'Partner agents'; UiLabel = 'Allow Claude coding agent'; Recommended = $false; Why = 'No other agent works in the repositories of the organization.' }
    @{ Section = 'copilot.partnerAgents'; Field = 'codex'; Type = 'boolean'; Mode = 'manual'; Page = 'copilot/coding_agent'; UiGroup = 'Partner agents'; UiLabel = 'Allow Codex coding agent'; Recommended = $false; Why = 'No other agent works in the repositories of the organization.' }
)

# Every config section validation walks, in the order its rows first appear: the endpoint sections of $script:Sections
# and the code security configuration, an object with its own lifecycle rather than an endpoint (see
# Read-CodeSecurityState and Get-CodeSecurityAction). A section exists through its rows, so each one has a row.
$script:ConfigSections = @($script:SettingDefinitions | ForEach-Object { $_.Section } | Select-Object -Unique)

# The config format this stage reads: a config of the same major and a minor not above this one. The major changes when
# a config needs an edit (a key added, removed, renamed or moved, a value no longer allowed); the minor when every
# config of the format stays valid and means the same. Independent of the release version of the engine.
$script:ConfigFormatVersion = '1.0'

# The top-level keys of the config, in the order of github.json; exceptions comes last. The sections by subject
# are in the shape once a row is in them.
$script:TopLevelSections = @(
    'configVersion', 'organization', 'inventory', 'settings', 'authenticationSecurity', 'memberPrivileges', 'repositoryDefaults', 'projects', 'actions', 'copilotCloudAgent', 'copilot', 'codeSecurity', 'ruleset', 'budgets', 'copilotSeats',
    'personalAccessTokens', 'oauthApps', 'codespaces', 'packages', 'discussions', 'interactionLimits', 'immutableReleases', 'dependabot', 'advancedSecurity'
)

# Every key a row of $script:SettingDefinitions may have; a test rejects any other, so a misspelled key cannot be
# ignored without a word (docs/architecture.md, "Config shapes").
$script:SettingRowKeys = @(
    'Section', 'Field', 'Type', 'Values', 'Mode', 'Nullable', 'Pattern', 'Rule', 'Minimum', 'Maximum', 'MinItems', 'Item', 'ItemKey', 'RuleExceptions',
    'Description', 'Recommended', 'Why', 'NoRecommendation', 'Sensitive', 'Page', 'NoUi', 'UiGroup', 'UiLabel', 'Hint', 'Options', 'Docs',
    'Read', 'Write', 'PlanRestriction', 'ReadRequiresPlan', 'Absent', 'AbsentValue', 'DependsOn'
)

function Get-SettingDefinition {
    param([Parameter(Mandatory)][string]$Section)
    return @($script:SettingDefinitions | Where-Object { $_.Section -eq $Section })
}

function Get-SettingPath {
    # '<section>.<field>', the name of a row in messages and tests.
    param([Parameter(Mandatory)][hashtable]$Definition)

    return "$($Definition.Section).$($Definition.Field)"
}

function Get-SettingRead {
    # @{ Endpoint; Field } the API read of a row (OpenAPI path), or $null. A Read of the row wins; an apply or check row
    # of a section of $script:Sections reads that section's endpoint and its field name; a manual row has no read.
    param([Parameter(Mandatory)][hashtable]$Definition)

    if ($Definition.ContainsKey('Read')) {
        return $Definition.Read
    }
    if ($Definition.Mode -in 'apply', 'check' -and $script:Sections.Contains($Definition.Section)) {
        return @{ Endpoint = '/orgs/{org}' + $script:Sections[$Definition.Section].Path; Field = $Definition.Field }
    }
    return $null
}

function Get-SettingWrite {
    # @{ Method; Endpoint } the API write of a row (OpenAPI path), or $null. A Write of the row wins; an apply row of a
    # section of $script:Sections writes with the section's method to its endpoint.
    param([Parameter(Mandatory)][hashtable]$Definition)

    if ($Definition.ContainsKey('Write')) {
        return $Definition.Write
    }
    if ($Definition.Mode -eq 'apply' -and $script:Sections.Contains($Definition.Section)) {
        $section = $script:Sections[$Definition.Section]
        return @{ Method = $section.Method; Endpoint = '/orgs/{org}' + $section.Path }
    }
    return $null
}

function Get-ConfigSection {
    # The config object of a section ('actions.selected' -> $Config.actions.selected); $null for a null section.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Section
    )

    $node = $Config
    foreach ($part in $Section.Split('.')) {
        if ($node -isnot [System.Management.Automation.PSCustomObject]) {
            return $null
        }
        $node = $node.$part
    }
    return $node
}

function Get-ConfiguredValue {
    # Field -> configured value of the fields of a section; empty for a null section.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Section
    )

    $values = [ordered]@{}
    $node = Get-ConfigSection -Config $Config -Section $Section
    if ($node -isnot [System.Management.Automation.PSCustomObject]) {
        return $values
    }
    foreach ($definition in (Get-SettingDefinition -Section $Section)) {
        $property = $node.PSObject.Properties[$definition.Field]
        if ($property) {
            $values[$definition.Field] = $property.Value
        }
    }
    return $values
}

function ConvertTo-SettingNode {
    # The shape node of a row of $script:SettingDefinitions.
    param([Parameter(Mandatory)][hashtable]$Definition)

    $node = switch ($Definition.Type) {
        'boolean' { @{ Type = 'boolean' } }
        'enum' { @{ Type = 'enum'; Values = $Definition.Values } }
        'email' { @{ Type = 'string'; Pattern = $script:EmailPattern; Rule = 'an email address such as security@example.com' } }
        'integer' { @{ Type = 'integer'; Minimum = 1 } }
        'list' { @{ Type = 'array'; Unique = $true; Items = @{ Type = 'string'; Pattern = '^\S+$'; Rule = 'a non-empty string without whitespace' } } }
        'enumList' { @{ Type = 'array'; Unique = $true; MinItems = 1; Items = @{ Type = 'enum'; Values = $Definition.Values } } }
        # Item: the fields of an item. ItemKey: the field that names an item, unique case-insensitively.
        'objectList' {
            $list = @{ Type = 'array'; Items = @{ Type = 'object'; Fields = $Definition.Item } }
            if ($Definition.ItemKey) {
                $list.ItemKey = $Definition.ItemKey
                $list.Unique = $true
            }
            $list
        }
        'string' { @{ Type = 'string'; Pattern = $Definition.Pattern; Rule = $Definition.Rule } }
        default { throw "Unknown setting type '$($Definition.Type)'." }
    }
    # 0 is a Minimum too, so ContainsKey rather than a truth test.
    foreach ($key in 'Minimum', 'Maximum', 'MinItems', 'Nullable', 'RuleExceptions', 'Recommended', 'Why', 'Description', 'Sensitive') {
        if ($Definition.ContainsKey($key)) {
            $node[$key] = $Definition[$key]
        }
    }
    # Why the engine takes no side goes after the description, so the schema shows it where a recommendation would be.
    if ($Definition.NoRecommendation) {
        $node.Description = @($Definition.Description, $Definition.NoRecommendation | Where-Object { $_ }) -join ' '
    }
    return $node
}

function Get-SectionNode {
    # The shape node of a config section: its settings, then its nested sections.
    param([Parameter(Mandatory)][string]$Section)

    $fields = [ordered]@{}
    foreach ($definition in (Get-SettingDefinition -Section $Section)) {
        $fields[$definition.Field] = ConvertTo-SettingNode -Definition $definition
    }
    foreach ($nested in $script:ConfigSections) {
        if (-not $nested.StartsWith("$Section.")) {
            continue
        }
        $name = $nested.Substring($Section.Length + 1)
        if (-not $name.Contains('.')) {
            $fields[$name] = Get-SectionNode -Section $nested
        }
    }
    $node = @{ Type = 'object'; Fields = $fields }
    if ($script:Sections[$Section].Nullable) {
        $node.Nullable = $true
    }
    return $node
}

function Get-GitHubOrgConfigShape {
    <#
    .SYNOPSIS
    The shape of a GitHub organization config, built from $script:SettingDefinitions and the inventory.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $fields = [ordered]@{}
    foreach ($name in $script:TopLevelSections) {
        switch ($name) {
            'configVersion' { $fields[$name] = @{ Type = 'string'; Pattern = '^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$'; Rule = 'major.minor, such as 1.0'; Description = 'The config format this config is written in. The engine reads its own major version up to its own minor version.' } }
            'organization' { $fields[$name] = (Get-ConfigPatternNode -Name Login) + @{ Description = 'The organization login.' } }
            'inventory' { $fields[$name] = Get-InventoryNode }
            'budgets' { $fields[$name] = Get-BudgetNode }
            'copilotSeats' { $fields[$name] = Get-CopilotSeatNode }
            default {
                # A section by subject exists through its rows, its own or those of a nested section.
                if (@($script:ConfigSections | Where-Object { $_ -eq $name -or $_.StartsWith("$name.") }).Count -gt 0) {
                    $fields[$name] = Get-SectionNode -Section $name
                }
            }
        }
    }
    $shape = @{ Type = 'object'; Fields = $fields }
    $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
    return $shape
}

function Test-GitHubOrgConfig {
    <#
    .SYNOPSIS
    Validates a GitHub organization config and returns error messages (empty when the config is valid).
    .DESCRIPTION
    The shape first; the rules between fields only when the shape is valid, since they assume it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        # The day of the run; a parameter so tests are deterministic.
        [datetime]$Today = [datetime]::UtcNow.Date
    )

    $shape = Get-GitHubOrgConfigShape
    # Before the shape: a config of another format differs in its keys, and those errors would hide the one that
    # explains them, so it gets this error alone. A missing or malformed version is left to the shape.
    $version = $Config.configVersion
    $format = $null
    if ($version -is [string] -and $version -cmatch $shape.Fields['configVersion'].Pattern -and -not $version.EndsWith("`n") -and [version]::TryParse($version, [ref]$format)) {
        $stage = [version]$script:ConfigFormatVersion
        if ($format.Major -ne $stage.Major -or $format.Minor -gt $stage.Minor) {
            return [string[]]@("configVersion '$version': this version of the engine reads config formats $($stage.Major).0 to $($stage.Major).$($stage.Minor). Update the engine or the config as the notes of the format say.")
        }
    }
    $errors = [string[]]@(Test-ConfigShape -Config $Config -Shape $shape)
    if ($errors.Count -gt 0) {
        return $errors
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $selected = $Config.actions.selected
    if ($Config.actions.allowed_actions -ceq 'selected') {
        if ($null -eq $selected) {
            $result.Add("actions.selected must be an object when actions.allowed_actions is 'selected': it is the list of allowed actions, and GitHub keeps whatever list it has stored otherwise.")
        }
    }
    elseif ($null -ne $selected) {
        $result.Add("actions.selected must be null unless actions.allowed_actions is 'selected'; GitHub rejects the list otherwise.")
    }
    # Unique by repository and path: one ItemKey cannot say it. The repository is a name (case-insensitive), the path
    # a file path, which GitHub compares exactly.
    $workflows = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($workflow in $Config.ruleset.rules.workflows) {
        if (-not $workflows.Add("$($workflow.repository.ToLowerInvariant())/$($workflow.path)")) {
            $result.Add("ruleset.rules.workflows: '$($workflow.repository)/$($workflow.path)' is listed more than once.")
        }
    }
    $result.AddRange([string[]]@(Test-ExceptionList -Exceptions @($Config.exceptions) -Shape $shape -Today $Today))
    $result.AddRange([string[]]@((Get-WorkflowReviewerReport -Config $Config -Today $Today).NotWaived))
    return $result.ToArray()
}

function Get-WorkflowReviewerReport {
    <#
    .SYNOPSIS
    Applies the rule that a team must approve changes to .github/workflows/** to a shape-valid config. Returns
    {NotWaived, Warnings, Waivers} of Get-RuleExceptionReport for ruleset.rules.pullRequest.requiredReviewers.
    .DESCRIPTION
    An entry covers the workflows when it needs at least one approval, has one of the patterns .github/workflows/**,
    .github/** or ** (compared exactly, as GitHub matches paths), and excludes neither .github/workflows nor .github
    with a negated pattern. Other patterns that would also match are not counted: the rule asks for the plain one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][datetime]$Today
    )

    $covering = @($Config.ruleset.rules.pullRequest.requiredReviewers | Where-Object {
            $patterns = @($_.file_patterns)
            $_.minimum_approvals -ge 1 -and
            @($patterns | Where-Object { $_ -cin '.github/workflows/**', '.github/**', '**' }).Count -gt 0 -and
            @($patterns | Where-Object { $_.StartsWith('!.github/workflows', [StringComparison]::Ordinal) -or $_.StartsWith('!.github/**', [StringComparison]::Ordinal) }).Count -eq 0
        })
    $finding = $null
    if ($covering.Count -eq 0) {
        $finding = 'ruleset.rules.pullRequest.requiredReviewers: no team must approve changes to .github/workflows/**, so anyone with write access and one approval changes the workflows of every repository. Add a requiredReviewers entry with minimum_approvals of at least 1 whose file_patterns include .github/workflows/**.'
    }
    Get-RuleExceptionReport -Config $Config -Shape (Get-GitHubOrgConfigShape) -Path 'ruleset.rules.pullRequest.requiredReviewers' -Finding $finding -NotNeeded 'a team must approve changes to .github/workflows/**' -Today $Today
}
