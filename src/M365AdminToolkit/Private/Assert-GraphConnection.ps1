function Assert-GraphConnection {
    <#
    .SYNOPSIS
        Throws a clear error if there is no active Microsoft Graph session
        with the scopes a command needs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $RequiredScopes
    )

    $context = Get-MgContext
    if (-not $context) {
        throw 'Not connected to Microsoft Graph. Run Connect-M365Toolkit first.'
    }

    # App-only (certificate) auth uses app roles, not delegated scopes; trust the app registration.
    if ($context.AuthType -eq 'AppOnly') { return }

    $missing = $RequiredScopes | Where-Object { $_ -notin $context.Scopes }
    if ($missing) {
        throw "Graph session is missing required scope(s): $($missing -join ', '). Reconnect with Connect-M365Toolkit."
    }
}
