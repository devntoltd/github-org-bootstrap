BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../Bootstrap.Common.psm1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'ConfigError.ps1')

    function Get-TestShape {
        @{
            Type   = 'object'
            Fields = [ordered]@{
                id       = @{ Type = 'string'; Pattern = '^[a-z-]+$'; Rule = "lower-case letters and '-'" }
                parent   = @{ Type = 'string'; Nullable = $true }
                enabled  = @{ Type = 'boolean' }
                mode     = @{ Type = 'enum'; Values = @('strict', 'loose') }
                days     = @{ Type = 'integer'; Minimum = 1 }
                tags     = @{ Type = 'array'; Unique = $true; Items = @{ Type = 'string' } }
                children = @{
                    Type = 'array'; MinItems = 1; ItemKey = 'name'; Unique = $true
                    Items = @{ Type = 'object'; Fields = [ordered]@{ name = @{ Type = 'string' }; size = @{ Type = 'integer' } } }
                }
                rights   = @{ Type = 'map'; KeyPattern = '^[a-z_]+$'; KeyRule = "lower-case letters and '_'"; Value = @{ Type = 'enum'; Values = @('read', 'write') } }
                nested   = @{ Type = 'object'; Nullable = $true; Fields = [ordered]@{ flag = @{ Type = 'boolean' } } }
            }
        }
    }

    function Get-TestShapeConfig {
        @'
{
  "id": "alpha",
  "parent": null,
  "enabled": true,
  "mode": "strict",
  "days": 30,
  "tags": [],
  "children": [ { "name": "one", "size": 1 } ],
  "rights": { "contents": "read" },
  "nested": { "flag": false }
}
'@ | ConvertFrom-Json
    }
}

