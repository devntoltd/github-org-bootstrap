# GitHub: the gh version and every GitHub REST call. Dot-sourced into
# Bootstrap.Common, so its functions share that module's scope (Pester -ModuleName Bootstrap.Common mocks).

# The oldest gh Invoke-GhApi works with: 'gh api --paginate --slurp' needs 2.48.0.
$script:GhMinimumVersion = '2.48.0'

# The GitHub CLI boundary: every gh call goes through Invoke-GhApi, which tests replace with a stub (shared/tests/GhStub.ps1).

function Test-GhInstalled {
    # Whether the GitHub CLI (gh) is on PATH.
    return [bool](Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue)
}

function Get-LatestGhVersion {
    # The version of the latest gh release, or $null. Informational only, like Get-LatestModuleVersion: any failure
    # (offline, gh not signed in) yields $null instead of an error.
    try {
        $release = Invoke-GhApi -Endpoint 'repos/cli/cli/releases/latest'
        return [version]([string]$release.tag_name).TrimStart('v')
    }
    catch {
        Write-Verbose "Could not read the latest gh release: $($_.Exception.Message)"
        return $null
    }
}

function Get-LatestGitHubApiVersion {
    # The newest REST API version GitHub supports (yyyy-MM-dd), or $null. Informational only, like Get-LatestGhVersion.
    try {
        return @(Invoke-GhApi -Endpoint 'versions' | ForEach-Object { [string]$_ } | Sort-Object -Descending)[0]
    }
    catch {
        Write-Verbose "Could not read the GitHub REST API versions: $($_.Exception.Message)"
        return $null
    }
}

function Assert-GhVersion {
    <#
    .SYNOPSIS
    Prints the installed, minimum and latest gh versions, and the pinned and latest GitHub REST API versions; throws if
    gh is missing or older than the minimum.
    .DESCRIPTION
    A minimum, not an exact version: gh updates almost weekly, and the winget hash check, GitHub's signature and the
    release attestations already guard the binary. Printed in the format of Import-RequiredModule, so the output of a
    run shows what it ran with. gh's own update notice never shows: Invoke-GhApi captures its output. A gh older than
    the minimum makes no API call. A newer REST API version is only reported: raising $script:GitHubApiVersion needs a
    review (see CONTRIBUTING.md).
    .PARAMETER SkipLatestVersionCheck
    Do not look up the latest gh release and REST API version.
    #>
    [CmdletBinding()]
    param(
        [switch]$SkipLatestVersionCheck
    )

    Write-Host 'Tools:'
    $skipped = if ($SkipLatestVersionCheck) { 'skipped' } else { 'unknown' }
    if (-not (Test-GhInstalled)) {
        Write-Host ($script:VersionRowFormat -f 'gh', 'missing', 'minimum', $script:GhMinimumVersion, $skipped, '')
        throw 'GitHub CLI (gh) is not installed. Install it with: winget install --id GitHub.cli -e, then sign in with: gh auth login'
    }

    $text = (@(& gh --version 2>&1) | ForEach-Object { [string]$_ }) -join "`n"
    if ($text -notmatch 'gh version (\d+\.\d+\.\d+)') {
        throw "Could not read the gh version from 'gh --version': '$($text.Trim())'."
    }
    $installed = [version]$Matches[1]
    $supported = $installed -ge [version]$script:GhMinimumVersion
    $lookup = $supported -and -not $SkipLatestVersionCheck
    $latest = if ($lookup) { Get-LatestGhVersion } else { $null }
    $latestText = if ($latest) { [string]$latest } else { $skipped }
    $note = if ($latest -and $latest -gt $installed) { '  (update available)' } else { '' }
    Write-Host ($script:VersionRowFormat -f 'gh', $installed, 'minimum', $script:GhMinimumVersion, $latestText, $note)

    # The latest column lines up with the row above.
    $latestApi = if ($lookup) { Get-LatestGitHubApiVersion } else { $null }
    $apiNote = if ($latestApi -and [string]::CompareOrdinal($latestApi, $script:GitHubApiVersion) -gt 0) { '  (new version available)' } else { '' }
    Write-Host ('  {0,-26} pinned {1,-28} latest {2}{3}' -f 'GitHub REST API', $script:GitHubApiVersion, ($latestApi ?? $skipped), $apiNote)
    if (-not $supported) {
        throw "gh $installed is older than $script:GhMinimumVersion, the minimum this script needs. Update it with: winget upgrade --id GitHub.cli -e"
    }
}

