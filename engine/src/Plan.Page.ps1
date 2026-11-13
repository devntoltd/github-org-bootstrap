# The settings pages as the run read them, for -PageWalk:
# every page with rows or an area, in menu order, each row with a mark from the state, the plan and the warnings of the
# run. Pure: no read and no write; GitHubOrg.psm1 prints it and stops at the pages.

# The pages of the areas whose actions the plan names, by action.
$script:AreaActionPages = @{
    CreateCodeSecurityConfiguration = 'security_products'
    UpdateCodeSecurityConfiguration = 'security_products'
    SetCodeSecurityDefault          = 'security_products'
    AttachCodeSecurityConfiguration = 'security_products'
    CreateRuleset                   = 'rules'
    UpdateRuleset                   = 'rules'
    CreateBudget                    = 'billing/budgets'
    UpdateBudget                    = 'billing/budgets'
    AddCopilotSeats                 = 'copilot/seat_management'
    AddCopilotTeam                  = 'copilot/seat_management'
}

$script:WalkMarks = @{ ok = '[ok]'; apply = '[apply]'; DIFF = '[DIFF]'; '?' = '[?]'; 'n/a' = '[n/a]'; set = '[set]' }

function ConvertTo-WarningItem {
    # A warning of a report that holds only text (recommendations, the reviewer rule), tagged with the row whose config
    # path starts it or follows "The exception for ", or with Page when it names no row.
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][string]$Page
    )

    $path = $null
    if ($Text -match '^The exception for (\S+) ' -or $Text -match '^(\S+) ') {
        $candidate = $Matches[1]
        $definition = @($script:SettingDefinitions | Where-Object { (Get-SettingPath -Definition $_) -ceq $candidate })[0]
        if ($definition) {
            return Get-TaggedWarning -Text $Text -Page $definition.Page -Path $candidate
        }
    }
    return Get-TaggedWarning -Text $Text -Page $Page -Path $path
}

function Get-SettingPageWalkWarning {
    # Every warning the run prints, tagged: the recommendations, the warnings of the organization, the reviewer rule.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$CurrentState,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [AllowEmptyCollection()][string[]]$Recommendations = @(),
        [AllowEmptyCollection()][string[]]$Reviewers = @()
    )

    @($Recommendations | Where-Object { $_ } | ForEach-Object { ConvertTo-WarningItem -Text $_ -Page $null })
    @(Get-GitHubOrgWarningItem -Config $Config -CurrentState $CurrentState -Plan $Plan)
    @($Reviewers | Where-Object { $_ } | ForEach-Object { Get-TaggedWarning -Text $_ -Page 'rules' -Path $null })
}

function Get-WalkRowNote {
    # The recommendation of a row whose config value differs from it, or the exception that waives it.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$Definition,
        [AllowNull()][object]$Desired,
        [Parameter(Mandatory)][datetime]$Today
    )

    if (-not $Definition.ContainsKey('Recommended') -or $Definition.Sensitive -or (Format-SettingValue $Definition.Recommended) -eq (Format-SettingValue $Desired)) {
        return $null
    }
    $path = Get-SettingPath -Definition $Definition
    $exception = @($Config.exceptions | Where-Object { $_ -and $_.field -ceq $path })[0]
    if ($exception) {
        $expires = [datetime]::ParseExact([string]$exception.expiresOn, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        if ($expires -ge $Today) {
            return "waived until $($exception.expiresOn)"
        }
    }
    return "recommended $(Format-ManualValue -Definition $Definition -Value $Definition.Recommended)"
}

