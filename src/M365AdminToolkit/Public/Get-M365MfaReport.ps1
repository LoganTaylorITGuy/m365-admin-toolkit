function Get-M365MfaReport {
    <#
    .SYNOPSIS
        Reports MFA registration coverage across the tenant.

    .DESCRIPTION
        Uses the Entra authentication-methods registration report to show who
        is MFA-capable, who only has weak methods (SMS/voice), and which admins
        are not protected. Pipe to Export-Csv for an audit artifact.

    .EXAMPLE
        Get-M365MfaReport | Where-Object { -not $_.MfaCapable }

    .EXAMPLE
        Get-M365MfaReport -AdminsOnly
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch] $AdminsOnly
    )

    Assert-GraphConnection -RequiredScopes 'AuditLog.Read.All', 'UserAuthenticationMethod.Read.All'

    $weakMethods = @('mobilePhone', 'alternateMobilePhone', 'officePhone', 'email')

    $rows = Get-MgReportAuthenticationMethodUserRegistrationDetail -All

    foreach ($r in $rows) {
        if ($AdminsOnly -and -not $r.IsAdmin) { continue }

        $methods = @($r.MethodsRegistered)
        $strong  = @($methods | Where-Object { $_ -notin $weakMethods })

        $risk = if (-not $r.IsMfaCapable -and $r.IsAdmin) { 'Critical' }
                elseif (-not $r.IsMfaCapable)             { 'High' }
                elseif ($strong.Count -eq 0)              { 'Medium' }
                else                                      { 'Low' }

        [pscustomobject]@{
            UserPrincipalName = $r.UserPrincipalName
            IsAdmin           = [bool]$r.IsAdmin
            MfaCapable        = [bool]$r.IsMfaCapable
            PasswordlessReady = [bool]$r.IsPasswordlessCapable
            StrongMethod      = $strong.Count -gt 0
            Methods           = $methods -join ', '
            Risk              = $risk
        }
    }
}
