---
name: "GitHub REST API version review"
about: Review a GitHub REST API version newer than the one the engine pins, then raise it or stay.
title: "Review GitHub REST API version"
labels: [github-api-version, enhancement]
assignees: [rodchenkov]
---

Opened by `tools/Invoke-GitHubApiVersionCheck.ps1` (weekly workflow `.github/workflows/recurring.yml`) for the version in the title; opened by hand, put the version in the title. The pinned version is `$script:GitHubApiVersion` in `shared/Bootstrap.Common.psm1`, sent by `Invoke-GhApi` as `X-GitHub-Api-Version`; GitHub supports it for at least 24 months after a newer one is released.

## Steps

- [ ] Read the [breaking changes](https://docs.github.com/en/rest/about-the-rest-api/breaking-changes) of the new version and list, per endpoint the engine calls, whether it changes (in the pull request description)
- [ ] Adapt the parsing in `State.ps1` and the request bodies in `Apply.ps1` where a shape changed; update the test fixtures to the new shapes
- [ ] Run `./tools/Invoke-ApiEndpointCheck.ps1 -Version <new> -Report`: it compares every operation of `engine/api-endpoints.psd1` with the new description and opens nothing; resolve every line it prints (new, removed and changed operations, the `Body` differences of every `write` operation, the response fields of every `read` GET that neither a row nor `Fields` lists) in the pull request, then set `ApiVersion` and `ReviewedOn` of the catalog and run `./tools/Build-SettingReference.ps1`
- [ ] Raise `$script:GitHubApiVersion`, the tests of `Invoke-GhApi` and the version named in CONTRIBUTING.md; a test fails while `ApiVersion` of the catalog differs, so both go into one pull request
- [ ] Run `./engine/bootstrap.ps1 -ConfigPath <config> -WhatIf` against a real organization: the plan must be the same as before, and the run shows the response fields the real answers carry beyond the catalog as warnings

Close this issue as **completed** with the pull request that raises the version. To stay on the pinned version for now, close it as **not planned**: no other issue opens until a still newer version appears.
