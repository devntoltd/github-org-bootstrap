# Config shapes: what a config must look like, checked before anything else. Dot-sourced into
# GitHubOrg.Common, so its functions share that module's scope (Pester -ModuleName GitHubOrg.Common mocks).

$script:ShapeTypeNames = @{
    object  = 'an object'
    map     = 'an object'
    array   = 'a list'
    string  = 'a string'
    boolean = 'true or false'
    integer = 'a whole number'
}

# Every key a shape node may hold. A misspelled key (Patern) would read as missing and turn its check off without an
# error, so Assert-ShapeDefinition rejects any other key.
$script:ShapeNodeKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
        'Type', 'Fields', 'Items', 'ItemKey', 'Unique', 'MinItems', 'ItemExceptions', 'Value', 'KeyPattern', 'KeyRule',
        'Pattern', 'Rule', 'SchemaEnum', 'Values', 'Minimum', 'Maximum', 'RuleExceptions', 'Nullable', 'Recommended', 'Why', 'Description', 'Sensitive'
    ), [StringComparer]::Ordinal)

# Patterns used by more than one field, with the rule a validation error names, so every field that takes one reports
# it the same way. Written with '$' as JSON Schema patterns; Test-ShapePattern anchors them.
$script:ConfigPatterns = @{
    Guid  = @{ Pattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'; Rule = 'a GUID' }
    Alias = @{ Pattern = '^[A-Za-z0-9_-]+$'; Rule = "a subscription alias of letters, digits, '-' and '_'" }
    # A user or an organization.
    Login = @{ Pattern = '^[A-Za-z0-9-]+$'; Rule = "a GitHub login of letters, digits and '-'" }
}

function Get-ConfigPattern {
    <#
    .SYNOPSIS
    A pattern used by more than one field of a config: Guid, Alias (a subscription alias) or Login (a GitHub login of a user or an organization).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('Guid', 'Alias', 'Login')][string]$Name
    )

    return $script:ConfigPatterns[$Name].Pattern
}

function Get-ConfigPatternNode {
    <#
    .SYNOPSIS
    The shape node of a field that takes a shared pattern: a string with its pattern and rule. A new node on every call,
    so a field can add its own keys (Description).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateSet('Guid', 'Alias', 'Login')][string]$Name
    )

    return @{ Type = 'string'; Pattern = $script:ConfigPatterns[$Name].Pattern; Rule = $script:ConfigPatterns[$Name].Rule }
}

function Test-IsGuid {
    <#
    .SYNOPSIS
    Returns $true when the value is a GUID string.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][object]$Value)

    return Test-ShapePattern -Value ([string]$Value) -Pattern (Get-ConfigPattern -Name Guid)
}

function Join-ShapePath {
    # 'settings' + 'email' -> 'settings.email'; the root has an empty path.
    param(
        [AllowEmptyString()][string]$Parent,
        [Parameter(Mandatory)][string]$Child
    )

    if ([string]::IsNullOrEmpty($Parent)) {
        return $Child
    }
    return "$Parent.$Child"
}

function Test-ShapePattern {
    # The patterns are also the JSON Schema patterns (ECMAScript), where '$' matches only at the end of the value.
    # In .NET it also matches before a final newline, so "name`n" would pass here and fail later in an Azure or
    # GitHub call; '\z' is the .NET anchor with the ECMAScript meaning. Case-sensitive: Azure and GitHub are.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$Pattern
    )
    return $Value -cmatch ($Pattern -replace '(?<!\\)\$', '\z')
}

function Format-ShapeValue {
    # A value as JSON: "30" and 30.0 would both print as 30, hiding what makes them invalid.
    param([AllowNull()][object]$Value)
    return ConvertTo-Json -InputObject $Value -Compress -Depth 5
}

function Get-ShapeTypeError {
    # The message for a value of the wrong type. Built only for an invalid value: serializing every value would cost
    # time and print truncation warnings for deeply nested ones.
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][hashtable]$Node,
        [AllowNull()][object]$Value
    )
    return "$Label must be $($script:ShapeTypeNames[$Node.Type]), got $(Format-ShapeValue $Value)."
}

