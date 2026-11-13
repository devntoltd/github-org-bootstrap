# The engine version run.ps1 runs: the repository, a release tag and the full commit of that tag. An upgrade changes
# Tag and Commit together, in a pull request with the -WhatIf plan of the new version (README.md, Upgrading). The
# commit below is a placeholder: take the one of the release you pin.
@{
    Repository = 'devntoltd/github-org-bootstrap'
    Tag        = 'v1.0.0'
    Commit     = '0000000000000000000000000000000000000000'
}
