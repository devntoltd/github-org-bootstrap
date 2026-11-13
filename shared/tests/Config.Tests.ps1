BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../Bootstrap.Common.psm1') -Force
}

Describe 'Import-BootstrapConfig' {
    BeforeEach {
        Mock -ModuleName Bootstrap.Common Write-Host { }
    }

    It 'shows which config file it read, relative to the current directory' {
        $path = Join-Path -Path $TestDrive -ChildPath 'shown.json'
        '{ "tenantId": "abc" }' | Set-Content -Path $path -Encoding utf8
        Push-Location -LiteralPath $TestDrive
        try {
            Import-BootstrapConfig -Path $path | Out-Null
        }
        finally {
            Pop-Location
        }

        Should -Invoke Write-Host -ModuleName Bootstrap.Common -Times 1 -Exactly -ParameterFilter {
            $Object -in @('Config:  ./shown.json', 'Config:  .\shown.json')
        }
    }

    It 'reads a JSON file' {
        $path = Join-Path -Path $TestDrive -ChildPath 'config.json'
        '{ "tenantId": "abc" }' | Set-Content -Path $path -Encoding utf8

        (Import-BootstrapConfig -Path $path).tenantId | Should -Be 'abc'
    }

    It 'returns the config when the validation finds nothing' {
        $path = Join-Path -Path $TestDrive -ChildPath 'valid.json'
        '{ "tenantId": "abc" }' | Set-Content -Path $path -Encoding utf8

        (Import-BootstrapConfig -Path $path -Validate { @() }).tenantId | Should -Be 'abc'
    }

    It 'passes the config to the validation and throws every error it returns' {
        $path = Join-Path -Path $TestDrive -ChildPath 'invalid.json'
        '{ "tenantId": "abc" }' | Set-Content -Path $path -Encoding utf8

        { Import-BootstrapConfig -Path $path -Validate { param($config) "tenantId '$($config.tenantId)' is bad."; 'name is required.' } } |
            Should -Throw "Config '$path' is invalid:`n - tenantId 'abc' is bad.`n - name is required."
    }

    It 'throws a single error of the validation' {
        $path = Join-Path -Path $TestDrive -ChildPath 'one-error.json'
        '{ "tenantId": "abc" }' | Set-Content -Path $path -Encoding utf8

        { Import-BootstrapConfig -Path $path -Validate { 'name is required.' } } | Should -Throw '*is invalid:*name is required.'
    }

    It 'reads non-ASCII text from a UTF-8 file with BOM' {
        $name = "$([char]0x0421)$([char]0x0435)$([char]0x043D)$([char]0x044E)"
        $path = Join-Path -Path $TestDrive -ChildPath 'bom.json'
        "{ `"displayName`": `"$name`" }" | Set-Content -Path $path -Encoding utf8BOM

        (Import-BootstrapConfig -Path $path).displayName | Should -Be $name
    }

    It 'keeps a date-time value as the string the operator wrote' {
        $path = Join-Path -Path $TestDrive -ChildPath 'date.json'
        '{ "expiresOn": "2027-04-01T00:00:00Z" }' | Set-Content -Path $path -Encoding utf8

        $value = (Import-BootstrapConfig -Path $path).expiresOn

        $value | Should -BeOfType [string]
        $value | Should -Be '2027-04-01T00:00:00Z'
    }

    It 'fails with the path when the file is missing' {
        $path = Join-Path -Path $TestDrive -ChildPath 'missing.json'

        { Import-BootstrapConfig -Path $path } | Should -Throw '*Config file not found*missing.json*'
    }

    It 'fails when the file is empty' {
        $path = Join-Path -Path $TestDrive -ChildPath 'empty.json'
        '' | Set-Content -Path $path -Encoding utf8

        { Import-BootstrapConfig -Path $path } | Should -Throw '*Config file is empty*'
    }

    It 'rejects a root that is not an object: <Json>' -ForEach @(
        @{ Json = '[ { "tenantId": "abc" } ]' }
        @{ Json = '[]' }
        @{ Json = '"text"' }
        @{ Json = '42' }
    ) {
        $path = Join-Path -Path $TestDrive -ChildPath 'root.json'
        $Json | Set-Content -Path $path -Encoding utf8

        { Import-BootstrapConfig -Path $path } | Should -Throw '*root.json*must be a JSON object*'
    }

    It 'shows a root that is not an object only one level deep' {
        $path = Join-Path -Path $TestDrive -ChildPath 'nested.json'
        '[ { "tenantId": "abc", "scope": { "name": "x" } } ]' | Set-Content -Path $path -Encoding utf8

        # -Be, not Should -Throw: its wildcard match reads '[]' as a pattern.
        $message = try { Import-BootstrapConfig -Path $path -WarningAction SilentlyContinue; 'no error' } catch { $_.Exception.Message }

        $message | Should -Be "Config '$path' must be a JSON object, got [{`"tenantId`":`"abc`",`"scope`":`"@{name=x}`"}]."
    }

    It 'fails with the path when JSON is invalid' {
        $path = Join-Path -Path $TestDrive -ChildPath 'broken.json'
        '{ not json' | Set-Content -Path $path -Encoding utf8

        { Import-BootstrapConfig -Path $path } | Should -Throw '*Failed to parse config*broken.json*'
    }
}