function Get-ShapeItemPath {
    # The path of an array item: under its key when the item has one ("children['one']"), by index otherwise.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Node,
        [AllowNull()][object]$Item,
        [Parameter(Mandatory)][int]$Index
    )

    if ($Node.ItemKey -and $Item -is [System.Management.Automation.PSCustomObject]) {
        $key = $Item.($Node.ItemKey)
        if ($key -is [string] -and $key -ne '') {
            return "$($Path)['$key']"
        }
    }
    return "$($Path)[$Index]"
}

function Get-ShapeDuplicateError {
    # The errors for the items of a Unique array that repeat: the strings, or the values of the ItemKey, compared
    # case-insensitively like the names they hold (docs/architecture.md, "Case in comparisons"). An item of the wrong
    # type is the error of its own check.
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][hashtable]$Node,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][object[]]$Items
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $prefix = ''
    if ($Node.ItemKey) {
        $prefix = "$($Node.ItemKey) "
    }
    foreach ($item in $Items) {
        $value = $item
        if ($Node.ItemKey) {
            if ($item -isnot [System.Management.Automation.PSCustomObject]) {
                continue
            }
            $value = $item.($Node.ItemKey)
        }
        if ($value -is [string] -and -not $seen.Add($value)) {
            "${Label}: $prefix'$value' is listed more than once."
        }
    }
}

function Get-ShapeProperty {
    # The property named exactly Name, or $null. Case-sensitive: 'subscriptionID' must not pass for 'subscriptionId'.
    # The indexer looks up case-insensitively, and an object holds no two names that differ only in case
    # (ConvertFrom-Json rejects them), so the one it finds is the only candidate.
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $property.Name -ceq $Name) {
        return $property
    }
    return $null
}

function Test-ShapeObject {
    # Adds the errors of an object: missing keys, unknown keys (a top-level $schema is allowed), and its fields.
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][hashtable]$Node,
        [AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    $keys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Node.Fields.Keys), [StringComparer]::Ordinal)
    foreach ($key in $Node.Fields.Keys) {
        $childPath = Join-ShapePath -Parent $Path -Child $key
        $property = Get-ShapeProperty -Object $Value -Name $key
        if (-not $property) {
            $Errors.Add("$childPath is required.")
            continue
        }
        Test-ShapeNode -Value $property.Value -Node $Node.Fields[$key] -Path $childPath -Errors $Errors
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($keys.Contains($property.Name)) {
            continue
        }
        if ($Path -eq '' -and $property.Name -ceq '$schema') {
            Test-ShapeNode -Value $property.Value -Node @{ Type = 'string' } -Path '$schema' -Errors $Errors
            continue
        }
        $Errors.Add("$(Join-ShapePath -Parent $Path -Child $property.Name) is not a supported key.")
    }
}

