BeforeAll {
    . (Join-Path $PSScriptRoot 'GraphStubs.ps1')
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'M365AdminToolkit' 'M365AdminToolkit.psd1'
    Import-Module $modulePath -Force

    $script:delegatedAll = [pscustomobject]@{
        AuthType = 'Delegated'
        Account  = 'admin@contoso.com'
        TenantId = '00000000-0000-0000-0000-000000000000'
        Scopes   = @('User.Read.All', 'User.ReadWrite.All', 'Group.ReadWrite.All', 'AuditLog.Read.All',
                     'UserAuthenticationMethod.Read.All', 'Organization.Read.All', 'Directory.ReadWrite.All')
    }
}

AfterAll {
    Remove-Module M365AdminToolkit -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest (Join-Path $PSScriptRoot '..' 'src' 'M365AdminToolkit' 'M365AdminToolkit.psd1') } | Should -Not -Throw
    }

    It 'exports exactly the public functions' {
        $exported = (Get-Module M365AdminToolkit).ExportedFunctions.Keys | Sort-Object
        $exported | Should -Be @('Connect-M365Toolkit', 'Get-M365LicenseReport', 'Get-M365MfaReport', 'Get-M365StaleUser', 'Invoke-M365UserOffboarding')
    }

    It 'has comment-based help with examples on every public function' {
        foreach ($fn in (Get-Module M365AdminToolkit).ExportedFunctions.Keys) {
            $help = Get-Help $fn -Full
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$fn needs a synopsis"
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because "$fn needs an example"
        }
    }
}

Describe 'Assert-GraphConnection' {
    It 'throws when not connected' {
        Mock -ModuleName M365AdminToolkit Get-MgContext { $null }
        { Get-M365StaleUser } | Should -Throw '*Connect-M365Toolkit*'
    }

    It 'throws and names the missing scope' {
        Mock -ModuleName M365AdminToolkit Get-MgContext { [pscustomobject]@{ AuthType = 'Delegated'; Scopes = @('User.Read.All') } }
        { Get-M365StaleUser } | Should -Throw '*AuditLog.Read.All*'
    }

    It 'trusts app-only sessions' {
        Mock -ModuleName M365AdminToolkit Get-MgContext { [pscustomobject]@{ AuthType = 'AppOnly'; Scopes = @() } }
        Mock -ModuleName M365AdminToolkit Get-MgUser { @() }
        { Get-M365StaleUser } | Should -Not -Throw
    }
}

Describe 'Connect-M365Toolkit' {
    BeforeAll {
        Mock -ModuleName M365AdminToolkit Connect-MgGraph { }
        Mock -ModuleName M365AdminToolkit Get-MgContext { $script:delegatedAll }
    }

    It 'requests write scopes by default' {
        Connect-M365Toolkit
        Should -Invoke -ModuleName M365AdminToolkit Connect-MgGraph -ParameterFilter { $Scopes -contains 'User.ReadWrite.All' }
    }

    It 'requests only read scopes with -ReadOnly' {
        Connect-M365Toolkit -ReadOnly
        Should -Invoke -ModuleName M365AdminToolkit Connect-MgGraph -ParameterFilter { $Scopes -notcontains 'User.ReadWrite.All' -and $Scopes -contains 'User.Read.All' }
    }

    It 'uses certificate auth for app-only' {
        Connect-M365Toolkit -TenantId t -ClientId c -CertificateThumbprint ABC123
        Should -Invoke -ModuleName M365AdminToolkit Connect-MgGraph -ParameterFilter { $CertificateThumbprint -eq 'ABC123' -and -not $Scopes }
    }
}

