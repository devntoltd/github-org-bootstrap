# Inventory warnings: what the organization has and the inventory does not expect, and the reverse. Pure: no GitHub calls.

function ConvertTo-PermissionMap {
    # Permission name -> level, from a config object or a state dictionary; names compare case-insensitively.
    param([AllowNull()][object]$Permissions)

    $map = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($Permissions -is [System.Collections.IDictionary]) {
        foreach ($name in $Permissions.Keys) {
            $map[[string]$name] = [string]$Permissions[$name]
        }
    }
    elseif ($null -ne $Permissions) {
        foreach ($property in $Permissions.PSObject.Properties) {
            $map[$property.Name] = [string]$property.Value
        }
    }
    return , $map
}

function Format-PermissionList {
    # 'contents: write, metadata: read', sorted by name; 'none' for an App without permissions.
    param([Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.Dictionary[string, string]]$Map)

    if ($Map.Count -eq 0) {
        return 'none'
    }
    return (@($Map.Keys | Sort-Object | ForEach-Object { "${_}: $($Map[$_])" }) -join ', ')
}

function Get-AppDifference {
    # Every difference between an installed App and its inventory entry, as one line; empty when they match.
    # Permissions: added ones first, then changed levels, then removed ones, each sorted by name.
    param(
        [Parameter(Mandatory)][object]$Expected,
        [Parameter(Mandatory)][object]$Installed
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    if ([string]$Installed.RepositorySelection -cne [string]$Expected.repositorySelection) {
        $parts.Add("repository access: $($Expected.repositorySelection) -> $($Installed.RepositorySelection)")
    }
    $expectedMap = ConvertTo-PermissionMap -Permissions $Expected.permissions
    $installedMap = ConvertTo-PermissionMap -Permissions $Installed.Permissions
    $changes = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($installedMap.Keys | Sort-Object | Where-Object { -not $expectedMap.ContainsKey($_) })) {
        $changes.Add("+ ${name}: $($installedMap[$name])")
    }
    foreach ($name in @($installedMap.Keys | Sort-Object | Where-Object { $expectedMap.ContainsKey($_) -and $expectedMap[$_] -cne $installedMap[$_] })) {
        $changes.Add("${name}: $($expectedMap[$name]) -> $($installedMap[$name])")
    }
    foreach ($name in @($expectedMap.Keys | Sort-Object | Where-Object { -not $installedMap.ContainsKey($_) })) {
        $changes.Add("- ${name}: $($expectedMap[$name])")
    }
    if ($changes.Count -gt 0) {
        $parts.Add("permissions: $($changes -join ', ')")
    }
    return $parts -join '; '
}

function Get-OwnerWarning {
    # Warnings for a single owner, and for owners that differ from inventory.owners.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory
    )

    $organization = [string]$Config.organization
    $expected = $Config.inventory
    $peoplePage = "https://github.com/orgs/$organization/people"
    $owners = [string[]]@($Inventory.Owners)
    # No owner at all cannot happen (the gh account is one); the missing-owner warnings below would report it.
    if ($owners.Count -eq 1) {
        "'$organization' has a single owner ($($owners[0])). If that account loses its second factor, nobody can recover the organization: add a second owner at $peoplePage, and keep the two-factor recovery codes offline."
    }
    $ownerDifference = Compare-NameSet -Expected $expected.owners -Actual $owners
    foreach ($login in $ownerDifference.Extra) {
        "'$login' is an owner of '$organization' but not in inventory.owners. An unexpected owner is the usual way to keep access after a compromise: if you did not add them, remove them at $peoplePage and review the audit log; if you did, add them to inventory.owners."
    }
    foreach ($login in $ownerDifference.Missing) {
        "'$login' is in inventory.owners but not an owner of '$organization'. Update the list, or make them an owner at $peoplePage."
    }
}

function Get-AppWarning {
    # Warnings for installed GitHub Apps that are not in inventory.apps or differ from it, and for listed ones that
    # are not installed.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory
    )

    $organization = [string]$Config.organization
    $expected = $Config.inventory
    $installationsPage = "https://github.com/organizations/$organization/settings/installations"
    $expectedApps = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($app in @($expected.apps)) {
        $expectedApps[[string]$app.slug] = $app
    }
    foreach ($app in @($Inventory.Apps)) {
        $entry = $expectedApps[$app.Slug]
        if ($null -eq $entry) {
            $permissions = Format-PermissionList -Map (ConvertTo-PermissionMap -Permissions $app.Permissions)
            "GitHub App '$($app.Slug)' is installed with access to $($app.RepositorySelection) repositories (permissions: $permissions) but not in inventory.apps. An app can read code and often change workflows: if it is not expected, uninstall it at $installationsPage; if it is, add it to inventory.apps."
            continue
        }
        $difference = Get-AppDifference -Expected $entry -Installed $app
        if ($difference) {
            "GitHub App '$($app.Slug)' differs from inventory.apps: $difference. If you did not approve this, review its access at $installationsPage and the audit log; if you did, update inventory.apps."
        }
    }
    foreach ($slug in (Compare-NameSet -Expected @($expected.apps | ForEach-Object { $_.slug }) -Actual @($Inventory.Apps | ForEach-Object { $_.Slug })).Missing) {
        "GitHub App '$slug' is in inventory.apps but not installed in '$organization'. Update the list, or install it again."
    }
}

