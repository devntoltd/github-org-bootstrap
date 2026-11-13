# Real modules on disk for the tests of the module loading: a mock of Get-Module cannot show which version
# Import-Module really loads. Dot-sourced by the test files; not a test file itself.

function Add-TestModule {
    # Writes <Root>/<Name>/<Version>/<Name>.psd1 and .psm1. The module exports Get-<Name without dots>Version, which
    # returns its version. Each name in ImportOnLoad is imported by the .psm1 when no version of it is loaded, the newest
    # installed, globally: what the Az modules do with Az.Accounts. Announce makes the .psm1 print 'Loaded <Name>
    # <Version>', for the tests that run a child pwsh.
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [string[]]$ImportOnLoad = @(),
        [switch]$Announce
    )

    $folder = Join-Path -Path $Root -ChildPath "$Name/$Version"
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $function = "Get-$($Name -replace '\W', '')Version"
    $lines = @(
        foreach ($dependency in $ImportOnLoad) {
            "if (-not (Get-Module -Name '$dependency')) { Import-Module -Name '$dependency' -MinimumVersion 0.0.1 -Scope Global }"
        }
        "function $function { '$Version' }"
        if ($Announce) { "Write-Host 'Loaded $Name $Version'" }
    )
    Set-Content -Path (Join-Path -Path $folder -ChildPath "$Name.psm1") -Value $lines
    New-ModuleManifest -Path (Join-Path -Path $folder -ChildPath "$Name.psd1") -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport $function
}