Describe 'Get-M365StaleUser' {
    BeforeAll {
        $script:asOf = [datetime]'2026-06-01T12:00:00Z'
        Mock -ModuleName M365AdminToolkit Get-MgContext { $script:delegatedAll }
        Mock -ModuleName M365AdminToolkit Get-MgUser {
            @(
                [pscustomobject]@{ Id = '1'; DisplayName = 'Active';  UserPrincipalName = 'active@contoso.com';  UserType = 'Member'; CreatedDateTime = [datetime]'2024-01-01'
                    SignInActivity = [pscustomobject]@{ LastSignInDateTime = [datetime]'2026-05-30'; LastNonInteractiveSignInDateTime = $null }; AssignedLicenses = @(1) }
                [pscustomobject]@{ Id = '2'; DisplayName = 'Stale';   UserPrincipalName = 'stale@contoso.com';   UserType = 'Member'; CreatedDateTime = [datetime]'2024-01-01'
                    SignInActivity = [pscustomobject]@{ LastSignInDateTime = [datetime]'2025-12-01'; LastNonInteractiveSignInDateTime = [datetime]'2026-01-10' }; AssignedLicenses = @(1) }
                [pscustomobject]@{ Id = '3'; DisplayName = 'Never';   UserPrincipalName = 'never@contoso.com';   UserType = 'Member'; CreatedDateTime = [datetime]'2025-01-01'
                    SignInActivity = $null; AssignedLicenses = @() }
                [pscustomobject]@{ Id = '4'; DisplayName = 'NewHire'; UserPrincipalName = 'newhire@contoso.com'; UserType = 'Member'; CreatedDateTime = [datetime]'2026-05-25'
                    SignInActivity = $null; AssignedLicenses = @(1) }
                [pscustomobject]@{ Id = '5'; DisplayName = 'Guest';   UserPrincipalName = 'guest_ext#EXT#@contoso.com'; UserType = 'Guest'; CreatedDateTime = [datetime]'2024-01-01'
                    SignInActivity = [pscustomobject]@{ LastSignInDateTime = [datetime]'2025-01-01'; LastNonInteractiveSignInDateTime = $null }; AssignedLicenses = @() }
            )
        }
    }

    It 'returns stale and never-signed-in members, not active users or new hires' {
        $r = Get-M365StaleUser -Days 90 -AsOf $script:asOf
        $r.DisplayName | Sort-Object | Should -Be @('Never', 'Stale')
    }

    It 'uses the most recent of interactive and non-interactive sign-in' {
        $r = Get-M365StaleUser -Days 90 -AsOf $script:asOf | Where-Object DisplayName -eq 'Stale'
        $r.LastSignIn   | Should -Be ([datetime]'2026-01-10')
        $r.DaysInactive | Should -Be 142
    }

    It 'flags never-signed-in accounts' {
        (Get-M365StaleUser -AsOf $script:asOf | Where-Object DisplayName -eq 'Never').NeverSignedIn | Should -BeTrue
    }

    It 'includes guests only when asked' {
        (Get-M365StaleUser -AsOf $script:asOf).DisplayName | Should -Not -Contain 'Guest'
        (Get-M365StaleUser -AsOf $script:asOf -IncludeGuests).DisplayName | Should -Contain 'Guest'
    }

    It 'queries only enabled accounts' {
        Get-M365StaleUser -AsOf $script:asOf | Out-Null
        Should -Invoke -ModuleName M365AdminToolkit Get-MgUser -ParameterFilter { $Filter -eq 'accountEnabled eq true' }
    }
}