function Get-WebhookWarning {
    # Warnings for webhooks to hosts not in inventory.webhookHosts, for insecure webhooks, and for listed hosts that
    # no webhook sends to.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory
    )

    $organization = [string]$Config.organization
    $expected = $Config.inventory
    $hooksPage = "https://github.com/organizations/$organization/settings/hooks"
    $expectedHosts = Get-NameSet -Value $expected.webhookHosts
    foreach ($hook in @($Inventory.Webhooks)) {
        $name = if ($hook.Host) { "Organization webhook $($hook.Url)" } else { 'Organization webhook without a readable URL' }
        if (-not $expectedHosts.Contains($hook.Host)) {
            $activity = if ($hook.Active) { 'active' } else { 'inactive' }
            $details = "($activity; events: $(@($hook.Events) -join ', ')) is not in inventory.webhookHosts. It sends organization events outside GitHub: if it is not expected, delete it at $hooksPage"
            if ($hook.Host) {
                "$name $details; if it is, add '$($hook.Host)' to inventory.webhookHosts."
            }
            else {
                # No host to list, so no advice to add one.
                "$name $details."
            }
        }
        # Listed or not: a listed host does not make the delivery safe.
        $problems = [System.Collections.Generic.List[string]]::new()
        if (-not $hook.Https) {
            $problems.Add('its URL does not use https, so the organization events travel in clear text (use an https URL)')
        }
        elseif ($hook.VerifiesTls -eq $false) {
            # Without https there is no certificate to verify.
            $problems.Add('SSL verification is off, so anyone between GitHub and the receiver can read and answer the deliveries (enable SSL verification)')
        }
        if (-not $hook.HasSecret) {
            $problems.Add('it has no secret, so the receiver cannot tell its deliveries from forged ones (set a secret and check X-Hub-Signature-256 in the receiver)')
        }
        if ($problems.Count -gt 0) {
            "$name is not secure: $($problems -join '; '). Fix it at $hooksPage."
        }
        if ($hook.Https -and $null -eq $hook.VerifiesTls) {
            # Not a problem found: nothing is known, so it stays out of "not secure".
            "${name}: GitHub did not report whether SSL verification is on, so it could not be checked. Check it at $hooksPage."
        }
    }
    foreach ($hookHost in (Compare-NameSet -Expected $expected.webhookHosts -Actual @($Inventory.Webhooks | ForEach-Object { $_.Host })).Missing) {
        "No organization webhook sends to '$hookHost', which is in inventory.webhookHosts. If it was deleted on purpose, update the list; otherwise check the audit log and add it again at $hooksPage."
    }
}

function Get-OutsideCollaboratorWarning {
    # Warnings for outside collaborators that differ from inventory.outsideCollaborators.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory
    )

    $organization = [string]$Config.organization
    $expected = $Config.inventory
    $collaboratorsPage = "https://github.com/orgs/$organization/outside-collaborators"
    $collaboratorDifference = Compare-NameSet -Expected $expected.outsideCollaborators -Actual $Inventory.OutsideCollaborators
    foreach ($login in $collaboratorDifference.Extra) {
        "'$login' is an outside collaborator of '$organization' but not in inventory.outsideCollaborators. They reach repositories without being members, so neither the base permission nor a review of the members covers them: if they are not expected, remove them at $collaboratorsPage; if they are, add them to inventory.outsideCollaborators."
    }
    foreach ($login in $collaboratorDifference.Missing) {
        "'$login' is in inventory.outsideCollaborators but not an outside collaborator of '$organization'. Update the list."
    }
}

function Get-InvitationWarning {
    # A warning for every pending invitation to the organization or a repository, expired repository ones included,
    # and for every repository whose invitations could not be read.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory
    )

    $organization = [string]$Config.organization
    $invitationsPage = "https://github.com/orgs/$organization/people/pending_invitations"
    # Pending invitations come and go, so the config does not list them: every one is reported.
    foreach ($invitation in @($Inventory.Invitations)) {
        $invitee = if ($invitation.Login) { $invitation.Login } else { $invitation.Email }
        "Pending invitation of '$invitee' to '$organization' as $($invitation.Role), sent by $($invitation.Inviter) on $($invitation.CreatedAt). An invitation is access waiting to be accepted, possibly by the wrong account: if it is not expected, cancel it at $invitationsPage and review the audit log."
    }
    foreach ($invitation in @($Inventory.RepositoryInvitations)) {
        $invitee = if ($invitation.Login) { "'$($invitation.Login)'" } else { 'an account GitHub does not name' }
        $about = "invitation of $invitee to repository '$organization/$($invitation.Repository)' with $($invitation.Permission) access, sent by $($invitation.Inviter) on $($invitation.CreatedAt)"
        $accessPage = "https://github.com/$organization/$($invitation.Repository)/settings/access"
        if ($invitation.Expired) {
            "Expired $about. It can no longer be accepted, but an administrator of the repository can resend it: if it is not expected, cancel it at $accessPage."
        }
        else {
            "Pending $about. Accepting it makes the account an outside collaborator: if it is not expected, cancel it at $accessPage and review the audit log."
        }
    }
    foreach ($repository in @($Inventory.SkippedRepositories | Where-Object { $_ })) {
        "Repository '$repository' was listed, but its invitations could not be read: GitHub answered 404 (deleted, renamed or transferred during the run, or the gh account cannot see it). Pending invitations to it are not in this run; re-run to check it."
    }
}

function Get-InventoryWarning {
    # Warnings for the owners, GitHub Apps, webhooks and outside collaborators that differ from the inventory of the
    # config, for a single owner, and for every pending invitation to the organization or a repository. The engine
    # never changes any of them.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory
    )

    Get-OwnerWarning -Config $Config -Inventory $Inventory
    Get-AppWarning -Config $Config -Inventory $Inventory
    Get-WebhookWarning -Config $Config -Inventory $Inventory
    Get-OutsideCollaboratorWarning -Config $Config -Inventory $Inventory
    Get-InvitationWarning -Config $Config -Inventory $Inventory
}
