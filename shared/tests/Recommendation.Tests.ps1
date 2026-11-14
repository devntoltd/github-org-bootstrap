BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../GitHubOrg.Common.psm1') -Force

    function Get-TestShape {
        $shape = @{
            Type   = 'object'
            Fields = [ordered]@{
                name   = @{ Type = 'string' }
                policy = @{
                    Type   = 'object'
                    Fields = [ordered]@{
                        locked = @{ Type = 'boolean'; Recommended = $true; Why = 'Unlocked is open to everyone.' }
                        mode   = @{ Type = 'enum'; Values = @('strict', 'loose'); Recommended = 'strict'; Why = 'Loose lets anything in.' }
                    }
                }
            }
        }
        $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
        return $shape
    }

    function Get-TestConfig {
        param([string]$Exceptions = '[]')
        "{ `"name`": `"x`", `"policy`": { `"locked`": true, `"mode`": `"strict`" }, `"exceptions`": $Exceptions }" | ConvertFrom-Json
    }

    function Get-TestException {
        param([string]$Field = 'policy.locked', [string]$ExpiresOn = '2027-04-01')
        "[ { `"field`": `"$Field`", `"category`": `"waiver`", `"reason`": `"Needed for the demo`", `"expiresOn`": `"$ExpiresOn`", `"reference`": null } ]"
    }

    function Get-TestItemShape {
        # Lists whose items take exceptions, next to a field with a recommendation.
        $shape = @{
            Type   = 'object'
            Fields = [ordered]@{
                roles  = @{ Type = 'array'; Items = @{ Type = 'string' }; ItemExceptions = $true }
                checks = @{ Type = 'array'; ItemKey = 'name'; Items = @{ Type = 'object'; Fields = [ordered]@{ name = @{ Type = 'string' } } }; ItemExceptions = $true }
                locked = @{ Type = 'boolean'; Recommended = $true; Why = 'Unlocked is open to everyone.' }
            }
        }
        $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
        return $shape
    }

    function Get-TestItemConfig {
        param([string[]]$Field = @(), [string]$ExpiresOn = '2027-04-01')
        $exceptions = @($Field | ForEach-Object { (Get-TestException -Field $_ -ExpiresOn $ExpiresOn) | ConvertFrom-Json })
        $config = '{ "roles": ["Reader", "Full Admin"], "checks": [{ "name": "open port" }], "locked": true }' | ConvertFrom-Json
        $config | Add-Member -NotePropertyName exceptions -NotePropertyValue $exceptions
        return $config
    }

    $script:today = [datetime]'2026-10-02'
}

Describe 'Get-ExceptionShape' {
    It 'rejects two exceptions for the same field' {
        $exception = Get-TestException
        $config = Get-TestConfig -Exceptions "[$($exception.Trim('[', ']', ' ')), $($exception.Trim('[', ']', ' '))]"

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be "exceptions: field 'policy.locked' is listed more than once."
    }

    It 'rejects two exceptions for the same item' {
        $config = Get-TestItemConfig -Field "roles['Full Admin']", "roles['Full Admin']"

        Test-ConfigShape -Config $config -Shape (Get-TestItemShape) | Should -Be "exceptions: field 'roles['Full Admin']' is listed more than once."
    }

    It 'offers the fields with a recommendation' {
        (Get-TestShape).Fields['exceptions'].Items.Fields['field'].SchemaEnum | Should -Be @('policy.locked', 'policy.mode')
    }

    It 'accepts an item of a list that takes exceptions, also with spaces: <Field>' -ForEach @(
        @{ Field = "roles['Full Admin']" }
        @{ Field = "checks['open port']" }
        @{ Field = 'locked' }
    ) {
        Test-ConfigShape -Config (Get-TestItemConfig -Field $Field) -Shape (Get-TestItemShape) | Should -BeNullOrEmpty
    }

    It 'names the rule of a field path or a list item, after the first list' {
        $config = Get-TestItemConfig -Field 'bad field'

        Test-ConfigShape -Config $config -Shape (Get-TestItemShape) |
            Should -Be "exceptions['bad field'].field must be a field path such as settings.email or a list item such as roles['<name>'], got 'bad field'."
    }

    It 'takes only list items when no field has a recommendation' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ roles = @{ Type = 'array'; Items = @{ Type = 'string' }; ItemExceptions = $true } } }
        $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
        $config = '{ "roles": [] }' | ConvertFrom-Json
        $config | Add-Member -NotePropertyName exceptions -NotePropertyValue @((Get-TestException -Field 'color') | ConvertFrom-Json)

        Test-ConfigShape -Config $config -Shape $shape | Should -Be "exceptions['color'].field must be a list item such as roles['<name>'], got 'color'."
    }

    It 'offers no fixed list of fields once list items take exceptions' {
        (Get-TestItemShape).Fields['exceptions'].Items.Fields['field'].SchemaEnum | Should -BeNullOrEmpty
    }

    It 'requires every key of an exception' {
        $config = Get-TestConfig -Exceptions (Get-TestException)
        $config.exceptions[0].PSObject.Properties.Remove('reference')

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be "exceptions['policy.locked'].reference is required."
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an unknown category'; Key = 'category'; Value = 'accepted'; Expected = "exceptions['policy.locked'].category must be one of waiver, mitigated, got 'accepted'." }
        @{ Name = 'an empty reason'; Key = 'reason'; Value = ' '; Expected = "exceptions['policy.locked'].reason must be a non-empty text, got ' '." }
        @{ Name = 'a date in another format'; Key = 'expiresOn'; Value = '01.04.2027'; Expected = "exceptions['policy.locked'].expiresOn must be a date yyyy-MM-dd, got '01.04.2027'." }
        @{ Name = 'a reference that is not https'; Key = 'reference'; Value = 'http://example.com/1'; Expected = "exceptions['policy.locked'].reference must be an https:// URL, got 'http://example.com/1'." }
    ) {
        $config = Get-TestConfig -Exceptions (Get-TestException)
        $config.exceptions[0].$Key = $Value

        Test-ConfigShape -Config $config -Shape (Get-TestShape) | Should -Be $Expected
    }
}

Describe 'Test-ExceptionList' {
    It 'accepts <Name>' -ForEach @(
        @{ Name = 'an exception within a year'; ExpiresOn = '2027-04-01' }
        @{ Name = 'an exception ending exactly a year ahead'; ExpiresOn = '2027-10-02' }
        @{ Name = 'an expired exception'; ExpiresOn = '2026-09-01' }
    ) {
        $exceptions = @((Get-TestException -ExpiresOn $ExpiresOn) | ConvertFrom-Json)

        Test-ExceptionList -Exceptions $exceptions -Shape (Get-TestShape) -Today $script:today | Should -BeNullOrEmpty
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an unknown field'; Field = 'policy.color'; ExpiresOn = '2027-04-01'; Expected = "exceptions['policy.color']: 'policy.color' is not a field with a recommended value." }
        @{ Name = 'a field without a recommendation'; Field = 'name'; ExpiresOn = '2027-04-01'; Expected = "exceptions['name']: 'name' is not a field with a recommended value." }
        @{ Name = 'a field in another case'; Field = 'Policy.locked'; ExpiresOn = '2027-04-01'; Expected = "exceptions['Policy.locked']: 'Policy.locked' is not a field with a recommended value." }
        @{ Name = 'a date that does not exist'; Field = 'policy.locked'; ExpiresOn = '2027-02-30'; Expected = "exceptions['policy.locked'].expiresOn '2027-02-30' is not a valid date." }
        @{ Name = 'a date more than a year ahead'; Field = 'policy.locked'; ExpiresOn = '2027-10-03'; Expected = "exceptions['policy.locked'].expiresOn must be at most one year ahead (2027-10-02), got '2027-10-03'." }
    ) {
        $exceptions = @((Get-TestException -Field $Field -ExpiresOn $ExpiresOn) | ConvertFrom-Json)

        Test-ExceptionList -Exceptions $exceptions -Shape (Get-TestShape) -Today $script:today | Should -Be $Expected
    }
}

Describe 'Test-ExceptionList with list items' {
    It 'accepts an item of a list that takes exceptions, also one the list does not hold' {
        $config = Get-TestItemConfig -Field "roles['Full Admin']", "roles['Gone']"

        Test-ExceptionList -Exceptions $config.exceptions -Shape (Get-TestItemShape) -Today $script:today | Should -BeNullOrEmpty
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an item of a list that takes no exceptions'; Field = "other['x']" }
        @{ Name = 'a list without an item'; Field = 'roles' }
        @{ Name = 'an unknown field'; Field = 'color' }
        @{ Name = 'an item of a list in another case'; Field = "Roles['Reader']" }
    ) {
        $config = Get-TestItemConfig -Field $Field

        Test-ExceptionList -Exceptions $config.exceptions -Shape (Get-TestItemShape) -Today $script:today |
            Should -Be "exceptions['$Field']: '$Field' is not a field with a recommended value or an item of roles, checks (such as roles['<name>'])."
    }

    It 'names only the lists when no field has a recommendation' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ roles = @{ Type = 'array'; Items = @{ Type = 'string' }; ItemExceptions = $true } } }
        $exceptions = @((Get-TestException -Field 'color') | ConvertFrom-Json)

        Test-ExceptionList -Exceptions $exceptions -Shape $shape -Today $script:today |
            Should -Be "exceptions['color']: 'color' is not an item of roles (such as roles['<name>'])."
    }
}

Describe 'Get-ItemExceptionReport' {
    BeforeAll {
        $script:findings = [ordered]@{ 'Full Admin' = "roles['Full Admin'] can do everything." }
        $script:report = @{ Shape = (Get-TestItemShape); List = 'roles'; NotNeeded = 'the role is harmless'; Today = $script:today }
    }

    It 'reports a finding without an exception as not waived' {
        $report = Get-ItemExceptionReport -Config (Get-TestItemConfig) -Finding $script:findings @script:report

        $report.NotWaived | Should -Be "roles['Full Admin'] can do everything. To keep it, add an entry to exceptions."
        $report.Warnings | Should -BeNullOrEmpty
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'turns a finding with an exception in force into a waiver line' {
        $config = Get-TestItemConfig -Field "roles['Full Admin']" -ExpiresOn '2026-10-03'

        $report = Get-ItemExceptionReport -Config $config -Finding $script:findings @script:report

        $report.NotWaived | Should -BeNullOrEmpty
        $report.Waivers | Should -Be "Waived until 2026-10-03 (waiver): roles['Full Admin'] - Needed for the demo (expires in 1 day)"
    }

    It 'reports a finding again once its exception has expired' {
        $config = Get-TestItemConfig -Field "roles['Full Admin']" -ExpiresOn '2026-10-01'

        $report = Get-ItemExceptionReport -Config $config -Finding $script:findings @script:report

        $report.NotWaived | Should -Be "roles['Full Admin'] can do everything. The exception expired on 2026-10-01."
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'warns about an exception for <Name>' -ForEach @(
        @{ Name = 'an item without a finding'; Field = "roles['Reader']"; Expected = "The exception for roles['Reader'] is not needed: the role is harmless. Remove it." }
        @{ Name = 'an item the list does not hold'; Field = "roles['Gone']"; Expected = "The exception for roles['Gone'] does not apply: 'Gone' is not in roles. Remove it." }
    ) {
        $report = Get-ItemExceptionReport -Config (Get-TestItemConfig -Field $Field) -Finding ([ordered]@{}) @script:report

        $report.Warnings | Should -Be $Expected
        $report.NotWaived | Should -BeNullOrEmpty
    }

    It 'does not take an exception for the list in another case' {
        $config = Get-TestItemConfig -Field "Roles['Full Admin']"

        $report = Get-ItemExceptionReport -Config $config -Finding $script:findings @script:report

        $report.NotWaived | Should -BeLike ([WildcardPattern]::Escape("roles['Full Admin'] can do everything.") + '*')
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a list that takes no exceptions'; List = 'locked' }
        @{ Name = 'a list in another case'; List = 'Roles' }
    ) {
        { Get-ItemExceptionReport -Config (Get-TestItemConfig) -Shape (Get-TestItemShape) -List $List -Finding ([ordered]@{}) -NotNeeded 'x' -Today $script:today } |
            Should -Throw "'$List' is not a list whose items take exceptions."
    }

    It 'finds an item of a list of objects by its key' {
        $config = Get-TestItemConfig -Field "checks['open port']"

        $report = Get-ItemExceptionReport -Config $config -Shape (Get-TestItemShape) -List checks -Finding ([ordered]@{}) -NotNeeded 'it is closed' -Today $script:today

        $report.Warnings | Should -BeLike ('*' + [WildcardPattern]::Escape("checks['open port'] is not needed") + '*')
    }

    It 'reads the items of a list of objects by their key and ignores exceptions of other lists' {
        $config = Get-TestItemConfig -Field "checks['open port']", "roles['Reader']"
        $findings = [ordered]@{ 'open port' = "checks['open port'] is open." }

        $report = Get-ItemExceptionReport -Config $config -Shape (Get-TestItemShape) -List checks -Finding $findings -NotNeeded 'it is closed' -Today $script:today

        $report.Waivers | Should -Be "Waived until 2027-04-01 (waiver): checks['open port'] - Needed for the demo"
        $report.Warnings | Should -BeNullOrEmpty
    }
}

Describe 'Get-RuleExceptionReport' {
    BeforeAll {
        function Get-TestRuleShape {
            $shape = @{
                Type   = 'object'
                Fields = [ordered]@{
                    list   = @{ Type = 'array'; Items = @{ Type = 'string' }; RuleExceptions = $true }
                    locked = @{ Type = 'boolean'; Recommended = $true; Why = 'Unlocked is open to everyone.' }
                }
            }
            $shape.Fields['exceptions'] = Get-ExceptionShape -Shape $shape
            return $shape
        }

        function Get-TestRuleConfig {
            param([string]$Field = '', [string]$ExpiresOn = '2027-04-01')
            $config = '{ "list": [], "locked": true }' | ConvertFrom-Json
            $exceptions = @()
            if ($Field) {
                $exceptions = @((Get-TestException -Field $Field -ExpiresOn $ExpiresOn) | ConvertFrom-Json)
            }
            $config | Add-Member -NotePropertyName exceptions -NotePropertyValue $exceptions
            return $config
        }

        $script:ruleReport = @{ Shape = (Get-TestRuleShape); Path = 'list'; Today = $script:today }
    }

    It 'reports a finding without an exception as not waived' {
        $report = Get-RuleExceptionReport -Config (Get-TestRuleConfig) -Finding 'The list is empty.' -NotNeeded 'x' @script:ruleReport

        $report.NotWaived | Should -Be 'The list is empty. To keep it, add an entry to exceptions.'
        $report.Warnings | Should -BeNullOrEmpty
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'turns a finding with an exception in force into a waiver line' {
        $config = Get-TestRuleConfig -Field 'list'

        $report = Get-RuleExceptionReport -Config $config -Finding 'The list is empty.' -NotNeeded 'x' @script:ruleReport

        $report.NotWaived | Should -BeNullOrEmpty
        $report.Waivers | Should -Be 'Waived until 2027-04-01 (waiver): list - Needed for the demo'
    }

    It 'reports a finding again once its exception has expired' {
        $config = Get-TestRuleConfig -Field 'list' -ExpiresOn '2026-10-01'

        $report = Get-RuleExceptionReport -Config $config -Finding 'The list is empty.' -NotNeeded 'x' @script:ruleReport

        $report.NotWaived | Should -Be 'The list is empty. The exception expired on 2026-10-01.'
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'warns about an exception when the rule holds' {
        $config = Get-TestRuleConfig -Field 'list'

        $report = Get-RuleExceptionReport -Config $config -Finding $null -NotNeeded 'the list has entries' @script:ruleReport

        $report.Warnings | Should -Be 'The exception for list is not needed: the list has entries. Remove it.'
        $report.NotWaived | Should -BeNullOrEmpty
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'reports nothing when the rule holds and there is no exception' {
        $report = Get-RuleExceptionReport -Config (Get-TestRuleConfig) -Finding '' -NotNeeded 'x' @script:ruleReport

        $report.NotWaived | Should -BeNullOrEmpty
        $report.Warnings | Should -BeNullOrEmpty
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'rejects a path not marked RuleExceptions: <Path>' -ForEach @(
        @{ Path = 'locked' }
        @{ Path = 'List' }
    ) {
        { Get-RuleExceptionReport -Config (Get-TestRuleConfig) -Shape (Get-TestRuleShape) -Path $Path -Finding 'x' -NotNeeded 'x' -Today $script:today } |
            Should -Throw "'$Path' is not a field whose rule takes exceptions."
    }

    It 'takes a field whose rule takes exceptions as an exception field' {
        $config = Get-TestRuleConfig -Field 'list'

        Test-ConfigShape -Config $config -Shape (Get-TestRuleShape) | Should -BeNullOrEmpty
        Test-ExceptionList -Exceptions $config.exceptions -Shape (Get-TestRuleShape) -Today $script:today | Should -BeNullOrEmpty
    }

    It 'names the fields with a rule in the error for an unknown path' {
        $config = Get-TestRuleConfig -Field 'color'

        Test-ExceptionList -Exceptions $config.exceptions -Shape (Get-TestRuleShape) -Today $script:today |
            Should -Be "exceptions['color']: 'color' is not a field with a recommended value or a rule."
    }
}

Describe 'Get-RecommendationReport' {
    It 'reports nothing when every value is the recommended one' {
        $report = Get-RecommendationReport -Config (Get-TestConfig) -Shape (Get-TestShape) -Today $script:today

        $report.Warnings | Should -BeNullOrEmpty
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'warns about a value that differs, with the reason' {
        $config = Get-TestConfig
        $config.policy.locked = $false
        $config.policy.mode = 'loose'

        $report = Get-RecommendationReport -Config $config -Shape (Get-TestShape) -Today $script:today

        $report.Warnings | Should -Be @(
            'policy.locked is false; recommended true: Unlocked is open to everyone. To keep it, add an entry to exceptions.'
            'policy.mode is "loose"; recommended "strict": Loose lets anything in. To keep it, add an entry to exceptions.'
        )
    }

    It 'lists an exception in force as a waiver, not a warning' {
        $config = Get-TestConfig -Exceptions (Get-TestException)
        $config.policy.locked = $false

        $report = Get-RecommendationReport -Config $config -Shape (Get-TestShape) -Today $script:today

        $report.Warnings | Should -BeNullOrEmpty
        $report.Waivers | Should -Be 'Waived until 2027-04-01 (waiver): policy.locked - Needed for the demo'
    }

    It 'says when an exception expires within 30 days: <ExpiresOn>' -ForEach @(
        @{ ExpiresOn = '2026-11-01'; Suffix = ' (expires in 30 days)' }
        @{ ExpiresOn = '2026-10-03'; Suffix = ' (expires in 1 day)' }
        @{ ExpiresOn = '2026-10-02'; Suffix = ' (expires today)' }
        @{ ExpiresOn = '2026-11-02'; Suffix = '' }
    ) {
        $config = Get-TestConfig -Exceptions (Get-TestException -ExpiresOn $ExpiresOn)
        $config.policy.locked = $false

        $report = Get-RecommendationReport -Config $config -Shape (Get-TestShape) -Today $script:today

        $report.Waivers | Should -Be "Waived until $ExpiresOn (waiver): policy.locked - Needed for the demo$Suffix"
    }

    It 'warns again once the exception has expired' {
        $config = Get-TestConfig -Exceptions (Get-TestException -ExpiresOn '2026-10-01')
        $config.policy.locked = $false

        $report = Get-RecommendationReport -Config $config -Shape (Get-TestShape) -Today $script:today

        $report.Warnings | Should -Be 'policy.locked is false; recommended true: Unlocked is open to everyone. The exception expired on 2026-10-01.'
        $report.Waivers | Should -BeNullOrEmpty
    }

    It 'warns about an exception that is not needed' {
        $report = Get-RecommendationReport -Config (Get-TestConfig -Exceptions (Get-TestException)) -Shape (Get-TestShape) -Today $script:today

        $report.Warnings | Should -Be 'The exception for policy.locked is not needed: the value is the recommended one. Remove it.'
    }

    It 'warns about an exception for a field the config has no value for' {
        $config = Get-TestConfig -Exceptions (Get-TestException -Field 'policy.mode')
        $config.policy = $null

        (Get-RecommendationReport -Config $config -Shape (Get-TestShape) -Today $script:today).Warnings |
            Should -Be 'The exception for policy.mode does not apply: the config has no value for it. Remove it.'
    }

    It 'compares a list recommendation as a whole: <Value>' -ForEach @(
        @{ Recommended = @(); Value = '[]'; Warns = $false }
        @{ Recommended = @('a', 'b'); Value = '["a","b"]'; Warns = $false }
        @{ Recommended = @('a', 'b'); Value = '["b","a"]'; Warns = $true }
        @{ Recommended = @('a'); Value = '["a","a"]'; Warns = $true }
        @{ Recommended = @('a'); Value = '["A"]'; Warns = $true }
    ) {
        $shape = @{
            Type   = 'object'
            Fields = [ordered]@{ tags = @{ Type = 'array'; Items = @{ Type = 'string' }; Recommended = $Recommended; Why = 'Fixed tags.' } }
        }
        $config = "{ `"tags`": $Value }" | ConvertFrom-Json -NoEnumerate

        $warnings = (Get-RecommendationReport -Config $config -Shape $shape -Today $script:today).Warnings

        [bool]$warnings | Should -Be $Warns
    }

    It 'shows neither value of a sensitive field: <Case>' -ForEach @(
        @{ Case = 'no exception'; Exceptions = '[]'; Expected = 'policy.code differs from the recommended value (sensitive, values not shown): A fixed code. To keep it, add an entry to exceptions.' }
        @{ Case = 'an expired exception'; Exceptions = '[ { "field": "policy.code", "category": "waiver", "reason": "Needed for the demo", "expiresOn": "2026-10-01", "reference": null } ]'; Expected = 'policy.code differs from the recommended value (sensitive, values not shown): A fixed code. The exception expired on 2026-10-01.' }
    ) {
        $shape = @{
            Type   = 'object'
            Fields = [ordered]@{
                policy = @{ Type = 'object'; Fields = [ordered]@{ code = @{ Type = 'string'; Recommended = 'recommended-7f3a'; Why = 'A fixed code.'; Sensitive = $true } } }
            }
        }
        $config = "{ `"policy`": { `"code`": `"configured-9c2e`" }, `"exceptions`": $Exceptions }" | ConvertFrom-Json

        $warnings = @((Get-RecommendationReport -Config $config -Shape $shape -Today $script:today).Warnings)

        $warnings | Should -Be $Expected
        ($warnings -join "`n") | Should -Not -BeLike '*configured-9c2e*'
        ($warnings -join "`n") | Should -Not -BeLike '*recommended-7f3a*'
    }

    It 'accepts Sensitive as a key of a shape node and leaves it out of the schema' {
        $shape = @{ Type = 'object'; Fields = [ordered]@{ code = @{ Type = 'string'; Sensitive = $true } } }

        Test-ConfigShape -Config ('{ "code": "x" }' | ConvertFrom-Json) -Shape $shape | Should -BeNullOrEmpty
        (ConvertTo-ConfigSchema -Shape $shape -Title 'Test' | ConvertTo-Json -Depth 10) | Should -Not -BeLike '*ensitive*'
    }

    It 'leaves exceptions for list items to Get-ItemExceptionReport' {
        $config = Get-TestItemConfig -Field "roles['Reader']"

        (Get-RecommendationReport -Config $config -Shape (Get-TestItemShape) -Today $script:today).Warnings | Should -BeNullOrEmpty
    }

    It 'skips a field missing from the config and a config without exceptions' {
        $config = Get-TestConfig
        $config.policy.PSObject.Properties.Remove('mode')
        $config.PSObject.Properties.Remove('exceptions')

        (Get-RecommendationReport -Config $config -Shape (Get-TestShape) -Today $script:today).Warnings | Should -BeNullOrEmpty
    }
}

Describe 'Write-BootstrapWaiver' {
    It 'prints the waiver on its own line' {
        Mock -ModuleName GitHubOrg.Common Write-Host { }

        Write-BootstrapWaiver -Message 'Waived until 2027-04-01 (waiver): policy.locked - Needed for the demo'

        Should -Invoke Write-Host -ModuleName GitHubOrg.Common -Times 1 -Exactly -ParameterFilter { $Object -eq 'Waived until 2027-04-01 (waiver): policy.locked - Needed for the demo' }
    }
}
