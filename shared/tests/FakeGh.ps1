# A native stand-in for the GitHub CLI, put on PATH by Register-TestNativeGh (NativeGh.ps1); not a test file itself.
# It runs as a separate process, so the caller gets what a real gh gives it: bytes on stdout and stderr, stdin and an
# exit code. Answers from routes.json next to it, by "<METHOD> <endpoint>" for 'gh api' and by the joined arguments
# otherwise ('--version'); records every call in calls.jsonl. Linux and macOS only: on Windows the gh.exe that
# NativeGh.ps1 builds does the same in C#, so a change here goes there too.
$ErrorActionPreference = 'Stop'

$arguments = [string[]]$args
$key = $arguments -join ' '
if ($arguments.Count -ge 4 -and $arguments[0] -eq 'api') {
    $key = "$($arguments[2]) $($arguments[3])"
}

# The body as bytes, decoded as UTF-8 like gh does: [Console]::In would decode it with the console code page.
$body = ''
if ($arguments -contains '--input') {
    $buffer = [System.IO.MemoryStream]::new()
    [Console]::OpenStandardInput().CopyTo($buffer)
    $body = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
}
$call = ConvertTo-Json -InputObject ([ordered]@{ Arguments = $arguments; Input = $body }) -Compress
Add-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'calls.jsonl') -Value $call -Encoding utf8

$routes = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'routes.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
$route = $routes[$key]
if ($null -eq $route) {
    $route = @{ ExitCode = 1; Error = "gh: Not Found (HTTP 404): $key" }
}

# UTF-8 bytes, as gh writes them whatever the console code page is.
foreach ($stream in @(@{ Text = $route['Output']; Stream = [Console]::OpenStandardOutput() }, @{ Text = $route['Error']; Stream = [Console]::OpenStandardError() })) {
    if ($stream.Text) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$($stream.Text)`n")
        $stream.Stream.Write($bytes, 0, $bytes.Length)
        $stream.Stream.Flush()
    }
}
exit [int]$route['ExitCode']
