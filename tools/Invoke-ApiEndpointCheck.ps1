<#
.SYNOPSIS
Compares the endpoint catalog of the engine with GitHub's OpenAPI description and opens one issue per difference of an
operation.
.DESCRIPTION
Downloads the description of a REST API version (the pinned one by default) from github/rest-api-description and
compares it with engine/api-endpoints.psd1. An operation is reported when it is under /orgs/{org} or
/organizations/{org} and not in the catalog (a new path or a new method of a listed path), when the catalog lists it
and the description no longer has it (any path), and, for a 'write' PUT or PATCH, when the request body fields of the
description differ from its Body; a request body that is not JSON or has a oneOf or anyOf cannot be compared and is
only reported. For each difference the script opens one issue from the template
.github/ISSUE_TEMPLATE/api-endpoint.md (its title with '<METHOD> <path>' appended, its labels, which must include
'api-endpoint', and assignees; above its body the marker of the operation, the marker of the difference and what
differs). An issue with that label that records the difference (both markers, or the operation marker alone, as one
opened by hand), open or closed, keeps another from opening, and so does any open issue of the operation; one that was
closed while the operation still differs in that way is listed in the job summary on every run.

Everything is gathered and checked before anything is written: a failed download, an answer that is not JSON or has no
paths, a reference of the description that does not resolve, a description without an /orgs/{org} operation, one
that has less than 90% of the listed operations or misses more than 10 of them, and a failed issue list each throw and
open nothing.

-Report opens nothing and reads no issue: it prints every difference, and also the response fields of every 'read'
GET with Fields that the description has and neither a row of the engine nor Fields lists (the review of a raise of
$script:GitHubApiVersion; the weekly run opens no issue for those, the run of the engine warns about the fields of
real answers).

The weekly workflow .github/workflows/recurring.yml runs it. Uses gh, signed in (GH_TOKEN in Actions) and pointed at
the repository (GH_REPO in Actions, the git remote of the current directory otherwise).
.EXAMPLE
./tools/Invoke-ApiEndpointCheck.ps1 -WhatIf
.EXAMPLE
./tools/Invoke-ApiEndpointCheck.ps1 -Version 2027-06-01 -Report
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The REST API version whose description is compared; the pinned one by default.
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$Version,
    # Print every difference, response fields included, and open nothing.
    [switch]$Report,
    # The module that pins the version.
    [string]$ModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'shared/Bootstrap.Common.psm1'),
    # The endpoint catalog.
    [string]$CatalogPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'engine/api-endpoints.psd1'),
    # The issue template of an operation.
    [string]$TemplatePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.github/ISSUE_TEMPLATE/api-endpoint.md'),
    # The engine module whose Get-GitHubOrgReadField names the response fields the rows read (-Report only).
    [string]$EngineModulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'engine/GitHubOrg.psm1')
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'GitHubIssue.ps1')

# The label the issues are matched by.
$label = 'api-endpoint'
# The methods of an OpenAPI path item, in the order the reports list them.
$methodOrder = @('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS', 'TRACE')
# Sanity checks of the description: the share of the listed operations it must have, and how many may be missing.
$minimumShare = 0.9
$maximumMissing = 10

# True for a path under /orgs/{org} or /organizations/{org}, the paths the catalog lists completely.
function Test-OrgPath {
    param([string]$Path)

    foreach ($prefix in '/orgs/{org}', '/organizations/{org}') {
        if ($Path -ceq $prefix -or $Path.StartsWith("$prefix/", [StringComparison]::Ordinal)) {
            return $true
        }
    }
    $false
}

# The node a local '$ref' (#/components/...) points at, followed until a node without one. A reference that is not
# local, points at nothing or goes round in a loop throws: read as an empty schema, it would report every field of
# it as removed, an issue that is not true and that keeps the real one from opening.
function Resolve-SchemaReference {
    param([object]$Node)

    for ($hops = 0; $Node -is [System.Collections.IDictionary] -and $Node.Contains('$ref'); $hops++) {
        $reference = [string]$Node['$ref']
        $unresolved = "The description of $Version has a reference it does not resolve: '$reference'; nothing was opened."
        if ($hops -ge 32 -or -not $reference.StartsWith('#/')) {
            throw $unresolved
        }
        $Node = $description
        foreach ($segment in $reference.Substring(2).Split('/')) {
            $key = $segment.Replace('~1', '/').Replace('~0', '~')
            if ($Node -isnot [System.Collections.IDictionary] -or -not $Node.Contains($key)) {
                throw $unresolved
            }
            $Node = $Node[$key]
        }
    }
    $Node
}

