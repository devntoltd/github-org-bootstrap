# The shape of the inventory: what the organization is expected to have. Pure: no GitHub calls.

$script:AppSlugPattern = '^[a-z0-9-]+$'
$script:PermissionNamePattern = '^[a-z_]+$'
$script:PermissionLevels = @('read', 'write', 'admin')
$script:RepositorySelections = @('all', 'selected')
# A host name only: a webhook URL can itself be a secret, and the config is committed.
$script:HostPattern = '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$'

function Get-InventoryNode {
    # The shape node of the inventory: what the organization is expected to have.
    $login = Get-ConfigPatternNode -Name Login
    @{
        Type        = 'object'
        Description = 'What the organization is expected to have; compared on every run, never changed.'
        Fields      = [ordered]@{
            owners               = @{ Type = 'array'; MinItems = 1; Unique = $true; Items = $login; Description = 'Logins of the owners, at least one.' }
            apps                 = @{
                Type        = 'array'
                ItemKey     = 'slug'
                Unique      = $true
                Description = 'One entry per installed GitHub App, as its installation shows it; [] for none.'
                Items       = @{
                    Type   = 'object'
                    Fields = [ordered]@{
                        slug                = @{ Type = 'string'; Pattern = $script:AppSlugPattern; Rule = "a slug of lower-case letters, digits and '-'" }
                        repositorySelection = @{ Type = 'enum'; Values = $script:RepositorySelections }
                        permissions         = @{ Type = 'map'; KeyPattern = $script:PermissionNamePattern; KeyRule = "lower-case letters and '_'"; Value = @{ Type = 'enum'; Values = $script:PermissionLevels } }
                    }
                }
            }
            webhookHosts         = @{
                Type        = 'array'
                Unique      = $true
                Items       = @{ Type = 'string'; Pattern = $script:HostPattern; Rule = 'a host name such as hooks.example.com, without scheme, path or port' }
                Description = 'Hosts of the organization webhooks, not the URL, which can be a secret; an internationalized host in its xn-- form. [] for none.'
            }
            outsideCollaborators = @{ Type = 'array'; Unique = $true; Items = $login; Description = 'Logins of the outside collaborators; [] for none.' }
        }
    }
}
