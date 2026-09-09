BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
}

Describe 'Ticket #39 auto-detect current entries' {

    It 'Invoke-PreventKitRun no longer exposes TablCurrentEntries, CniCurrentEntries or CniAuto' {
        $parameters = (Get-Command Invoke-PreventKitRun).Parameters.Keys

        $parameters | Should -Not -Contain 'TablCurrentEntries'
        $parameters | Should -Not -Contain 'CniCurrentEntries'
        $parameters | Should -Not -Contain 'CniAuto'
        $parameters | Should -Contain 'TablAuto'
        $parameters | Should -Contain 'CniToken'
    }

    It 'Start-PreventKitRun no longer exposes TablCurrentEntries, CniCurrentEntries or CniAuto' {
        $parameters = (Get-Command Start-PreventKitRun).Parameters.Keys

        $parameters | Should -Not -Contain 'TablCurrentEntries'
        $parameters | Should -Not -Contain 'CniCurrentEntries'
        $parameters | Should -Not -Contain 'CniAuto'
    }

    It 'a TABL run reads current entries live via Get-TenantAllowBlockListItems (manual path)' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            Mock Get-ExchangeOnlineSession { return [pscustomobject]@{ IsConnected = $true } }
            if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) { function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) } }
            Mock Get-TenantAllowBlockListItems { return @() }
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -TablCapacity 10

            Assert-MockCalled Get-TenantAllowBlockListItems -Times 1 -Exactly -ParameterFilter { $ListType -eq 'Url' -and $Block }
        }
    }

    It 'a CNI run reads current indicators live via Get-CniCurrentIndicators' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            Mock Get-CniCurrentIndicators { return @() }
            Mock Add-CniManagedEntry { return $Mappings }
            Mock Remove-CniManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -CniCapacity 10 -CniToken 'test-token'

            Assert-MockCalled Get-CniCurrentIndicators -Times 1 -Exactly
        }
    }

    It 'a WhatIf run performs no target reads' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            Mock Get-ExchangeOnlineSession { throw 'must not be called' }
            if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) { function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) } }
            Mock Get-TenantAllowBlockListItems { throw 'must not be called' }
            Mock Get-CniCurrentIndicators { throw 'must not be called' }
            Mock Get-CniTokenFromAzureCli { throw 'must not be called' }

            $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -WhatIf -TablCapacity 10 -CniCapacity 10 -CniToken 'test-token')

            $report | Should -Not -BeNullOrEmpty
            Assert-MockCalled Get-TenantAllowBlockListItems -Times 0 -Exactly
            Assert-MockCalled Get-CniCurrentIndicators -Times 0 -Exactly
        }
    }
}

Describe 'Ticket #40 pre-check existence before TABL adds' {

    It 'a TABL run with managed entries for all desired values reports NoChanges with no writes' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $allManaged = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'boot.net.anydesk.com'; Identity = '2'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'server.absolute.com'; Identity = '3'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = '136.243.104.235'; Identity = '4'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'GetScreen.me'; Identity = '5'; Notes = 'PreventKit managed entry' }
            )

            Mock Get-ExchangeOnlineSession { return [pscustomobject]@{ IsConnected = $true } }
            if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) { function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) } }
            Mock Get-TenantAllowBlockListItems { return $allManaged }
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 10

            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $entry.TargetOutcomes[0].Target | Should -Be 'Tabl'
            $entry.TargetOutcomes[0].Status | Should -Be 'NoChanges'
        }
    }

    It 'a TABL run with unmanaged entries for desired values reports them without adding' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $withUnmanaged = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '1'; Notes = 'administrator note' },
                [pscustomobject]@{ Value = 'boot.net.anydesk.com'; Identity = '2'; Notes = 'administrator note' }
            )

            Mock Get-ExchangeOnlineSession { return [pscustomobject]@{ IsConnected = $true } }
            if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) { function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) } }
            Mock Get-TenantAllowBlockListItems { return $withUnmanaged }
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 10

            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Values | Where-Object { $_ -in @('*.anydesk.com', 'boot.net.anydesk.com') }).Count -gt 0
            }

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $entry.TargetOutcomes[0].UnmanagedMatchCount | Should -Be 2
        }
    }

    It 'a TABL run that fails to read current entries surfaces Failed before any write' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Get-ExchangeOnlineSession { return [pscustomobject]@{ IsConnected = $true } }
            if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) { function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) } }
            Mock Get-TenantAllowBlockListItems { throw 'Exchange Online session not connected' }
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            { Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 10 -ErrorAction Stop } | Should -Throw

            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $entry.Status | Should -Be 'Failed'
        }
    }
}

