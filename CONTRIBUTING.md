# Contributing

How to change this repository. How to use the engine is in the [README](README.md) and the [engine reference](engine/README.md).

## Setup

On a new machine or clone, and again after a version below changes:

```powershell
./tools/Install-DevTools.ps1 -WhatIf   # what is missing
./tools/Install-DevTools.ps1           # installs it; open a new terminal afterwards (winget updates PATH for new sessions)
```

It skips what is already in place and installs:

- the command-line tools of the checks (`Tools` of `dev-tools.psd1`: actionlint, shellcheck, zizmor, Betterleaks, lychee, editorconfig-checker) at the exact versions CI uses, through winget; without winget (not Windows) it names what to install;
- the `Modules` of `dev-tools.psd1` (Pester, PSScriptAnalyzer), at exactly those versions with `Install-PSResource -SkipDependencyCheck` (signature checked on Windows), after checking that every dependency the Gallery lists for them is locked. `-ModulesOnly` installs only these, as CI does;
- `git config --local core.hooksPath .githooks`: the pre-commit hook scans the staged changes for secrets. Without Betterleaks the hook stops every commit with a hint to this section;
- `git config --local blame.ignoreRevsFile .git-blame-ignore-revs`: `git blame` skips the commits that only reformat code (GitHub reads the file by itself).

Markdown lint needs Node.js, which the script does not install.

