# Helpers of the scripts in tools/ that call GitHub through gh and open issues from a template; dot-sourced, not
# runnable on its own.

# The GitHub REST API version the engine pins: the line $script:GitHubApiVersion = 'yyyy-MM-dd' of the module at $Path
# (shared/GitHubOrg.Common.psm1). gh api calls of the scripts send it too, so their response shapes are reviewed with it.
function Get-PinnedGitHubApiVersion {
    param([string]$Path)

    $match = [regex]::Match((Get-Content -Path $Path -Raw), "(?m)^\`$script:GitHubApiVersion = '(?<version>\d{4}-\d{2}-\d{2})'")
    if (-not $match.Success) {
        throw "$Path sets no `$script:GitHubApiVersion = 'yyyy-MM-dd'."
    }
    $match.Groups['version'].Value
}

# Runs gh and returns its output as one string; throws when it fails.
function Invoke-Gh {
    $output = & gh @args
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($args[0..1] -join ' ') failed with exit code $LASTEXITCODE."
    }
    $output -join "`n"
}

# The front matter ('key: value' and 'key: [a, b]' lines between two '---' lines) and the body of an issue template.
function Read-IssueTemplate {
    param([string]$Path)

    $text = (Get-Content -Path $Path -Raw) -replace "`r`n", "`n"
    if ($text -notmatch '(?s)\A---\n(?<front>.*?)\n---\n(?<body>.*)\z') {
        return @{ Fields = @{}; Body = $text.Trim() }
    }
    $front = $Matches.front
    $body = $Matches.body.Trim()
    $fields = @{}
    foreach ($line in $front -split "`n") {
        if ($line -notmatch '^(?<key>[A-Za-z_]+):\s*(?<value>.*?)\s*$') {
            continue
        }
        $key = $Matches.key
        $value = $Matches.value
        if ($value -match '^\[(?<items>.*)\]$') {
            $fields[$key] = [string[]]@($Matches.items -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ })
        }
        else {
            $fields[$key] = $value.Trim('"', "'")
        }
    }
    @{ Fields = $fields; Body = $body }
}

# The template of the issues a script opens, checked before any call to GitHub: its title, labels (which must include
# $Label, the label the issues are matched by), assignees and body.
function Assert-IssueTemplate {
    param([string]$Path, [string]$Label)

    $template = Read-IssueTemplate -Path $Path
    $name = Split-Path -Path $Path -Leaf
    $labels = [string[]]@($template.Fields.labels | Where-Object { $_ })
    if (-not $template.Fields.title) {
        throw "${name}: the front matter has no title."
    }
    if ($labels -notcontains $Label) {
        throw "${name}: the labels must include '$Label', which the issues are matched by."
    }
    [pscustomobject]@{
        Title     = $template.Fields.title
        Labels    = $labels
        Assignees = [string[]]@($template.Fields.assignees | Where-Object { $_ })
        Body      = $template.Body
    }
}

# Every issue with the label, open or closed, oldest first: {number, state, body}. gh returns at most -Limit issues, so
# a list that reaches it throws: an issue past it would be opened again as a duplicate.
function Get-LabeledIssue {
    param([string]$Label, [int]$Limit = 10000)

    $listArguments = @('issue', 'list', '--label', $Label, '--state', 'all', '--limit', $Limit, '--json', 'number,state,body')
    $issues = @(Invoke-Gh @listArguments | ConvertFrom-Json)
    if ($issues.Count -ge $Limit) {
        throw "gh issue list returned $($issues.Count) issues with the label '$Label', its limit: some may be missing, so nothing was opened."
    }
    $issues | Sort-Object -Property number
}

# The first of the issues whose body holds every marker (an HTML comment the script wrote above the template body).
function Find-IssueByMarker {
    param([object[]]$Issue, [string[]]$Marker)

    $Issue | Where-Object {
        $body = [string]$_.body
        @($Marker | Where-Object { -not $body.Contains($_) }).Count -eq 0
    } | Select-Object -First 1
}

# The labels of the repository, read by the first Add-MissingLabel of a run; it adds the ones it creates.
$script:RepositoryLabels = $null

# Creates the labels that do not exist yet: GitHub silently drops a label that does not exist, also when the operator
# opens a template by hand. Label names are case-insensitive on GitHub.
function Add-MissingLabel {
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$Name, [string]$Description)

    if ($null -eq $script:RepositoryLabels) {
        $labelArguments = @('label', 'list', '--limit', '1000', '--json', 'name')
        $existing = [string[]]@(Invoke-Gh @labelArguments | ConvertFrom-Json | ForEach-Object { $_.name })
        $script:RepositoryLabels = [System.Collections.Generic.HashSet[string]]::new($existing, [StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($label in @($Name | Where-Object { $_ })) {
        if (-not $script:RepositoryLabels.Contains($label) -and $PSCmdlet.ShouldProcess($label, 'gh label create')) {
            $createArguments = @('label', 'create', $label, '--description', $Description)
            Invoke-Gh @createArguments | Out-Null
            [void]$script:RepositoryLabels.Add($label)
        }
    }
}

# Opens an issue with the labels (created first when missing) and assignees of its template, and returns its number;
# nothing with -WhatIf, which shows Target.
function New-IssueFromTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Title,
        [string]$Body,
        [string[]]$Label,
        [string[]]$Assignee,
        # What -WhatIf names: the version or candidates the issue is about.
        [string]$Target,
        # The description of a label the script creates.
        [string]$LabelDescription
    )

    if (-not $PSCmdlet.ShouldProcess($Target, 'gh issue create')) {
        return
    }
    # -Confirm:$false: the confirmed issue needs its labels, so they are not asked about one by one.
    Add-MissingLabel -Name $Label -Description $LabelDescription -Confirm:$false
    $issueArguments = @('issue', 'create', '--title', $Title, '--body', $Body)
    foreach ($name in $Label) { $issueArguments += @('--label', $name) }
    foreach ($name in @($Assignee | Where-Object { $_ })) { $issueArguments += @('--assignee', $name) }
    (Invoke-Gh @issueArguments).Trim() -replace '.*/', ''
}

# Appends the lines to the job summary of the GitHub Actions run; nothing outside Actions.
function Add-StepSummary {
    param([string[]]$Line)

    if ($env:GITHUB_STEP_SUMMARY) {
        # -WhatIf:$false: a dry run reports too.
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Line -WhatIf:$false
    }
}