Describe 'Get-M365MfaReport' {
    BeforeAll {
        Mock -ModuleName M365AdminToolkit Get-MgContext { $script:delegatedAll }
        Mock -ModuleName M365AdminToolkit Get-MgReportAuthenticationMethodUserRegistrationDetail {
            @(
                [pscustomobject]@{ UserPrincipalName = 'admin-nomfa@contoso.com'; IsAdmin = $true;  IsMfaCapable = $false; IsPasswordlessCapable = $false; MethodsRegistered = @() }
                [pscustomobject]@{ UserPrincipalName = 'user-nomfa@contoso.com';  IsAdmin = $false; IsMfaCapable = $false; IsPasswordlessCapable = $false; MethodsRegistered = @() }
                [pscustomobject]@{ UserPrincipalName = 'sms-only@contoso.com';    IsAdmin = $false; IsMfaCapable = $true;  IsPasswordlessCapable = $false; MethodsRegistered = @('mobilePhone') }
                [pscustomobject]@{ UserPrincipalName = 'strong@contoso.com';      IsAdmin = $true;  IsMfaCapable = $true;  IsPasswordlessCapable = $true;  MethodsRegistered = @('microsoftAuthenticatorPush', 'fido2') }
            )
        }
    }

    It 'grades risk: <Upn> -> <Risk>' -ForEach @(
        @{ Upn = 'admin-nomfa@contoso.com'; Risk = 'Critical' }
        @{ Upn = 'user-nomfa@contoso.com';  Risk = 'High' }
        @{ Upn = 'sms-only@contoso.com';    Risk = 'Medium' }
        @{ Upn = 'strong@contoso.com';      Risk = 'Low' }
    ) {
        (Get-M365MfaReport | Where-Object UserPrincipalName -eq $Upn).Risk | Should -Be $Risk
    }

    It 'filters to admins' {
        (Get-M365MfaReport -AdminsOnly).UserPrincipalName | Sort-Object | Should -Be @('admin-nomfa@contoso.com', 'strong@contoso.com')
    }
}

Describe 'Get-M365LicenseReport' {
    BeforeAll {
        Mock -ModuleName M365AdminToolkit Get-MgContext { $script:delegatedAll }
        Mock -ModuleName M365AdminToolkit Get-MgSubscribedSku {
            @(
                [pscustomobject]@{ SkuPartNumber = 'SPB';              ConsumedUnits = 18; PrepaidUnits = [pscustomobject]@{ Enabled = 25;      Suspended = 0 } }
                [pscustomobject]@{ SkuPartNumber = 'EXCHANGESTANDARD'; ConsumedUnits = 5;  PrepaidUnits = [pscustomobject]@{ Enabled = 5;       Suspended = 0 } }
                [pscustomobject]@{ SkuPartNumber = 'FLOW_FREE';        ConsumedUnits = 3;  PrepaidUnits = [pscustomobject]@{ Enabled = 1000000; Suspended = 0 } }
            )
        }
    }

    It 'computes unused seats and monthly waste' {
        $r = Get-M365LicenseReport -PricePerSeat @{ SPB = 22 } | Where-Object Sku -eq 'SPB'
        $r.Unused       | Should -Be 7
        $r.MonthlyWaste | Should -Be 154
    }

    It 'leaves waste null when no price is known' {
        (Get-M365LicenseReport | Where-Object Sku -eq 'EXCHANGESTANDARD').MonthlyWaste | Should -BeNullOrEmpty
    }

    It 'hides free SKUs by default' {
        (Get-M365LicenseReport).Sku | Should -Not -Contain 'FLOW_FREE'
        (Get-M365LicenseReport -IncludeFreeSkus).Sku | Should -Contain 'FLOW_FREE'
    }
}