Describe 'Ticket #41 CNI automatic configuration by default' {

    It 'a supplied CniToken skips Azure CLI acquisition but still verifies and reads' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            Mock Get-CniTokenFromAzureCli { throw 'must not be called' }
            Mock Get-CniCurrentIndicators { return @() }
            Mock Add-CniManagedEntry { return $Mappings }
            Mock Remove-CniManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -CniCapacity 10 -CniToken 'explicit-token'

            Assert-MockCalled Get-CniTokenFromAzureCli -Times 0 -Exactly
            Assert-MockCalled Get-CniCurrentIndicators -Times 1 -Exactly
        }
    }

    It 'an omitted CniToken acquires the token from Azure CLI' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:usedToken = $null
            Mock Get-CniTokenFromAzureCli { return 'cli-token' }
            Mock Get-CniCurrentIndicators {
                $script:usedToken = $Token
                return @()
            }
            Mock Add-CniManagedEntry { return $Mappings }
            Mock Remove-CniManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -CniCapacity 10

            $script:usedToken | Should -Be 'cli-token'
        }
    }

    It 'a run with no token fails before any request is sent' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            Mock Get-CniTokenFromAzureCli { return $null }
            Mock Invoke-CniApiRequest { throw 'must not be called' }
            Mock Invoke-CniReconciliation { }

            $errorMessage = $null
            try {
                Invoke-PreventKitRun -CatalogueDirectory $cleanDir -CniCapacity 10 -ErrorAction Stop
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Match 'token'
            Assert-MockCalled Invoke-CniReconciliation -Times 0 -Exactly
            Assert-MockCalled Invoke-CniApiRequest -Times 0 -Exactly
        }
    }
}

