function Get-M365LicenseReport {
    <#
    .SYNOPSIS
        Shows purchased vs. assigned licenses per SKU and the monthly cost of unused seats.

    .DESCRIPTION
        License waste is one of the easiest wins in an M365 review. Supply a
        price table (SKU part number -> monthly cost per seat) to turn unused
        seats into a dollar figure for a QBR or renewal conversation.

    .EXAMPLE
        Get-M365LicenseReport | Format-Table

    .EXAMPLE
        $prices = @{ SPB = 22.00; O365_BUSINESS_PREMIUM = 22.00; EXCHANGESTANDARD = 4.00 }
        Get-M365LicenseReport -PricePerSeat $prices | Sort-Object MonthlyWaste -Descending
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [hashtable] $PricePerSeat = @{},

        # Hide free/viral SKUs that have huge "purchased" counts and no cost.
        [switch] $IncludeFreeSkus
    )

    Assert-GraphConnection -RequiredScopes 'Organization.Read.All'

    foreach ($sku in Get-MgSubscribedSku -All) {
        $purchased = [int]$sku.PrepaidUnits.Enabled
        $assigned  = [int]$sku.ConsumedUnits

        if (-not $IncludeFreeSkus -and $purchased -ge 10000) { continue }

        $unused = [math]::Max(0, $purchased - $assigned)
        $price  = if ($PricePerSeat.ContainsKey($sku.SkuPartNumber)) { [decimal]$PricePerSeat[$sku.SkuPartNumber] } else { $null }

        [pscustomobject]@{
            Sku          = $sku.SkuPartNumber
            Purchased    = $purchased
            Assigned     = $assigned
            Unused       = $unused
            Suspended    = [int]$sku.PrepaidUnits.Suspended
            PricePerSeat = $price
            MonthlyWaste = if ($null -ne $price) { [math]::Round($unused * $price, 2) } else { $null }
        }
    }
}
