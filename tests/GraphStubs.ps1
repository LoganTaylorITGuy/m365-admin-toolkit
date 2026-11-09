# Minimal stand-ins for Microsoft.Graph cmdlets so the suite runs in CI
# without installing the (very large) Graph SDK. Pester mocks replace these;
# the param blocks only need to match how the module calls them.
$stubs = @{
    'Get-MgContext'                                         = 'param()'
    'Connect-MgGraph'                                       = 'param($Scopes,$TenantId,$ClientId,$CertificateThumbprint,[switch]$NoWelcome)'
    'Get-MgUser'                                            = 'param($UserId,[switch]$All,$Filter,$Property)'
    'Update-MgUser'                                         = 'param($UserId,[switch]$AccountEnabled,$BodyParameter)'
    'Revoke-MgUserSignInSession'                            = 'param($UserId)'
    'Get-MgUserMemberOf'                                    = 'param($UserId,[switch]$All)'
    'Remove-MgGroupMemberByRef'                             = 'param($GroupId,$DirectoryObjectId)'
    'Set-MgUserLicense'                                     = 'param($UserId,$AddLicenses,$RemoveLicenses)'
    'Get-MgSubscribedSku'                                   = 'param([switch]$All)'
    'Get-MgReportAuthenticationMethodUserRegistrationDetail' = 'param([switch]$All)'
}

foreach ($name in $stubs.Keys) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        $body = "[CmdletBinding()] $($stubs[$name]) throw 'Graph stub called without a mock: $name'"
        Set-Item -Path "function:global:$name" -Value ([scriptblock]::Create($body))
    }
}
