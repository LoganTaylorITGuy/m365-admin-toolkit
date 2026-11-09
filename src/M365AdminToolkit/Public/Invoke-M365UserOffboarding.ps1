function Invoke-M365UserOffboarding {
    <#
    .SYNOPSIS
        Runs a repeatable, auditable offboarding sequence for one or more users.

    .DESCRIPTION
        Steps, in order (each can be skipped):
          1. Block sign-in
          2. Revoke all refresh tokens / sessions
          3. Remove from all directly-assigned security and M365 groups
          4. Remove all assigned licenses (after groups, so group-based licensing is gone too)
          5. Stamp the account description with who/when for the audit trail

        Supports -WhatIf / -Confirm. Returns one result object per step so the
        output can be saved as evidence for a ticket or compliance review.

        Mailbox conversion to shared and forwarding are Exchange Online tasks
        and intentionally out of scope; see docs/offboarding-runbook.md.

    .EXAMPLE
        Invoke-M365UserOffboarding -UserPrincipalName jdoe@contoso.com -WhatIf

    .EXAMPLE
        Get-Content leavers.txt | Invoke-M365UserOffboarding -Confirm:$false |
            Export-Csv "offboarding-$(Get-Date -Format yyyyMMdd-HHmm).csv" -NoTypeInformation
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('UPN', 'Id')]
        [string[]] $UserPrincipalName,

        [switch] $KeepGroups,
        [switch] $KeepLicenses,

        [string] $Ticket
    )

    begin {
        Assert-GraphConnection -RequiredScopes 'User.ReadWrite.All', 'Group.ReadWrite.All'
        $operator     = (Get-MgContext).Account
        $ticketSuffix = if ($Ticket) { " ticket $Ticket" } else { '' }

        function ConvertTo-StepResult($Upn, $Step, $Status, $Detail) {
            [pscustomobject]@{
                Timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                UserPrincipalName = $Upn
                Step              = $Step
                Status            = $Status
                Detail            = $Detail
            }
        }
    }

    process {
        foreach ($upn in $UserPrincipalName) {
            try {
                $user = Get-MgUser -UserId $upn -Property 'id', 'userPrincipalName', 'assignedLicenses' -ErrorAction Stop
            }
            catch {
                ConvertTo-StepResult $upn 'Lookup' 'Failed' $_.Exception.Message
                continue
            }

            $steps = [ordered]@{
                'BlockSignIn'    = { Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop; 'Sign-in blocked' }
                'RevokeSessions' = { Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop | Out-Null; 'Refresh tokens revoked' }
            }

            if (-not $KeepGroups) {
                $steps['RemoveGroups'] = {
                    $groups = @(Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction Stop |
                        Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' })
                    $removed = 0
                    foreach ($g in $groups) {
                        # Dynamic groups can't be edited directly; they drop the user once attributes change.
                        if (@($g.AdditionalProperties.groupTypes) -contains 'DynamicMembership') { continue }
                        Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                        $removed++
                    }
                    "Removed from $removed group(s)"
                }
            }

            if (-not $KeepLicenses) {
                $steps['RemoveLicenses'] = {
                    $current = @(Get-MgUser -UserId $user.Id -Property 'assignedLicenses' -ErrorAction Stop).AssignedLicenses
                    $skuIds  = @($current | ForEach-Object SkuId)
                    if ($skuIds.Count -eq 0) { return 'No direct licenses' }
                    Set-MgUserLicense -UserId $user.Id -AddLicenses @() -RemoveLicenses $skuIds -ErrorAction Stop | Out-Null
                    "Removed $($skuIds.Count) license(s)"
                }
            }

            $steps['AuditStamp'] = {
                $note = "Offboarded $((Get-Date).ToString('yyyy-MM-dd HH:mm')) by $operator$ticketSuffix"
                Update-MgUser -UserId $user.Id -BodyParameter @{ employeeType = 'Offboarded'; officeLocation = $note } -ErrorAction Stop
                $note
            }

            foreach ($name in $steps.Keys) {
                if (-not $PSCmdlet.ShouldProcess($upn, $name)) {
                    ConvertTo-StepResult $upn $name 'Skipped' 'WhatIf / declined'
                    continue
                }
                try {
                    $detail = & $steps[$name]
                    ConvertTo-StepResult $upn $name 'Success' $detail
                }
                catch {
                    ConvertTo-StepResult $upn $name 'Failed' $_.Exception.Message
                    # Never leave an account half-offboarded silently: if blocking fails, stop this user.
                    if ($name -eq 'BlockSignIn') { break }
                }
            }
        }
    }
}
