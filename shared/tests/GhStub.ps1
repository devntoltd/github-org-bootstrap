# The gh CLI replaced by a global function, for the tests of everything that calls GitHub through Invoke-GhApi,
# with the responses gh prints (objects, lists read page by page) and routes that answer by method and endpoint.
# Dot-sourced by the test files; not a test file itself.

function Register-TestGhStub {
    # Replaces the gh CLI with a global function (the module under test must see it): records every call and
    # answers with the output of $Responder, which gets the gh arguments ([string[]]) and the stdin text (the request
    # body, '' without one) and returns @{ ExitCode; Output }.
    # Each '--header <value>' pair is recorded in Headers and left out of Arguments: the API version header goes with
    # every call, and only the test of Invoke-GhApi checks it.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The stub must be visible from the module under test.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '', Justification = 'Emulates the exit code of a native command.')]
    param(
        [scriptblock]$Responder = { [pscustomobject]@{ ExitCode = 0; Output = '{}' } }
    )

    $global:TestGhCalls = [System.Collections.Generic.List[object]]::new()
    $global:TestGhResponder = $Responder
    # No [CmdletBinding()]: a simple function keeps every argument (including '--method') in $args.
    function global:gh {
        $arguments = [System.Collections.Generic.List[string]]::new()
        $headers = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $args.Count; $i++) {
            if ($args[$i] -eq '--header') {
                $i++
                $headers.Add([string]$args[$i])
            }
            else {
                $arguments.Add([string]$args[$i])
            }
        }
        $arguments = $arguments.ToArray()
        $inputText = @($input) -join "`n"
        $global:TestGhCalls.Add([pscustomobject]@{ Arguments = $arguments; Headers = $headers.ToArray(); Input = $inputText })
        $response = & $global:TestGhResponder $arguments $inputText
        $global:LASTEXITCODE = $response.ExitCode
        $response.Output
    }
}

function Get-TestGhCall {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Reads what the gh stub recorded.')]
    param()
    $global:TestGhCalls.ToArray()
}

function Unregister-TestGhStub {
    # 'Function:gh', not 'function:global:gh': the provider has no scope qualifier, so that path never matched
    # and the stub outlived the test, shadowing a native gh on PATH.
    Remove-Item -Path 'Function:gh' -ErrorAction SilentlyContinue
    Remove-Variable -Name TestGhCalls, TestGhResponder -Scope Global -ErrorAction SilentlyContinue
}

function Get-TestGhResponse {
    # A successful gh answer carrying the object as JSON.
    param([Parameter(Mandatory)][object]$Body)
    [pscustomobject]@{ ExitCode = 0; Output = ($Body | ConvertTo-Json -Depth 10 -Compress) }
}

function Get-TestGhListResponse {
    # A successful gh answer carrying a JSON array, also for zero or one item.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items)
    [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject @($Items) -Depth 6 -Compress) }
}

function Get-TestGhPagesResponse {
    # What gh api --paginate --slurp prints: the items split into pages, wrapped in one outer array.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [int]$PageSize = 100
    )

    $pages = [System.Collections.Generic.List[object]]::new()
    for ($start = 0; $start -lt $Items.Count; $start += $PageSize) {
        $pages.Add([object[]]@($Items | Select-Object -Skip $start -First $PageSize))
    }
    if ($pages.Count -eq 0) {
        $pages.Add([object[]]@())
    }
    [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject $pages -Depth 8 -Compress); Paginated = $true }
}

function Get-TestGhObjectPagesResponse {
    # What gh api --paginate --slurp prints for a list whose every page is an object holding the items in a property,
    # with the total count beside it (orgs/{org}/installations, repos/{repo}/actions/variables).
    param(
        [Parameter(Mandatory)][string]$Property,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [int]$PageSize = 100
    )

    $pages = [System.Collections.Generic.List[object]]::new()
    for ($start = 0; $start -lt $Items.Count; $start += $PageSize) {
        $pages.Add([pscustomobject]@{ total_count = $Items.Count; $Property = [object[]]@($Items | Select-Object -Skip $start -First $PageSize) })
    }
    if ($pages.Count -eq 0) {
        $pages.Add([pscustomobject]@{ total_count = 0; $Property = [object[]]@() })
    }
    [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject $pages -Depth 8 -Compress); Paginated = $true }
}

function Register-TestGhRoute {
    # The gh stub answering by "<METHOD> <endpoint>" (a call other than gh api, such as '--version', by its arguments);
    # any other call fails the way gh does for an unknown endpoint.
    # A list (a response from Get-TestGh*PagesResponse) answers only a call that reads every page: without
    # --paginate, gh returns the first page alone and a run misses the rest without an error.
    param([Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Route)

    $routes = $Route
    $responder = {
        param([string[]]$Arguments)
        $key = if ($Arguments[0] -eq 'api') { "$($Arguments[2]) $($Arguments[3])" } else { $Arguments -join ' ' }
        if ($routes.ContainsKey($key)) {
            $response = $routes[$key]
            if ($response.PSObject.Properties['Paginated'] -and $Arguments -notcontains '--paginate') {
                return [pscustomobject]@{ ExitCode = 1; Output = "test: $key is a list; read it with -Paginate" }
            }
            return $response
        }
        [pscustomobject]@{ ExitCode = 1; Output = "gh: Not Found (HTTP 404): $key" }
    }.GetNewClosure()
    Register-TestGhStub -Responder $responder
}
