# A fake GitHub REST API behind the gh stub: an in-memory store, so a write changes what a later read returns.
# For round-trip tests (apply, then read again); call-by-call answers stay with Register-TestGhStub.
# Dot-sourced by the test files; not a test file itself.

. (Join-Path -Path $PSScriptRoot -ChildPath 'GhStub.ps1')

function ConvertTo-TestGhFakeEndpoint {
    # The store key of an endpoint: per_page only sizes the pages, so it is left out.
    param([Parameter(Mandatory)][string]$Endpoint)

    $parts = $Endpoint.Split('?', 2)
    if ($parts.Count -eq 1) {
        return $Endpoint
    }
    $query = @($parts[1].Split('&') | Where-Object { $_ -and $_ -notmatch '^per_page=' })
    if ($query.Count -eq 0) {
        return $parts[0]
    }
    return "$($parts[0])?$($query -join '&')"
}

function ConvertTo-TestGhFakeValue {
    # A value as a JSON response parses: objects become PSCustomObjects, lists stay lists.
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    return , (ConvertTo-Json -InputObject $Value -Depth 10 -Compress | ConvertFrom-Json -NoEnumerate)
}

function Get-TestGhFakeResponse {
    # A gh answer from a handler: Output as gh prints it ('' for 202 Accepted or 204 No Content).
    param(
        [AllowEmptyString()][string]$Output = '',
        [int]$ExitCode = 0
    )
    [pscustomobject]@{ PSTypeName = 'TestGhFakeResponse'; ExitCode = $ExitCode; Output = $Output }
}

function Get-TestGhFakeError {
    # A failed gh call from a handler, such as 'gh: Conflict (HTTP 409)'.
    param([Parameter(Mandatory)][string]$Message)
    Get-TestGhFakeResponse -Output $Message -ExitCode 1
}

function Register-TestGhFake {
    <#
    .SYNOPSIS
    Replaces gh with a fake API over a store of endpoint -> response object.
    .DESCRIPTION
    GET returns the stored object ($null: 204 No Content; with --paginate, gh's --slurp form of one page), PUT
    replaces it, PATCH merges the body into it; an endpoint that is not in the store answers 404, and so does every
    other method. Handler: an ordered map of regex on "<METHOD> <endpoint>" -> scriptblock, tried first, for what
    the generic rules do not cover (POST, conflicts, writes that change other endpoints). It gets the store and the
    request ({Method; Endpoint; Body; Match}) and returns an object (200 with it as JSON), a Get-TestGhFakeResponse
    or Get-TestGhFakeError, or nothing to fall back to the generic rules. Endpoints are compared without per_page.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The store must outlive the call so tests can read it.')]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Resource,
        [System.Collections.IDictionary]$Handler = [ordered]@{}
    )

    $global:TestGhFakeStore = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $Resource.Keys) {
        $global:TestGhFakeStore[(ConvertTo-TestGhFakeEndpoint -Endpoint $key)] = ConvertTo-TestGhFakeValue -Value $Resource[$key]
    }
    $handlers = $Handler
    # The closure sees variables, not the functions of the test scope.
    $normalize = ${function:ConvertTo-TestGhFakeEndpoint}
    $responder = {
        param([string[]]$Arguments, [string]$InputText)

        $store = $global:TestGhFakeStore
        $method = $Arguments[2]
        $endpoint = & $normalize -Endpoint $Arguments[3]
        $body = $null
        if ($InputText) {
            $body = $InputText | ConvertFrom-Json
        }
        $notFound = [pscustomobject]@{ ExitCode = 1; Output = "gh: Not Found (HTTP 404): $method $endpoint" }

        foreach ($pattern in $handlers.Keys) {
            if ("$method $endpoint" -notmatch $pattern) {
                continue
            }
            $request = [pscustomobject]@{ Method = $method; Endpoint = $endpoint; Body = $body; Match = $Matches.Clone() }
            $result = & $handlers[$pattern] $store $request
            if ($null -eq $result) {
                break
            }
            if ($result.PSObject.TypeNames -contains 'TestGhFakeResponse') {
                return $result
            }
            return [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject $result -Depth 10 -Compress) }
        }

        if (-not $store.ContainsKey($endpoint)) {
            return $notFound
        }
        switch ($method) {
            'GET' {
                $value = $store[$endpoint]
                if ($null -eq $value) {
                    return [pscustomobject]@{ ExitCode = 0; Output = '' }
                }
                if ($Arguments -contains '--paginate') {
                    $value = , $value
                }
                return [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject $value -Depth 10 -Compress) }
            }
            'PUT' {
                $store[$endpoint] = $body
                return [pscustomobject]@{ ExitCode = 0; Output = '' }
            }
            'PATCH' {
                $stored = $store[$endpoint]
                foreach ($property in $body.PSObject.Properties) {
                    $stored | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                }
                return [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject $stored -Depth 10 -Compress) }
            }
        }
        return $notFound
    }.GetNewClosure()
    Register-TestGhStub -Responder $responder
}

function Get-TestGhFakeResource {
    # The object the fake stores for an endpoint.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Reads the store of the fake.')]
    param([Parameter(Mandatory)][string]$Endpoint)
    $global:TestGhFakeStore[(ConvertTo-TestGhFakeEndpoint -Endpoint $Endpoint)]
}

function Unregister-TestGhFake {
    Unregister-TestGhStub
    Remove-Variable -Name TestGhFakeStore -Scope Global -ErrorAction SilentlyContinue
}