Describe 'Invoke-M365UserOffboarding' {
    BeforeEach {
        Mock -ModuleName M365AdminToolkit Get-MgContext { $script:delegatedAll }
        Mock -ModuleName M365AdminToolkit Get-MgUser {
            [pscustomobject]@{ Id = 'u1'; UserPrincipalName = 'leaver@contoso.com'; AssignedLicenses = @([pscustomobject]@{ SkuId = 'sku-a' }, [pscustomobject]@{ SkuId = 'sku-b' }) }
        }
        Mock -ModuleName M365AdminToolkit Update-MgUser { }
        Mock -ModuleName M365AdminToolkit Revoke-MgUserSignInSession { $true }
        Mock -ModuleName M365AdminToolkit Get-MgUserMemberOf {
            @(
                [pscustomobject]@{ Id = 'g-static'; AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.group'; groupTypes = @('Unified') } }
                [pscustomobject]@{ Id = 'g-dyn';    AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.group'; groupTypes = @('DynamicMembership') } }
                [pscustomobject]@{ Id = 'role-1';   AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.directoryRole' } }
            )
        }
        Mock -ModuleName M365AdminToolkit Remove-MgGroupMemberByRef { }
        Mock -ModuleName M365AdminToolkit Set-MgUserLicense { }
    }

    It 'makes no changes under -WhatIf' {
        $r = Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -WhatIf
        $r.Status | Select-Object -Unique | Should -Be 'Skipped'
        Should -Invoke -ModuleName M365AdminToolkit Update-MgUser -Times 0
        Should -Invoke -ModuleName M365AdminToolkit Revoke-MgUserSignInSession -Times 0
        Should -Invoke -ModuleName M365AdminToolkit Set-MgUserLicense -Times 0
    }

    It 'runs every step in order and reports success' {
        $r = Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -Ticket 'T-1042' -Confirm:$false
        $r.Step   | Should -Be @('BlockSignIn', 'RevokeSessions', 'RemoveGroups', 'RemoveLicenses', 'AuditStamp')
        $r.Status | Select-Object -Unique | Should -Be 'Success'
        ($r | Where-Object Step -eq 'AuditStamp').Detail | Should -BeLike '*T-1042*'
    }

    It 'blocks sign-in before anything else' {
        Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -Confirm:$false | Out-Null
        Should -Invoke -ModuleName M365AdminToolkit Update-MgUser -ParameterFilter { $AccountEnabled -eq $false } -Times 1
    }

    It 'skips dynamic groups and directory roles' {
        Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -Confirm:$false | Out-Null
        Should -Invoke -ModuleName M365AdminToolkit Remove-MgGroupMemberByRef -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g-static' }
        Should -Invoke -ModuleName M365AdminToolkit Remove-MgGroupMemberByRef -Times 1 -Exactly
    }

    It 'removes every assigned license' {
        Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -Confirm:$false | Out-Null
        Should -Invoke -ModuleName M365AdminToolkit Set-MgUserLicense -ParameterFilter { ($RemoveLicenses -join ',') -eq 'sku-a,sku-b' }
    }

    It 'honours -KeepGroups and -KeepLicenses' {
        $r = Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -KeepGroups -KeepLicenses -Confirm:$false
        $r.Step | Should -Not -Contain 'RemoveGroups'
        $r.Step | Should -Not -Contain 'RemoveLicenses'
    }

    It 'stops processing a user if blocking sign-in fails' {
        Mock -ModuleName M365AdminToolkit Update-MgUser { throw 'Insufficient privileges' } -ParameterFilter { $AccountEnabled -eq $false }
        $r = Invoke-M365UserOffboarding -UserPrincipalName leaver@contoso.com -Confirm:$false
        $r.Step   | Should -Be @('BlockSignIn')
        $r.Status | Should -Be 'Failed'
        Should -Invoke -ModuleName M365AdminToolkit Revoke-MgUserSignInSession -Times 0
    }

    It 'reports a lookup failure and continues with the next user' {
        Mock -ModuleName M365AdminToolkit Get-MgUser { throw 'Resource not found' } -ParameterFilter { $UserId -eq 'ghost@contoso.com' }
        $r = 'ghost@contoso.com', 'leaver@contoso.com' | Invoke-M365UserOffboarding -Confirm:$false
        ($r | Where-Object UserPrincipalName -eq 'ghost@contoso.com').Status | Should -Be 'Failed'
        ($r | Where-Object UserPrincipalName -eq 'leaver@contoso.com' | Where-Object Step -eq 'AuditStamp').Status | Should -Be 'Success'
    }
}
