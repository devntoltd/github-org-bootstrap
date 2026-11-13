# The gh calls of a tools/ script under test, recorded by its 'Mock gh' in $script:TestGhCalls (one string[] per call).
# Dot-sourced in BeforeAll.

# Stand-in for the native command, so Pester can mock it on a machine without it.
function gh { }

# The recorded gh calls whose first two arguments are $Command ('issue create', 'label create', ...), as one list:
# the comma keeps a single call (a string[]) from being unrolled into its arguments.
function Get-GhCall {
    param([string]$Command)

    , @($script:TestGhCalls | Where-Object { ($_[0..1] -join ' ') -eq $Command })
}

# Every value that follows the option $Name in one recorded call.
function Get-GhOption {
    param([string[]]$Call, [string]$Name)

    for ($i = 0; $i -lt $Call.Count - 1; $i++) {
        if ($Call[$i] -eq $Name) { $Call[$i + 1] }
    }
}
