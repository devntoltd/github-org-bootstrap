# Inventory reads: owners, Apps, webhooks, outside collaborators and invitations. Read-only.

function ConvertTo-DayString {
    # The UTC day of a GitHub timestamp: ConvertFrom-Json turns ISO 8601 strings into dates, other values stay strings.
    param([AllowNull()][object]$Value)

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    }
    $text = [string]$Value
    if ($text.Length -ge 10) {
        return $text.Substring(0, 10)
    }
    return $text
}

function Read-Owner {
    # The logins of the owners.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'owners'
    Read-OrgEndpoint -Endpoint "orgs/$Organization/members?role=admin&per_page=100" -Paginate | ForEach-Object { [string]$_.login }
}

function Read-InstalledApp {
    # The installed GitHub Apps: {Slug, RepositorySelection, Permissions}.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'GitHub Apps'
    # Unlike other lists, each page of installations is an object whose installations property holds the items.
    foreach ($page in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/installations?per_page=100" -Paginate)) {
        foreach ($installation in @($page.installations | Where-Object { $null -ne $_ })) {
            $permissions = [ordered]@{}
            if ($installation.permissions) {
                foreach ($permission in $installation.permissions.PSObject.Properties) {
                    $permissions[$permission.Name] = [string]$permission.Value
                }
            }
            [pscustomobject]@{
                Slug                = [string]$installation.app_slug
                RepositorySelection = [string]$installation.repository_selection
                Permissions         = $permissions
            }
        }
    }
}

function Read-Webhook {
    # The organization webhooks: {Host, Url, Events, Active, Https, VerifiesTls, HasSecret}, never the secret or the
    # path of the URL. VerifiesTls is $null when GitHub does not say.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'webhooks'
    foreach ($hook in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/hooks?per_page=100" -Paginate)) {
        $uri = $null
        $hookHost = ''
        $shownUrl = ''
        if ([uri]::TryCreate([string]$hook.config.url, [UriKind]::Absolute, [ref]$uri)) {
            # IdnHost: an internationalized host in the ASCII (punycode) form inventory.webhookHosts accepts.
            $hookHost = $uri.IdnHost
            # The path, query and user info of a webhook URL can hold a secret (a Slack incoming webhook, for
            # example), so only the scheme and host leave this function.
            $shownUrl = "$($uri.Scheme)://$hookHost/..."
        }
        # insecure_ssl is "0" (or 0) when TLS verification is on and "1" (or 1) when it is off; anything else proves
        # neither.
        $verifiesTls = switch ([string]$hook.config.insecure_ssl) {
            '0' { $true }
            '1' { $false }
            default { $null }
        }
        # GitHub masks a set secret as ********, so only whether one is set leaves this function.
        [pscustomobject]@{
            Host        = $hookHost
            Url         = $shownUrl
            Events      = [string[]]@($hook.events | Where-Object { $null -ne $_ })
            Active      = [bool]$hook.active
            Https       = $null -ne $uri -and $uri.Scheme -eq 'https'
            VerifiesTls = $verifiesTls
            HasSecret   = -not [string]::IsNullOrEmpty([string]$hook.config.secret)
        }
    }
}

function Read-OutsideCollaborator {
    # The logins of the outside collaborators.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'outside collaborators'
    Read-OrgEndpoint -Endpoint "orgs/$Organization/outside_collaborators?per_page=100" -Paginate | ForEach-Object { [string]$_.login }
}

function Read-Invitation {
    # The pending invitations to the organization: {Login, Email, Role, Inviter, CreatedAt}.
    param([Parameter(Mandatory)][string]$Organization)

    Write-StateProgress -Status 'invitations'
    foreach ($invitation in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/invitations?per_page=100" -Paginate)) {
        # An invitation by email has no login until it is accepted.
        [pscustomobject]@{
            Login     = $invitation.login
            Email     = $invitation.email
            Role      = [string]$invitation.role
            Inviter   = [string]$invitation.inviter.login
            CreatedAt = ConvertTo-DayString -Value $invitation.created_at
        }
    }
}

function Read-RepositoryInvitation {
    # The invitations to each repository, {Invitations, Skipped}: Invitations are {Repository, Login, Permission,
    # Inviter, CreatedAt, Expired}, Skipped the repositories that answered 404.
    param(
        [Parameter(Mandatory)][string]$Organization,
        # From Read-OrgRepository.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OrgRepository
    )

    # An outside collaborator is invited to a single repository, and GitHub lists those invitations only per
    # repository. Archived repositories too: accepting still gives read access to the code.
    $invitations = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $OrgRepository) {
        Write-StateProgress -Status "invitations of repository '$($entry.Name)'"
        try {
            $items = @(Read-OrgEndpoint -Endpoint "repos/$Organization/$($entry.Name)/invitations?per_page=100" -Paginate)
        }
        catch {
            # Deleted, renamed or transferred since the repository list was read, or not visible to this account:
            # a warning says so, since its invitations are not in the result.
            if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                throw
            }
            $skipped.Add($entry.Name)
            continue
        }
        foreach ($invitation in $items) {
            # The list includes expired invitations (expired: true); no invitee is an account GitHub answers as null.
            $invitations.Add([pscustomobject]@{
                    Repository = $entry.Name
                    Login      = $invitation.invitee.login
                    Permission = [string]$invitation.permissions
                    Inviter    = [string]$invitation.inviter.login
                    CreatedAt  = ConvertTo-DayString -Value $invitation.created_at
                    Expired    = [bool]$invitation.expired
                })
        }
    }
    return [pscustomobject]@{
        Invitations = $invitations.ToArray()
        Skipped     = $skipped.ToArray()
    }
}

function Read-InventoryState {
    # Owners, installed GitHub Apps, organization webhooks, outside collaborators and pending invitations to the
    # organization and its repositories. Read on every run: only the config says what is expected, so they are
    # compared with its inventory whatever else it manages.
    param(
        [Parameter(Mandatory)][string]$Organization,
        # From Read-OrgRepository.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OrgRepository
    )

    $repositoryInvitations = Read-RepositoryInvitation -Organization $Organization -OrgRepository $OrgRepository
    return [pscustomobject]@{
        Owners                = [string[]]@(Read-Owner -Organization $Organization)
        Apps                  = @(Read-InstalledApp -Organization $Organization)
        Webhooks              = @(Read-Webhook -Organization $Organization)
        OutsideCollaborators  = [string[]]@(Read-OutsideCollaborator -Organization $Organization)
        Invitations           = @(Read-Invitation -Organization $Organization)
        RepositoryInvitations = @($repositoryInvitations.Invitations)
        SkippedRepositories   = [string[]]@($repositoryInvitations.Skipped)
    }
}
