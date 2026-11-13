---
name: "GitHub API endpoint review"
about: Decide on an organization API operation that the endpoint catalog of the engine does not match.
title: "Review GitHub API endpoint"
labels: [api-endpoint, enhancement]
assignees: [rodchenkov]
---

Opened by `tools/Invoke-ApiEndpointCheck.ps1` (weekly workflow `.github/workflows/recurring.yml`) for the operation in the title, when the OpenAPI description of the pinned REST API version differs from `engine/api-endpoints.psd1`: a new operation under `/orgs/{org}` or `/organizations/{org}`, a listed operation that is no longer in the description, or request body fields of a `write` PUT or PATCH that differ from its `Body`. What differs is above, and the line `<!-- api-endpoint-difference: ... -->` records it: a later difference of the same operation that no issue records opens a new issue once this one is closed. Opened by hand, put the line `<!-- api-endpoint: <METHOD> <path> -->` at the top of the body, as the script does: it finds an issue by that line, and opens a duplicate without it; without the difference line, the issue covers every difference of the operation. A renamed path parameter (`{id}` to `{hook_id}`) shows as a removed and a new operation, two issues: one pull request renames the path in the catalog and closes both. Each operation is its own decision.

## Steps

- [ ] Read the operation in the [REST API documentation](https://docs.github.com/en/rest) (the link above) and decide: the engine reads or writes it (`read` or `write` with its row), or leaves it alone (`unused` with the reason)
- [ ] A new operation: add it to `engine/api-endpoints.psd1` with that status; a removed one: remove it, and the rows and code that call it
- [ ] Request body fields: update `Body` of the operation; a new field of a PUT section is an `apply` row of that section, since a PUT replaces the whole section and would reset a field it does not send
- [ ] Run `./tools/Build-SettingReference.ps1`, then `./build.ps1 all`; `./tools/Invoke-ApiEndpointCheck.ps1 -WhatIf` must no longer list the operation

Close this issue as **completed** with the pull request that changes the catalog; several issues of one feature close with one pull request. The closed issue is the record of the decision on this difference: no other issue opens for it, and one closed while the operation still differs in the same way is listed in the summary of every weekly run.
