BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../Bootstrap.Common.psm1') -Force

    function Get-TestShape {
        $shape = @{
            Type   = 'object'
            Fields = [ordered]@{
                id     = @{ Type = 'string'; Pattern = '^[a-z]+$'; Rule = 'lower-case letters'; Description = 'The id.' }
                parent = @{ Type = 'string'; Nullable = $true }
                mode   = @{ Type = 'enum'; Values = @('strict', 'loose'); Nullable = $true }
                locked = @{ Type = 'boolean'; Recommended = $true; Why = 'Unlocked is open.' }
                sealed = @{ Type = 'boolean'; Recommended = $false; Why = 'A seal cannot be undone.'; Description = 'Seals it.' }
                days   = @{ Type = 'integer'; Minimum = 1 }
                tags   = @{ Type = 'array'; MinItems = 1; Unique = $true; Items = @{ Type = 'string' } }
                rights = @{ Type = 'map'; KeyPattern = '^[a-z_]+$'; KeyRule = 'lower-case'; Value = @{ Type = 'enum'; Values = @('read') } }
            }
        }
        $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
        return $shape
    }

    $script:text = ConvertTo-ConfigSchema -Shape (Get-TestShape) -Title 'test config'
    $script:schema = $script:text | ConvertFrom-Json -AsHashtable
}

Describe 'ConvertTo-ConfigSchema' {
    It 'writes LF line endings and one trailing newline' {
        $script:text.Contains("`r") | Should -BeFalse
        $script:text.EndsWith("}`n") | Should -BeTrue
    }

    It 'starts with the draft and the title, and allows $schema' {
        $script:schema['$schema'] | Should -Be 'https://json-schema.org/draft/2020-12/schema'
        $script:schema['title'] | Should -Be 'test config'
        $script:schema['properties']['$schema']['type'] | Should -Be 'string'
        $script:schema['required'] | Should -Not -Contain '$schema'
    }

    It 'lists $schema first among the properties' {
        @($script:schema['properties'].Keys)[0] | Should -Be '$schema'
    }

    It 'requires every key and rejects others' {
        $script:schema['type'] | Should -Be 'object'
        $script:schema['required'] | Should -Be @('id', 'parent', 'mode', 'locked', 'sealed', 'days', 'tags', 'rights', 'exceptions')
        $script:schema['additionalProperties'] | Should -BeFalse
    }

    It 'maps <Name>' -ForEach @(
        @{ Name = 'a string with a pattern and a description'; Key = 'id'; Expected = '{"type":"string","markdownDescription":"The id.","pattern":"^[a-z]+$"}' }
        @{ Name = 'a nullable string'; Key = 'parent'; Expected = '{"type":["string","null"]}' }
        @{ Name = 'a nullable enum'; Key = 'mode'; Expected = '{"type":["string","null"],"enum":["strict","loose",null]}' }
        @{ Name = 'a recommendation'; Key = 'locked'; Expected = '{"type":"boolean","markdownDescription":"Recommended: `true`. Unlocked is open.","default":true}' }
        @{ Name = 'a recommendation with a description'; Key = 'sealed'; Expected = '{"type":"boolean","markdownDescription":"Seals it. Recommended: `false`. A seal cannot be undone.","default":false}' }
        @{ Name = 'an integer'; Key = 'days'; Expected = '{"type":"integer","minimum":1}' }
        @{ Name = 'an array of unique strings'; Key = 'tags'; Expected = '{"type":"array","items":{"type":"string"},"minItems":1,"uniqueItems":true}' }
        @{ Name = 'a map'; Key = 'rights'; Expected = '{"type":"object","patternProperties":{"^[a-z_]+$":{"type":"string","enum":["read"]}},"additionalProperties":false}' }
    ) {
        ConvertTo-Json -InputObject $script:schema['properties'][$Key] -Depth 10 -Compress | Should -Be $Expected
    }

    It 'maps an integer without a minimum to its type alone' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ count = @{ Type = 'integer' } } }

        $schema = ConvertTo-ConfigSchema -Shape $shape -Title 'test config' | ConvertFrom-Json -AsHashtable

        ConvertTo-Json -InputObject $schema['properties']['count'] -Compress | Should -Be '{"type":"integer"}'
    }

    It 'maps an integer maximum' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ count = @{ Type = 'integer'; Minimum = 0; Maximum = 10 } } }

        $schema = ConvertTo-ConfigSchema -Shape $shape -Title 'test config' | ConvertFrom-Json -AsHashtable

        $schema['properties']['count']['maximum'] | Should -Be 10
    }

    It 'offers the fields whose rule takes exceptions for an exception' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ locked = @{ Type = 'boolean'; Recommended = $true; Why = 'w' }; list = @{ Type = 'array'; Items = @{ Type = 'string' }; RuleExceptions = $true } } }
        $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape

        $schema = ConvertTo-ConfigSchema -Shape $shape -Title 'test config' | ConvertFrom-Json -AsHashtable

        $schema['properties']['exceptions']['items']['properties']['field']['enum'] | Should -Be @('locked', 'list')
    }

    It 'leaves uniqueness by a key out, which JSON Schema cannot express' {
        $script:schema['properties']['exceptions'].Contains('uniqueItems') | Should -BeFalse
    }

    It 'offers the recommended fields for an exception' {
        $script:schema['properties']['exceptions']['items']['properties']['field']['enum'] | Should -Be @('locked', 'sealed')
    }

    It 'allows exceptions for the items of a list that takes them' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ roles = @{ Type = 'array'; Items = @{ Type = 'string' }; ItemExceptions = $true } } }
        $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
        $text = ConvertTo-ConfigSchema -Shape $shape -Title 'test config'
        $exception = '{ "field": "roles[''Full Admin'']", "category": "waiver", "reason": "r", "expiresOn": "2027-01-01", "reference": null }'

        "{ `"roles`": [], `"exceptions`": [$exception] }" | Test-Json -Schema $text | Should -BeTrue
        "{ `"roles`": [], `"exceptions`": [$($exception.Replace('roles[', 'other['))] }" | Test-Json -Schema $text -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'rejects a shape with an unknown node key' {
        $shape = Get-TestShape
        $shape.Fields['id']['Patern'] = '^[a-z]+$'

        { ConvertTo-ConfigSchema -Shape $shape -Title 'test config' } | Should -Throw "Invalid shape: id: unknown key 'Patern'."
    }

    It 'accepts a valid config and rejects an unknown key with Test-Json' {
        $valid = '{ "$schema": "./x.json", "id": "a", "parent": null, "mode": null, "locked": true, "sealed": false, "days": 1, "tags": ["t"], "rights": { "contents": "read" }, "exceptions": [] }'
        $valid | Test-Json -Schema $script:text | Should -BeTrue
        $valid.Replace('"days": 1', '"days": 1, "other": 2') | Test-Json -Schema $script:text -ErrorAction SilentlyContinue | Should -BeFalse
    }
}
