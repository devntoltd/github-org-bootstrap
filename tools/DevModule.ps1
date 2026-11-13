# Loads the PowerShell modules of the checks at the exact versions of dev-tools.psd1; dot-sourced by the scripts in
# tools/ that use them, not runnable on its own. PowerShell would otherwise autoload the newest installed version.

# Imports, globally, exactly the version of dev-tools.psd1 of each module in $Name; throws when it is not installed or
# another version is already loaded.
function Import-DevModule {
    param(
        [Parameter(Mandatory)][string[]]$Name,
        [string]$Path = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'dev-tools.psd1')
    )

    $modules = (Import-PowerShellDataFile -Path $Path).Modules
    foreach ($moduleName in $Name) {
        if (-not $modules.Contains($moduleName)) {
            throw "$moduleName is not in the Modules of dev-tools.psd1."
        }
        $version = [version]$modules[$moduleName]
        $loaded = Get-Module -Name $moduleName | Where-Object { $_.Version -ne $version } | Select-Object -First 1
        if ($loaded) {
            throw "$moduleName $($loaded.Version) is loaded in this session, not $version of dev-tools.psd1; start a new pwsh."
        }
        if (-not (Get-Module -ListAvailable -Name $moduleName | Where-Object { $_.Version -eq $version })) {
            throw "$moduleName $version (dev-tools.psd1) is not installed; run ./tools/Install-DevTools.ps1."
        }
        Import-Module -Name $moduleName -RequiredVersion $version -Global
    }
}