function Test-ShapeNode {
    # Adds the errors of a value against a shape node to Errors.
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][hashtable]$Node,
        [AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )

    $label = $Path
    if ($label -eq '') {
        $label = 'The config'
    }
    if ($null -eq $Value) {
        if (-not $Node.Nullable) {
            $Errors.Add("$label must not be null.")
        }
        return
    }

    switch ($Node.Type) {
        'object' {
            if ($Value -isnot [System.Management.Automation.PSCustomObject]) {
                $Errors.Add((Get-ShapeTypeError -Label $label -Node $Node -Value $Value))
                return
            }
            Test-ShapeObject -Value $Value -Node $Node -Path $Path -Errors $Errors
        }
        'map' {
            if ($Value -isnot [System.Management.Automation.PSCustomObject]) {
                $Errors.Add((Get-ShapeTypeError -Label $label -Node $Node -Value $Value))
                return
            }
            foreach ($property in $Value.PSObject.Properties) {
                if (-not (Test-ShapePattern -Value $property.Name -Pattern $Node.KeyPattern)) {
                    $Errors.Add("${label}: invalid key '$($property.Name)' ($($Node.KeyRule)).")
                    continue
                }
                Test-ShapeNode -Value $property.Value -Node $Node.Value -Path (Join-ShapePath -Parent $Path -Child $property.Name) -Errors $Errors
            }
        }
        'array' {
            if ($Value -isnot [array]) {
                $Errors.Add((Get-ShapeTypeError -Label $label -Node $Node -Value $Value))
                return
            }
            $minimum = [int]$Node.MinItems
            if ($Value.Count -lt $minimum) {
                $noun = 'entries'
                if ($minimum -eq 1) {
                    $noun = 'entry'
                }
                $Errors.Add("$label must contain at least $minimum $noun.")
            }
            for ($i = 0; $i -lt $Value.Count; $i++) {
                $itemPath = Get-ShapeItemPath -Path $Path -Node $Node -Item $Value[$i] -Index $i
                Test-ShapeNode -Value $Value[$i] -Node $Node.Items -Path $itemPath -Errors $Errors
            }
            if ($Node.Unique) {
                foreach ($message in @(Get-ShapeDuplicateError -Label $label -Node $Node -Items $Value)) {
                    $Errors.Add($message)
                }
            }
        }
        'string' {
            if ($Value -isnot [string]) {
                $Errors.Add((Get-ShapeTypeError -Label $label -Node $Node -Value $Value))
                return
            }
            if ($Node.Pattern -and -not (Test-ShapePattern -Value $Value -Pattern $Node.Pattern)) {
                $Errors.Add("$label must be $($Node.Rule), got '$Value'.")
            }
        }
        'enum' {
            # Case-sensitive: Azure and GitHub expect the exact value.
            if ($Value -isnot [string]) {
                # As JSON: a list or a boolean printed as text would look like a valid value.
                $Errors.Add("$label must be one of $($Node.Values -join ', '), got $(Format-ShapeValue $Value).")
            }
            elseif ($Value -cnotin $Node.Values) {
                $Errors.Add("$label must be one of $($Node.Values -join ', '), got '$Value'.")
            }
        }
        'boolean' {
            if ($Value -isnot [bool]) {
                $Errors.Add((Get-ShapeTypeError -Label $label -Node $Node -Value $Value))
            }
        }
        'integer' {
            # ConvertFrom-Json reads whole numbers as int or long, beyond the long range as BigInteger; 30.0 and 1.5
            # become double or decimal.
            if ($Value -is [System.Numerics.BigInteger]) {
                $Errors.Add("$label is out of range for a whole number, got $Value.")
                return
            }
            if ($Value -isnot [int] -and $Value -isnot [long]) {
                $Errors.Add((Get-ShapeTypeError -Label $label -Node $Node -Value $Value))
                return
            }
            if ($Node.ContainsKey('Minimum') -and $Value -lt $Node.Minimum) {
                $Errors.Add("$label must be at least $($Node.Minimum), got $Value.")
            }
            if ($Node.ContainsKey('Maximum') -and $Value -gt $Node.Maximum) {
                $Errors.Add("$label must be at most $($Node.Maximum), got $Value.")
            }
        }
    }
}

function Get-ShapeDefinitionError {
    # The errors of a shape itself, for every node, also those the config has no value for: unknown keys and types.
    param(
        [Parameter(Mandatory)][hashtable]$Node,
        [AllowEmptyString()][string]$Path
    )

    $label = $Path
    if ($label -eq '') {
        $label = '(root)'
    }
    foreach ($key in @($Node.Keys | Sort-Object)) {
        if (-not $script:ShapeNodeKeys.Contains($key)) {
            "${label}: unknown key '$key'"
        }
    }
    if (-not $script:SchemaTypes.ContainsKey([string]$Node.Type)) {
        "${label}: unknown type '$($Node.Type)'"
    }
    if ($Node.Fields) {
        foreach ($key in $Node.Fields.Keys) {
            Get-ShapeDefinitionError -Node $Node.Fields[$key] -Path (Join-ShapePath -Parent $Path -Child $key)
        }
    }
    if ($Node.Items) {
        Get-ShapeDefinitionError -Node $Node.Items -Path "$Path[]"
    }
    if ($Node.Value) {
        Get-ShapeDefinitionError -Node $Node.Value -Path "$Path.*"
    }
}

