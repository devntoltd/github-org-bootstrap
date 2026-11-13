# github-org-bootstrap — Design

Date: 2026-11-13
Status: implemented

The founding decision of this repository: what the tool is, the rules it keeps, and how organizations use it. The
tool was developed in a private repository before v1.0.0; this record states the decisions that hold at v1.0.0, not
their history.

## What it is

A PowerShell tool that keeps the settings of one GitHub organization in line with one config file. Every run reads
the organization, plans the difference from the config, prints the plan and the warnings, asks once, and applies only
what the config says. It manages organization settings and policies only: member privileges, repository creation
policies, authentication and code security settings, GitHub Actions policies, one organization ruleset on the default
branch, budgets, Copilot settings and seats; and it reports an inventory (owners, GitHub Apps, webhooks, outside
collaborators, invitations) without changing it.

**Never in scope:** creating, deleting or archiving repositories; teams and their members; repository collaborators;
general-purpose resource management. A setting that controls whether members may create repositories is in scope;
creating repositories is not.

## Rules the tool keeps

- **No deletes.** It never deletes or cancels anything; what it does not manage is a warning.
- **Plan, then one question.** Reads in `src/State*.ps1`, writes in `src/Apply.ps1`, everything between them pure.
  `-WhatIf` stops after the plan; `-ValidateOnly` stops after the config and calls nothing.
- **Strict config.** Every key is required and an unknown key is an error, so a typo cannot turn a setting off and the
  config shows the full desired state. One shape per setting row drives validation, recommendations and the JSON Schema.
- **Recommendations with reasons.** Every setting has a recommended value with its reason, or says why it has none
  (project data, or a decision of the owner). A value that differs is a warning on every run unless a dated exception
  with a reason and an expiry of at most one year covers it.
- **Traceability.** Every setting of the organization's settings pages is a config row or a reasoned unmanaged entry,
  with its UI location and its API read and write (`engine/api-endpoints.psd1`, `engine/settings.md`). Settings without
  an API are listed for a person to check; GitHub fields the tool does not know are warnings.
- **Pinned API version.** Every REST call goes through `Invoke-GhApi` with the pinned `X-GitHub-Api-Version`; a newer
  version is adopted only after its breaking changes and the endpoint catalog are reviewed.
- **Owner rights only for a run.** The gh token needs `admin:org` and `admin:org_hook`; every run prints the command
  that removes them, and nothing stores a credential.

## How organizations use it

- **The config lives with the organization**, in a repository of its own; the engine holds only an example.
- **Pinned versions.** A config repository pins a release by tag and full commit (`engine.psd1`); `run.ps1` checks
  out exactly that commit and stops when the tag does not point at it. Nothing follows a branch.
- **Config format versions.** `configVersion` (`major.minor`) names the format. An engine reads its own major up to its
  own minor and stops before any GitHub call otherwise. A major changes when a config needs an edit; the changelog says
  which. An upgrade is one pull request in the config repository with the `-WhatIf` plan of the new version: a plan that
  changes anything is a change to the organization and is reviewed as one. Automatic migration of configs is not
  provided.

## Considered and rejected

- **Optional keys with recommended defaults**: an upgrade would change organizations without a config change.
- **Distribution through the PowerShell Gallery**: a publishing key could release a version that runs with owner
  rights, and the package is not the code a reviewer reads; a pinned git commit is.
- **Running apply in CI with a stored owner credential**: runs stay local, with scopes granted for one run.