function Get-WalkRow {
    # One row of a page: its mark, the expected and current values, the notes, and the warnings and actions it shows.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$CurrentState,
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Warnings,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Skipped,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Observations,
        [AllowNull()][System.Collections.IDictionary]$CheckedValues,
        [Parameter(Mandatory)][datetime]$Today
    )

    $path = Get-SettingPath -Definition $Definition
    $ui = Resolve-UiText -Definition $Definition -Organization ([string]$Config.organization)
    $desired = (Get-ConfiguredValue -Config $Config -Section $Definition.Section)[$Definition.Field]
    $own = @($Warnings | Where-Object { $_.Path -ceq $path })
    $notes = [System.Collections.Generic.List[string]]::new()
    $actions = @()
    $current = $null
    $hasCurrent = $false

    # A null section of the config (actions.selected while allowed_actions is not selected) sets nothing: whatever
    # GitHub still holds there is neither a difference nor a recommendation.
    $nullSection = $script:Sections.Contains($Definition.Section) -and $script:Sections[$Definition.Section].Nullable -and $null -eq (Get-ConfigSection -Config $Config -Section $Definition.Section)
    $inactive = if ($nullSection) { $null } else { Get-InactiveDependency -Config $Config -Definition $Definition }

    if ($Definition.Mode -eq 'manual') {
        $mark = 'set'
    }
    elseif ($nullSection) {
        $mark = 'n/a'
        $notes.Add('not set by the config: its section is null')
    }
    elseif ($inactive) {
        # As Get-SectionAction: GitHub ignores the field, so its value is neither a difference nor a change.
        $mark = 'n/a'
        $notes.Add("not applied while $inactive is false: GitHub keeps it as it is")
    }
    elseif ($Observations.Contains($path)) {
        $observation = $Observations[$path]
        $mark = if ($observation.Status -eq 'NotApplicable') { 'n/a' } else { '?' }
        $notes.Add($observation.Reason)
    }
    else {
        # As Get-GitHubOrgWarningItem: a row of an endpoint section from its section state, any other from
        # CheckedValues. A row of an endpoint section reads only that endpoint (test 'reads every row of an endpoint
        # section from that endpoint, so none is manual'), so the two never disagree.
        if ($script:Sections.Contains($Definition.Section)) {
            $property = $CurrentState.PSObject.Properties[$script:Sections[$Definition.Section].StateKey]
            $section = if ($property) { $property.Value } else { $null }
            if ($null -ne $section) {
                $current = $section[$Definition.Field]
                $hasCurrent = $true
            }
        }
        elseif ($null -ne $CheckedValues -and $CheckedValues.Contains($path)) {
            $current = $CheckedValues[$path]
            $hasCurrent = $true
        }
        $sectionAction = $null
        if ($Definition.Mode -eq 'apply' -and $script:Sections.Contains($Definition.Section) -and $Definition.Section -notin $Skipped) {
            $sectionAction = @($Plan | Where-Object { $_.Action -eq $script:Sections[$Definition.Section].Action })[0]
        }
        if (-not $hasCurrent -and $sectionAction) {
            # Not read (actions.selected before allowed_actions is selected), and this run sets it.
            $mark = 'apply'
            $actions = @($sectionAction.Summary)
        }
        elseif (-not $hasCurrent) {
            $mark = 'n/a'
            $notes.Add('not read this run')
        }
        elseif (Test-SettingEqual -Definition $Definition -Current $current -Desired $desired) {
            $mark = 'ok'
        }
        elseif ($Definition.Mode -eq 'check') {
            $mark = 'DIFF'
        }
        else {
            $action = @($Plan | Where-Object { $_.Action -eq $script:Sections[$Definition.Section].Action })[0]
            if ($action -and $Definition.Section -notin $Skipped) {
                $mark = 'apply'
                $actions = @($action.Summary)
            }
            else {
                $mark = 'DIFF'
                $notes.Add('not applied this run: GitHub returned fields the engine does not know (see "Not on a settings page")')
            }
        }
    }
    $note = if ($nullSection) { $null } else { Get-WalkRowNote -Config $Config -Definition $Definition -Desired $desired -Today $Today }
    if ($note) {
        $notes.Add($note)
    }

    $expected = 'a value that is not shown'
    $shown = $null
    if (-not $Definition.Sensitive) {
        $expected = Format-ManualValue -Definition $ui -Value $desired
        if ($mark -in @('DIFF', 'apply')) {
            $shown = if ($hasCurrent) { Format-ManualValue -Definition $ui -Value $current } else { 'not read' }
        }
    }
    [pscustomobject]@{
        Path     = $path
        Group    = $ui.UiGroup
        Control  = $(if ($ui.UiLabel -or $ui.Hint) { Get-ControlText -Definition $ui } else { $ui.UiGroup })
        Mark     = $mark
        Expected = $expected
        Current  = $shown
        Note     = $(if ($notes.Count -gt 0) { $notes -join '; ' } else { $null })
        Why      = $(if ($Definition.Why) { $Definition.Why } else { $Definition.Description })
        Warnings = @($own | ForEach-Object { $_.Text })
        # The mark of a checked mismatch and of an unread row tells its own warning; any other warning (a recommendation,
        # an expired exception) is printed under the row.
        Printed  = @($own | ForEach-Object { $_.Text } | Where-Object {
                -not ($mark -eq '?' -and $_ -like '* is not observed: *') -and -not ($mark -eq 'DIFF' -and $Definition.Mode -eq 'check' -and $_ -like '*, the config expects *')
            })
        Actions  = $actions
    }
}