function Assert-ShapeDefinition {
    # Throws on an invalid shape: a code error, found by any test that uses the shape.
    param([Parameter(Mandatory)][hashtable]$Shape)

    $errors = @(Get-ShapeDefinitionError -Node $Shape -Path '')
    if ($errors) {
        throw "Invalid shape: $($errors -join '; ')."
    }
}

function Test-ConfigShape {
    <#
    .SYNOPSIS
    Checks a config against its shape and returns error messages (empty when the shape is valid).
    .DESCRIPTION
    Every key of an object is required, unknown keys are errors (a top-level $schema is allowed), and every value must
    match its node. The items of an array marked Unique must not repeat: the strings, or the values of its ItemKey,
    compared case-insensitively. All errors are collected at once.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Config,
        [Parameter(Mandatory)][hashtable]$Shape
    )

    Assert-ShapeDefinition -Shape $Shape
    $errors = [System.Collections.Generic.List[string]]::new()
    Test-ShapeNode -Value $Config -Node $Shape -Path '' -Errors $errors
    return $errors.ToArray()
}

function Find-ShapeField {
    # Path -> node of every field for which Match returns true, in shape order. Only objects are walked: arrays and maps
    # hold project data.
    param(
        [Parameter(Mandatory)][hashtable]$Node,
        [Parameter(Mandatory)][scriptblock]$Match,
        [AllowEmptyString()][string]$Path = ''
    )

    $result = [ordered]@{}
    if ($Node.Type -ne 'object') {
        return $result
    }
    foreach ($key in $Node.Fields.Keys) {
        $child = $Node.Fields[$key]
        $childPath = Join-ShapePath -Parent $Path -Child $key
        if (& $Match $child) {
            $result[$childPath] = $child
        }
        $nested = Find-ShapeField -Node $child -Match $Match -Path $childPath
        foreach ($nestedPath in $nested.Keys) {
            $result[$nestedPath] = $nested[$nestedPath]
        }
    }
    return $result
}

function Get-ShapeRecommendation {
    # Path -> node of every field with a recommended value, in shape order.
    param([Parameter(Mandatory)][hashtable]$Node)
    return Find-ShapeField -Node $Node -Match { param($field) $field.ContainsKey('Recommended') }
}

function Get-ShapeRuleField {
    # Path -> node of every field whose engine rule takes exceptions (RuleExceptions), in shape order.
    param([Parameter(Mandatory)][hashtable]$Node)
    return Find-ShapeField -Node $Node -Match { param($field) $field.RuleExceptions }
}

function Get-ShapeItemList {
    # Path -> node of every list whose items take exceptions (ItemExceptions), in shape order.
    param([Parameter(Mandatory)][hashtable]$Node)
    return Find-ShapeField -Node $Node -Match { param($field) $field.Type -eq 'array' -and $field.ItemExceptions }
}

function Split-ExceptionItemPath {
    # "roles['Full Admin']" -> {List = 'roles'; Item = 'Full Admin'}; $null for a field path.
    param([AllowNull()][string]$Path)

    if ($Path -cmatch "^(?<list>[^\[\]']+)\['(?<item>[^']+)'\]\z") {
        return [pscustomobject]@{ List = $Matches.list; Item = $Matches.item }
    }
    return $null
}

function Get-ExceptionWaiver {
    # The waiver line of an exception in force on Today, or $null once it has expired (it applies through its expiresOn day).
    param(
        [Parameter(Mandatory)][object]$Exception,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][datetime]$Today
    )

    $expires = [datetime]::ParseExact($Exception.expiresOn, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $days = ($expires - $Today.Date).Days
    if ($days -lt 0) {
        return $null
    }
    $line = "Waived until $($Exception.expiresOn) ($($Exception.category)): $Path - $($Exception.reason)"
    if ($days -eq 0) {
        $line += ' (expires today)'
    }
    elseif ($days -eq 1) {
        $line += ' (expires in 1 day)'
    }
    elseif ($days -le 30) {
        $line += " (expires in $days days)"
    }
    return $line
}

