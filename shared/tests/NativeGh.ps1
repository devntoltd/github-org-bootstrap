# The GitHub CLI replaced by a native program on PATH, for tests that need what Register-TestGhStub (GhStub.ps1)
# bypasses: the decoding of native output, stderr, stdin and exit codes, or a child process (the bootstrap.ps1 smoke
# tests). Dot-sourced by the test files; not a test file itself. On Linux and macOS each call starts a pwsh, so keep
# these tests few.

function Register-TestNativeGh {
    # Puts a gh program in $Directory first on PATH: on Linux and macOS an executable shell script that runs FakeGh.ps1
    # with the current pwsh, on Windows an exe that does what FakeGh.ps1 does (a gh.cmd would break on the '&' of query
    # strings).
    param(
        [Parameter(Mandatory)][string]$Directory,
        [hashtable]$Route = @{}
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    if ($IsWindows) {
        # FakeGh.ps1 ported to C# 5 (the compiler of .NET Framework 4): a pwsh started per call takes about a second on
        # Windows, this about 0.2 s. The two keep the same contract, which the native gh tests check on each
        # platform. Arguments come split by the Windows rules, as gh gets them.
        $source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
class FakeGh {
    static int Main() {
        string[] all = Environment.GetCommandLineArgs();
        string[] arguments = new string[all.Length - 1];
        Array.Copy(all, 1, arguments, 0, arguments.Length);
        string key = arguments.Length >= 4 && arguments[0] == "api" ? arguments[2] + " " + arguments[3] : string.Join(" ", arguments);

        // The body as bytes, decoded as UTF-8 like gh does.
        string body = "";
        if (Array.IndexOf(arguments, "--input") >= 0) {
            MemoryStream buffer = new MemoryStream();
            Console.OpenStandardInput().CopyTo(buffer);
            body = Encoding.UTF8.GetString(buffer.ToArray());
        }
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        UTF8Encoding utf8 = new UTF8Encoding(false);
        JavaScriptSerializer json = new JavaScriptSerializer();
        json.MaxJsonLength = int.MaxValue;
        Dictionary<string, object> call = new Dictionary<string, object>();
        call["Arguments"] = arguments;
        call["Input"] = body;
        File.AppendAllText(Path.Combine(directory, "calls.jsonl"), json.Serialize(call) + "\n", utf8);

        Dictionary<string, object> routes = json.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(directory, "routes.json"), utf8));
        object found;
        Dictionary<string, object> route = routes.TryGetValue(key, out found) ? found as Dictionary<string, object> : null;
        if (route == null) {
            route = new Dictionary<string, object>();
            route["ExitCode"] = 1;
            route["Error"] = "gh: Not Found (HTTP 404): " + key;
        }

        // UTF-8 bytes, as gh writes them whatever the console code page is.
        Write(route, "Output", Console.OpenStandardOutput(), utf8);
        Write(route, "Error", Console.OpenStandardError(), utf8);
        object code;
        return route.TryGetValue("ExitCode", out code) && code != null ? Convert.ToInt32(code) : 0;
    }

    static void Write(Dictionary<string, object> route, string name, Stream stream, Encoding encoding) {
        object text;
        if (route.TryGetValue(name, out text) && text != null && text.ToString().Length > 0) {
            byte[] bytes = encoding.GetBytes(text.ToString() + "\n");
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }
    }
}
'@
        $sourcePath = Join-Path -Path $Directory -ChildPath 'FakeGh.cs'
        Set-Content -LiteralPath $sourcePath -Value $source -Encoding utf8
        # The C# compiler of .NET Framework 4, part of every Windows installation.
        $csc = Join-Path -Path $env:WINDIR -ChildPath 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        $output = & $csc /nologo /target:exe /reference:System.Web.Extensions.dll "/out:$(Join-Path -Path $Directory -ChildPath 'gh.exe')" $sourcePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not build the fake gh.exe: $($output -join "`n")"
        }
    }
    else {
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'FakeGh.ps1') -Destination $Directory
        $pwsh = (Get-Process -Id $PID).Path
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
