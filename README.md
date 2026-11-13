# github-org-bootstrap

Settings of a GitHub organization as a reviewable config: a PowerShell tool reads the organization, plans the
difference from your config, asks once, and applies only what the config says. Published by
[Devnto](https://github.com/devntoltd) under the [Apache License 2.0](LICENSE).

## What it manages

- Organization settings and member privileges: base permissions, who may create repositories, pages and teams,
  forking, visibility changes, two-factor requirements.
- GitHub Actions policies: allowed actions and SHA pinning, workflow permissions, self-hosted runners, fork pull
  requests, retention and cache.
- Code security: one code security configuration, default for new repositories and attached to those without one.
- One organization ruleset on the default branch of every repository, with required reviewers and required workflows.
- Budgets of the paid products, Copilot settings and seats.
- An inventory it compares and never changes: owners, GitHub Apps, webhooks, outside collaborators, invitations.
- Every setting of the organization's settings pages, traced to its UI location and API: settings GitHub has no API
  for are listed for a person to check (`-ManualChecklist`, `-PageWalk`).

The full reference of every setting is [engine/settings.md](engine/settings.md); the config fields are in
[engine/README.md](engine/README.md#config).

## What it never does

- Create, delete or archive repositories; create teams or change their members; manage repository collaborators.
  Those are objects, not organization settings: manage them with another tool.
- Delete or cancel anything, even what differs from the config: what it does not manage is reported as a warning.
- Change anything without showing the plan first.

## How it stays safe

- **Plan, then one question.** Every run reads the organization, prints the plan and the warnings, and asks once
  before it changes anything; `-WhatIf` stops after the plan.
- **Strict config.** Every key of the config is required and an unknown key is an error, so a typo cannot turn a
  setting off. A value that differs from the recommended one is a warning on every run, unless the config records a
  dated exception with a reason.
- **Owner rights only for one run.** The run needs an organization owner's gh token with the `admin:org` and
  `admin:org_hook` scopes; it prints the command that removes them after the run.
- **No secret stored.** The config holds settings, never credentials.

## Requirements

- PowerShell 7.6 or later (`pwsh`).
- [GitHub CLI](https://cli.github.com/) 2.48.0 or later, signed in as an owner of the organization:
  `gh auth login`, then `gh auth refresh -h github.com -s admin:org,admin:org_hook` before a run.
- No PowerShell module besides what the repository holds.

## Quick start

1. Clone this repository and work from its root.
2. Copy [engine/examples/github.json](engine/examples/github.json) to `./github.json` and edit it for your
   organization: `organization`, the inventory, every setting. Set its `$schema` to `./engine/github.schema.json`
   (the path from the copy to the schema); VS Code then completes the fields and shows the recommended value with its
   reason.
3. Check it offline: `./engine/bootstrap.ps1 -ConfigPath ./github.json -ValidateOnly`.
4. Do the [manual setup](engine/README.md#manual-setup) once: the `ruleset` section is required, and a run stops
   until the `.github` repository with the central workflow and the reviewer team the config names exist.
5. See the plan: `./engine/bootstrap.ps1 -ConfigPath ./github.json -WhatIf`.
6. Apply: `./engine/bootstrap.ps1 -ConfigPath ./github.json`, answer the question, then remove the scopes with the
   command the run prints.

## Keeping your config in your own repository

Keep `github.json` in a private repository of your organization and run a pinned version of this engine against it:

1. Copy [engine/examples/run.ps1](engine/examples/run.ps1) and [engine/examples/engine.psd1](engine/examples/engine.psd1)
   next to `github.json`, and add `.engine/` to its `.gitignore`. Set `$schema` in `github.json` to
   `./.engine/engine/github.schema.json`, the schema of the pinned engine once `run.ps1` has checked it out.
2. Set `Tag` and `Commit` in `engine.psd1` to a release of this repository. `run.ps1` checks out exactly that commit
   into `.engine/`, stops when the tag does not point at it, and never follows a branch.
3. Run `./run.ps1 -WhatIf`, then `./run.ps1`. A CI job of that repository can run `./run.ps1 -ValidateOnly`, which needs
   git and access to github.com, but no gh and no credentials.
4. If your ruleset requires a central workflow, keep its reference copy (such as
   [engine/examples/org-checks.yml](engine/examples/org-checks.yml)) next to `github.json` under the same file name;
   every run compares the workflow at the configured commit with it.

## Upgrading

`configVersion` in the config names its format (`major.minor`). An engine reads its own major version up to its own
minor and stops before any GitHub call otherwise. The [changelog](CHANGELOG.md) lists every format change with the
edit it needs. Upgrade in one pull request of your config repository: raise `Tag` and `Commit`, edit `github.json` as
the changelog says, run `./run.ps1 -WhatIf` and put the plan in the pull request. A plan that changes anything is a
change to your organization and is reviewed as one.

## Contributing and security

[CONTRIBUTING.md](CONTRIBUTING.md) describes the checks and the rules for changes; [SECURITY.md](SECURITY.md) how to
report a vulnerability. The [decisions](docs/decisions/README.md) record why the tool works as it does. This project
follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

The tool was developed in a private repository before v1.0.0; this repository starts from that version.