function Get-ShapeValue {
    # The value at a dotted path, and whether every key on the way exists (compared case-sensitively).
    param(
        [AllowNull()][object]$Config,
        [Parameter(Mandatory)][string]$Path
    )

    $node = $Config
    foreach ($part in $Path.Split('.')) {
        if ($node -isnot [System.Management.Automation.PSCustomObject]) {
            return [pscustomobject]@{ Found = $false; Value = $null }
        }
        $property = Get-ShapeProperty -Object $node -Name $part
        if (-not $property) {
            return [pscustomobject]@{ Found = $false; Value = $null }
        }
        $node = $property.Value
    }
    return [pscustomobject]@{ Found = $true; Value = $node }
}

function Get-ExceptionShape {
    <#
    .SYNOPSIS
    The shape of the exceptions list of a config: deliberate, dated deviations from the recommended values of Shape, or
    items of its lists marked ItemExceptions that break a rule of the engine.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][hashtable]$Shape)

    $fields = [string[]]@((Get-ShapeRecommendation -Node $Shape).Keys)
    $fields += [string[]]@((Get-ShapeRuleField -Node $Shape).Keys | Where-Object { $_ -cnotin $fields })
    $lists = [string[]]@((Get-ShapeItemList -Node $Shape).Keys)
    $field = @{ Type = 'string'; Pattern = '^\S+$'; Rule = 'a field path such as settings.email'; SchemaEnum = $fields; Description = 'Path of the field the exception covers.' }
    if ($lists) {
        # An item path such as roles['Full Admin'] may hold spaces, and the list of item names is project data, so the
        # schema offers no fixed list of paths.
        $alternatives = @($lists | ForEach-Object { "$([regex]::Escape($_))\['[^']+'\]" })
        $item = "$($lists[0])['<name>']"
        $rules = @("a list item such as $item")
        $description = "The list item the exception covers, such as $item."
        if ($fields) {
            $alternatives = @('\S+') + $alternatives
            $rules = @('a field path such as settings.email') + $rules
            $description = "Path of the field or list item the exception covers; an item as $item."
        }
        $field = @{ Type = 'string'; Pattern = "^(?:$($alternatives -join '|'))$"; Rule = $rules -join ' or '; Description = $description }
    }
    @{
        Type        = 'array'
        ItemKey     = 'field'
        Unique      = $true
        Description = 'Deliberate deviations from a recommended value or a rule, each with a reason and an expiry date at most one year ahead; [] for none.'
        Items       = @{
            Type   = 'object'
            Fields = [ordered]@{
                field     = $field
                category  = @{ Type = 'enum'; Values = @('waiver', 'mitigated'); Description = 'waiver: the risk is accepted. mitigated: another control covers it.' }
                reason    = @{ Type = 'string'; Pattern = '\S'; Rule = 'a non-empty text'; Description = 'Why the recommended value or the rule is not followed.' }
                expiresOn = @{ Type = 'string'; Pattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; Rule = 'a date yyyy-MM-dd'; Description = 'Last day the exception applies, at most one year ahead; then the warning or error returns.' }
                reference = @{ Type = 'string'; Nullable = $true; Pattern = '^https://\S+$'; Rule = 'an https:// URL'; Description = 'An issue or decision behind the exception, or null.' }
            }
        }
    }
}