function Get-GhErrorStatus {
    # The HTTP status of a failed gh call, or $null when gh got no answer. gh names it as "(HTTP 404)", or as
    # "HTTP 502" for a body that is not JSON; when it cannot read a JSON error body (a 409 on 2026-09-29 had "errors"
    # as a string), only the body's "status" has it.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Stdout
    )

    if ($Text -match '\bHTTP (?<code>\d{3})\b') {
        return [Enum]::ToObject([System.Net.HttpStatusCode], [int]$Matches.code)
    }
    # The body is one line of stdout (gh prints it as GitHub sent it), next to whatever else gh printed there.
    foreach ($line in ($Stdout -split "`n")) {
        try {
            $body = $line | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
        }
        catch {
            continue
        }
        # Not [pscustomobject]: that accelerator is PSObject, which an array also is.
        if ($body -is [System.Management.Automation.PSCustomObject] -and [string]$body.status -match '^\d{3}$') {
            return [Enum]::ToObject([System.Net.HttpStatusCode], [int]$body.status)
        }
    }
    return $null
}

function Invoke-GhApi {
    <#
    .SYNOPSIS
    Calls the GitHub REST API through gh and returns the parsed JSON response ($null when it is empty).
    .DESCRIPTION
    The body goes to gh as JSON on stdin; a non-zero exit code becomes an HttpRequestException carrying gh's output and,
    when gh got an answer, the HTTP status as StatusCode: callers check it with Test-GhStatus, never the message text.
    .PARAMETER Paginate
    For a list endpoint: gh follows the Link headers (page numbers and cursors alike) and the items of every page
    are returned.
    .PARAMETER NoEnumerate
    Without -Paginate: returns the parsed JSON root as it is, so a JSON array stays an array, also with one item or none.
    By default the items of an array root are returned, and a single-item array looks like the object it holds.
    #>
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT')][string]$Method = 'GET',
        [System.Collections.IDictionary]$Body,
        [switch]$Paginate,
        [switch]$NoEnumerate
    )

    $arguments = @('api', '--method', $Method, $Endpoint, '--header', "X-GitHub-Api-Version: $script:GitHubApiVersion")
    if ($Paginate) {
        # --slurp wraps the pages in one outer array: [[page 1 items], [page 2 items], ...].
        $arguments += @('--paginate', '--slurp')
    }
    # gh writes UTF-8, but PowerShell decodes native output with [Console]::OutputEncoding, the OEM code page in a
    # Windows console: non-ASCII text would come back corrupted. The body goes out as $OutputEncoding, UTF-8 already.
    $consoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    try {
        if ($Body) {
            $arguments += @('--input', '-')
            $output = $Body | ConvertTo-Json -Depth 10 -Compress | & gh @arguments 2>&1
        }
        else {
            $output = & gh @arguments 2>&1
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $consoleEncoding
    }

    # stderr lines arrive as ErrorRecords; only stdout carries the JSON.
    $json = (@($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n").Trim()
    if ($exitCode -ne 0) {
        $text = (@($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
        throw [System.Net.Http.HttpRequestException]::new("gh api --method $Method $Endpoint failed (exit code $exitCode): $text", $null, (Get-GhErrorStatus -Text $text -Stdout $json))
    }
    if ($Paginate) {
        # An empty response is no page at all: no item, not a $null one.
        foreach ($page in ($json | ConvertFrom-Json -NoEnumerate)) {
            foreach ($item in @($page)) {
                $item
            }
        }
        return
    }
    if (-not $json) {
        return $null
    }
    if ($NoEnumerate) {
        # The comma keeps an array root from being enumerated on its way out.
        return , ($json | ConvertFrom-Json -NoEnumerate)
    }
    return $json | ConvertFrom-Json
}

function Get-GhStatus {
    <#
    .SYNOPSIS
    Gives the HTTP status of an error of Invoke-GhApi, or of an error wrapping one as its inner exception; $null without an answer.
    #>
    [OutputType([System.Nullable[int]])]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        if ($exception -is [System.Net.Http.HttpRequestException] -and $null -ne $exception.StatusCode) {
            return [int]$exception.StatusCode
        }
    }
    return $null
}

function Test-GhStatus {
    <#
    .SYNOPSIS
    Tells whether an error of Invoke-GhApi, or an error wrapping one as its inner exception, has the HTTP status.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)][int]$StatusCode
    )

    return (Get-GhStatus -ErrorRecord $ErrorRecord) -eq $StatusCode
}
