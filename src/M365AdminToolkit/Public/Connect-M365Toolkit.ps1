function Connect-M365Toolkit {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph with the scopes this toolkit needs.

    .DESCRIPTION
        Interactive (delegated) sign-in by default. For unattended runs, pass
        -ClientId, -TenantId and -CertificateThumbprint to use an Entra app
        registration with certificate auth. No secrets are stored by this module.

    .EXAMPLE
        Connect-M365Toolkit

    .EXAMPLE
        Connect-M365Toolkit -TenantId $env:M365_TENANT_ID -ClientId $env:M365_CLIENT_ID -CertificateThumbprint $env:M365_CERT_THUMBPRINT
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'AppOnly')]
        [string] $TenantId,

        [Parameter(Mandatory, ParameterSetName = 'AppOnly')]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'AppOnly')]
        [string] $CertificateThumbprint,

        [Parameter(ParameterSetName = 'Interactive')]
        [switch] $ReadOnly
    )

    $readScopes  = @('User.Read.All', 'AuditLog.Read.All', 'UserAuthenticationMethod.Read.All', 'Organization.Read.All')
    $writeScopes = @('User.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All')

    if ($PSCmdlet.ParameterSetName -eq 'AppOnly') {
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
    }
    else {
        $scopes = if ($ReadOnly) { $readScopes } else { $readScopes + $writeScopes }
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }

    $ctx = Get-MgContext
    Write-Verbose "Connected to tenant $($ctx.TenantId) as $($ctx.Account) ($($ctx.AuthType))."
}
