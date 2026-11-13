# Exact versions of the developer's tools, installed by tools/Install-DevTools.ps1. Dependabot does not update them; the
# weekly recurring.yml opens an issue for newer versions (tools/Invoke-DependencyUpdateCheck.ps1).
@{
    # PowerShell modules of the checks: name -> version. tools/Invoke-Coverage.ps1 and tools/Invoke-Lint.ps1 load
    # exactly these. Not read by the engine, whose runtime modules (none) are in modules.lock.psd1.
    Modules = @{
        'Pester'           = '6.2.0'
        'PSScriptAnalyzer' = '1.25.0'
    }
    # Command-line tools of the checks: command -> winget package, the version .github/workflows/ci.yml pins (a test
    # keeps both equal) and the GitHub repository of its releases.
    Tools   = @{
        'actionlint'           = @{ WinGetId = 'rhysd.actionlint'; Version = '1.7.12'; Repository = 'rhysd/actionlint' }
        'betterleaks'          = @{ WinGetId = 'Betterleaks.Betterleaks'; Version = '1.9.0'; Repository = 'betterleaks/betterleaks' }
        'editorconfig-checker' = @{ WinGetId = 'EditorConfig-Checker.EditorConfig-Checker'; Version = '4.0.2'; Repository = 'editorconfig-checker/editorconfig-checker' }
        'lychee'               = @{ WinGetId = 'lycheeverse.lychee'; Version = '0.24.2'; Repository = 'lycheeverse/lychee' }
        # actionlint runs it on the run: scripts of the workflows only when it is installed, and skips them silently otherwise.
        'shellcheck'           = @{ WinGetId = 'koalaman.shellcheck'; Version = '0.11.0'; Repository = 'koalaman/shellcheck' }
        'zizmor'               = @{ WinGetId = 'zizmor.zizmor'; Version = '1.31.1'; Repository = 'zizmorcore/zizmor' }
    }
}
