# The one config error of $Path among $Errors, holding every part of $Part; fails otherwise. The wording of the shape
# errors is checked in shared/tests, so a stage test passes only the parts it is about: the value, the allowed values,
# a rule of its own. The path is compared as text: '[' and '*' in a path are no wildcards. -Only: it is the only error.
function Assert-ConfigError {
    param([string[]]$Errors, [string]$Path, [string[]]$Part = @(), [switch]$Only)

    if ($Only) {
        $Errors | Should -HaveCount 1 -Because "the error of $Path is expected to be the only one, the errors are: $($Errors -join ' | ')"
    }
    $found = @($Errors | Where-Object { $_.StartsWith("$Path ", [StringComparison]::Ordinal) -or $_.StartsWith("${Path}:", [StringComparison]::Ordinal) })
    $found | Should -HaveCount 1 -Because "one error is expected for $Path, the errors are: $($Errors -join ' | ')"
    # After the path: a value that is also a key of the path ('sub dev!' in subscriptions['sub dev!'].alias) is in the
    # error once more only when the error names it.
    $rest = $found[0].Substring($Path.Length)
    foreach ($text in $Part) {
        $rest.Contains($text) | Should -BeTrue -Because "the error of $Path should contain '$text' after the path: $($found[0])"
    }
}
