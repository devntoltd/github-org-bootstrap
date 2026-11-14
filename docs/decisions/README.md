# Decisions

Back to the [overview](../../README.md).

Each decision records a design with its date and reasoning and is not edited afterwards ([CONTRIBUTING](../../CONTRIBUTING.md#how-changes-are-made)), so a later decision can replace part of an earlier one. This index says which still holds: one row per decision, with what a later one superseded or changed. The current code is described in [docs/architecture.md](../architecture.md).

| Date | Decision | Status | Superseded or changed by |
| --- | --- | --- | --- |
| 2026-11-13 | [github-org-bootstrap](2026-11-13-github-org-bootstrap-design.md): what the tool manages and never does, the rules it keeps (no deletes, plan then one question, strict config, recommendations with reasons, traceability, pinned API version, owner rights for one run), configs in their own repository with a pinned engine and a format version | implemented | — |
| 2026-11-14 | [Release workflow](2026-11-14-release-workflow.md): the merge of the release pull request tags the commit and publishes the release from the changelog section, in a CI job with `contents: write` after every check passed, checked before writing since releases are immutable | implemented | — |