Describe 'Test-ConfigShape' {
    It 'accepts a valid config' {
        Test-ConfigShape -Config (Get-TestShapeConfig) -Shape (Get-TestShape) | Should -BeNullOrEmpty
    }

    It 'reports an integer above its maximum and accepts the maximum' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ count = @{ Type = 'integer'; Minimum = 0; Maximum = 10 } } }

        Test-ConfigShape -Config ('{ "count": 11 }' | ConvertFrom-Json) -Shape $shape | Should -Be 'count must be at most 10, got 11.'
        Test-ConfigShape -Config ('{ "count": 10 }' | ConvertFrom-Json) -Shape $shape | Should -BeNullOrEmpty
    }

    It 'accepts a top-level $schema and nothing else that is unknown' {
        $config = Get-TestShapeConfig
        $config | Add-Member -NotePropertyName '$schema' -NotePropertyValue './x.schema.json'

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -BeNullOrEmpty
    }

    It 'reports <Name>' -ForEach @(
        @{ Name = 'a missing key'; Mutate = { param($c) $c.PSObject.Properties.Remove('days') }; Expected = 'days is required.' }
        @{ Name = 'an unknown key'; Mutate = { param($c) $c | Add-Member -NotePropertyName extra -NotePropertyValue 1 }; Expected = 'extra is not a supported key.' }
        @{ Name = 'an unknown nested key'; Mutate = { param($c) $c.nested | Add-Member -NotePropertyName other -NotePropertyValue 1 }; Expected = 'nested.other is not a supported key.' }
        @{ Name = 'a missing nested key'; Mutate = { param($c) $c.nested.PSObject.Properties.Remove('flag') }; Expected = 'nested.flag is required.' }
        @{ Name = 'null where not allowed'; Mutate = { param($c) $c.mode = $null }; Expected = 'mode must not be null.' }
        @{ Name = 'a string that is not a string'; Mutate = { param($c) $c.id = 5 }; Expected = 'id must be a string, got 5.' }
        @{ Name = 'a string that breaks its pattern'; Mutate = { param($c) $c.id = 'Alpha' }; Expected = "id must be lower-case letters and '-', got 'Alpha'." }
        @{ Name = 'a string with a trailing newline'; Mutate = { param($c) $c.id = "alpha`n" }; Expected = "id must be lower-case letters and '-', got 'alpha`n'." }
        @{ Name = 'a boolean written as a string'; Mutate = { param($c) $c.enabled = 'true' }; Expected = 'enabled must be true or false, got "true".' }
        @{ Name = 'an enum value with the wrong case'; Mutate = { param($c) $c.mode = 'Strict' }; Expected = "mode must be one of strict, loose, got 'Strict'." }
        @{ Name = 'an enum value written as a list'; Mutate = { param($c) $c.mode = @('strict') }; Expected = 'mode must be one of strict, loose, got ["strict"].' }
        @{ Name = 'an enum value written as a boolean'; Mutate = { param($c) $c.mode = $true }; Expected = 'mode must be one of strict, loose, got true.' }
        @{ Name = 'an integer written as a string'; Mutate = { param($c) $c.days = '30' }; Expected = 'days must be a whole number, got "30".' }
        @{ Name = 'an integer below its minimum'; Mutate = { param($c) $c.days = 0 }; Expected = 'days must be at least 1, got 0.' }
        @{ Name = 'a list that is not a list'; Mutate = { param($c) $c.tags = 'a' }; Expected = 'tags must be a list, got "a".' }
        @{ Name = 'a list below its minimum count'; Mutate = { param($c) $c.children = @() }; Expected = 'children must contain at least 1 entry.' }
        @{ Name = 'a null list item'; Mutate = { param($c) $c.tags = @($null) }; Expected = 'tags[0] must not be null.' }
        @{ Name = 'an item error under its key'; Mutate = { param($c) $c.children[0].size = 'big' }; Expected = "children['one'].size must be a whole number, got `"big`"." }
        @{ Name = 'an item error by index when the key is not a string'; Mutate = { param($c) $c.children[0].name = 7 }; Expected = 'children[0].name must be a string, got 7.' }
        # A list holding the object: its .name would read the key of the object through member enumeration.
        @{ Name = 'an item error by index when the item is a list'; Mutate = { param($c) $c.children = @(, @($c.children[0])) }; Expected = 'children[0] must be an object, got [{"name":"one","size":1}].' }
        @{ Name = 'no repeat for an item of the wrong type'; Mutate = { param($c) $c.children = @(@($c.children[0]), $c.children[0]) }; Expected = 'children[0] must be an object, got [{"name":"one","size":1}].' }
        @{ Name = 'a repeated list item, in any case'; Mutate = { param($c) $c.tags = @('a', 'b', 'A') }; Expected = "tags: 'A' is listed more than once." }
        @{ Name = 'a repeated item key, in any case'; Mutate = { param($c) $c.children += [pscustomobject]@{ name = 'One'; size = 2 } }; Expected = "children: name 'One' is listed more than once." }
        @{ Name = 'an object that is not an object'; Mutate = { param($c) $c.nested = 'yes' }; Expected = 'nested must be an object, got "yes".' }
        @{ Name = 'a map that is not an object'; Mutate = { param($c) $c.rights = 'all' }; Expected = 'rights must be an object, got "all".' }
        @{ Name = 'a top-level $schema in another case'; Mutate = { param($c) $c | Add-Member -NotePropertyName '$Schema' -NotePropertyValue './x.schema.json' }; Expected = '$Schema is not a supported key.' }
        @{ Name = 'an invalid map key'; Mutate = { param($c) $c.rights | Add-Member -NotePropertyName 'Pull-Requests' -NotePropertyValue 'read' }; Expected = "rights: invalid key 'Pull-Requests' (lower-case letters and '_')." }
        @{ Name = 'a map key with a trailing newline'; Mutate = { param($c) $c.rights | Add-Member -NotePropertyName "issues`n" -NotePropertyValue 'read' }; Expected = "rights: invalid key 'issues`n' (lower-case letters and '_')." }
        @{ Name = 'an invalid map value'; Mutate = { param($c) $c.rights.contents = 'own' }; Expected = "rights.contents must be one of read, write, got 'own'." }
    ) {
        $config = Get-TestShapeConfig
        & $Mutate $config

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be $Expected
    }

    It 'rejects a shape with an unknown node key or type, also where the config has no value for the node' {
        # A misspelled key (Patern) would otherwise turn its check off without an error.
        $shape = Get-TestShape
        $shape.Fields['tags'].Items = @{ Type = 'string'; Patern = '^[a-z]+$' }
        $shape.Fields['rights'].Value = @{ Type = 'enumm'; Values = @('read') }
        $shape['Fieldz'] = @{}

        # -Be, not Should -Throw: its wildcard match reads '[]' and '*' as patterns.
        $message = try { Test-ConfigShape -Config (Get-TestShapeConfig) -Shape $shape; 'no error' } catch { $_.Exception.Message }

        $message | Should -Be "Invalid shape: (root): unknown key 'Fieldz'; tags[]: unknown key 'Patern'; rights.*: unknown type 'enumm'."
    }

    It 'accepts null where the node is nullable' {
        $config = Get-TestShapeConfig
        $config.nested = $null

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -BeNullOrEmpty
    }

    It 'compares key names case-sensitively' {
        $config = Get-TestShapeConfig
        $config.PSObject.Properties.Remove('days')
        $config | Add-Member -NotePropertyName Days -NotePropertyValue 30

        $errors = @(Test-ConfigShape -Config $config -Shape (Get-TestShape))

        $errors | Should -Be @('days is required.', 'Days is not a supported key.')
    }

    It 'rejects a config that is not an object' {
        Test-ConfigShape -Config @(1) -Shape (Get-TestShape) | Should -Be 'The config must be an object, got [1].'
    }

    It 'reports every error at once' {
        $config = Get-TestShapeConfig
        $config.id = 'Alpha'
        $config.days = 0
        $config | Add-Member -NotePropertyName extra -NotePropertyValue 1

        @(Test-ConfigShape -Config $config -Shape (Get-TestShape)).Count | Should -Be 3
    }

    It 'rejects a top-level $schema that is not a string' {
        $config = Get-TestShapeConfig
        $config | Add-Member -NotePropertyName '$schema' -NotePropertyValue 5

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be '$schema must be a string, got 5.'
    }

    It 'reports a whole number beyond the 64-bit range as out of range' {
        $config = '{ "id": "a", "parent": null, "enabled": true, "mode": "strict", "days": 99999999999999999999, "tags": [], "children": [ { "name": "one", "size": 1 } ], "rights": {}, "nested": null }' | ConvertFrom-Json

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be 'days is out of range for a whole number, got 99999999999999999999.'
    }

    It 'does not serialize valid values (no truncation warning for deep nesting)' {
        $leaf = @{ Type = 'object'; Fields = [ordered]@{ flag = @{ Type = 'boolean' } } }
        $shape = $leaf
        for ($i = 0; $i -lt 7; $i++) {
            $shape = @{ Type = 'object'; Fields = [ordered]@{ inner = $shape } }
        }
        $json = '{ "flag": true }'
        for ($i = 0; $i -lt 7; $i++) {
            $json = "{ `"inner`": $json }"
        }

        $output = @(Test-ConfigShape -Config ($json | ConvertFrom-Json) -Shape $shape 3>&1)

        $output | Should -BeNullOrEmpty
    }

    It 'accepts an integer at its minimum' {
        $config = Get-TestShapeConfig
        $config.days = 1

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -BeNullOrEmpty
    }

    It 'names a minimum count above one in the plural' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ tags = @{ Type = 'array'; MinItems = 2; Items = @{ Type = 'string' } } } }

        Test-ConfigShape -Config ('{ "tags": ["a"] }' | ConvertFrom-Json) -Shape $shape | Should -Be 'tags must contain at least 2 entries.'
    }

    It 'accepts repeated items in a list that is not unique' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ tags = @{ Type = 'array'; Items = @{ Type = 'string' } } } }

        Test-ConfigShape -Config ('{ "tags": ["a", "a"] }' | ConvertFrom-Json) -Shape $shape | Should -BeNullOrEmpty
    }

    It 'shows a value of the wrong type up to six levels deep' {
        $config = Get-TestShapeConfig
        $config.id = '{"a":{"b":{"c":{"d":{"e":{"f":{"g":1}}}}}}}' | ConvertFrom-Json

        Test-ConfigShape -Config $config -Shape (Get-TestShape) -WarningAction SilentlyContinue |
            Should -Be 'id must be a string, got {"a":{"b":{"c":{"d":{"e":{"f":"@{g=1}"}}}}}}.'
    }

    It 'shows a fractional number as written' {
        $config = '{ "id": "a", "parent": null, "enabled": true, "mode": "strict", "days": 30.0, "tags": [], "children": [ { "name": "one", "size": 1 } ], "rights": {}, "nested": null }' | ConvertFrom-Json

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be 'days must be a whole number, got 30.0.'
    }
}

Describe 'Test-IsGuid' {
    It 'returns <Expected> for <Value>' -ForEach @(
        @{ Value = '11111111-1111-1111-1111-111111111111'; Expected = $true }
        @{ Value = 'AAAAAAAA-0000-0000-0000-00000000000F'; Expected = $true }
        @{ Value = 'not-a-guid'; Expected = $false }
        @{ Value = "11111111-1111-1111-1111-111111111111`n"; Expected = $false }
        @{ Value = $null; Expected = $false }
    ) {
        Test-IsGuid $Value | Should -Be $Expected
    }
}

Describe 'Get-ConfigPattern' {
    It 'returns the <Name> pattern shared by the engines' -ForEach @(
        @{ Name = 'Guid'; Valid = 'AAAAAAAA-0000-0000-0000-00000000000f'; Invalid = 'not-a-guid' }
        @{ Name = 'Alias'; Valid = 'sub_prod-1'; Invalid = 'sub.prod' }
        @{ Name = 'Login'; Valid = 'octo-cat42'; Invalid = 'my_org' }
    ) {
        $pattern = Get-ConfigPattern -Name $Name

        $Valid | Should -MatchExactly $pattern
        $Invalid | Should -Not -MatchExactly $pattern
    }

    It 'rejects an unknown name' {
        { Get-ConfigPattern -Name 'Other' } | Should -Throw
    }
}

Describe 'Get-ConfigPatternNode' {
    It 'returns the <Name> node shared by the engines' -ForEach @(
        @{ Name = 'Guid'; Rule = 'a GUID' }
        @{ Name = 'Alias'; Rule = "a subscription alias of letters, digits, '-' and '_'" }
        @{ Name = 'Login'; Rule = "a GitHub login of letters, digits and '-'" }
    ) {
        $node = Get-ConfigPatternNode -Name $Name

        $node.Type | Should -Be 'string'
        $node.Pattern | Should -Be (Get-ConfigPattern -Name $Name)
        $node.Rule | Should -BeExactly $Rule
    }

    It 'returns a new node on every call' {
        $first = Get-ConfigPatternNode -Name 'Login'
        $first.Description = 'changed'

        (Get-ConfigPatternNode -Name 'Login').ContainsKey('Description') | Should -BeFalse
    }
}

Describe 'Assert-ConfigError' {
    It 'finds the error of a path with brackets' {
        { Assert-ConfigError -Errors @("identities['a'].name must be x, got 'b'.") -Path "identities['a'].name" -Part "'b'" } | Should -Not -Throw
    }

    It 'does not take the error of a longer path' {
        $errors = @("actions.selected.patterns_allowed[1] must be x, got 'y'.")

        { Assert-ConfigError -Errors $errors -Path 'actions.selected' } | Should -Throw -ErrorId 'PesterAssertionFailed'
    }

    It 'fails when the path has no error or several' {
        { Assert-ConfigError -Errors @() -Path 'a' } | Should -Throw -ErrorId 'PesterAssertionFailed'
        { Assert-ConfigError -Errors @('a must be x, got 1.', 'a: other rule.') -Path 'a' } | Should -Throw -ErrorId 'PesterAssertionFailed'
    }

    It 'fails with -Only when there are other errors too' {
        $errors = @('a must be x, got 1.', 'b is required.')

        { Assert-ConfigError -Errors $errors -Path 'a' } | Should -Not -Throw
        { Assert-ConfigError -Errors $errors -Path 'a' -Only } | Should -Throw -ErrorId 'PesterAssertionFailed'
    }

    It 'looks for a part after the path, not in it' {
        { Assert-ConfigError -Errors @("subscriptions['sub dev!'].alias must be x.") -Path "subscriptions['sub dev!'].alias" -Part "'sub dev!'" } |
            Should -Throw -ErrorId 'PesterAssertionFailed'
    }

    It 'fails for a missing part, naming it' {
        { Assert-ConfigError -Errors @('a must be x, got 1.') -Path 'a' -Part 'y' } | Should -Throw "*'y'*" -ErrorId 'PesterAssertionFailed'
    }
}
