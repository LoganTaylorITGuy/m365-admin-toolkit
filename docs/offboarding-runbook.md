# Offboarding Runbook

The checklist I follow when someone leaves, and which steps this module automates.
The order matters: **cut access first, clean up second.**

## Same day (security-critical)

| # | Step | Automated | Why it's in this order |
|---|------|:---:|---|
| 1 | Block sign-in | ✅ `BlockSignIn` | Stops new logins immediately. If this fails, the module stops processing that user. |
| 2 | Revoke sessions / refresh tokens | ✅ `RevokeSessions` | Blocking sign-in doesn't kill existing sessions. This forces every app and device to re-authenticate. |
| 3 | Reset password | ⬜ | Good practice in hybrid/AD environments where the on-prem account syncs back. |
| 4 | Remove MFA methods / wipe or retire devices in Intune | ⬜ | Removes the leaver's phone as a trusted factor. Retire BYOD; wipe corporate devices. |
| 5 | Check for mail forwarding rules and OAuth app consents | ⬜ | A common way data keeps leaking after someone leaves. |

## Within 24–48 hours (cleanup)

| # | Step | Automated | Notes |
|---|------|:---:|---|
| 6 | Convert mailbox to shared, delegate to manager | ⬜ | Exchange Online (`Set-Mailbox -Type Shared`). Do this **before** removing licenses, or the mailbox goes into a 30-day soft-delete. |
| 7 | Transfer OneDrive ownership to manager | ⬜ | Entra keeps OneDrive for 30 days after deletion by default. |
| 8 | Remove from groups | ✅ `RemoveGroups` | Skips dynamic groups; they drop the user when attributes change. |
| 9 | Remove licenses | ✅ `RemoveLicenses` | Frees seats right away. Check `Get-M365LicenseReport` before the renewal. |
| 10 | Stamp audit trail | ✅ `AuditStamp` | Records who ran it, when, and the ticket number. |

## Usage

```powershell
Connect-M365Toolkit

# 1. Dry run. Always.
Invoke-M365UserOffboarding -UserPrincipalName jdoe@contoso.com -Ticket T-1042 -WhatIf

# 2. Convert the mailbox to shared first (Exchange Online), then:
Invoke-M365UserOffboarding -UserPrincipalName jdoe@contoso.com -Ticket T-1042 -Confirm:$false |
    Export-Csv "offboard-jdoe-$(Get-Date -Format yyyyMMdd-HHmm).csv" -NoTypeInformation
```

Attach the CSV to the ticket as evidence.
