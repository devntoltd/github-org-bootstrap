# Loading a config file. Dot-sourced into
# GitHubOrg.Common, so its functions share that module's scope (Pester -ModuleName GitHubOrg.Common mocks).

function Import-BootstrapConfig {
    <#
    .SYNOPSIS
    Reads a bootstrap JSON config file, validates it when Validate is given, and returns it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        # Returns the error messages of the config; created in the engine module, so it runs in that module's scope.
        [scriptblock]$Validate
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }

    # Shown with the account: a "No changes" result is only meaningful for the config that was read.
    Write-Host "Config:  $(Resolve-Path -LiteralPath $Path -Relative)"

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Config file is empty: $Path"
    }

    try {
        # -NoEnumerate: otherwise a root array of one object unwraps into that object and passes validation.
        # -DateKind String: otherwise an ISO date-time string becomes a [datetime] and fails as "must be a string".
        $config = $raw | ConvertFrom-Json -NoEnumerate -DateKind String -ErrorAction Stop
    }
    catch {
        throw "Failed to parse config '$Path': $($_.Exception.Message)"
    }
    if ($config -isnot [System.Management.Automation.PSCustomObject]) {
        throw "Config '$Path' must be a JSON object, got $(ConvertTo-Json -InputObject $config -Compress -Depth 1)."
    }
    if ($Validate) {
        $errors = @(& $Validate $config)
        if ($errors.Count -gt 0) {
            throw "Config '$Path' is invalid:`n" + (($errors | ForEach-Object { " - $_" }) -join "`n")
        }
    }
    return $config
}