Describe 'Ticket #42 TABL batch operations' {

    It 'uses the documented operational batch sizes (add 50, remove 100)' {
        InModuleScope PreventKit {
            # Documented in Invoke-TablReconciliation help as operational choices
            # within the tenant block-entry limits (no per-call cap documented).
            $definition = (Get-Command Invoke-TablReconciliation).Definition
            $definition | Should -Match '\$AddBatchSize = 50'
            $definition | Should -Match '\$RemoveBatchSize = 100'
        }
    }

    It 'calls New-TenantAllowBlockListItems once per batch with the batch Entries array and OutputJson' {
        InModuleScope PreventKit {
            if (-not (Get-Command -Name New-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) {
                function New-TenantAllowBlockListItems {
                    [CmdletBinding()]
                    param($ListType, [switch]$Block, [string[]]$Entries, [string]$Notes, [switch]$NoExpiration, [switch]$OutputJson)
                }
            }
            $script:captured = @()
            Mock New-TenantAllowBlockListItems {
                $script:captured += [pscustomobject]@{
                    Entries    = @($Entries)
                    OutputJson = [bool]$OutputJson
                }
            }

            Add-TablManagedEntry -Values @('a.example.com', 'b.example.net') -Notes 'PreventKit managed entry'

            $script:captured.Count | Should -Be 1
            @($script:captured[0].Entries) | Should -Be @('a.example.com', 'b.example.net')
            $script:captured[0].OutputJson | Should -BeTrue
        }
    }

    It 'normalizes an OutputJson response and detects per-entry failures' {
        InModuleScope PreventKit {
            if (-not (Get-Command -Name New-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) {
                function New-TenantAllowBlockListItems {
                    [CmdletBinding()]
                    param($ListType, [switch]$Block, [string[]]$Entries, [string]$Notes, [switch]$NoExpiration, [switch]$OutputJson)
                }
            }
            Mock New-TenantAllowBlockListItems {
                return '[{"Value":"good.example.com","Status":"Success"},{"Value":"bad value","Status":"Failed","Error":"Invalid URL syntax"}]'
            }

            $result = Add-TablManagedEntry -Values @('good.example.com', 'bad value') -Notes 'PreventKit managed entry'

            $result.HasFailures | Should -BeTrue
            $result.Status | Should -Be 'Failed'
            $result.RawResponse | Should -Match 'Invalid URL syntax'
            @($result.Response).Count | Should -Be 2
            $result.Response[1].Error | Should -Be 'Invalid URL syntax'
        }
    }

    It 'reports an undocumented non-JSON response instead of assuming success' {
        InModuleScope PreventKit {
            if (-not (Get-Command -Name New-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) {
                function New-TenantAllowBlockListItems {
                    [CmdletBinding()]
                    param($ListType, [switch]$Block, [string[]]$Entries, [string]$Notes, [switch]$NoExpiration, [switch]$OutputJson)
                }
            }
            Mock New-TenantAllowBlockListItems { return 'unexpected response' }

            $result = Add-TablManagedEntry -Values @('good.example.com') -Notes 'PreventKit managed entry'

            $result.Status | Should -Be 'Unknown'
            $result.IsSuccessConfirmed | Should -BeFalse
            $result.RawResponse | Should -Be 'unexpected response'
            $result.Response | Should -Be 'unexpected response'
        }
    }

    It 'requires an explicit success marker before confirming an OutputJson response' {
        InModuleScope PreventKit {
            if (-not (Get-Command -Name New-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) {
                function New-TenantAllowBlockListItems {
                    [CmdletBinding()]
                    param($ListType, [switch]$Block, [string[]]$Entries, [string]$Notes, [switch]$NoExpiration, [switch]$OutputJson)
                }
            }
            Mock New-TenantAllowBlockListItems { return '[{"Value":"good.example.com","Status":"Success"}]' }

            $result = Add-TablManagedEntry -Values @('good.example.com') -Notes 'PreventKit managed entry'

            $result.Status | Should -Be 'Succeeded'
            $result.IsSuccessConfirmed | Should -BeTrue
        }
    }

    It 'does not treat false or zero-valued error fields as failures' {
        InModuleScope PreventKit {
            $response = [pscustomobject]@{
                Status  = 'Success'
                Error   = $false
                Failure = 0
            }

            Get-TablBatchResponseStatus -Response $response | Should -Be 'Succeeded'
        }
    }

    It 'a partially failed add batch is reported and does not abort remaining batches' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'a.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'b.example.net'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'c.example.org'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )

            $script:attempts = 0
            Mock Add-TablManagedEntry {
                $script:attempts++
                if ($script:attempts -eq 1) {
                    return [pscustomobject]@{
                        HasFailures = $true
                        Response    = @(
                            [pscustomobject]@{ Value = 'a.example.com'; Status = 'Success' },
                            [pscustomobject]@{ Value = 'b.example.net'; Status = 'Failed'; Error = 'Invalid URL syntax' }
                        )
                    }
                }
                return [pscustomobject]@{ HasFailures = $false; Response = @() }
            }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries $desired -CurrentEntries @() -Capacity 10 -AddBatchSize 2

            $script:attempts | Should -Be 2
            $result.Status | Should -Be 'PartiallyReconciled'
            $result.FailedBatchCount | Should -Be 1
            @($result.BatchResults).Count | Should -Be 2
            $result.BatchResults[0].Status | Should -Be 'Partial'
            $result.BatchResults[0].RawResponse | Should -Not -BeNullOrEmpty
            $result.BatchResults[0].Response[1].Error | Should -Be 'Invalid URL syntax'
            $result.BatchResults[1].Status | Should -Be 'Succeeded'
        }
    }

    It 'a partially reconciled target makes the Run log Partial' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir } {
            $outcome = [pscustomobject]@{
                Target              = 'Tabl'
                Status              = 'PartiallyReconciled'
                Preflight           = [pscustomobject]@{ Passed = $true; PlannedCount = 3; Capacity = 10 }
                AddCount            = 3
                RemoveCount         = 0
                UnchangedCount      = 0
                UnmanagedMatchCount = 0
                FailedBatchCount    = 1
                BatchResults        = @([pscustomobject]@{ Operation = 'Add'; Status = 'Partial' })
            }

            $written = Write-PreventKitRunLog -LogDirectory $logDir -Snapshots @() -TargetOutcomes @($outcome)

            $written.Status | Should -Be 'Partial'
            $persisted = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $persisted.Status | Should -Be 'Partial'
            $persisted.TargetOutcomes[0].BatchResults[0].Status | Should -Be 'Partial'
        }
    }

    It 'a command-level batch failure is reported and later batches still run' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'a.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'b.example.net'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )

            $script:attempts = 0
            Mock Add-TablManagedEntry {
                $script:attempts++
                if ($script:attempts -eq 1) { throw 'Exchange command failed' }
                return [pscustomobject]@{ HasFailures = $false; Response = @() }
            }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries $desired -CurrentEntries @() -Capacity 10 -AddBatchSize 1

            $script:attempts | Should -Be 2
            $result.Status | Should -Be 'PartiallyReconciled'
            $result.BatchResults[0].Status | Should -Be 'Failed'
            $result.BatchResults[0].ErrorMessage | Should -Be 'Exchange command failed'
            $result.BatchResults[1].Status | Should -Be 'Succeeded'
        }
    }

    It 'persists a partial TABL Run with its per-batch response' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Get-ExchangeOnlineSession { return [pscustomobject]@{ IsConnected = $true } }
            if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) { function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) } }
            Mock Get-TenantAllowBlockListItems { return @() }
            if (-not (Get-Command -Name New-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) {
                function New-TenantAllowBlockListItems {
                    [CmdletBinding()]
                    param($ListType, [switch]$Block, [string[]]$Entries, [string]$Notes, [switch]$NoExpiration, [switch]$OutputJson)
                }
            }
            Mock New-TenantAllowBlockListItems {
                return '[{"Value":"bad value","Status":"Failed","Error":"Invalid URL syntax"}]'
            }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 10

            Assert-MockCalled New-TenantAllowBlockListItems -Times 1 -Exactly
            $persisted = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $persisted.Status | Should -Be 'Partial'
            $persisted.TargetOutcomes[0].Status | Should -Be 'PartiallyReconciled'
            $persisted.TargetOutcomes[0].BatchResults[0].RawResponse | Should -Match 'Invalid URL syntax'
            $persisted.TargetOutcomes[0].BatchResults[0].Response[0].Error | Should -Be 'Invalid URL syntax'
        }
    }

    It 'the remove path uses the same batching symmetrically' {
        InModuleScope PreventKit {
            $current = @(
                [pscustomobject]@{ Value = 'a.example.com'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'b.example.net'; Identity = '2'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'c.example.org'; Identity = '3'; Notes = 'PreventKit managed entry' }
            )

            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries @() -CurrentEntries $current -Capacity 10 -RemoveBatchSize 2

            $result.Status | Should -Be 'Reconciled'
            $result.RemoveCount | Should -Be 3
            Assert-MockCalled Remove-TablManagedEntry -Times 2 -Exactly
        }
    }
}