VS Code offers the recommended extensions (`.vscode/extensions.json`) when the folder is opened: PowerShell, Pester Tests (run or debug a single `Describe`/`It` from the editor), Coverage Gutters (see [Code coverage](#code-coverage)) and others.

Claude Code offers the plugins of `.claude/settings.json` when the folder is trusted: the [superpowers](https://github.com/obra/superpowers) skills (brainstorming, plans, test-driven development, verification before completion). Personal settings go into `.claude/settings.local.json`, which git ignores.

## Checks

Run from the repository root; CI (`.github/workflows/ci.yml`, Ubuntu) runs the same checks on every pull request and on pushes to `main`; a new push to a pull request cancels the run still going for the previous one, and a run stops after 15 minutes.

```powershell
./build.ps1 all          # every check below in a row, then a summary; exits non-zero when one failed
./build.ps1 <name>       # one check or developer script, e.g. ./build.ps1 lint, ./build.ps1 tests -Target 90
./build.ps1              # menu of the checks and the scripts in tools/
```

The checks and the scripts are listed in `build.psd1`; they run from the repository root wherever `build.ps1` is started, so a relative path among the parameters is relative to the root; a check whose tool is missing is skipped with what to install, and zizmor takes `GH_TOKEN` from `gh auth token` when it is not set. A new check is a row in `build.psd1` and a step in `ci.yml` with the same name in `CiStep` (a test fails until both are there, and until its command is in `dev-tools.psd1` or the row names its own `Install`); a new script in `tools/` is a row in `Tools`. `reminders`, `api-version` and `dependencies` run with `-WhatIf` only: they write to GitHub without asking, and the real run is `recurring.yml`'s. `./tools/Invoke-Coverage.ps1` and `./tools/Invoke-Lint.ps1` load exactly the Pester and PSScriptAnalyzer of `dev-tools.psd1` (`tools/DevModule.ps1`) and stop in a session that has another version loaded; a plain `Invoke-Pester` loads the newest installed Pester, so prefer `./build.ps1 tests`. What each check runs, by hand:

```powershell
Invoke-Pester -Path . -Output Detailed                                  # all tests
Invoke-Pester -Path ./engine/tests/Plan.Tests.ps1 -Output Detailed   # one file
./tools/Invoke-Lint.ps1                                                  # lint: PSScriptAnalyzer, every rule; must print nothing
editorconfig-checker                                                    # editorconfig: every file against .editorconfig; must print nothing
npx markdownlint-cli2@0.23.3                                            # markdownlint: must report 0 errors (config: .markdownlint-cli2.jsonc)
lychee --offline --include-fragments '--exclude-path=decisions.\d{4}-' './**/*.md'  # links: links and anchors between the docs; must report 0 errors
shellcheck .githooks/pre-commit                                         # shellcheck: the hook script; must print nothing
actionlint                                                              # actionlint: workflow correctness, shellcheck on run: scripts; must print nothing
$env:GH_TOKEN = gh auth token; zizmor --persona=pedantic .              # zizmor: workflow security (online audits, as CI); must report no findings
betterleaks git --redact --verbose .                                    # secrets: secrets in the full git history; must find no leaks
```

`./tools/Invoke-Lint.ps1` runs every analyzer rule but the excluded ones, one rule per call: in a single call the analyzer runs the rules in parallel, and the rules that look up commands then fail at random and lose their findings ([PSScriptAnalyzer#1867](https://github.com/PowerShell/PSScriptAnalyzer/issues/1867)). `PSScriptAnalyzerSettings.psd1` lists no `IncludeRules`, which would turn the default rules off; VS Code reads it too. Its comments say which rules are off and why. The settings include the formatting rules of the `CodeFormattingStroustrup` preset; `Invoke-Formatter -ScriptDefinition (Get-Content -Raw <file>) -Settings ./PSScriptAnalyzerSettings.psd1` fixes what they report, and so does **Format Document** in VS Code. The formatter can leave a space at the end of a line where it breaks one: trim it, editorconfig-checker reports it. A commit that only reformats code gets its full SHA in `.git-blame-ignore-revs`, in the same pull request; pull requests are merged with merge commits, so the SHA stays valid.

editorconfig-checker checks what `.editorconfig` sets for every tracked file: charset, line endings, final newline, trailing whitespace, spaces and indent size. Markdown and PowerShell files set `indent_size = unset`: Markdown lists and wrapped lines are not multiples of 4, and the analyzer checks the indentation of the PowerShell code, whose help text and here-strings hold other indentation. That `.ps1`/`.psm1`/`.psd1` files are ASCII-only is a test (`tools/tests/RepositoryFiles.Tests.ps1`), since `charset = utf-8` allows any character.

The tests never call GitHub, so CI needs no credentials; only zizmor's online audits use the job's read-only `GITHUB_TOKEN`. CI runs on Ubuntu, so paths are case-sensitive there.

The workflows follow the rules the engine recommends for every organization: actions pinned by full commit SHA, and every `actions/checkout` sets `persist-credentials: false`. A tool without an action (actionlint, shellcheck, Betterleaks, editorconfig-checker) is downloaded in the workflow, pinned by version and SHA-256; Dependabot updates only the actions, so those versions are raised by hand in `ci.yml` and `dev-tools.psd1` together (a test fails while they differ). Dependabot never updates `engine/examples/org-checks.yml`, the example of a central workflow, so a pull request that raises an action or tool in `ci.yml` fails a test until it raises the same one there.

A secret found by the hook or by CI is revoked and rotated first, even if the commit was never pushed: removing it from the history does not make it safe again. A false positive gets a `betterleaks:allow` comment on its line, or its fingerprint in `.betterleaksignore`.

### Code coverage

```powershell
./tools/Invoke-Coverage.ps1                    # all tests with coverage; prints coverage per file and the missed lines
./tools/Invoke-Coverage.ps1 -Output Detailed   # the same with the full Pester output, as CI runs it
Get-Help ./tools/Invoke-Coverage.ps1 -Detailed # parameters
```

The script measures the module code of `shared/` and of the engine (`engine/*.psm1`, `engine/src/*.ps1`; not the tests, not `bootstrap.ps1` and not the scripts in `tools/`) and writes `coverage.xml` (JaCoCo, git-ignored) in the repository root. It fails when a test fails or the total coverage is below the target (`-Target`, 95% by default). CI runs it instead of a plain `Invoke-Pester` and adds the per-file table to the job summary of the run.

The target is a floor, not the goal: lines that stay uncovered are usually defensive `throw`s for cases that cannot happen. A drop in a file you changed is the signal to look at, not the total.

To see covered and missed lines in the editor: run the script, then **Coverage Gutters: Display Coverage** from the command palette (green and red marks next to the lines). With **Coverage Gutters: Watch** (or **Watch** in the status bar) instead, the marks refresh by themselves after every run.

### In VS Code

`.vscode/tasks.json` has every check and developer script as a task, each running `./build.ps1 <name>`: **Terminal → Run Task…** lists *All checks*, *Tests with coverage*, the single checks (*Lint*, *EditorConfig*, *Markdown lint*, *Markdown links*, *shellcheck*, *actionlint*, *zizmor*, *Secret scan*, *Module imports*) and the scripts (*Build config schemas*, *Build settings reference*, *API endpoint catalog*, *Install dev tools*, *Recurring reminders*, *GitHub API version*, *Dependency updates*, *Dependency update issue*); a test keeps the tasks and `build.psd1` in line. *All checks* is the default build task, so **Ctrl+Shift+B** runs it; *Tests with coverage* is the default test task (**Tasks: Run Test Task**, no default key). Together with Coverage Gutters in watch mode, one run updates the coverage marks in the open files.

Other keys: **F5** runs the open file under the debugger (a `*.Tests.ps1` file runs through Pester, without coverage), **F8** runs the selection; the Pester Tests extension puts the tests into the Testing view, where **Ctrl+; A** runs all tests, **Ctrl+; F** the current file, **Ctrl+; C** the test at the cursor and **Ctrl+; L** the last run again.

## How changes are made

- **A change to how the engine works** (a new area, a change of the pipeline, of the config format or of a contract) is recorded as a decision first: a dated file in `docs/decisions/`. Smaller changes need no documents.
- **A decision records** its date and reasoning; it is not updated after implementation. A later change gets its own dated file that links to the one it builds on. `Status:` is `approved` until the implementation is complete, then `implemented` in the same pull request. READMEs link to decisions for the reasoning, not for current details.
- **The [index of the decisions](docs/decisions/README.md)** has a row per decision: a new decision adds its row in the same pull request; one that replaces or changes a decision fills the last column of that decision's row; a change of `Status:` changes the row's status. A test checks every decision against its row.
- **Branches and pull requests:** work on a branch and merge through a pull request; nothing is committed to `main` directly.
- **Releases:** one pull request moves the `[Unreleased]` entries of [CHANGELOG.md](CHANGELOG.md) under the new version and raises `ModuleVersion` of `engine/GitHubOrg.psd1` to it (a test keeps the two equal); after the merge, a tag `vX.Y.Z` on `main` and a GitHub release with that section. A change of the config format raises `configVersion` (major for a change a config must follow, minor for one every config stays valid under), and its changelog entry says what a config must change.
- **Backlog:** [GitHub Issues](https://github.com/devntoltd/github-org-bootstrap/issues), label `enhancement` for improvements.
- **Language:** everything committed is in English: code, messages, docs, decisions, commit messages.

## Raising a locked version

The versions of `dev-tools.psd1` (modules and command-line tools of the checks) are exact; `modules.lock.psd1` (runtime modules of the engine) is empty. Every Monday `recurring.yml` looks for newer ones published at least 7 days ago (`tools/Find-DependencyUpdate.ps1`), runs every test on the new module versions in a job that can write nothing, and opens or updates one issue (`tools/Invoke-DependencyUpdateCheck.ps1`, template `.github/ISSUE_TEMPLATE/dependency-update.md`, label `dependency-update`). `./build.ps1 updates` shows the same locally.

To raise a version, in one pull request:

1. Change the version in `dev-tools.psd1`. A module that needs another one needs it locked in the same file: `./tools/Install-DevTools.ps1` checks this against the Gallery, in CI too. A command-line tool also changes `VERSION` and `SHA256` of its step in `ci.yml`.
2. Run `./tools/Install-DevTools.ps1`, then `./build.ps1 all`.

## Recurring operations

The weekly `recurring.yml` (reminders, the REST API version and endpoint checks, dependency updates) is a scheduled workflow, which GitHub disables in a public repository after 60 days without activity. A run of the workflow by hand (*Actions → Recurring operations → Run workflow*) or any commit to `main` keeps it going; a maintainer checks the *Actions* tab when the repository has been quiet for a while.

An operation a maintainer repeats by hand, such as the review of the settings pages, is added in one
pull request:

1. An issue template `.github/ISSUE_TEMPLATE/recurring-<operation>.md`:
   - `name: "Recurring: <Name>"` and a one-line `about` (the "New issue" chooser shows both);
   - `title: "[Recurring] <action>"`: a short imperative in sentence case that names the system where needed
     ("Rerun the GitHub secret risk assessment"); the script appends `(due <date>)`;
   - `labels: [recurring, "recurring:<operation>"]` and `assignees`;
   - a body with why (a link to the source), the steps as a checklist and the closing rule, each paragraph and list item on one line: GitHub shows every line break of an issue body; links are absolute, since relative links do not resolve in an issue.

   The front matter takes only `key: value` and `key: [a, b]` lines.
2. Its interval in days in `.github/recurring-operations.psd1`.
3. `Invoke-Pester -Path ./tools/tests` checks that templates and intervals match;
   `./tools/Invoke-RecurringReminder.ps1 -WhatIf` lists the new operation.

The label `recurring:<operation>` holds the history: renaming the file starts a new history unless the old issues get
the new label. A template without the label `recurring` (a bug or enhancement form) is not an operation.

## Code rules

- Code is organization-agnostic: no organization or project names in `.ps1`/`.psm1` files, test data included. Organization data belongs only in a config (`engine/examples/github.json` is the example).
- `.ps1`/`.psm1`/`.psd1` files are ASCII-only (a test checks it).
- The engine never deletes or cancels anything and ignores objects that are not in the config. What it does not manage is reported as a warning.
- The engine keeps GitHub reads in `src/State*.ps1`, writes in `src/Apply.ps1`, and `src/Config*.ps1` / `src/Plan*.ps1` free of such calls; a step file that holds several areas is [split by area](docs/architecture.md#where-each-step-lives) into `src/<Step>.<Area>.ps1`.
- `PSAvoidUsingWriteHost` (interactive scripts) and `PSMissingModuleManifestField` (it takes the empty `modules.lock.psd1` for a manifest; `engine/tests/Manifest.Tests.ps1` checks the real one) are the only excluded analyzer rules. Avoid 3+ positional arguments and `New-`/`Set-`/`Update-` verbs on helpers without `ShouldProcess`: the analyzer flags them.
- New behavior comes with a test that fails first.
- A test checks a behavior at the level that owns it. What a shared helper does (output format, response shapes, retries) is tested in `shared/tests`; an engine test checks only that the engine uses it, e.g. one progress step per action. Apply tests take their actions from `Get-GitHubOrgPlan`, not from hand-built objects. Assert results, not an ordered list of calls or texts, unless the order or the text is the behavior. Before adding a test, look for one that covers the behavior already, and extend or replace it.
- The full text of a warning or of the `Summary` of an action is checked by one test, the one about that message; every other test that meets it checks only the parts it is about with `-BeLike` (the name, the value, the reason), so a change of wording breaks one test. Tests find an action in a plan with `Get-PlanAction`, or its position with `Get-PlanIndex` (`shared/tests/PlanIndex.ps1`).
- The wording of a config validation error that `Test-ConfigShape` or `Test-ExceptionList` builds, and the rule of a shared pattern (`Get-ConfigPatternNode`), are checked in `shared/tests`. An engine test checks such an error with `Assert-ConfigError` (`shared/tests/ConfigError.ps1`) on its path and on the parts the engine owns: the value, the allowed values, a rule the engine defines itself; `-Only` when it must be the only error. An error the engine builds itself is its own text.
- Every GitHub REST call goes through `Invoke-GhApi` (`shared/src/GitHub.ps1`), which asks for the API version in `$script:GitHubApiVersion` (`2026-03-10`, in `shared/Bootstrap.Common.psm1`) with the `X-GitHub-Api-Version` header; without it GitHub picks its own default, and response shapes could change without notice. As with the locked module versions in `modules.lock.psd1`, raise it only after reviewing the [breaking changes](https://docs.github.com/en/rest/about-the-rest-api/breaking-changes) of the new version for the endpoints the engine calls and verifying their response shapes. The raise is also a review of the endpoint catalog `engine/api-endpoints.psd1` against the new version, in the same pull request (a test fails while its `ApiVersion` differs): `./tools/Invoke-ApiEndpointCheck.ps1 -Version <new> -Report` prints, opening nothing, the new, removed and changed operations, the `Body` differences of every `write` operation and the response fields of every `read` GET that neither a row nor `Fields` lists; the pull request resolves every line, then sets `ApiVersion` and `ReviewedOn`, and a maintainer's `./engine/bootstrap.ps1 -ConfigPath <config> -WhatIf` on the new version shows what the real answers carry. Every week `recurring.yml` compares the catalog with the description of the pinned version and opens one issue per operation that differs (`tools/Invoke-ApiEndpointCheck.ps1`, template `.github/ISSUE_TEMPLATE/api-endpoint.md`, label `api-endpoint`). Every run prints the pinned and the latest supported version, and the weekly `recurring.yml` opens an issue for a newer one (`tools/Invoke-GitHubApiVersionCheck.ps1`, which reads the version from the line `$script:GitHubApiVersion = 'yyyy-MM-dd'`: keep that form). The gh stub of the tests records the header in `Headers`, apart from `Arguments`.
- `tools/` holds standalone developer scripts, not modules, so it has no `src/`. A script there runs with `$ErrorActionPreference = 'Stop'` and reports a failure by throwing; it checks the exit code of every native command it relies on (as `Invoke-Gh` does) and throws on a failure. `./build.ps1 <tool>` and the VS Code tasks see only the error: an exit code left by a probe such as `actionlint --version` must not fail a run that succeeded. The shared files are `tools/GitHubIssue.ps1` (`Invoke-Gh`, `Get-PinnedGitHubApiVersion`, and the template, label, issue and job summary helpers of the weekly scripts, tested in `tools/tests/GitHubIssue.Tests.ps1`), dot-sourced by the scripts that call GitHub, and `tools/DevModule.ps1` (`Import-DevModule`), dot-sourced by the scripts that use Pester or PSScriptAnalyzer. A `gh api` call of a script sends the pinned version too (`--header "X-GitHub-Api-Version: <version>"`). Their tests in `tools/tests/` run the script (`& $script`) with the external commands mocked; a native command such as `winget` gets a stub function in the test first, since Pester mocks only commands that exist. Like `bootstrap.ps1`, they are not part of the coverage.
- The modules run without `Set-StrictMode` (decided on 2026-10-04). It would turn every read of a missing property into an error, and the code reads missing values as `$null` on purpose: optional keys of shape nodes, and fields of GitHub responses, 44 of the about 80 fields the engine reads are optional in GitHub's OpenAPI description (`2026-03-10`), such as `config.secret` of a webhook without a secret. Each of them would need an explicit check, and one forgotten would stop a real run where the tests pass. Its main catch, a misspelled shape key that silently turns a check off, is an error instead: `Test-ConfigShape` and `ConvertTo-ConfigSchema` reject a shape node with a key or type the validator does not know (`$script:ShapeNodeKeys` in `shared/src/ConfigShape.ps1`, where a new node key is added).
- The config is described once, by its shape (`Get-GitHubOrgConfigShape` in `engine/src/Config.ps1`, built from the rows of `$script:SettingDefinitions`): type, rule, `null`, uniqueness of list items, description, recommended value (a row has `Recommended` with `Why`, or `NoRecommendation` with why it has none: `Project data: ...` or `Owner decides: ...`; a test requires one of the two, so every value of the config has a reason). Validation (`Test-ConfigShape`), recommendations and the JSON Schema all come from it. A new field is a node or a row, its tests, and a regenerated schema: `./tools/Build-ConfigSchema.ps1` (the tests fail while a schema is stale). In the engine a row it applies goes into the section of its endpoint (`$script:Sections`), which holds only rows that read that endpoint; a checked row with a `Read` of its own and a `manual` row go into the section of their page or subject, and keep that path when GitHub adds a read. In the engine, a changed row, settings page or `api-endpoints.psd1` also regenerates `engine/settings.md` with `./tools/Build-SettingReference.ps1` (a test fails while it is stale). Rules between fields stay small functions in `src/Config.ps1` that run once the shape is valid.

## Documentation rules

- The root [README](README.md) is for someone deciding whether to use the engine and setting it up: what it does and never does, the safety model, the quick start, keeping a config in its own repository, upgrading. This file is for whoever changes the code.
- [docs/architecture.md](docs/architecture.md) describes how the code is put together: the pipeline, the files of each step, the contracts between the steps and the test doubles. It is updated in the same change as the code it describes.
- [engine/README.md](engine/README.md) is the reference of the engine: requirements, permissions, usage, every config field, the warnings, troubleshooting and manual verification, updated in the same change as the code.
- The items of Warnings and Troubleshooting in the engine reference lead with what to do (the instruction or the command); the reason follows briefly, and the full reasoning is a link to the decision.
- Relative links and `#anchors` between Markdown files are checked in CI by [lychee](https://github.com/lycheeverse/lychee): after renaming a heading, fix the links to it.
