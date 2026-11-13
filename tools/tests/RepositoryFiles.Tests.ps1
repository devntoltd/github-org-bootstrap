BeforeDiscovery {
    $root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
    # Tracked files only: what CI checks out, not local leftovers.
    $script:powerShellFiles = @(git -C $root ls-files '*.ps1' '*.psm1' '*.psd1' | ForEach-Object { @{ File = $_; Path = Join-Path -Path $root -ChildPath $_ } })
    # Scripts whose help is the script's own: the file starts with it, after #Requires lines and blank lines.
    $script:helpScripts = @(foreach ($file in $script:powerShellFiles | Where-Object { $_.File -like '*.ps1' }) {
            $lines = @(Get-Content -Path $file.Path | Where-Object { $_.Trim() -and $_ -notmatch '^#Requires\b' })
            if ($lines.Count -gt 1 -and $lines[0].Trim() -eq '<#' -and $lines[1].Trim() -eq '.SYNOPSIS') {
                # The first line of the synopsis, which may go on over more lines.
                $file + @{ Synopsis = $lines[2].Trim() }
            }
        })
}

Describe 'PowerShell files' {
    # Discovery variables are not visible when the tests run, so the count is passed in.
    It 'are found' -ForEach @{ Count = $script:powerShellFiles.Count } {
        $Count | Should -BeGreaterThan 0
    }

    It '<File> is ASCII-only' -ForEach $script:powerShellFiles {
        $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
        $found = for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '[^\x00-\x7F]') {
                "line $($i + 1): '$($Matches[0])' (U+$(([int][char]$Matches[0]).ToString('X4')))"
            }
        }
        # A BOM is non-ASCII too; ReadAllLines drops it, so check the first bytes.
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $found = @('byte order mark') + @($found)
        }

        $found | Should -BeNullOrEmpty -Because "$File must be ASCII-only (CONTRIBUTING.md > Code rules)"
    }

    It 'finds scripts with help' -ForEach @{ Count = $script:helpScripts.Count } {
        $Count | Should -BeGreaterThan 0
    }

    # Get-Help shows only the syntax when the help does not parse, e.g. a help block right after #Requires with no
    # blank line between them.
    It '<File> has help that Get-Help reads' -ForEach $script:helpScripts {
        ([string](Get-Help -Name $Path).Synopsis).StartsWith($Synopsis) | Should -BeTrue -Because "Get-Help should show '$Synopsis'"
    }
}

Describe 'Engine files' {
    It 'hold no issue references, since they are copied into a repository where the numbers mean other issues' {
        $root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
        # The engine and the shared code: issue numbers of the repository it came from would point at other issues here.
        # The READMEs are docs; settings.md and github.schema.json are generated from the rows.
        $files = @(git -C $root ls-files 'engine' 'shared/src' 'shared/tests' 'shared/Bootstrap.Common.psm1' |
                Where-Object { $_ -notin 'engine/README.md', 'engine/github.json', 'engine/settings.md', 'engine/github.schema.json' })
        $found = @(foreach ($file in $files) {
                Select-String -LiteralPath (Join-Path -Path $root -ChildPath $file) -Pattern '(?<![\w&])#\d+\b' |
                    ForEach-Object { "${file}:$($_.LineNumber): $($_.Matches[0].Value)" }
            })

        $found | Should -BeNullOrEmpty
    }
}

Describe 'Decision index' {
    BeforeAll {
        $root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')
        $script:specs = Join-Path -Path $root -ChildPath 'docs/decisions'
        # Tracked files only, as above; every dated file is a decision, whatever its suffix.
        $script:files = @(git -C $root ls-files 'docs/decisions/2*.md' | Split-Path -Leaf | Sort-Object)
        $rowPattern = '^\|\s*(?<date>\d{4}-\d{2}-\d{2})\s*\|\s*\[[^\]]+\]\((?<file>[^)#]+)\)[^|]*\|\s*(?<status>[a-z]+)\s*\|'
        $script:rows = @(foreach ($line in Get-Content -Path (Join-Path -Path $specs -ChildPath 'README.md')) {
                if ($line -match $rowPattern) { [pscustomobject]@{ File = $Matches.file; Date = $Matches.date; Status = $Matches.status } }
            })
    }

    It 'lists every design once' {
        $files.Count | Should -BeGreaterThan 0
        @($rows.File | Sort-Object) | Should -Be $files
    }

    # The file names start with the date, so their order is the order of date, then name.
    It 'lists the designs in order of date, then file name' {
        @($rows.File) | Should -Be $files
    }

    It 'shows the date and status of each design' {
        $found = foreach ($row in $rows) {
            $lines = Get-Content -Path (Join-Path -Path $specs -ChildPath $row.File)
            $date = ($lines -match '^Date:\s*') -replace '^Date:\s*' | Select-Object -First 1
            $status = ($lines -match '^Status:\s*') -replace '^Status:\s*' | Select-Object -First 1
            if ($date -ne $row.Date -or $status -ne $row.Status) { "$($row.File): index $($row.Date) $($row.Status), spec $date $status" }
        }
        $found | Should -BeNullOrEmpty
    }
}
