# Every operation of the GitHub REST API under /orgs/{org} and /organizations/{org} of the description of the
# pinned version (ApiVersion), and every other operation the engine calls. Data only: tools/ and the tests read it
# without importing the engine. Status: read (the engine calls this GET), write (Apply calls this method), unused (with
# the Reason). Fields (a read GET whose response fields are tracked): every response field no row reads, with the reason;
# a field of the answer that is neither is a warning of the run. Body (a write PUT or PATCH): every request body field
# of the description. Paths, methods, field names and reasons only, never values.
@{
    ApiVersion = '2026-03-10'
    ReviewedOn = '2026-11-10'
    Paths      = @{
        '/organizations/{org}/actions/cache/retention-limit'                                        = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'answered 404 to the owner''s token (scope admin:org) on 2026-11-10; the page shows the limits, the manual rows actions.cache' }
            PUT      = @{ Status = 'unused'; Reason = 'a write the engine could not read back: the GET answered 404 to the owner''s token (scope admin:org) on 2026-11-10; the limits stay the manual rows actions.cache' }
        }
        '/organizations/{org}/actions/cache/storage-limit'                                          = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'answered 404 to the owner''s token (scope admin:org) on 2026-11-10; the page shows the limits, the manual rows actions.cache' }
            PUT      = @{ Status = 'unused'; Reason = 'a write the engine could not read back: the GET answered 404 to the owner''s token (scope admin:org) on 2026-11-10; the limits stay the manual rows actions.cache' }
        }
        '/organizations/{org}/settings/billing/ai_credit/usage'                                     = @{
            Category = 'billing'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/organizations/{org}/settings/billing/budgets'                                             = @{
            Category = 'billing'
            GET      = @{ Status = 'read' }
            POST     = @{ Status = 'write' }
        }
        '/organizations/{org}/settings/billing/budgets/{budget_id}'                                 = @{
            Category = 'billing'
            GET      = @{ Status = 'unused'; Reason = 'the budgets area reads the list, which answers every budget' }
            PATCH    = @{ Status = 'write'; Body = @('budget_amount', 'prevent_further_usage', 'budget_alerting', 'expires_at') }
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never deletes a budget' }
        }
        '/organizations/{org}/settings/billing/premium_request/usage'                               = @{
            Category = 'billing'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/organizations/{org}/settings/billing/usage'                                               = @{
            Category = 'billing'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/organizations/{org}/settings/billing/usage/summary'                                       = @{
            Category = 'billing'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}'                                                                               = @{
            Category = 'orgs'
            GET      = @{
                Status = 'read'
                Fields = @{
                    advanced_security_enabled_for_new_repositories               = 'deprecated; the code security configuration (codeSecurity) replaces it'
                    archived_at                                                  = 'profile data, not managed'
                    avatar_url                                                   = 'a link or a count, not a setting'
                    billing_email                                                = 'profile data, not managed'
                    blog                                                         = 'profile data, not managed'
                    collaborators                                                = 'a link or a count, not a setting'
                    company                                                      = 'profile data, not managed'
                    created_at                                                   = 'profile data, not managed'
                    dependabot_alerts_enabled_for_new_repositories               = 'deprecated; the code security configuration (codeSecurity) replaces it'
                    dependabot_security_updates_enabled_for_new_repositories     = 'deprecated; the code security configuration (codeSecurity) replaces it'
                    dependency_graph_enabled_for_new_repositories                = 'deprecated; the code security configuration (codeSecurity) replaces it'
                    description                                                  = 'profile data, not managed'
                    disk_usage                                                   = 'a link or a count, not a setting'
                    events_url                                                   = 'a link or a count, not a setting'
                    followers                                                    = 'a link or a count, not a setting'
                    following                                                    = 'a link or a count, not a setting'
                    hooks_url                                                    = 'a link or a count, not a setting'
                    html_url                                                     = 'a link or a count, not a setting'
                    id                                                           = 'profile data, not managed'
                    issues_url                                                   = 'a link or a count, not a setting'
                    location                                                     = 'profile data, not managed'
                    login                                                        = 'profile data, not managed'
                    members_allowed_repository_creation_type                     = 'deprecated; members_can_create_*_repositories replace it'
                    members_can_create_internal_repositories                     = 'internal repositories need GitHub Enterprise Cloud'
                    members_url                                                  = 'a link or a count, not a setting'
                    name                                                         = 'profile data, not managed'
                    node_id                                                      = 'profile data, not managed'
                    owned_private_repos                                          = 'a link or a count, not a setting'
                    plan                                                         = 'read for the plan name (3.4), not a setting'
                    private_gists                                                = 'a link or a count, not a setting'
                    public_gists                                                 = 'a link or a count, not a setting'
                    public_members_url                                           = 'a link or a count, not a setting'
                    public_repos                                                 = 'a link or a count, not a setting'
                    repos_url                                                    = 'a link or a count, not a setting'
                    secret_scanning_enabled_for_new_repositories                 = 'deprecated; the code security configuration (codeSecurity) replaces it'
                    secret_scanning_push_protection_enabled_for_new_repositories = 'deprecated; the code security configuration (codeSecurity) replaces it'
                    total_private_repos                                          = 'a link or a count, not a setting'
                    twitter_username                                             = 'profile data, not managed'
                    type                                                         = 'profile data, not managed'
                    updated_at                                                   = 'profile data, not managed'
                    url                                                          = 'a link or a count, not a setting'
                }
            }
            PATCH    = @{ Status = 'write'; Body = @('billing_email', 'company', 'email', 'twitter_username', 'location', 'name', 'description', 'has_organization_projects', 'has_repository_projects', 'default_repository_permission', 'members_can_create_repositories', 'members_can_create_internal_repositories', 'members_can_create_private_repositories', 'members_can_create_public_repositories', 'members_allowed_repository_creation_type', 'members_can_create_pages', 'members_can_create_public_pages', 'members_can_create_private_pages', 'members_can_fork_private_repositories', 'web_commit_signoff_required', 'blog', 'advanced_security_enabled_for_new_repositories', 'dependabot_alerts_enabled_for_new_repositories', 'dependabot_security_updates_enabled_for_new_repositories', 'dependency_graph_enabled_for_new_repositories', 'secret_scanning_enabled_for_new_repositories', 'secret_scanning_push_protection_enabled_for_new_repositories', 'secret_scanning_push_protection_custom_link', 'deploy_keys_enabled_for_repositories') }
            DELETE   = @{ Status = 'unused'; Reason = 'deletes the organization' }
        }
        '/orgs/{org}/actions/cache/usage'                                                           = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'usage reports, not settings' }
        }
        '/orgs/{org}/actions/cache/usage-by-repository'                                             = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'usage reports, not settings' }
        }
        '/orgs/{org}/actions/hosted-runners'                                                        = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
            POST     = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/images/custom'                                          = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}'                    = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions'           = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions/{version}' = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/images/github-owned'                                    = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/images/partner'                                         = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/limits'                                                 = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/machine-sizes'                                          = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/platforms'                                              = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/hosted-runners/{hosted_runner_id}'                                     = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
            PATCH    = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/oidc/customization/properties/repo'                                    = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'claims of custom properties, none defined (outside this tool)' }
            POST     = @{ Status = 'unused'; Reason = 'claims of custom properties, none defined (outside this tool)' }
        }
        '/orgs/{org}/actions/oidc/customization/properties/repo/{custom_property_name}'             = @{
            Category = 'actions'
            DELETE   = @{ Status = 'unused'; Reason = 'claims of custom properties, none defined (outside this tool)' }
        }
        '/orgs/{org}/actions/oidc/customization/sub'                                                = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'answered 404 to the owner''s token on 2026-11-08 (no template stored); the page shows the template, a manual row' }
            PUT      = @{ Status = 'unused'; Reason = 'a write the engine cannot read back, so the template stays a manual row' }
        }
        '/orgs/{org}/actions/permissions'                                                           = @{
            Category = 'actions'
            GET      = @{
                Status = 'read'
                Fields = @{
                    selected_actions_url      = 'a link or a count, not a setting'
                    selected_repositories_url = 'a link or a count, not a setting'
                }
            }
            PUT      = @{ Status = 'write'; Body = @('enabled_repositories', 'allowed_actions', 'sha_pinning_required') }
        }
        '/orgs/{org}/actions/permissions/artifact-and-log-retention'                                = @{
            Category = 'actions'
            GET      = @{
                Status = 'read'
                Fields = @{
                    maximum_allowed_days = 'the maximum GitHub allows, read-only, not a setting'
                }
            }
            PUT      = @{ Status = 'write'; Body = @('days') }
        }
        '/orgs/{org}/actions/permissions/fork-pr-contributor-approval'                              = @{
            Category = 'actions'
            GET      = @{ Status = 'read'; Fields = @{} }
            PUT      = @{ Status = 'write'; Body = @('approval_policy') }
        }
        '/orgs/{org}/actions/permissions/fork-pr-workflows-private-repos'                           = @{
            Category = 'actions'
            GET      = @{ Status = 'read'; Fields = @{} }
            PUT      = @{ Status = 'write'; Body = @('run_workflows_from_fork_pull_requests', 'send_write_tokens_to_workflows', 'send_secrets_and_variables', 'require_approval_for_fork_pr_workflows') }
        }
        '/orgs/{org}/actions/permissions/repositories'                                              = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'used only while enabled_repositories is selected, which the config never sets' }
            PUT      = @{ Status = 'unused'; Reason = 'used only while enabled_repositories is selected, which the config never sets' }
        }
        '/orgs/{org}/actions/permissions/repositories/{repository_id}'                              = @{
            Category = 'actions'
            PUT      = @{ Status = 'unused'; Reason = 'used only while enabled_repositories is selected, which the config never sets' }
            DELETE   = @{ Status = 'unused'; Reason = 'used only while enabled_repositories is selected, which the config never sets' }
        }
        '/orgs/{org}/actions/permissions/selected-actions'                                          = @{
            Category = 'actions'
            GET      = @{ Status = 'read'; Fields = @{} }
            PUT      = @{ Status = 'write'; Body = @('github_owned_allowed', 'verified_allowed', 'patterns_allowed') }
        }
        '/orgs/{org}/actions/permissions/self-hosted-runners'                                       = @{
            Category = 'actions'
            GET      = @{
                Status = 'read'
                Fields = @{
                    selected_repositories_url = 'a link or a count, not a setting'
                }
            }
            PUT      = @{ Status = 'write'; Body = @('enabled_repositories') }
        }
        '/orgs/{org}/actions/permissions/self-hosted-runners/repositories'                          = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use self-hosted runners, used only while actions.selfHostedRunners.enabled_repositories is selected; it is none' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use self-hosted runners, used only while actions.selfHostedRunners.enabled_repositories is selected; it is none' }
        }
        '/orgs/{org}/actions/permissions/self-hosted-runners/repositories/{repository_id}'          = @{
            Category = 'actions'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use self-hosted runners, used only while actions.selfHostedRunners.enabled_repositories is selected; it is none' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use self-hosted runners, used only while actions.selfHostedRunners.enabled_repositories is selected; it is none' }
        }
        '/orgs/{org}/actions/permissions/workflow'                                                  = @{
            Category = 'actions'
            GET      = @{ Status = 'read'; Fields = @{} }
            PUT      = @{ Status = 'write'; Body = @('default_workflow_permissions', 'can_approve_pull_request_reviews') }
        }
        '/orgs/{org}/actions/policies'                                                              = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'Actions policies are objects, none defined' }
            POST     = @{ Status = 'unused'; Reason = 'Actions policies are objects, none defined' }
        }
        '/orgs/{org}/actions/policies/{policy_id}'                                                  = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'Actions policies are objects, none defined' }
            PUT      = @{ Status = 'unused'; Reason = 'Actions policies are objects, none defined' }
            DELETE   = @{ Status = 'unused'; Reason = 'Actions policies are objects, none defined' }
        }
        '/orgs/{org}/actions/runner-groups'                                                         = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            POST     = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runner-groups/{runner_group_id}'                                       = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            PATCH    = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runner-groups/{runner_group_id}/hosted-runners'                        = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'larger GitHub-hosted runners are not used' }
        }
        '/orgs/{org}/actions/runner-groups/{runner_group_id}/repositories'                          = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            PUT      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runner-groups/{runner_group_id}/repositories/{repository_id}'          = @{
            Category = 'actions'
            PUT      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runner-groups/{runner_group_id}/runners'                               = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            PUT      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runner-groups/{runner_group_id}/runners/{runner_id}'                   = @{
            Category = 'actions'
            PUT      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners'                                                               = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/deprecations/{version}'                                        = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/downloads'                                                     = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/generate-jitconfig'                                            = @{
            Category = 'actions'
            POST     = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/registration-token'                                            = @{
            Category = 'actions'
            POST     = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/remove-token'                                                  = @{
            Category = 'actions'
            POST     = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/{runner_id}'                                                   = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/{runner_id}/labels'                                            = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            PUT      = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            POST     = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/runners/{runner_id}/labels/{name}'                                     = @{
            Category = 'actions'
            DELETE   = @{ Status = 'unused'; Reason = 'self-hosted runners and their groups are not used' }
        }
        '/orgs/{org}/actions/secrets'                                                               = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
        }
        '/orgs/{org}/actions/secrets/public-key'                                                    = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'the key that encrypts a secret before it is written, which the engine never does' }
        }
        '/orgs/{org}/actions/secrets/{secret_name}'                                                 = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
            PUT      = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
        }
        '/orgs/{org}/actions/secrets/{secret_name}/repositories'                                    = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/actions/secrets/{secret_name}/repositories/{repository_id}'                    = @{
            Category = 'actions'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/actions/variables'                                                             = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'workflow variables, objects of the workflows, not settings' }
            POST     = @{ Status = 'unused'; Reason = 'writes a workflow variable, an object of the workflows, not a setting' }
        }
        '/orgs/{org}/actions/variables/{name}'                                                      = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'workflow variables, objects of the workflows, not settings' }
            PATCH    = @{ Status = 'unused'; Reason = 'writes a workflow variable, an object of the workflows, not a setting' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a workflow variable, an object of the workflows, not a setting' }
        }
        '/orgs/{org}/actions/variables/{name}/repositories'                                         = @{
            Category = 'actions'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
        }
        '/orgs/{org}/actions/variables/{name}/repositories/{repository_id}'                         = @{
            Category = 'actions'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
        }
        '/orgs/{org}/agents/secrets'                                                                = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
        }
        '/orgs/{org}/agents/secrets/public-key'                                                     = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'the key that encrypts a secret before it is written, which the engine never does' }
        }
        '/orgs/{org}/agents/secrets/{secret_name}'                                                  = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
            PUT      = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
        }
        '/orgs/{org}/agents/secrets/{secret_name}/repositories'                                     = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/agents/secrets/{secret_name}/repositories/{repository_id}'                     = @{
            Category = 'agents'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/agents/variables'                                                              = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'workflow variables, objects of the workflows, not settings' }
            POST     = @{ Status = 'unused'; Reason = 'writes a workflow variable, an object of the workflows, not a setting' }
        }
        '/orgs/{org}/agents/variables/{name}'                                                       = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'workflow variables, objects of the workflows, not settings' }
            PATCH    = @{ Status = 'unused'; Reason = 'writes a workflow variable, an object of the workflows, not a setting' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a workflow variable, an object of the workflows, not a setting' }
        }
        '/orgs/{org}/agents/variables/{name}/repositories'                                          = @{
            Category = 'agents'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
        }
        '/orgs/{org}/agents/variables/{name}/repositories/{repository_id}'                          = @{
            Category = 'agents'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use a variable, part of the variable' }
        }
        '/orgs/{org}/artifacts/metadata/deployment-record'                                          = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/artifacts/metadata/deployment-record/cluster/{cluster}'                        = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/artifacts/metadata/deployment-record/cluster/{cluster}/jobs'                   = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/artifacts/metadata/deployment-record/cluster/{cluster}/jobs/{job_id}'          = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/artifacts/metadata/storage-record'                                             = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/artifacts/{subject_digest}/metadata/deployment-records'                        = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/artifacts/{subject_digest}/metadata/storage-records'                           = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/attestations/bulk-list'                                                        = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/attestations/delete-request'                                                   = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/attestations/digest/{subject_digest}'                                          = @{
            Category = 'orgs'
            DELETE   = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/attestations/repositories'                                                     = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/attestations/{attestation_id}'                                                 = @{
            Category = 'orgs'
            DELETE   = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/attestations/{subject_digest}'                                                 = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'artifact and attestation records, not settings' }
        }
        '/orgs/{org}/blocks'                                                                        = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'blocked users, a list of accounts' }
        }
        '/orgs/{org}/blocks/{username}'                                                             = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'blocked users, a list of accounts' }
            PUT      = @{ Status = 'unused'; Reason = 'blocked users, a list of accounts' }
            DELETE   = @{ Status = 'unused'; Reason = 'blocked users, a list of accounts' }
        }
        '/orgs/{org}/campaigns'                                                                     = @{
            Category = 'campaigns'
            GET      = @{ Status = 'unused'; Reason = 'security campaigns, objects, none created' }
            POST     = @{ Status = 'unused'; Reason = 'security campaigns, objects, none created' }
        }
        '/orgs/{org}/campaigns/{campaign_number}'                                                   = @{
            Category = 'campaigns'
            GET      = @{ Status = 'unused'; Reason = 'security campaigns, objects, none created' }
            PATCH    = @{ Status = 'unused'; Reason = 'security campaigns, objects, none created' }
            DELETE   = @{ Status = 'unused'; Reason = 'security campaigns, objects, none created' }
        }
        '/orgs/{org}/code-scanning/ai-scan'                                                         = @{
            Category = 'code-scanning'
            GET      = @{ Status = 'read'; Fields = @{ repository_scan = 'described, but the answer on 2026-11-10 held only pr_scan; the page shows it, the manual row advancedSecurity.ai_scan_repositories' } }
            PATCH    = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/code-scanning/alerts'                                                          = @{
            Category = 'code-scanning'
            GET      = @{ Status = 'unused'; Reason = 'alerts, not settings' }
        }
        '/orgs/{org}/code-security/configurations'                                                  = @{
            Category = 'code-security'
            GET      = @{ Status = 'read' }
            POST     = @{ Status = 'write' }
        }
        '/orgs/{org}/code-security/configurations/defaults'                                         = @{
            Category = 'code-security'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/code-security/configurations/detach'                                           = @{
            Category = 'code-security'
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never deletes or detaches a configuration' }
        }
        '/orgs/{org}/code-security/configurations/{configuration_id}'                               = @{
            Category = 'code-security'
            GET      = @{ Status = 'unused'; Reason = 'the list of configurations answers every one' }
            PATCH    = @{ Status = 'write'; Body = @('name', 'description', 'advanced_security', 'code_security', 'dependency_graph', 'dependency_graph_autosubmit_action', 'dependency_graph_autosubmit_action_options', 'dependabot_alerts', 'dependabot_reachability', 'dependabot_security_updates', 'dependabot_delegated_alert_dismissal', 'code_scanning_default_setup', 'code_scanning_default_setup_options', 'code_scanning_options', 'code_scanning_delegated_alert_dismissal', 'secret_protection', 'secret_scanning', 'secret_scanning_push_protection', 'secret_scanning_delegated_bypass', 'secret_scanning_delegated_bypass_options', 'secret_scanning_validity_checks', 'secret_scanning_non_provider_patterns', 'secret_scanning_generic_secrets', 'secret_scanning_generic_secrets_push_protection', 'secret_scanning_delegated_alert_dismissal', 'secret_scanning_extended_metadata', 'private_vulnerability_reporting', 'enforcement') }
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never deletes or detaches a configuration' }
        }
        '/orgs/{org}/code-security/configurations/{configuration_id}/attach'                        = @{
            Category = 'code-security'
            POST     = @{ Status = 'write' }
        }
        '/orgs/{org}/code-security/configurations/{configuration_id}/defaults'                      = @{
            Category = 'code-security'
            PUT      = @{ Status = 'write'; Body = @('default_for_new_repos') }
        }
        '/orgs/{org}/code-security/configurations/{configuration_id}/repositories'                  = @{
            Category = 'code-security'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/codespaces'                                                                    = @{
            Category = 'codespaces'
            GET      = @{ Status = 'unused'; Reason = 'codespaces of members, not settings' }
        }
        '/orgs/{org}/codespaces/access'                                                             = @{
            Category = 'codespaces'
            PUT      = @{ Status = 'unused'; Reason = 'write without a read: the engine cannot verify it, so codespaces.access is manual' }
        }
        '/orgs/{org}/codespaces/access/selected_users'                                              = @{
            Category = 'codespaces'
            POST     = @{ Status = 'unused'; Reason = 'used only while Codespaces access is for selected members' }
            DELETE   = @{ Status = 'unused'; Reason = 'used only while Codespaces access is for selected members' }
        }
        '/orgs/{org}/codespaces/secrets'                                                            = @{
            Category = 'codespaces'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
        }
        '/orgs/{org}/codespaces/secrets/public-key'                                                 = @{
            Category = 'codespaces'
            GET      = @{ Status = 'unused'; Reason = 'the key that encrypts a secret before it is written, which the engine never does' }
        }
        '/orgs/{org}/codespaces/secrets/{secret_name}'                                              = @{
            Category = 'codespaces'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
            PUT      = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
        }
        '/orgs/{org}/codespaces/secrets/{secret_name}/repositories'                                 = @{
            Category = 'codespaces'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/codespaces/secrets/{secret_name}/repositories/{repository_id}'                 = @{
            Category = 'codespaces'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/copilot-spaces'                                                                = @{
            Category = 'copilot-spaces'
            GET      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            POST     = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
        }
        '/orgs/{org}/copilot-spaces/{space_number}'                                                 = @{
            Category = 'copilot-spaces'
            GET      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            PUT      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            DELETE   = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
        }
        '/orgs/{org}/copilot-spaces/{space_number}/collaborators'                                   = @{
            Category = 'copilot-spaces'
            GET      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            POST     = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
        }
        '/orgs/{org}/copilot-spaces/{space_number}/collaborators/{actor_type}/{actor_identifier}'   = @{
            Category = 'copilot-spaces'
            PUT      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            DELETE   = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
        }
        '/orgs/{org}/copilot-spaces/{space_number}/resources'                                       = @{
            Category = 'copilot-spaces'
            GET      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            POST     = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
        }
        '/orgs/{org}/copilot-spaces/{space_number}/resources/{space_resource_id}'                   = @{
            Category = 'copilot-spaces'
            GET      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            PUT      = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
            DELETE   = @{ Status = 'unused'; Reason = 'Copilot Spaces, objects of the members; the Spaces policies are rows of copilot.policies' }
        }
        '/orgs/{org}/copilot/billing'                                                               = @{
            Category = 'copilot'
            GET      = @{
                Status = 'read'
                Fields = @{
                    plan_type               = 'read for the plan type of the ruleset (state Ruleset.Copilot), not a setting'
                    seat_breakdown          = 'read by the Copilot seats area, not a setting'
                    seat_management_setting = 'read by the Copilot seats area, not a setting'
                }
            }
        }
        '/orgs/{org}/copilot/billing/seats'                                                         = @{
            Category = 'copilot'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/copilot/billing/selected_teams'                                                = @{
            Category = 'copilot'
            POST     = @{ Status = 'write' }
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never cancels a seat' }
        }
        '/orgs/{org}/copilot/billing/selected_users'                                                = @{
            Category = 'copilot'
            POST     = @{ Status = 'write' }
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never cancels a seat' }
        }
        '/orgs/{org}/copilot/code-review/runner'                                                    = @{
            Category = 'copilot'
            GET      = @{
                Status = 'read'
                Fields = @{
                    configured_by     = 'the page that last set the runner, not a setting'
                    runner_group_name = 'used only with labeled runners, which the engine does not use'
                    runner_labels     = 'used only with labeled runners, which the engine does not use'
                }
            }
            PUT      = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/copilot/code-review/settings'                                                  = @{
            Category = 'copilot'
            GET      = @{
                Status = 'read'
                Fields = @{
                    available_review_efforts = 'the efforts the plan offers, not a setting'
                }
            }
            PATCH    = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/copilot/coding-agent/permissions'                                              = @{
            Category = 'copilot'
            GET      = @{
                Status = 'read'
                Fields = @{
                    selected_repositories_url = 'a link or a count, not a setting'
                }
            }
            PUT      = @{ Status = 'write'; Body = @('enabled_repositories') }
        }
        '/orgs/{org}/copilot/coding-agent/permissions/repositories'                                 = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'the repository list of selected access, which the engine does not manage' }
            PUT      = @{ Status = 'unused'; Reason = 'the repository list of selected access, which the engine does not manage' }
        }
        '/orgs/{org}/copilot/coding-agent/permissions/repositories/{repository_id}'                 = @{
            Category = 'copilot'
            PUT      = @{ Status = 'unused'; Reason = 'the repository list of selected access, which the engine does not manage' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repository list of selected access, which the engine does not manage' }
        }
        '/orgs/{org}/copilot/content_exclusion'                                                     = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'rules per repository of the paths Copilot must not read, objects; the answer was {} (none) on 2026-11-10' }
            PUT      = @{ Status = 'unused'; Reason = 'writes rules of paths Copilot must not read, which the engine never does' }
        }
        '/orgs/{org}/copilot/metrics/reports/organization-1-day'                                    = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/copilot/metrics/reports/organization-28-day/latest'                            = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/copilot/metrics/reports/repos-1-day'                                           = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/copilot/metrics/reports/user-teams-1-day'                                      = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/copilot/metrics/reports/users-1-day'                                           = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/copilot/metrics/reports/users-28-day/latest'                                   = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/copilot/policies/code-review'                                                  = @{
            Category = 'copilot'
            GET      = @{
                Status = 'read'
                Fields = @{
                    editable        = 'whether the enterprise lets the organization change it, not a setting'
                    effective_state = 'the policy after enterprise policy; the row reads the configured one (spec 7)'
                    managed_by      = 'whether the enterprise or the organization controls it, not a setting'
                }
            }
            PUT      = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/dependabot/alerts'                                                             = @{
            Category = 'dependabot'
            GET      = @{ Status = 'unused'; Reason = 'alerts, not settings' }
        }
        '/orgs/{org}/dependabot/repository-access'                                                  = @{
            Category = 'dependabot'
            GET      = @{
                Status = 'read'
                Fields = @{
                    accessible_repositories = 'the repositories added one by one, not managed'
                }
            }
            PATCH    = @{ Status = 'unused'; Reason = 'adds or removes repositories one by one, not managed' }
        }
        '/orgs/{org}/dependabot/repository-access/default-level'                                    = @{
            Category = 'dependabot'
            PUT      = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/dependabot/secrets'                                                            = @{
            Category = 'dependabot'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
        }
        '/orgs/{org}/dependabot/secrets/public-key'                                                 = @{
            Category = 'dependabot'
            GET      = @{ Status = 'unused'; Reason = 'the key that encrypts a secret before it is written, which the engine never does' }
        }
        '/orgs/{org}/dependabot/secrets/{secret_name}'                                              = @{
            Category = 'dependabot'
            GET      = @{ Status = 'unused'; Reason = 'the names of the secrets, objects; the engine never reads or writes a secret value' }
            PUT      = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a secret, which the engine never does' }
        }
        '/orgs/{org}/dependabot/secrets/{secret_name}/repositories'                                 = @{
            Category = 'dependabot'
            GET      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id}'                 = @{
            Category = 'dependabot'
            PUT      = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
            DELETE   = @{ Status = 'unused'; Reason = 'the repositories that may use a secret, part of the secret' }
        }
        '/orgs/{org}/docker/conflicts'                                                              = @{
            Category = 'packages'
            GET      = @{ Status = 'unused'; Reason = 'a report of the Docker package migration, not a setting' }
        }
        '/orgs/{org}/events'                                                                        = @{
            Category = 'activity'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/failed_invitations'                                                            = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'invitations, objects; the inventory reads the pending ones, and managing members is outside this tool' }
        }
        '/orgs/{org}/hooks'                                                                         = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
            POST     = @{ Status = 'unused'; Reason = 'the engine never changes a webhook; the inventory reads the list' }
        }
        '/orgs/{org}/hooks/{hook_id}'                                                               = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'the list of webhooks answers what the inventory checks' }
            PATCH    = @{ Status = 'unused'; Reason = 'the engine never changes a webhook; the inventory reads the list' }
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never changes a webhook; the inventory reads the list' }
        }
        '/orgs/{org}/hooks/{hook_id}/config'                                                        = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'the list of webhooks answers what the inventory checks' }
            PATCH    = @{ Status = 'unused'; Reason = 'the engine never changes a webhook; the inventory reads the list' }
        }
        '/orgs/{org}/hooks/{hook_id}/deliveries'                                                    = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'the list of webhooks answers what the inventory checks' }
        }
        '/orgs/{org}/hooks/{hook_id}/deliveries/{delivery_id}'                                      = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'the list of webhooks answers what the inventory checks' }
        }
        '/orgs/{org}/hooks/{hook_id}/deliveries/{delivery_id}/attempts'                             = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'the engine never changes a webhook; the inventory reads the list' }
        }
        '/orgs/{org}/hooks/{hook_id}/pings'                                                         = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'the engine never changes a webhook; the inventory reads the list' }
        }
        '/orgs/{org}/insights/api/route-stats/{actor_type}/{actor_id}'                              = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/subject-stats'                                                    = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/summary-stats'                                                    = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/summary-stats/users/{user_id}'                                    = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/summary-stats/{actor_type}/{actor_id}'                            = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/time-stats'                                                       = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/time-stats/users/{user_id}'                                       = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/time-stats/{actor_type}/{actor_id}'                               = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/insights/api/user-stats/{user_id}'                                             = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/installation'                                                                  = @{
            Category = 'apps'
            GET      = @{ Status = 'unused'; Reason = 'for the token of a GitHub App only' }
        }
        '/orgs/{org}/installations'                                                                 = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/interaction-limits'                                                            = @{
            Category = 'interactions'
            GET      = @{
                Status = 'read'
                Fields = @{
                    expires_at = 'when the temporary limit ends, not a setting'
                    origin     = 'where the temporary limit was set, not a setting'
                }
            }
            PUT      = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
            DELETE   = @{ Status = 'unused'; Reason = 'removes the temporary limit; the engine checks it' }
        }
        '/orgs/{org}/interaction-limits/pulls/creation-cap'                                         = @{
            Category = 'interactions'
            GET      = @{
                Status = 'read'
                Fields = @{
                    include_drafts         = 'matters only while the cap is enabled, which the engine checks'
                    max_open_pull_requests = 'matters only while the cap is enabled, which the engine checks'
                }
            }
            PATCH    = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/invitations'                                                                   = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
            POST     = @{ Status = 'unused'; Reason = 'invitations, objects; the inventory reads the pending ones, and managing members is outside this tool' }
        }
        '/orgs/{org}/invitations/{invitation_id}'                                                   = @{
            Category = 'orgs'
            DELETE   = @{ Status = 'unused'; Reason = 'invitations, objects; the inventory reads the pending ones, and managing members is outside this tool' }
        }
        '/orgs/{org}/invitations/{invitation_id}/teams'                                             = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/issue-fields'                                                                  = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'issue fields, objects of the planning pages' }
            POST     = @{ Status = 'unused'; Reason = 'issue fields, objects of the planning pages' }
        }
        '/orgs/{org}/issue-fields/{issue_field_id}'                                                 = @{
            Category = 'orgs'
            PATCH    = @{ Status = 'unused'; Reason = 'issue fields, objects of the planning pages' }
            DELETE   = @{ Status = 'unused'; Reason = 'issue fields, objects of the planning pages' }
        }
        '/orgs/{org}/issue-types'                                                                   = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'issue types, objects of the planning pages' }
            POST     = @{ Status = 'unused'; Reason = 'issue types, objects of the planning pages' }
        }
        '/orgs/{org}/issue-types/{issue_type_id}'                                                   = @{
            Category = 'orgs'
            PUT      = @{ Status = 'unused'; Reason = 'issue types, objects of the planning pages' }
            DELETE   = @{ Status = 'unused'; Reason = 'issue types, objects of the planning pages' }
        }
        '/orgs/{org}/issues'                                                                        = @{
            Category = 'issues'
            GET      = @{ Status = 'unused'; Reason = 'issues of the user, not settings' }
        }
        '/orgs/{org}/members'                                                                       = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/members/{username}'                                                            = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'members, objects; the inventory reads the owners, and managing members is outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'members, objects; the inventory reads the owners, and managing members is outside this tool' }
        }
        '/orgs/{org}/members/{username}/codespaces'                                                 = @{
            Category = 'codespaces'
            GET      = @{ Status = 'unused'; Reason = 'codespaces of members, not settings' }
        }
        '/orgs/{org}/members/{username}/codespaces/{codespace_name}'                                = @{
            Category = 'codespaces'
            DELETE   = @{ Status = 'unused'; Reason = 'codespaces of members, not settings' }
        }
        '/orgs/{org}/members/{username}/codespaces/{codespace_name}/stop'                           = @{
            Category = 'codespaces'
            POST     = @{ Status = 'unused'; Reason = 'codespaces of members, not settings' }
        }
        '/orgs/{org}/members/{username}/copilot'                                                    = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'the seat list answers every seat' }
        }
        '/orgs/{org}/memberships/{username}'                                                        = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'members, objects; the inventory reads the owners, and managing members is outside this tool' }
            PUT      = @{ Status = 'unused'; Reason = 'members, objects; the inventory reads the owners, and managing members is outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'members, objects; the inventory reads the owners, and managing members is outside this tool' }
        }
        '/orgs/{org}/migrations'                                                                    = @{
            Category = 'migrations'
            GET      = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
            POST     = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
        }
        '/orgs/{org}/migrations/{migration_id}'                                                     = @{
            Category = 'migrations'
            GET      = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
        }
        '/orgs/{org}/migrations/{migration_id}/archive'                                             = @{
            Category = 'migrations'
            GET      = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
            DELETE   = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
        }
        '/orgs/{org}/migrations/{migration_id}/repos/{repo_name}/lock'                              = @{
            Category = 'migrations'
            DELETE   = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
        }
        '/orgs/{org}/migrations/{migration_id}/repositories'                                        = @{
            Category = 'migrations'
            GET      = @{ Status = 'unused'; Reason = 'one-off data export, not a setting' }
        }
        '/orgs/{org}/organization-roles'                                                            = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/organization-roles/teams/{team_slug}'                                          = @{
            Category = 'orgs'
            DELETE   = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
        }
        '/orgs/{org}/organization-roles/teams/{team_slug}/{role_id}'                                = @{
            Category = 'orgs'
            PUT      = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
        }
        '/orgs/{org}/organization-roles/users/{username}'                                           = @{
            Category = 'orgs'
            DELETE   = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
        }
        '/orgs/{org}/organization-roles/users/{username}/{role_id}'                                 = @{
            Category = 'orgs'
            PUT      = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
        }
        '/orgs/{org}/organization-roles/{role_id}'                                                  = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
        }
        '/orgs/{org}/organization-roles/{role_id}/teams'                                            = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/organization-roles/{role_id}/users'                                            = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'organization roles and their assignments, managed with teams and members, outside this tool' }
        }
        '/orgs/{org}/outside_collaborators'                                                         = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/outside_collaborators/{username}'                                              = @{
            Category = 'orgs'
            PUT      = @{ Status = 'unused'; Reason = 'changes an outside collaborator, which the inventory only reads (outside this tool)' }
            DELETE   = @{ Status = 'unused'; Reason = 'changes an outside collaborator, which the inventory only reads (outside this tool)' }
        }
        '/orgs/{org}/packages'                                                                      = @{
            Category = 'packages'
            GET      = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
        }
        '/orgs/{org}/packages/{package_type}/{package_name}'                                        = @{
            Category = 'packages'
            GET      = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
            DELETE   = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
        }
        '/orgs/{org}/packages/{package_type}/{package_name}/restore'                                = @{
            Category = 'packages'
            POST     = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
        }
        '/orgs/{org}/packages/{package_type}/{package_name}/versions'                               = @{
            Category = 'packages'
            GET      = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
        }
        '/orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}'          = @{
            Category = 'packages'
            GET      = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
            DELETE   = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
        }
        '/orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}/restore'  = @{
            Category = 'packages'
            POST     = @{ Status = 'unused'; Reason = 'packages and their versions, objects; the package policies are rows of packages' }
        }
        '/orgs/{org}/personal-access-token-requests'                                                = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
            POST     = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
        }
        '/orgs/{org}/personal-access-token-requests/{pat_request_id}'                               = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
        }
        '/orgs/{org}/personal-access-token-requests/{pat_request_id}/repositories'                  = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
        }
        '/orgs/{org}/personal-access-tokens'                                                        = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
            POST     = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
        }
        '/orgs/{org}/personal-access-tokens/{pat_id}'                                               = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
        }
        '/orgs/{org}/personal-access-tokens/{pat_id}/repositories'                                  = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'tokens and requests of members, not settings' }
        }
        '/orgs/{org}/private-registries'                                                            = @{
            Category = 'private-registries'
            GET      = @{ Status = 'unused'; Reason = 'private registries, objects with credentials; the engine never reads or writes a credential' }
            POST     = @{ Status = 'unused'; Reason = 'writes a private registry and its credential, which the engine never does' }
        }
        '/orgs/{org}/private-registries/public-key'                                                 = @{
            Category = 'private-registries'
            GET      = @{ Status = 'unused'; Reason = 'the key that encrypts a registry credential before it is written, which the engine never does' }
        }
        '/orgs/{org}/private-registries/{secret_name}'                                              = @{
            Category = 'private-registries'
            GET      = @{ Status = 'unused'; Reason = 'private registries, objects with credentials; the engine never reads or writes a credential' }
            PATCH    = @{ Status = 'unused'; Reason = 'writes a private registry and its credential, which the engine never does' }
            DELETE   = @{ Status = 'unused'; Reason = 'writes a private registry and its credential, which the engine never does' }
        }
        '/orgs/{org}/projectsV2'                                                                    = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}'                                                   = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/drafts'                                            = @{
            Category = 'projects'
            POST     = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/fields'                                            = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
            POST     = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/fields/{field_id}'                                 = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/items'                                             = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
            POST     = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/items/{item_id}'                                   = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
            PATCH    = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
            DELETE   = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/views'                                             = @{
            Category = 'projects'
            POST     = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/projectsV2/{project_number}/views/{view_number}/items'                         = @{
            Category = 'projects'
            GET      = @{ Status = 'unused'; Reason = 'projects and their items, objects; the projects policies are rows' }
        }
        '/orgs/{org}/properties/installations'                                                      = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
            POST     = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/properties/installations/schema'                                               = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/properties/installations/values'                                               = @{
            Category = 'orgs'
            PATCH    = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/properties/installations/values/{property_name}'                               = @{
            Category = 'orgs'
            PATCH    = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
            DELETE   = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/properties/schema'                                                             = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
            PATCH    = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/properties/schema/{custom_property_name}'                                      = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
            PUT      = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
            DELETE   = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/properties/values'                                                             = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
            PATCH    = @{ Status = 'unused'; Reason = 'custom properties are objects, none defined (outside this tool)' }
        }
        '/orgs/{org}/public_members'                                                                = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'whether membership is public is each member''s choice, not a setting' }
        }
        '/orgs/{org}/public_members/{username}'                                                     = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'whether membership is public is each member''s choice, not a setting' }
            PUT      = @{ Status = 'unused'; Reason = 'whether membership is public is each member''s choice, not a setting' }
            DELETE   = @{ Status = 'unused'; Reason = 'whether membership is public is each member''s choice, not a setting' }
        }
        '/orgs/{org}/repos'                                                                         = @{
            Category = 'repos'
            GET      = @{ Status = 'read' }
            POST     = @{ Status = 'unused'; Reason = 'the engine never creates a repository (outside this tool)' }
        }
        '/orgs/{org}/rulesets'                                                                      = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
            POST     = @{ Status = 'write' }
        }
        '/orgs/{org}/rulesets/rule-suites'                                                          = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/rulesets/rule-suites/{rule_suite_id}'                                          = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'reports, not settings' }
        }
        '/orgs/{org}/rulesets/{ruleset_id}'                                                         = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
            PUT      = @{ Status = 'write'; Body = @('name', 'target', 'enforcement', 'bypass_actors', 'conditions', 'rules') }
            DELETE   = @{ Status = 'unused'; Reason = 'the engine never deletes a ruleset' }
        }
        '/orgs/{org}/rulesets/{ruleset_id}/history'                                                 = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'versions of the ruleset, not settings' }
        }
        '/orgs/{org}/rulesets/{ruleset_id}/history/{version_id}'                                    = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'versions of the ruleset, not settings' }
        }
        '/orgs/{org}/secret-scanning/alerts'                                                        = @{
            Category = 'secret-scanning'
            GET      = @{ Status = 'unused'; Reason = 'alerts, not settings' }
        }
        '/orgs/{org}/secret-scanning/custom-patterns'                                               = @{
            Category = 'secret-scanning'
            GET      = @{ Status = 'unused'; Reason = 'custom secret patterns, objects, none defined' }
            POST     = @{ Status = 'unused'; Reason = 'custom secret patterns, objects, none defined' }
            DELETE   = @{ Status = 'unused'; Reason = 'custom secret patterns, objects, none defined' }
        }
        '/orgs/{org}/secret-scanning/custom-patterns/{pattern_id}'                                  = @{
            Category = 'secret-scanning'
            PATCH    = @{ Status = 'unused'; Reason = 'custom secret patterns, objects, none defined' }
        }
        '/orgs/{org}/secret-scanning/pattern-configurations'                                        = @{
            Category = 'secret-scanning'
            GET      = @{ Status = 'unused'; Reason = 'the push protection of each secret pattern, a choice per pattern: on 2026-11-10 all 604 provider patterns answered not-set (GitHub''s default) and none was custom' }
            PATCH    = @{ Status = 'unused'; Reason = 'overrides the push protection of single patterns, which the engine leaves at GitHub''s defaults' }
        }
        '/orgs/{org}/security-advisories'                                                           = @{
            Category = 'security-advisories'
            GET      = @{ Status = 'unused'; Reason = 'advisories of repositories, not settings' }
        }
        '/orgs/{org}/security-managers'                                                             = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'teams with the security manager role, which reads every repository; teams and their roles are managed outside this tool' }
        }
        '/orgs/{org}/security-managers/teams/{team_slug}'                                           = @{
            Category = 'orgs'
            PUT      = @{ Status = 'unused'; Reason = 'teams with the security manager role, which reads every repository; teams and their roles are managed outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'teams with the security manager role, which reads every repository; teams and their roles are managed outside this tool' }
        }
        '/orgs/{org}/settings/immutable-releases'                                                   = @{
            Category = 'orgs'
            GET      = @{
                Status = 'read'
                Fields = @{
                    selected_repositories_url = 'a link or a count, not a setting'
                }
            }
            PUT      = @{ Status = 'unused'; Reason = 'writable; the engine checks it and applies it in a later issue (step 3)' }
        }
        '/orgs/{org}/settings/immutable-releases/repositories'                                      = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'used only while enforced_repositories is selected' }
            PUT      = @{ Status = 'unused'; Reason = 'used only while enforced_repositories is selected' }
        }
        '/orgs/{org}/settings/immutable-releases/repositories/{repository_id}'                      = @{
            Category = 'orgs'
            PUT      = @{ Status = 'unused'; Reason = 'used only while enforced_repositories is selected' }
            DELETE   = @{ Status = 'unused'; Reason = 'used only while enforced_repositories is selected' }
        }
        '/orgs/{org}/settings/network-configurations'                                               = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'private networking of hosted runners, which are not used' }
            POST     = @{ Status = 'unused'; Reason = 'private networking of hosted runners, which are not used' }
        }
        '/orgs/{org}/settings/network-configurations/{network_configuration_id}'                    = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'private networking of hosted runners, which are not used' }
            PATCH    = @{ Status = 'unused'; Reason = 'private networking of hosted runners, which are not used' }
            DELETE   = @{ Status = 'unused'; Reason = 'private networking of hosted runners, which are not used' }
        }
        '/orgs/{org}/settings/network-settings/{network_settings_id}'                               = @{
            Category = 'orgs'
            GET      = @{ Status = 'unused'; Reason = 'private networking of hosted runners, which are not used' }
        }
        '/orgs/{org}/teams'                                                                         = @{
            Category = 'teams'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
            POST     = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/teams/{team_slug}'                                                             = @{
            Category = 'teams'
            GET      = @{ Status = 'read' }
            PATCH    = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/teams/{team_slug}/copilot/customizations'                                      = @{
            Category = 'copilot'
            GET      = @{ Status = 'unused'; Reason = 'Copilot customizations of a team, objects (outside this tool)' }
            PUT      = @{ Status = 'unused'; Reason = 'Copilot customizations of a team, objects (outside this tool)' }
            DELETE   = @{ Status = 'unused'; Reason = 'Copilot customizations of a team, objects (outside this tool)' }
        }
        '/orgs/{org}/teams/{team_slug}/invitations'                                                 = @{
            Category = 'teams'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/teams/{team_slug}/members'                                                     = @{
            Category = 'teams'
            GET      = @{ Status = 'read' }
        }
        '/orgs/{org}/teams/{team_slug}/memberships/{username}'                                      = @{
            Category = 'teams'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
            PUT      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/teams/{team_slug}/repos'                                                       = @{
            Category = 'teams'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}'                                        = @{
            Category = 'teams'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
            PUT      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
            DELETE   = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/teams/{team_slug}/teams'                                                       = @{
            Category = 'teams'
            GET      = @{ Status = 'unused'; Reason = 'teams and their members and repositories, managed outside this tool' }
        }
        '/orgs/{org}/{security_product}/{enablement}'                                               = @{
            Category = 'orgs'
            POST     = @{ Status = 'unused'; Reason = 'turns a feature on or off on every repository at once; the code security configuration does it' }
        }
        '/repos/{owner}/{repo}'                                                                     = @{
            Category = 'repos'
            GET      = @{ Status = 'read' }
        }
        '/repos/{owner}/{repo}/actions/permissions/access'                                          = @{
            Category = 'actions'
            GET      = @{ Status = 'read' }
        }
        '/repos/{owner}/{repo}/code-security-configuration'                                         = @{
            Category = 'code-security'
            GET      = @{ Status = 'read' }
        }
        '/repos/{owner}/{repo}/contents/{path}'                                                     = @{
            Category = 'repos'
            GET      = @{ Status = 'read' }
        }
        '/repos/{owner}/{repo}/invitations'                                                         = @{
            Category = 'collaborators'
            GET      = @{ Status = 'read' }
        }
        '/user/memberships/orgs/{org}'                                                              = @{
            Category = 'orgs'
            GET      = @{ Status = 'read' }
        }
    }
}
