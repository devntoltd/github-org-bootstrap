# Real modules on disk for the tests of the module loading: a mock of Get-Module cannot show which version
# Import-Module really loads. Dot-sourced by the test files; not a test file itself.

function Add-TestModule {
    # Writes <Root>/<Name>/<Version>/<Name>.psd1 and .psm1. The module exports Get-<Name without dots>Version, which
    # returns its version.
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version
    )

    $folder = Join-Path -Path $Root -ChildPath "$Name/$Version"
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $function = "Get-$($Name -replace '\W', '')Version"
    Set-Content -Path (Join-Path -Path $folder -ChildPath "$Name.psm1") -Value "function $function { '$Version' }"
    New-ModuleManifest -Path (Join-Path -Path $folder -ChildPath "$Name.psd1") -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport $function
}