# Throws past 32 levels of nested schemas: a traversal cut short there would read the schema as comparable, or drop
# the fields below it and report them removed.
function Assert-SchemaDepth {
    param([int]$Depth, [string]$Reference)

    if ($Depth -gt 32) {
        $where = if ($Reference) { "'$Reference'" } else { 'an inline schema' }
        throw "The description of $Version nests schemas deeper than 32 levels at ${where}; nothing was opened."
    }
}

# The property names of a schema, its '$ref' and allOf parts resolved. The fields are a union, so each reference is
# visited once per body (Seen): a schema many allOf parts refer to is not walked once per path to it, which grows
# exponentially. Every path is still checked against the depth limit until it meets a reference seen before.
function Get-SchemaField {
    param([object]$Schema, [int]$Depth = 0, [System.Collections.Generic.HashSet[string]]$Seen = [System.Collections.Generic.HashSet[string]]::new())

    $reference = if ($Schema -is [System.Collections.IDictionary] -and $Schema.Contains('$ref')) { [string]$Schema['$ref'] } else { $null }
    if ($reference -and -not $Seen.Add($reference)) {
        return
    }
    Assert-SchemaDepth -Depth $Depth -Reference $reference
    $Schema = Resolve-SchemaReference -Node $Schema
    if ($Schema -isnot [System.Collections.IDictionary]) {
        return
    }
    if ($Schema['properties'] -is [System.Collections.IDictionary]) {
        $Schema['properties'].Keys
    }
    foreach ($part in @($Schema['allOf'])) {
        if ($null -ne $part) {
            Get-SchemaField -Schema $part -Depth ($Depth + 1) -Seen $Seen
        }
    }
}

# The result of Get-SchemaVariant per reference, {Variant, Height}: a schema many parts refer to is visited once, not
# once per path to it, which grows exponentially. A reference still being visited is a cycle, whose fields have no end:
# it counts as a variant, not comparable, so no schema of the cycle is cached as comparable before the cycle is known.
# Height is how many levels the schema nests below itself, so a reference found in the cache is still checked against
# the depth limit from where this path reaches it, whichever operation visited it first.
$schemaVariants = @{}

# {Variant, Height} of a schema at Depth: Variant is true when it has a oneOf or anyOf, itself or in an allOf part, or is
# part of a cycle. Every allOf part and every variant is visited, also after a variant, so a reference that does not
# resolve still throws, and so does nesting deeper than 32 levels, which a truncated traversal would read as comparable.
function Get-SchemaVariant {
    param([object]$Schema, [int]$Depth)

    $reference = if ($Schema -is [System.Collections.IDictionary] -and $Schema.Contains('$ref')) { [string]$Schema['$ref'] } else { $null }
    if ($reference -and $schemaVariants.ContainsKey($reference)) {
        $cached = $schemaVariants[$reference]
        Assert-SchemaDepth -Depth ($Depth + $cached.Height) -Reference $reference
        return $cached
    }
    Assert-SchemaDepth -Depth $Depth -Reference $reference
    if ($reference) {
        $schemaVariants[$reference] = [pscustomobject]@{ Variant = $true; Height = 0 }
    }
    $result = [pscustomobject]@{ Variant = $false; Height = 0 }
    $Schema = Resolve-SchemaReference -Node $Schema
    if ($Schema -is [System.Collections.IDictionary]) {
        $result.Variant = $Schema.Contains('oneOf') -or $Schema.Contains('anyOf')
        foreach ($part in @($Schema['allOf']) + @($Schema['oneOf']) + @($Schema['anyOf'])) {
            if ($null -ne $part) {
                $child = Get-SchemaVariant -Schema $part -Depth ($Depth + 1)
                $result.Variant = $result.Variant -or $child.Variant
                $result.Height = [Math]::Max($result.Height, $child.Height + 1)
            }
        }
    }
    if ($reference) {
        $schemaVariants[$reference] = $result
    }
    $result
}

# True when the fields of a schema cannot be compared: it has a oneOf or anyOf, itself or in an allOf part, or is part
# of a cycle (Get-SchemaVariant).
function Test-SchemaVariant {
    param([object]$Schema)

    (Get-SchemaVariant -Schema $Schema -Depth 0).Variant
}

