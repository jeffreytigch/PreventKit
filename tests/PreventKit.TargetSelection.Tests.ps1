BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
}

Describe 'PreventKit destination selection contract' {

    It 'reconciles both destinations by default' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:tablConfigured = 0
            $script:cniConfigured  = 0

            Mock Get-AutoTablConfiguration {
                $script:tablConfigured++
                return [pscustomobject]@{ Capacity = $Capacity; CurrentEntries = @(); SessionVerified = $true; ConfigurationMode = 'Auto' }
            }
            Mock Get-AutoCniConfiguration {
                $script:cniConfigured++
                return [pscustomobject]@{ Token = 'token'; Capacity = $Capacity; CurrentEntries = @(); AuthorizationVerified = $true; ConfigurationMode = 'Auto' }
            }
            Mock Invoke-TablReconciliation { return [pscustomobject]@{ Target = 'Tabl'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }
            Mock Invoke-CniReconciliation { return [pscustomobject]@{ Target = 'Cni'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir

            $script:tablConfigured | Should -Be 1
            $script:cniConfigured | Should -Be 1
        }
    }

    It 'narrows the Run to TABL with -Target Tabl' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:cniConfigured = 0

            Mock Get-AutoTablConfiguration { return [pscustomobject]@{ Capacity = $Capacity; CurrentEntries = @(); SessionVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Get-AutoCniConfiguration { $script:cniConfigured++; return [pscustomobject]@{ Token = 'token'; Capacity = $Capacity; CurrentEntries = @(); AuthorizationVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Invoke-TablReconciliation { return [pscustomobject]@{ Target = 'Tabl'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }
            Mock Invoke-CniReconciliation { return [pscustomobject]@{ Target = 'Cni'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -Target Tabl

            $script:cniConfigured | Should -Be 0
        }
    }

    It 'narrows the Run to CNI with -Target Cni' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:tablConfigured = 0

            Mock Get-AutoTablConfiguration { $script:tablConfigured++; return [pscustomobject]@{ Capacity = $Capacity; CurrentEntries = @(); SessionVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Get-AutoCniConfiguration { return [pscustomobject]@{ Token = 'token'; Capacity = $Capacity; CurrentEntries = @(); AuthorizationVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Invoke-TablReconciliation { return [pscustomobject]@{ Target = 'Tabl'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }
            Mock Invoke-CniReconciliation { return [pscustomobject]@{ Target = 'Cni'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -Target Cni

            $script:tablConfigured | Should -Be 0
        }
    }

    It 'applies the plan-default capacities (TABL 1000, CNI 15000) when none are supplied' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:tablCapacity = $null
            $script:cniCapacity  = $null

            Mock Get-AutoTablConfiguration { $script:tablCapacity = $Capacity; return [pscustomobject]@{ Capacity = $Capacity; CurrentEntries = @(); SessionVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Get-AutoCniConfiguration { $script:cniCapacity = $Capacity; return [pscustomobject]@{ Token = 'token'; Capacity = $Capacity; CurrentEntries = @(); AuthorizationVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Invoke-TablReconciliation { return [pscustomobject]@{ Target = 'Tabl'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }
            Mock Invoke-CniReconciliation { return [pscustomobject]@{ Target = 'Cni'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir

            $script:tablCapacity | Should -Be 1000
            $script:cniCapacity | Should -Be 15000
        }
    }

    It 'applies a caller-supplied capacity as an override for a selected destination' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:tablCapacity = $null
            $script:cniCapacity  = $null

            Mock Get-AutoTablConfiguration { $script:tablCapacity = $Capacity; return [pscustomobject]@{ Capacity = $Capacity; CurrentEntries = @(); SessionVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Get-AutoCniConfiguration { $script:cniCapacity = $Capacity; return [pscustomobject]@{ Token = 'token'; Capacity = $Capacity; CurrentEntries = @(); AuthorizationVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Invoke-TablReconciliation { return [pscustomobject]@{ Target = 'Tabl'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }
            Mock Invoke-CniReconciliation { return [pscustomobject]@{ Target = 'Cni'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -TablCapacity 42 -CniCapacity 7

            $script:tablCapacity | Should -Be 42
            $script:cniCapacity | Should -Be 7
        }
    }

    It 'rejects an empty -Target selection' {
        { Invoke-PreventKitRun -CatalogueDirectory $cleanDir -Target @() } | Should -Throw
    }

    It 'rejects a CNI capacity supplied when CNI is not selected' {
        { Invoke-PreventKitRun -CatalogueDirectory $cleanDir -Target Tabl -CniCapacity 5 } |
            Should -Throw -ExpectedMessage '*not selected*'
    }

    It 'rejects a TABL capacity supplied when TABL is not selected' {
        { Invoke-PreventKitRun -CatalogueDirectory $cleanDir -Target Cni -TablCapacity 5 -CniToken 'x' } |
            Should -Throw -ExpectedMessage '*not selected*'
    }

    It 'records an unselected destination as skipped with a Not selected reason' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir; logDir = $logDir } {
            Mock Get-AutoTablConfiguration { return [pscustomobject]@{ Capacity = $Capacity; CurrentEntries = @(); SessionVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Get-AutoCniConfiguration { return [pscustomobject]@{ Token = 'token'; Capacity = $Capacity; CurrentEntries = @(); AuthorizationVerified = $true; ConfigurationMode = 'Auto' } }
            Mock Invoke-TablReconciliation { return [pscustomobject]@{ Target = 'Tabl'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }
            Mock Invoke-CniReconciliation { return [pscustomobject]@{ Target = 'Cni'; Status = 'NoChanges'; Preflight = [pscustomobject]@{ Passed = $true }; AddCount = 0; RemoveCount = 0; UnchangedCount = 0; UnmanagedMatchCount = 0 } }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -Target Tabl

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $cniConfig = $entry.TargetConfigurations | Where-Object { $_.Target -eq 'Cni' }
            $cniConfig.Status | Should -Be 'Skipped'
            $cniConfig.SelectionReason | Should -Be 'Not selected'
        }
    }
}

Describe 'PreventKit wrapper target forwarding' {

    It 'forwards -Target from Start-PreventKitRun to the Run engine' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:receivedTarget = $null
            Mock Invoke-PreventKitRun {
                $script:receivedTarget = @($Target)
                return $null
            }

            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir -Target Cni -CniCapacity 5

            @($script:receivedTarget) | Should -Be @('Cni')
        }
    }

    It 'does not forward -Target when the caller omits it' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:receivedTarget = 'sentinel'
            Mock Invoke-PreventKitRun {
                $script:receivedTarget = $Target
                return $null
            }

            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir

            $script:receivedTarget | Should -BeNullOrEmpty
        }
    }

    It 'the scheduled wrapper accepts -Target with the Tabl and Cni values' {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scheduled' 'Start-PreventKitScheduledRun.ps1'
        $parameters = (Get-Command $scriptPath).Parameters

        $parameters.Keys | Should -Contain 'Target'
        $parameters['Target'].Attributes.ValidValues | Should -Contain 'Tabl'
        $parameters['Target'].Attributes.ValidValues | Should -Contain 'Cni'
    }
}