function Get-SettingPageWalk {
    <#
    .SYNOPSIS
    The settings pages of the walk: {ReadAt, Pages, Other, ManualCount}. Each page {Path, Label, Url, Area, ReviewedOn,
    Rows, AreaLines, Stop}; Other {Actions, Warnings} holds what no page shows, so every action and warning of the run
    appears once.
    #>
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$CurrentState,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Warnings,
        [Parameter(Mandatory)][datetime]$Today
    )

    $observations = $CurrentState.PSObject.Properties['Observations'].Value
    if ($null -eq $observations) {
        $observations = @{}
    }
    $checkedValues = $CurrentState.PSObject.Properties['CheckedValues'].Value
    $skipped = [string[]]@(Get-SkippedPutSection -CurrentState $CurrentState)
    $usedWarnings = [System.Collections.Generic.HashSet[object]]::new()
    $usedActions = [System.Collections.Generic.HashSet[object]]::new()
    $pages = [System.Collections.Generic.List[object]]::new()
    $manual = 0

    foreach ($page in $script:SettingPages) {
        $url = "https://github.com/organizations/$($Config.organization)/settings/$($page.Path)"
        $pageWarnings = @($Warnings | Where-Object { $_.Page -eq $page.Path })
        if ($page.Area) {
            $lines = @(
                foreach ($action in @($Plan | Where-Object { $script:AreaActionPages[$_.Action] -eq $page.Path })) {
                    [void]$usedActions.Add($action)
                    [pscustomobject]@{ Mark = 'apply'; Text = $action.Summary }
                }
                foreach ($warning in $pageWarnings) {
                    [void]$usedWarnings.Add($warning)
                    [pscustomobject]@{ Mark = 'DIFF'; Text = $warning.Text }
                }
            )
            if ($lines.Count -eq 0) {
                $lines = @([pscustomobject]@{ Mark = 'ok'; Text = 'managed by the engine, no change planned, no warning' })
            }
            $pages.Add([pscustomobject]@{ Path = $page.Path; Label = $page.Label; Url = $url; Area = $page.Area; ReviewedOn = $page.ReviewedOn; Rows = @(); AreaLines = $lines; Stop = [bool]@($lines | Where-Object { $_.Mark -ne 'ok' }).Count })
            continue
        }
        $definitions = @(Get-PageRow -Page $page)
        if ($definitions.Count -eq 0) {
            continue
        }
        $rows = @(foreach ($definition in $definitions) {
                Get-WalkRow -Config $Config -CurrentState $CurrentState -Definition $definition -Plan $Plan -Warnings $Warnings -Skipped $skipped -Observations $observations -CheckedValues $checkedValues -Today $Today
            })
        $paths = @($rows | ForEach-Object { $_.Path })
        foreach ($warning in @($Warnings | Where-Object { $_.Path -and $_.Path -cin $paths })) {
            [void]$usedWarnings.Add($warning)
        }
        foreach ($row in @($rows | Where-Object { $_.Mark -eq 'apply' })) {
            foreach ($action in @($Plan | Where-Object { $_.Summary -cin $row.Actions })) {
                [void]$usedActions.Add($action)
            }
        }
        # A warning of the page that names no row of it stands on its own line.
        $lines = @(foreach ($warning in @($pageWarnings | Where-Object { -not $usedWarnings.Contains($_) -and -not $_.Path })) {
                [void]$usedWarnings.Add($warning)
                [pscustomobject]@{ Mark = 'DIFF'; Text = $warning.Text }
            })
        $manual += @($rows | Where-Object { $_.Mark -eq 'set' }).Count
        $stop = [bool](@($rows | Where-Object { $_.Mark -notin @('ok', 'n/a') -or @($_.Printed).Count -gt 0 }).Count + $lines.Count)
        $pages.Add([pscustomobject]@{ Path = $page.Path; Label = $page.Label; Url = $url; Area = $null; ReviewedOn = $page.ReviewedOn; Rows = $rows; AreaLines = $lines; Stop = $stop })
    }

    # An apply row without a page (NoUi) changes with the action of its section, which the plan shows, but on no page.
    $noPage = @(foreach ($definition in @($script:SettingDefinitions | Where-Object { $_.NoUi -and $_.Mode -eq 'apply' })) {
            $row = Get-WalkRow -Config $Config -CurrentState $CurrentState -Definition $definition -Plan $Plan -Warnings $Warnings -Skipped $skipped -Observations $observations -CheckedValues $checkedValues -Today $Today
            if ($row.Mark -in @('apply', 'DIFF')) {
                $row.Control = $row.Path
                $row
            }
        })
    # Its row stands for the action, as a row of a page does.
    foreach ($row in @($noPage | Where-Object { $_.Mark -eq 'apply' })) {
        foreach ($action in @($Plan | Where-Object { $_.Summary -cin $row.Actions })) {
            [void]$usedActions.Add($action)
        }
    }

    [pscustomobject]@{
        ReadAt      = $CurrentState.PSObject.Properties['ReadAt'].Value
        Pages       = $pages.ToArray()
        Other       = [pscustomobject]@{
            Rows     = $noPage
            Actions  = @($Plan | Where-Object { -not $usedActions.Contains($_) })
            Warnings = @($Warnings | Where-Object { -not $usedWarnings.Contains($_) })
        }
        ManualCount = $manual
    }
}