# The JSON fields of a request body or a response of the description, sorted: {Fields, Reason}. Reason says why the
# fields cannot be compared (not JSON, a oneOf or anyOf), $null when they can: read as no fields, such a body would
# report every Body entry as removed and open an issue that is not true.
function Get-ContentField {
    param([object]$Content)

    $content = Resolve-SchemaReference -Node $Content
    if ($content -isnot [System.Collections.IDictionary] -or $content['content'] -isnot [System.Collections.IDictionary]) {
        return [pscustomobject]@{ Fields = [string[]]@(); Reason = $null }
    }
    $json = $content['content']['application/json']
    if ($json -isnot [System.Collections.IDictionary]) {
        return [pscustomobject]@{ Fields = [string[]]@(); Reason = "it is not JSON ($(@($content['content'].Keys) -join ', '))" }
    }
    if (Test-SchemaVariant -Schema $json['schema']) {
        return [pscustomobject]@{ Fields = [string[]]@(); Reason = 'its schema has a oneOf or anyOf, or refers to itself, so its fields cannot be listed' }
    }
    [pscustomobject]@{ Fields = [string[]]@(Get-SchemaField -Schema $json['schema'] | Sort-Object -Unique -CaseSensitive); Reason = $null }
}

# What a difference is, for its marker: the kind, and for request body fields the fields that differ ('+new -gone').
function Get-DifferenceSignature {
    param([object]$Difference)

    if ($Difference.PSObject.Properties['Signature']) { $Difference.Signature } else { $Difference.Kind }
}

# The issue that records a difference of an operation: one of the operation with the same difference marker, or one
# opened by hand with only the operation marker, which covers every difference of it; else an open issue of the
# operation, whose pull request meets the new difference too. $null opens a new issue: a difference that no issue
# records, such as a new body field a year after the last one was decided.
function Find-DifferenceIssue {
    param([object[]]$Issue, [string]$Operation, [string]$Signature)

    $own = @($Issue | Where-Object { ([string]$_.body).Contains("<!-- api-endpoint: $Operation -->") })
    $recorded = Find-IssueByMarker -Issue $own -Marker "<!-- api-endpoint-difference: $Signature -->"
    if ($recorded) {
        return $recorded
    }
    # A marker is a line of its own: the template's text explains the difference line too.
    $byHand = @($own | Where-Object { [string]$_.body -notmatch '(?m)^<!-- api-endpoint-difference: .+ -->\r?$' }) | Select-Object -First 1
    if ($byHand) {
        return $byHand
    }
    @($own | Where-Object { [string]$_.state -eq 'OPEN' }) | Select-Object -First 1
}

# '`a`, `b`' of field names.
function Format-FieldList {
    param([string[]]$Field)

    (@($Field | ForEach-Object { '`' + $_ + '`' }) -join ', ')
}

$template = Assert-IssueTemplate -Path $TemplatePath -Label $label
$pinned = Get-PinnedGitHubApiVersion -Path $ModulePath
if (-not $Version) {
    $Version = $pinned
}
$catalog = Import-PowerShellDataFile -LiteralPath $CatalogPath

# 1. The description, only parsed as JSON.
$downloadArguments = @(
    'api', '--header', 'Accept: application/vnd.github.raw', '--header', "X-GitHub-Api-Version: $pinned"
    "repos/github/rest-api-description/contents/descriptions/api.github.com/api.github.com.$Version.json"
)
try {
    $text = Invoke-Gh @downloadArguments
}
catch {
    throw "Downloading the description of $Version failed: $($_.Exception.Message)"
}
try {
    $description = $text | ConvertFrom-Json -AsHashtable
}
catch {
    throw "The description of $Version is not JSON: $($_.Exception.Message)"
}
if ($description -isnot [System.Collections.IDictionary] -or $description['paths'] -isnot [System.Collections.IDictionary]) {
    throw "The description of $Version has no paths."
}

# Operation ('<METHOD> <path>') -> its description entry.
$described = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($path in $description.paths.Keys) {
    $item = $description.paths[$path]
    if ($item -isnot [System.Collections.IDictionary]) {
        continue
    }
    foreach ($key in $item.Keys) {
        $method = ([string]$key).ToUpperInvariant()
        if ($method -cin $methodOrder) {
            $described["$method $path"] = [pscustomobject]@{ Method = $method; Path = $path; Operation = $item[$key] }
        }
    }
}
# Operation -> its catalog entry.
$listed = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($path in $catalog.Paths.Keys) {
    $entry = $catalog.Paths[$path]
    foreach ($method in @($entry.Keys | Where-Object { $_ -cne 'Category' })) {
        $listed["$method $path"] = [pscustomobject]@{ Method = $method; Path = $path; Category = $entry.Category; Operation = $entry[$method] }
    }
}