function Test-ExceptionList {
    <#
    .SYNOPSIS
    Rules between fields of a shape-valid exceptions list: a field with a recommended value or an item of a list that
    takes exceptions, and a real date at most one year after Today. Returns error messages. That a field has one
    exception at most is part of the shape (Unique).
    .DESCRIPTION
    An item the list does not hold is not an error here: Get-ItemExceptionReport warns about it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Exceptions,
        [Parameter(Mandatory)][hashtable]$Shape,
        [Parameter(Mandatory)][datetime]$Today
    )

    $ruleFields = @((Get-ShapeRuleField -Node $Shape).Keys)
    $fields = @((Get-ShapeRecommendation -Node $Shape).Keys) + $ruleFields
    $lists = @((Get-ShapeItemList -Node $Shape).Keys)
    $expected = @()
    if ($ruleFields) {
        $expected += 'a field with a recommended value or a rule'
    }
    elseif ($fields) {
        $expected += 'a field with a recommended value'
    }
    if ($lists) {
        $expected += "an item of $($lists -join ', ') (such as $($lists[0])['<name>'])"
    }
    $horizon = $Today.Date.AddYears(1)
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($exception in $Exceptions) {
        $path = "exceptions['$($exception.field)']"
        $item = Split-ExceptionItemPath -Path $exception.field
        # -cin: paths are case-sensitive, and [ordered] dictionaries are not.
        if ($exception.field -cnotin $fields -and -not ($item -and $item.List -cin $lists)) {
            $errors.Add("${path}: '$($exception.field)' is not $($expected -join ' or ').")
        }
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($exception.expiresOn, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
            $errors.Add("$path.expiresOn '$($exception.expiresOn)' is not a valid date.")
        }
        elseif ($date -gt $horizon) {
            $errors.Add("$path.expiresOn must be at most one year ahead ($($horizon.ToString('yyyy-MM-dd'))), got '$($exception.expiresOn)'.")
        }
    }
    return $errors.ToArray()
}

function Get-RecommendationReport {
    <#
    .SYNOPSIS
    Compares a valid config with the recommended values of its shape. Returns {Warnings, Waivers}: a deviation without
    an exception in force, an expired or unneeded exception are warnings; an exception in force is a waiver line.
    .DESCRIPTION
    A field missing from the config is skipped: validation reports it. An exception applies through its expiresOn day.
    The warning of a Sensitive node names the field, never its value or the recommended one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$Shape,
        [Parameter(Mandatory)][datetime]$Today
    )

    $exceptions = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($exception in @($Config.exceptions | Where-Object { $null -ne $_ })) {
        $exceptions[[string]$exception.field] = $exception
    }
    $warnings = [System.Collections.Generic.List[string]]::new()
    $waivers = [System.Collections.Generic.List[string]]::new()
    $fields = Get-ShapeRecommendation -Node $Shape
    foreach ($path in $fields.Keys) {
        $node = $fields[$path]
        $found = Get-ShapeValue -Config $Config -Path $path
        $exception = $null
        if ($exceptions.ContainsKey($path)) {
            $exception = $exceptions[$path]
        }
        if (-not $found.Found) {
            # A field inside a null section (actions.selected while allowed_actions is not 'selected').
            if ($exception) {
                $warnings.Add("The exception for $path does not apply: the config has no value for it. Remove it.")
            }
            continue
        }
        # As JSON: -ceq against a list filters it instead of comparing, and the shape makes the types match.
        if ((Format-ShapeValue $found.Value) -ceq (Format-ShapeValue $node.Recommended)) {
            if ($exception) {
                $warnings.Add("The exception for $path is not needed: the value is the recommended one. Remove it.")
            }
            continue
        }
        $recommendation = if ($node.Sensitive) {
            "$path differs from the recommended value (sensitive, values not shown): $($node.Why)"
        }
        else {
            "$path is $(Format-ShapeValue $found.Value); recommended $(Format-ShapeValue $node.Recommended): $($node.Why)"
        }
        if (-not $exception) {
            $warnings.Add("$recommendation To keep it, add an entry to exceptions.")
            continue
        }
        $waiver = Get-ExceptionWaiver -Exception $exception -Path $path -Today $Today
        if (-not $waiver) {
            $warnings.Add("$recommendation The exception expired on $($exception.expiresOn).")
            continue
        }
        $waivers.Add($waiver)
    }
    [pscustomobject]@{ Warnings = $warnings.ToArray(); Waivers = $waivers.ToArray() }
}