function Format-SettingPageWalkStart {
    # The first line of the walk: when the state it shows was read.
    param([AllowNull()][object]$ReadAt)

    if ($ReadAt -is [datetime]) {
        return "Page walk of the state read at $($ReadAt.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)) UTC. The marks show that read, not the pages now."
    }
    return 'Page walk of the state read by this run. The marks show that read, not the pages now.'
}

function Format-SettingPageWalkEnd {
    # The last line of the walk: the manual settings stay unchecked whatever the operator did.
    param([Parameter(Mandatory)][int]$ManualCount)

    return "$ManualCount manual settings were not checked by this run; the walk records nothing."
}

function Format-WalkRowLine {
    # One row: its mark, the control and the value the config expects, then in one pair of parentheses what it is now
    # and the notes.
    param([Parameter(Mandatory)][object]$Row)

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($Row.Mark -eq 'apply') {
        $parts.Add("now $($Row.Current)")
        $parts.Add('the engine sets it after the confirmation')
    }
    elseif ($Row.Mark -eq 'DIFF' -and $null -ne $Row.Current) {
        $parts.Add("now $($Row.Current)")
    }
    if ($Row.Note) {
        $parts.Add($Row.Note)
    }
    $line = '    {0,-8} {1}: {2}' -f $script:WalkMarks[$Row.Mark], $Row.Control, $Row.Expected
    if ($parts.Count -gt 0) {
        $line += " ($($parts -join '; '))"
    }
    return $line
}

function Format-SettingPageWalkPage {
    # The lines of one page: its header, then its rows under their groups, or one line when nothing needs a person.
    param(
        [Parameter(Mandatory)][object]$Page,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$Total
    )

    $header = "[$Index/$Total] $($Page.Label)  $($Page.Url)"
    if ($Page.ReviewedOn) {
        $header += "  (UI read $($Page.ReviewedOn))"
    }
    $header
    if (-not $Page.Stop) {
        if ($Page.Area) {
            '  [ok] managed by the engine, no change planned, no warning'
        }
        else {
            # Only the rows that match count; a row that was not compared keeps its line and its reason.
            "  [ok] $(@($Page.Rows | Where-Object { $_.Mark -eq 'ok' }).Count) settings match"
            $group = $null
            foreach ($row in @($Page.Rows | Where-Object { $_.Mark -ne 'ok' })) {
                if ($row.Group -cne $group) {
                    $group = $row.Group
                    "  $group"
                }
                Format-WalkRowLine -Row $row
            }
        }
        return
    }
    $group = $null
    foreach ($row in @($Page.Rows)) {
        if ($row.Group -cne $group) {
            $group = $row.Group
            "  $group"
        }
        Format-WalkRowLine -Row $row
        if ($row.Mark -in @('DIFF', 'set') -and $row.Why) {
            "             $($row.Why)"
        }
        foreach ($warning in @($row.Printed | Where-Object { $_ })) {
            "             ! $warning"
        }
    }
    foreach ($line in @($Page.AreaLines)) {
        '    {0,-8} {1}' -f $script:WalkMarks[$line.Mark], $line.Text
    }
}

function Format-SettingPageWalkOther {
    # The actions and warnings no settings page shows, or nothing.
    param([Parameter(Mandatory)][object]$Other)

    if (@($Other.Rows).Count + @($Other.Actions).Count + @($Other.Warnings).Count -eq 0) {
        return
    }
    'Not on a settings page'
    foreach ($row in @($Other.Rows)) {
        Format-WalkRowLine -Row $row
    }
    foreach ($action in @($Other.Actions)) {
        '    {0,-8} {1}' -f '[apply]', $action.Summary
    }
    foreach ($warning in @($Other.Warnings)) {
        '    {0,-8} {1}' -f '[DIFF]', $warning.Text
    }
}