# 2. Sanity checks: a truncated or wrong file shows up as many removed operations.
if (-not @($described.Values | Where-Object { Test-OrgPath -Path $_.Path }).Count) {
    throw "The description of $Version has no operation under /orgs/{org}: not the description of the REST API."
}
$missing = @($listed.Keys | Where-Object { -not $described.ContainsKey($_) } | Sort-Object -CaseSensitive)
$present = $listed.Count - $missing.Count
if ($listed.Count -gt 0 -and $present -lt $minimumShare * $listed.Count) {
    throw "Only $present of $($listed.Count) operations of the catalog are in the description of $Version (at least $($minimumShare * 100)% are expected): a truncated or wrong file."
}
if ($missing.Count -gt $maximumMissing) {
    throw "$($missing.Count) operations of the catalog are missing from the description of $Version (more than $maximumMissing): review them by hand: $($missing -join ', ')."
}

# The differences, one per operation.
$differences = [System.Collections.Generic.List[object]]::new()
foreach ($key in $described.Keys) {
    $operation = $described[$key]
    if ((Test-OrgPath -Path $operation.Path) -and -not $listed.ContainsKey($key)) {
        $entry = $operation.Operation
        $category = if ($entry['x-github'] -is [System.Collections.IDictionary]) { $entry['x-github']['category'] } else { $null }
        $docs = if ($entry['externalDocs'] -is [System.Collections.IDictionary]) { $entry['externalDocs']['url'] } else { $null }
        $differences.Add([pscustomobject]@{
                Method = $operation.Method; Path = $operation.Path; Kind = 'new operation'; Issue = $true
                Detail = "New in the description: $($entry['summary']) (category ``$category``, $docs). List it in ``engine/api-endpoints.psd1``: ``read`` or ``write`` with its row, or ``unused`` with the reason."
            })
    }
}
foreach ($key in $missing) {
    $operation = $listed[$key]
    $differences.Add([pscustomobject]@{
            Method = $operation.Method; Path = $operation.Path; Kind = 'removed operation'; Issue = $true
            Detail = "Listed in ``engine/api-endpoints.psd1`` (category ``$($operation.Category)``, status ``$($operation.Operation.Status)``), no longer in the description."
        })
}
$readFields = $null
# In a fixed order: the schema cache is shared between operations, and the depth limit of a schema on a cycle can
# depend on which body reached the cycle first, so the same description always gives the same result.
foreach ($key in @($listed.Keys | Sort-Object -CaseSensitive)) {
    $operation = $listed[$key]
    if (-not $described.ContainsKey($key)) {
        continue
    }
    $entry = $described[$key].Operation
    if ($operation.Operation.Status -ceq 'write' -and $operation.Method -cin 'PUT', 'PATCH') {
        $request = Get-ContentField -Content $entry['requestBody']
        $fields = $request.Fields
        $body = [string[]]@($operation.Operation.Body)
        $added = [string[]]@($fields | Where-Object { $_ -cnotin $body })
        # Sorted, as the described fields are, so the marker of a difference does not depend on the order of Body.
        $removed = [string[]]@($body | Where-Object { $_ -cnotin $fields } | Sort-Object -CaseSensitive)
        if ($request.Reason) {
            # Report only: an issue would claim every Body field removed, and once closed it would hide the operation.
            $differences.Add([pscustomobject]@{
                    Method = $operation.Method; Path = $operation.Path; Kind = 'request body not comparable'; Issue = $false
                    Detail = "$($request.Reason); review ``Body`` against the description by hand."
                })
        }
        elseif ($added.Count -or $removed.Count) {
            $parts = @(
                if ($added.Count) { "In the description and not in ``Body``: $(Format-FieldList -Field $added)." }
                if ($removed.Count) { "In ``Body`` and no longer in the description: $(Format-FieldList -Field $removed)." }
            )
            $category = if ($entry['x-github'] -is [System.Collections.IDictionary]) { $entry['x-github']['category'] } else { $null }
            $docs = if ($entry['externalDocs'] -is [System.Collections.IDictionary]) { $entry['externalDocs']['url'] } else { $null }
            $differences.Add([pscustomobject]@{
                    Method = $operation.Method; Path = $operation.Path; Kind = 'request body fields'; Issue = $true
                    Detail    = "Request body fields of $($entry['summary']) (category ``$category``, $docs). $($parts -join ' ')"
                    Signature = "request body fields: $(@(@($added | ForEach-Object { "+$_" }) + @($removed | ForEach-Object { "-$_" })) -join ' ')"
                })
        }
    }
    # Report only: the run of the engine warns about the fields of real answers.
    if ($Report -and $operation.Method -ceq 'GET' -and $operation.Operation.Status -ceq 'read' -and $operation.Operation.ContainsKey('Fields')) {
        if ($null -eq $readFields) {
            # The engine module uses the shared module, which its callers import first.
            Import-Module $ModulePath
            Import-Module $EngineModulePath
            $readFields = Get-GitHubOrgReadField
        }
        $known = @(@($operation.Operation.Fields.Keys) + @($readFields[$operation.Path]))
        $ok = if ($entry['responses'] -is [System.Collections.IDictionary]) { $entry['responses']['200'] } else { $null }
        $response = Get-ContentField -Content $ok
        $unknown = [string[]]@($response.Fields | Where-Object { $_ -cnotin $known })
        if ($response.Reason) {
            $differences.Add([pscustomobject]@{
                    Method = $operation.Method; Path = $operation.Path; Kind = 'response not comparable'; Issue = $false
                    Detail = "$($response.Reason); review its fields against ``Fields`` and the rows by hand."
                })
        }
        elseif ($unknown.Count) {
            $differences.Add([pscustomobject]@{
                    Method = $operation.Method; Path = $operation.Path; Kind = 'response fields'; Issue = $false
                    Detail = "Response fields in the description that neither a row reads nor ``Fields`` lists: $(Format-FieldList -Field $unknown)."
                })
        }
    }
}
$sorted = @($differences | Sort-Object -Property @{ Expression = { $_.Path } }, @{ Expression = { $methodOrder.IndexOf($_.Method) } } -CaseSensitive)

