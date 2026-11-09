@{
    RootModule           = 'M365AdminToolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '6f1d3c2a-8b4e-4f7a-9c1d-2e5b7a9f0c13'
    Author               = 'Logan D Taylor'
    Copyright            = '(c) Logan D Taylor. MIT License.'
    Description          = 'Microsoft 365 / Entra ID admin automation: offboarding, stale-account audit, MFA coverage, and license waste reporting via Microsoft Graph.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Connect-M365Toolkit'
        'Get-M365StaleUser'
        'Get-M365MfaReport'
        'Get-M365LicenseReport'
        'Invoke-M365UserOffboarding'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Microsoft365', 'EntraID', 'MicrosoftGraph', 'Offboarding', 'Security', 'MSP')
            LicenseUri = 'https://github.com/LoganTaylorITGuy/m365-admin-toolkit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/LoganTaylorITGuy/m365-admin-toolkit'
        }
    }
}
