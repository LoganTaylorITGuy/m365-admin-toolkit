function Get-M365StaleUser {
    <#
    .SYNOPSIS
        Finds enabled accounts that have not signed in for N days.

    .DESCRIPTION
        Stale-but-enabled accounts are a common audit finding and a common
        attack path. This reports enabled users whose last interactive or
        non-interactive sign-in is older than -Days, plus accounts that have
        never signed in. Requires Entra ID P1 (signInActivity).

    .EXAMPLE
        Get-M365StaleUser -Days 90 | Export-Csv stale-users.csv -NoTypeInformation

    .EXAMPLE
        Get-M365StaleUser -Days 30 -IncludeGuests
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 3650)]
        [int] $Days = 90,

        [switch] $IncludeGuests,

        # Injectable for tests; defaults to now (UTC).
        [datetime] $AsOf = [datetime]::UtcNow
    )

    Assert-GraphConnection -RequiredScopes 'User.Read.All', 'AuditLog.Read.All'

    $cutoff = $AsOf.AddDays(-$Days)
    $props  = 'id', 'displayName', 'userPrincipalName', 'userType', 'accountEnabled', 'createdDateTime', 'signInActivity', 'assignedLicenses'

    $users = Get-MgUser -All -Filter 'accountEnabled eq true' -Property $props

    foreach ($u in $users) {
        if (-not $IncludeGuests -and $u.UserType -eq 'Guest') { continue }

        # signInActivity is null for accounts that have never signed in.
        $activity = $u.SignInActivity
        $last = if ($activity) {
            @($activity.LastSignInDateTime, $activity.LastNonInteractiveSignInDateTime) |
                Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        }

        # Brand-new accounts that simply haven't been used yet aren't "stale".
        if (-not $last -and $u.CreatedDateTime -gt $cutoff) { continue }
        if ($last -and $last -gt $cutoff) { continue }

        [pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            UserType          = $u.UserType
            LastSignIn        = $last
            DaysInactive      = if ($last) { [int]($AsOf - $last).TotalDays } else { $null }
            NeverSignedIn     = -not $last
            Licensed          = @($u.AssignedLicenses).Count -gt 0
            Id                = $u.Id
        }
    }
}
