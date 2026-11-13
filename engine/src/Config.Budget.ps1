# The shape of the budgets: a monthly limit per paid product. Pure: no GitHub calls.

$script:BudgetTypes = @('BundlePricing', 'ProductPricing', 'SkuPricing')

function Get-BudgetNode {
    # The shape node of the budgets, in the names of GitHub's API. Scope and alerts are not in the config: a budget here
    # is always the organization's, and it always alerts the owners of inventory.owners.
    @{
        Type        = 'array'
        ItemKey     = 'budget_product_sku'
        Unique      = $true
        Description = 'One entry per budget of the organization; a paid product without a budget has no limit. [] for none.'
        Items       = @{
            Type   = 'object'
            Fields = [ordered]@{
                budget_type           = @{ Type = 'enum'; Values = $script:BudgetTypes; Description = 'BundlePricing for ai_credits, ProductPricing for a product, SkuPricing for a single SKU.' }
                budget_product_sku    = @{ Type = 'string'; Pattern = '^[a-z0-9_]+$'; Rule = "a GitHub product or SKU id of lower-case letters, digits and '_'"; Description = 'The product or SKU id, such as actions or ghas_secret_protection_licenses.' }
                budget_amount         = @{ Type = 'integer'; Minimum = 0; Description = 'Whole dollars a month; the number of licenses for a license-based SKU.' }
                prevent_further_usage = @{ Type = 'boolean'; Description = 'Whether usage stops at the limit.' }
            }
        }
    }
}
