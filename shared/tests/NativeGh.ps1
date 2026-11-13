# The GitHub CLI replaced by a native program on PATH, for tests that need what Register-TestGhStub (GhStub.ps1)
# bypasses: the decoding of native output, stderr, stdin and exit codes, or a child process (the bootstrap.ps1 smoke
# tests). Dot-sourced by the test files; not a test file itself. Each call starts a pwsh, so keep these tests few.

function Register-TestNativeGh {
    # Puts a gh program in $Directory first on PATH: an executable shell script on Linux and macOS, a small launcher
    # exe on Windows (a gh.cmd would break on the '&' of query strings). Both run FakeGh.ps1 with the current pwsh.
    param(
        [Parameter(Mandatory)][string]$Directory,
        [hashtable]$Route = @{}
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'FakeGh.ps1') -Destination $Directory
    $pwsh = (Get-Process -Id $PID).Path
    if ($IsWindows) {
        # The raw command line after the program name goes to pwsh unchanged, so arguments arrive as gh would get them.
        $source = @"
using System;
using System.Diagnostics;
class FakeGh {
    static int Main() {
        string line = Environment.CommandLine;
        int end = line.StartsWith("\"") ? line.IndexOf('"', 1) + 1 : line.IndexOf(' ');
        string rest = end < 0 ? "" : line.Substring(end);
        string script = AppDomain.CurrentDomain.BaseDirectory + "FakeGh.ps1";
        ProcessStartInfo start = new ProcessStartInfo(@"$pwsh", "-NoProfile -NonInteractive -File \"" + script + "\"" + rest);
        start.UseShellExecute = false;
        Process process = Process.Start(start);
        process.WaitForExit();
        return process.ExitCode;
    }
}
"@
        $sourcePath = Join-Path -Path $Directory -ChildPath 'FakeGh.cs'
        Set-Content -LiteralPath $sourcePath -Value $source -Encoding utf8
        # The C# compiler of .NET Framework 4, part of every Windows installation.
        $csc = Join-Path -Path $env:WINDIR -ChildPath 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        $output = & $csc /nologo /target:exe "/out:$(Join-Path -Path $Directory -ChildPath 'gh.exe')" $sourcePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not build the fake gh.exe: $($output -join "`n")"
        }
    }
    else {
        $wrapper = Join-Path -Path $Directory -ChildPath 'gh'
        $text = "#!/bin/sh`nexec '$pwsh' -NoProfile -NonInteractive -File `"`$(dirname `"`$0`")/FakeGh.ps1`" `"`$@`"`n"
        [System.IO.File]::WriteAllText($wrapper, $text)
        & chmod +x $wrapper
    }
    Set-TestNativeGhRoute -Directory $Directory -Route $Route

    $script:TestNativeGhPath = $env:PATH
    $env:PATH = $Directory + [System.IO.Path]::PathSeparator + $env:PATH

    # A function wins over a program: a gh stub left by another test would quietly replace the fake.
    $command = Get-Command -Name gh
    if ($command.CommandType -ne 'Application' -or (Split-Path -Path $command.Source -Parent) -ne $Directory) {
        throw "gh resolves to $($command.CommandType) '$($command.Source)', not the fake in $Directory; a test left a gh stub behind."
    }
}

function Set-TestNativeGhRoute {
    # The answers of the fake: "<METHOD> <endpoint>" or the joined arguments -> @{ ExitCode; Output; Error }; any
    # other call fails like gh does for an unknown endpoint. '--version' answers a current gh unless set.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes a file of the test drive.')]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Route
    )

    $routes = @{ '--version' = @{ ExitCode = 0; Output = 'gh version 2.101.0 (2026-09-15)' } }
    foreach ($key in $Route.Keys) {
        $routes[$key] = $Route[$key]
    }
    $routes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path -Path $Directory -ChildPath 'routes.json') -Encoding utf8
    Remove-Item -LiteralPath (Join-Path -Path $Directory -ChildPath 'calls.jsonl') -ErrorAction SilentlyContinue
}

function Get-TestNativeGhCall {
    # The calls the fake recorded since its routes were set: { Arguments; Input }.
    param([Parameter(Mandatory)][string]$Directory)

    $path = Join-Path -Path $Directory -ChildPath 'calls.jsonl'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }
    Get-Content -LiteralPath $path -Encoding utf8 | ForEach-Object { $_ | ConvertFrom-Json }
}

function Unregister-TestNativeGh {
    if ($null -ne $script:TestNativeGhPath) {
        $env:PATH = $script:TestNativeGhPath
        $script:TestNativeGhPath = $null
    }
}