# 3. The issues, read once before anything is written; 4. one new issue per operation without one.
$closed = [System.Collections.Generic.List[string]]::new()
$issues = if (-not $Report -and @($sorted | Where-Object { $_.Issue }).Count) { @(Get-LabeledIssue -Label $label) } else { @() }
foreach ($difference in $sorted) {
    $operation = "$($difference.Method) $($difference.Path)"
    $difference | Add-Member -NotePropertyName Status -NotePropertyValue $(
        if (-not $difference.Issue) {
            'report only'
        }
        elseif ($Report) {
            'report'
        }
        elseif ($existing = Find-DifferenceIssue -Issue $issues -Operation $operation -Signature (Get-DifferenceSignature -Difference $difference)) {
            $state = ([string]$existing.state).ToLowerInvariant()
            if ($state -ceq 'closed') {
                $closed.Add("- #$($existing.number) ``$operation``: $($difference.Kind)")
            }
            "$state #$($existing.number)"
        }
        else {
            $issue = @{
                Title            = "$($template.Title) $operation"
                Body             = "<!-- api-endpoint: $operation -->`n<!-- api-endpoint-difference: $(Get-DifferenceSignature -Difference $difference) -->`n``$operation``, REST API description ``$Version``: $($difference.Kind). $($difference.Detail)`n`n$($template.Body)"
                Label            = $template.Labels
                Assignee         = $template.Assignees
                Target           = $operation
                LabelDescription = 'Issue of tools/Invoke-ApiEndpointCheck.ps1'
            }
            if ($number = New-IssueFromTemplate @issue) { "opened #$number" } else { 'new' }
        }
    )
    Write-Host "$operation, $($difference.Kind): $($difference.Detail) [$($difference.Status)]"
}

$summary = @('## API endpoint catalog', '')
if ($sorted.Count) {
    Write-Host "API endpoint catalog against REST API description ${Version}: $($sorted.Count) operations differ"
    $summary += @("REST API description ``$Version``.", '', '| Operation | Difference | Status |', '|---|---|---|')
    $summary += @($sorted | ForEach-Object { "| ``$($_.Method) $($_.Path)`` | $($_.Kind) | $($_.Status) |" })
    if ($closed.Count) {
        $summary += @('', '### Closed without a catalog change', '', 'Closed issues of operations that still differ from the catalog:', '') + @($closed)
    }
}
else {
    Write-Host "API endpoint catalog against REST API description ${Version}: no change"
    $summary += "REST API description ``$Version``: no change."
}
Add-StepSummary -Line $summary
