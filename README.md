# M365 Admin Toolkit

[![CI](https://github.com/LoganTaylorITGuy/m365-admin-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/LoganTaylorITGuy/m365-admin-toolkit/actions/workflows/ci.yml)
![PowerShell 7.2+](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)
![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-0078D4?logo=microsoft&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

A PowerShell module for the Microsoft 365 / Entra ID tasks that come up every week in an
MSP or small IT shop: **offboarding, stale-account cleanup, MFA coverage, and license waste.**
It uses the Microsoft Graph PowerShell SDK, so no legacy MSOnline or AzureAD modules are needed.

## Why I built this

After years of managing M365 tenants for multiple small-business clients, I saw the same
problems in almost every tenant: accounts left enabled after someone quit, admins without
MFA, and licenses paid for but never assigned. These are also the first things an auditor
or cyber-insurance questionnaire asks about.

This module turns those checks into one command each, with output you can attach to a
ticket or drop into a quarterly business review.

## Commands

| Command | What it answers |
|---|---|
| `Connect-M365Toolkit` | Signs in with least-privilege scopes (`-ReadOnly` for audits) or certificate-based app-only auth for unattended runs. |
| `Get-M365StaleUser` | *Who is still enabled but hasn't signed in for 90 days?* Checks both interactive and non-interactive sign-ins, ignores brand-new hires, and leaves out guests unless you include them. |
| `Get-M365MfaReport` | *Who can't do MFA, and which admins are exposed?* Rates each user Critical / High / Medium / Low and flags SMS-only users as weak. |
| `Get-M365LicenseReport` | *How much are we spending on seats nobody uses?* Shows purchased vs. assigned per SKU, with an optional monthly dollar figure for waste. |
| `Invoke-M365UserOffboarding` | Blocks sign-in, revokes sessions, removes groups, removes licenses, and stamps an audit note. Supports `-WhatIf` and `-Confirm` and returns a per-step result for each user. |

## Quick start

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
git clone https://github.com/LoganTaylorITGuy/m365-admin-toolkit.git
Import-Module ./m365-admin-toolkit/src/M365AdminToolkit

Connect-M365Toolkit -ReadOnly

# Tenant health check in three lines
Get-M365StaleUser -Days 90       | Export-Csv stale-users.csv -NoTypeInformation
Get-M365MfaReport                | Where-Object Risk -in 'Critical','High'
Get-M365LicenseReport -PricePerSeat @{ SPB = 22; O365_BUSINESS_STANDARD = 12.50 } |
    Sort-Object MonthlyWaste -Descending
```

### Example output

```text
PS> Get-M365LicenseReport -PricePerSeat @{ SPB = 22 } | Format-Table

Sku               Purchased Assigned Unused Suspended PricePerSeat MonthlyWaste
---               --------- -------- ------ --------- ------------ ------------
SPB                      25       18      7         0           22          154
EXCHANGESTANDARD          5        5      0         0
```

```text
PS> Invoke-M365UserOffboarding -UserPrincipalName jdoe@contoso.com -Ticket T-1042 -Confirm:$false

Timestamp           UserPrincipalName  Step           Status  Detail
---------           -----------------  ----           ------  ------
2026-06-01 14:02:11 jdoe@contoso.com   BlockSignIn    Success Sign-in blocked
2026-06-01 14:02:12 jdoe@contoso.com   RevokeSessions Success Refresh tokens revoked
2026-06-01 14:02:14 jdoe@contoso.com   RemoveGroups   Success Removed from 6 group(s)
2026-06-01 14:02:15 jdoe@contoso.com   RemoveLicenses Success Removed 2 license(s)
2026-06-01 14:02:15 jdoe@contoso.com   AuditStamp     Success Offboarded 2026-06-01 14:02 by admin@contoso.com ticket T-1042
```

See [docs/offboarding-runbook.md](docs/offboarding-runbook.md) for the full checklist, including
the Exchange and Intune steps the module deliberately leaves to a human.

## Design decisions

- **Fail safe.** If blocking sign-in fails, offboarding stops for that user rather than
  continuing and reporting a half-finished job as success.
- **`-WhatIf` everywhere it matters.** Destructive commands use `SupportsShouldProcess` with
  `ConfirmImpact = 'High'`, so they prompt by default.
- **Least privilege.** `-ReadOnly` requests only read scopes. Each command checks its own
  scopes up front and tells you exactly which one is missing.
- **No secrets in code.** Unattended runs use certificate auth on an Entra app registration;
  the module never stores credentials.
- **Testable without a tenant.** Graph cmdlets are stubbed and mocked, so the test suite runs
  in CI on Linux and Windows without the 100+ MB Graph SDK or any credentials.

## Testing

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed
```

30 Pester tests, about 99% code coverage, and a clean PSScriptAnalyzer run, checked by
GitHub Actions on every push.

## Requirements

- PowerShell 7.2+
- `Microsoft.Graph` PowerShell SDK
- Entra ID P1 for sign-in activity (`Get-M365StaleUser`)
- An admin role that can grant the requested Graph scopes

## License

MIT © Logan D Taylor