function Get-ItemExceptionReport {
    <#
    .SYNOPSIS
    Applies the exceptions for the items of one list to the findings of an engine rule on that list. Returns
    {NotWaived, Warnings, Waivers}: a finding without an exception in force is not waived (the engine decides whether
    that is an error or a warning); an exception in force is a waiver line; an exception for an item without a finding,
    or for an item the list does not hold, is a warning.
    .DESCRIPTION
    Finding maps an item of the list (the string, or the value of the list's ItemKey) to its message. Items are compared
    case-sensitively, as field paths are.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$Shape,
        [Parameter(Mandatory)][string]$List,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.IDictionary]$Finding,
        # Why an exception for an item without a finding is not needed, such as 'the role cannot grant access'.
        [Parameter(Mandatory)][string]$NotNeeded,
        [Parameter(Mandatory)][datetime]$Today
    )

    $lists = Get-ShapeItemList -Node $Shape
    if ($List -cnotin @($lists.Keys)) {
        throw "'$List' is not a list whose items take exceptions."
    }
    $itemKey = $lists[$List].ItemKey
    $items = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in @((Get-ShapeValue -Config $Config -Path $List).Value)) {
        $items.Add([string]($itemKey ? $item.$itemKey : $item)) | Out-Null
    }
    $findingItems = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Finding.Keys), [StringComparer]::Ordinal)
    $exceptions = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($exception in @($Config.exceptions | Where-Object { $null -ne $_ })) {
        $parsed = Split-ExceptionItemPath -Path $exception.field
        if ($parsed -and $parsed.List -ceq $List) {
            $exceptions[$parsed.Item] = $exception
        }
    }

    $notWaived = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $waivers = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Finding.Keys) {
        $message = $Finding[$item]
        if (-not $exceptions.ContainsKey($item)) {
            $notWaived.Add("$message To keep it, add an entry to exceptions.")
            continue
        }
        $exception = $exceptions[$item]
        $waiver = Get-ExceptionWaiver -Exception $exception -Path $exception.field -Today $Today
        if (-not $waiver) {
            $notWaived.Add("$message The exception expired on $($exception.expiresOn).")
            continue
        }
        $waivers.Add($waiver)
    }
    foreach ($item in $exceptions.Keys) {
        if ($findingItems.Contains($item)) {
            continue
        }
        $path = $exceptions[$item].field
        if (-not $items.Contains($item)) {
            $warnings.Add("The exception for $path does not apply: '$item' is not in $List. Remove it.")
        }
        else {
            $warnings.Add("The exception for $path is not needed: $NotNeeded. Remove it.")
        }
    }
    [pscustomobject]@{ NotWaived = $notWaived.ToArray(); Warnings = $warnings.ToArray(); Waivers = $waivers.ToArray() }
}

function Get-RuleExceptionReport {
    <#
    .SYNOPSIS
    Applies the exception for one field to the finding of an engine rule on that field (a field marked RuleExceptions).
    Returns {NotWaived, Warnings, Waivers} as Get-ItemExceptionReport does: a finding without an exception in force is
    not waived; an exception in force is a waiver line; an exception while the rule holds is a warning.
    .DESCRIPTION
    Finding is the message of the rule, or $null or empty when the rule holds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$Shape,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][AllowEmptyString()][string]$Finding,
        # Why an exception while the rule holds is not needed, such as 'the list has entries'.
        [Parameter(Mandatory)][string]$NotNeeded,
        [Parameter(Mandatory)][datetime]$Today
    )

    if ($Path -cnotin @((Get-ShapeRuleField -Node $Shape).Keys)) {
        throw "'$Path' is not a field whose rule takes exceptions."
    }
    $exception = @($Config.exceptions | Where-Object { $null -ne $_ -and $_.field -ceq $Path }) | Select-Object -First 1
    $notWaived = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $waivers = [System.Collections.Generic.List[string]]::new()
    if (-not $Finding) {
        if ($exception) {
            $warnings.Add("The exception for $Path is not needed: $NotNeeded. Remove it.")
        }
    }
    elseif (-not $exception) {
        $notWaived.Add("$Finding To keep it, add an entry to exceptions.")
    }
    else {
        $waiver = Get-ExceptionWaiver -Exception $exception -Path $Path -Today $Today
        if ($waiver) {
            $waivers.Add($waiver)
        }
        else {
            $notWaived.Add("$Finding The exception expired on $($exception.expiresOn).")
        }
    }
    [pscustomobject]@{ NotWaived = $notWaived.ToArray(); Warnings = $warnings.ToArray(); Waivers = $waivers.ToArray() }
}

