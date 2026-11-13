# Review instructions

PowerShell tool that keeps the settings of a GitHub organization in line with a config file. The rules are in [CONTRIBUTING.md](../CONTRIBUTING.md), how the code is put together in [docs/architecture.md](../docs/architecture.md).

## Check these

CI does not catch them.

- GitHub reads are only in `src/State*.ps1`, writes only in `src/Apply.ps1`. `src/Config*.ps1` and `src/Plan*.ps1` make no such calls.
- The engine never deletes or cancels anything. What it does not manage is reported as a warning.
- Every GitHub REST call goes through `Invoke-GhApi`.
- A failed read must not look like an empty result. A read that could not be done ends in an error or a warning, never in silence.
- New behavior comes with a test. A test checks a behavior at the level that owns it, and asserts results, not an ordered list of calls.
- The full text of a warning or of a `Summary` is checked by one test only; every other test uses `-BeLike` on the parts it is about.
- `.ps1` and `.psm1` files hold no organization or project names, test data included. Organization data belongs in a config.
- A new setting is a row of the shape, its tests and a regenerated schema.
- A change of the config format raises `configVersion` and has a changelog entry that says what a config must change.
- `docs/architecture.md` and `engine/README.md` change in the same pull request as the code they describe.
- Everything committed is in English.

## Do not comment on

- Formatting, line endings, ASCII-only files, broken links, workflow pins: CI checks them.
- `docs/decisions/` files with a date: records, not edited afterwards.
- The missing `Set-StrictMode`: the modules run without it on purpose (CONTRIBUTING.md).
