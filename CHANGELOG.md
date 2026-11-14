# Changelog

All notable changes are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release that changes the config format has a
**Config format** section with the edit a config needs; a release without one reads the configs of the previous
release unchanged.

## [Unreleased]

### Changed

- `engine/examples/run.ps1` stops when `.engine/` has local changes (an edited or added file), instead of running
  them; remove `.engine/` to check out the pinned engine again.

## [1.0.0] - 2026-11-13

### Added

- The first public release of the engine: organization settings, Actions policies, code security, the organization
  ruleset, budgets, Copilot settings and seats, the inventory, the manual checklist and the settings page walk.
- `engine/examples/run.ps1` and `engine.psd1` to run a pinned release against a config kept in another repository.

### Config format

`1.0`: the first format. A config sets `"configVersion": "1.0"`.

[Unreleased]: https://github.com/devntoltd/github-org-bootstrap/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/devntoltd/github-org-bootstrap/releases/tag/v1.0.0