$script:SchemaTypes = @{ object = 'object'; map = 'object'; array = 'array'; string = 'string'; enum = 'string'; boolean = 'boolean'; integer = 'integer' }

function ConvertTo-SchemaNode {
    # The JSON Schema of a shape node, as an ordered dictionary.
    param([Parameter(Mandatory)][hashtable]$Node)

    $schema = [ordered]@{}
    $type = $script:SchemaTypes[$Node.Type]
    if ($Node.Nullable) {
        $schema['type'] = @($type, 'null')
    }
    else {
        $schema['type'] = $type
    }
    $description = @()
    if ($Node.Description) {
        $description += $Node.Description
    }
    if ($Node.ContainsKey('Recommended')) {
        $description += "Recommended: ``$(Format-ShapeValue $Node.Recommended)``. $($Node.Why)"
    }
    if ($description) {
        $schema['markdownDescription'] = $description -join ' '
    }
    if ($Node.ContainsKey('Recommended')) {
        $schema['default'] = $Node.Recommended
    }
    switch ($Node.Type) {
        'object' {
            $properties = [ordered]@{}
            foreach ($key in $Node.Fields.Keys) {
                $properties[$key] = ConvertTo-SchemaNode -Node $Node.Fields[$key]
            }
            $schema['properties'] = $properties
            $schema['required'] = [string[]]@($Node.Fields.Keys)
            $schema['additionalProperties'] = $false
        }
        'map' {
            $schema['patternProperties'] = [ordered]@{ $Node.KeyPattern = ConvertTo-SchemaNode -Node $Node.Value }
            $schema['additionalProperties'] = $false
        }
        'array' {
            $schema['items'] = ConvertTo-SchemaNode -Node $Node.Items
            if ($Node.MinItems) {
                $schema['minItems'] = $Node.MinItems
            }
            # Exact repeats only: JSON Schema compares strings case-sensitively and cannot compare objects by one key.
            if ($Node.Unique -and $Node.Items.Type -ne 'object') {
                $schema['uniqueItems'] = $true
            }
        }
        'string' {
            if ($Node.Pattern) {
                $schema['pattern'] = $Node.Pattern
            }
            if ($Node.SchemaEnum) {
                $schema['enum'] = [string[]]$Node.SchemaEnum
            }
        }
        'enum' {
            $values = [System.Collections.Generic.List[object]]::new()
            foreach ($value in $Node.Values) {
                $values.Add($value)
            }
            if ($Node.Nullable) {
                $values.Add($null)
            }
            $schema['enum'] = $values.ToArray()
        }
        'integer' {
            if ($Node.ContainsKey('Minimum')) {
                $schema['minimum'] = $Node.Minimum
            }
            if ($Node.ContainsKey('Maximum')) {
                $schema['maximum'] = $Node.Maximum
            }
        }
    }
    return $schema
}

function ConvertTo-ConfigSchema {
    <#
    .SYNOPSIS
    The JSON Schema (draft 2020-12) of a config, as text with LF line endings, for editor completion and hover.
    .DESCRIPTION
    Generated from the same shape the validator uses; the validator stays the authority (rules between fields are not
    in the schema).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Shape,
        [Parameter(Mandatory)][string]$Title
    )

    Assert-ShapeDefinition -Shape $Shape
    $root = [ordered]@{ '$schema' = 'https://json-schema.org/draft/2020-12/schema'; title = $Title }
    $body = ConvertTo-SchemaNode -Node $Shape
    foreach ($key in $body.Keys) {
        $root[$key] = $body[$key]
    }
    $root['properties'].Insert(0, '$schema', [ordered]@{ type = 'string'; markdownDescription = 'This schema, for the editor.' })
    $json = ConvertTo-Json -InputObject $root -Depth 64
    return ($json -replace "`r`n", "`n") + "`n"
}
