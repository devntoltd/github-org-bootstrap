# Pull request

## What and why

<!-- What changes, and the reason; link the issue it closes. -->

## Checklist

- [ ] A test for the new behavior, seen failing first
- [ ] `./build.ps1 all` passes
- [ ] `CHANGELOG.md`: an entry under `[Unreleased]`
- [ ] A changed config format raises `configVersion` and says in the changelog what a config must change
- [ ] A new or changed setting row: `./tools/Build-ConfigSchema.ps1` and `./tools/Build-SettingReference.ps1` run
- [ ] `engine/README.md` and `docs/architecture.md` updated where they describe the change
