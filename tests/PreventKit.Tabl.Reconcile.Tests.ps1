BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'PreventKit reconcile diff (TABL)' {

    It 'adds desired values that are missing and keeps matching managed entries unchanged' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'bad.example.net'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ Value = 'bad.example.net'; Identity = '1'; Notes = 'PreventKit managed'; Classification = 'Managed' }
            )

            $diff = Get-ReconcileDiff -DesiredEntries $desired -CurrentEntries $current -CurrentValueProperty 'Value'

            @($diff.Adds).Count | Should -Be 1
            $diff.Adds[0].Value | Should -Be 'evil.example.com'
            @($diff.Removes).Count | Should -Be 0
            @($diff.Unchanged).Count | Should -Be 1
            $diff.UnmanagedMatchCount | Should -Be 0
        }
    }

    It 'marks stale managed entries for removal' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed'; Classification = 'Managed' },
                [pscustomobject]@{ Value = 'stale.example.org'; Identity = '2'; Notes = 'PreventKit managed'; Classification = 'Managed' }
            )

            $diff = Get-ReconcileDiff -DesiredEntries $desired -CurrentEntries $current -CurrentValueProperty 'Value'

            @($diff.Adds).Count | Should -Be 0
            @($diff.Removes).Count | Should -Be 1
            $diff.Removes[0].Value | Should -Be 'stale.example.org'
            @($diff.Unchanged).Count | Should -Be 1
        }
    }

    It 'never removes unmanaged matches' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed'; Classification = 'Managed' },
                [pscustomobject]@{ Value = 'admin.example.org'; Identity = '2'; Notes = 'administrator note'; Classification = 'UnmanagedMatch' }
            )

            $diff = Get-ReconcileDiff -DesiredEntries $desired -CurrentEntries $current -CurrentValueProperty 'Value'

            @($diff.Removes | Where-Object { $_.Classification -eq 'UnmanagedMatch' }).Count | Should -Be 0
            $diff.UnmanagedMatchCount | Should -Be 1
        }
    }

    It 'returns zero counts for empty desired and empty current' {
        InModuleScope PreventKit {
            $diff = Get-ReconcileDiff -DesiredEntries @() -CurrentEntries @() -CurrentValueProperty 'Value'

            @($diff.Adds).Count | Should -Be 0
            @($diff.Removes).Count | Should -Be 0
            @($diff.Unchanged).Count | Should -Be 0
            $diff.UnmanagedMatchCount | Should -Be 0
        }
    }
}

Describe 'PreventKit capacity preflight' {

    It 'passes when the planned managed count fits' {
        InModuleScope PreventKit {
            $preflight = Test-CapacityPreflight -CurrentManagedCount 4 -AddCount 2 -RemoveCount 1 -Capacity 10

            $preflight.Passed | Should -BeTrue
            $preflight.PlannedCount | Should -Be 5
            $preflight.Capacity | Should -Be 10
        }
    }

    It 'fails when the planned managed count exceeds capacity' {
        InModuleScope PreventKit {
            $preflight = Test-CapacityPreflight -CurrentManagedCount 9 -AddCount 3 -RemoveCount 0 -Capacity 10

            $preflight.Passed | Should -BeFalse
            $preflight.PlannedCount | Should -Be 12
        }
    }

    It 'counts removals as freeing capacity' {
        InModuleScope PreventKit {
            $preflight = Test-CapacityPreflight -CurrentManagedCount 9 -AddCount 2 -RemoveCount 2 -Capacity 10

            $preflight.Passed | Should -BeTrue
            $preflight.PlannedCount | Should -Be 9
        }
    }
}

Describe 'PreventKit TABL reconciliation' {

    It 'adds missing entries and removes stale managed entries, leaving unmanaged matches alone' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'new.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'keep.example.net'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ Value = 'keep.example.net'; Identity = '1'; Notes = 'PreventKit managed' },
                [pscustomobject]@{ Value = 'stale.example.org'; Identity = '2'; Notes = 'PreventKit managed' },
                [pscustomobject]@{ Value = 'admin.example.org'; Identity = '3'; Notes = 'administrator note' }
            )

            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries $desired -CurrentEntries $current -Capacity 10

            $result.Status | Should -Be 'Reconciled'
            Assert-MockCalled Add-TablManagedEntry -Times 1 -Exactly -ParameterFilter { $Values -contains 'new.example.com' }
            Assert-MockCalled Remove-TablManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Identities).Count -eq 1 -and @($Identities) -contains '2' -and @($Identities) -notcontains '3'
            }
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly -ParameterFilter { $Identities -contains '3' }
        }
    }

    It 'adds missing entries in batches carrying the owner marker in Notes' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'a.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'b.example.net'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'c.example.org'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )

            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries $desired -CurrentEntries @() -Capacity 10 -AddBatchSize 2

            Assert-MockCalled Add-TablManagedEntry -Times 2 -Exactly
            Assert-MockCalled Add-TablManagedEntry -Times 2 -Exactly -ParameterFilter { $Notes -match $script:ownerMarker }
        }
    }

    It 'aborts without any write when capacity preflight fails' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'new.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )

            Mock Add-TablManagedEntry { }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries $desired -CurrentEntries @() -Capacity 0

            $result.Status | Should -Be 'Aborted'
            $result.Preflight.Passed | Should -BeFalse
            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly
        }
    }

    It 'a second run against the reconciled target makes no changes' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Tool' }
            )
            $afterFirstRun = @(
                [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed entry' }
            )

            Mock Add-TablManagedEntry { }
            Mock Remove-TablManagedEntry { }

            $result = Invoke-TablReconciliation -DesiredEntries $desired -CurrentEntries $afterFirstRun -Capacity 10

            $result.Status | Should -Be 'NoChanges'
            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly
        }
    }
}

Describe 'PreventKit TABL managed entry removal' {

    It 'calls the target cmdlet with its supported parameter set, never with -Block' {
        InModuleScope PreventKit {
            function Remove-TenantAllowBlockListItems {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)][string]$ListType,
                    [Parameter(Mandatory)][string[]]$Ids,
                    [string[]]$Entries,
                    [string]$ListSubType
                )
            }

            $script:captured = @()
            Mock Remove-TenantAllowBlockListItems {
                $script:captured += [pscustomobject]@{
                    ListType = $ListType
                    Ids      = @($Ids)
                    Block    = $PSBoundParameters.ContainsKey('Block')
                }
            }

            Remove-TablManagedEntry -Identities @('1', '2')

            $script:captured.Count | Should -Be 1
            $script:captured[0].ListType | Should -Be 'Url'
            @($script:captured[0].Ids) | Should -Be @('1', '2')
            $script:captured[0].Block | Should -BeFalse
        }
    }
}

Describe 'PreventKit batch grouping' {

    It 'splits items into groups no larger than the batch size' {
        InModuleScope PreventKit {
            $items = 1..5
            $groups = @(Get-BatchGroup -Items $items -BatchSize 2)

            $groups.Count | Should -Be 3
            @($groups[0]).Count | Should -Be 2
            @($groups[1]).Count | Should -Be 2
            @($groups[2]).Count | Should -Be 1
        }
    }

    It 'returns a single empty group for empty input' {
        InModuleScope PreventKit {
            $groups = @(Get-BatchGroup -Items @() -BatchSize 2)

            $groups.Count | Should -Be 1
            @($groups[0]).Count | Should -Be 0
        }
    }
}
