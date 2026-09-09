BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
    $scheduledScript = Join-Path $PSScriptRoot '..' 'scheduled' 'Start-PreventKitScheduledRun.ps1'
}

Describe 'PreventKit scheduled Run wrapper' {

    It 'calls the same Run engine as a manual Run' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:calls = @()
            Mock Invoke-PreventKitRun {
                $script:calls += [pscustomobject]@{
                    CatalogueDirectory = $CatalogueDirectory
                    ExceptionKey       = $ExceptionKey
                }
                return $null
            }

            $exitCode = Start-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionKey @('domain:GetScreen.me')

            $exitCode | Should -Be 0
            $script:calls.Count | Should -Be 1
            $script:calls[0].CatalogueDirectory | Should -Be $cleanDir
            @($script:calls[0].ExceptionKey) | Should -Contain 'domain:GetScreen.me'
        }
    }

    It 'returns a zero exit code after a successful Run' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $exitCode = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir

            $exitCode | Should -Be 0
        }
    }

    It 'records a successful scheduled Run in the run log as Completed' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $entry.Status | Should -Be 'Completed'
            @($entry.SourceFingerprints).Count | Should -Be 1
        }
    }

    It 'returns a non-zero exit code when the Run fails' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Invoke-PreventKitRun { throw 'Engine failure' }

            $exitCode = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir

            $exitCode | Should -Be 1
        }
    }

    It 'a failing Run is observable in the run log with its error message' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Invoke-PreventKitRun { throw 'Engine failure' }

            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $entry.Status | Should -Be 'Failed'
            $entry.ErrorMessage | Should -Match 'Engine failure'
        }
    }

    It 'a failing Run still records the global exceptions that were in force' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $exceptionsDir = Join-Path $TestDrive 'exceptions'
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir; exceptionsDir = $exceptionsDir } {
            Mock Get-GlobalExceptionKey { return @('service:lolrmm/AnyDesk') }
            Mock Invoke-PreventKitRun { throw 'Engine failure' }

            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -ExceptionDirectory $exceptionsDir

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            @($entry.GlobalExceptions) | Should -Contain 'service:lolrmm/AnyDesk'
        }
    }

    It 'a scheduled Run failing during reconciliation records one Failed entry with partial outcomes' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }
            Mock Invoke-CniReconciliation { throw 'CNI API unavailable' }

            $exitCode = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir `
                -TablCapacity 10 -CniCapacity 10 -CniToken 'test-token'

            $exitCode | Should -Be 1
            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)
            $entries.Count | Should -Be 1
            $entries[0].Status | Should -Be 'Failed'
            $entries[0].ErrorMessage | Should -Match 'CNI API unavailable'
            @($entries[0].TargetOutcomes).Count | Should -Be 1
            $entries[0].TargetOutcomes[0].Target | Should -Be 'Tabl'
        }
    }

    It 'a scheduled Run with an aborted target is logged as Partial and exits zero' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $exitCode = Start-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 0

            $exitCode | Should -Be 0
            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)
            $entries.Count | Should -Be 1
            $entries[0].Status | Should -Be 'Partial'
            @($entries[0].TargetOutcomes).Count | Should -Be 1
            $entries[0].TargetOutcomes[0].Target | Should -Be 'Tabl'
            $entries[0].TargetOutcomes[0].Status | Should -Be 'Aborted'
        }
    }

    It 'forwards target capacities to the Run engine' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:received = $null
            Mock Invoke-PreventKitRun {
                $script:received = [pscustomobject]@{
                    TablCapacity = $TablCapacity
                    CniCapacity  = $CniCapacity
                }
                return $null
            }

            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir -TablCapacity 42 -CniCapacity 7

            $script:received.TablCapacity | Should -Be 42
            $script:received.CniCapacity | Should -Be 7
        }
    }

    It 'forwards the CNI token to the Run engine' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $script:receivedToken = $null
            Mock Invoke-PreventKitRun {
                $script:receivedToken = $CniToken
                return $null
            }

            $null = Start-PreventKitRun -CatalogueDirectory $cleanDir -CniCapacity 7 -CniToken 'test-token'

            $script:receivedToken | Should -Be 'test-token'
        }
    }
}

Describe 'PreventKit scheduled Run log entry' {

    It 'write-run-log records a custom status and error message' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir } {
            $written = Write-PreventKitRunLog -LogDirectory $logDir -Status 'Failed' `
                -ErrorMessage 'Something went wrong' -Snapshots @()

            $entry = Get-PreventKitRunLog -LogDirectory $logDir -RunId $written.RunId
            $entry.Status | Should -Be 'Failed'
            $entry.ErrorMessage | Should -Be 'Something went wrong'
        }
    }

    It 'a run log entry is Completed by default' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir } {
            $written = Write-PreventKitRunLog -LogDirectory $logDir -Snapshots @()

            $entry = Get-PreventKitRunLog -LogDirectory $logDir -RunId $written.RunId
            $entry.Status | Should -Be 'Completed'
            $entry.ErrorMessage | Should -BeNullOrEmpty
        }
    }

    It 'derives a Partial run status when a target outcome is Aborted' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir } {
            $abortedOutcome = [pscustomobject]@{
                Target             = 'Tabl'
                Status                  = 'Aborted'
                Preflight               = [pscustomobject]@{ Passed = $false; PlannedCount = 4; Capacity = 1 }
                AddCount                = 4
                RemoveCount             = 0
                UnchangedCount          = 0
                UnmanagedMatchCount = 0
            }

            $written = Write-PreventKitRunLog -LogDirectory $logDir -Snapshots @() -TargetOutcomes @($abortedOutcome)

            $written.Status | Should -Be 'Partial'
            $entry = Get-PreventKitRunLog -LogDirectory $logDir -RunId $written.RunId
            $entry.Status | Should -Be 'Partial'
        }
    }

    It 'an explicitly Failed status overrides the outcome-derived run status' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir } {
            $abortedOutcome = [pscustomobject]@{
                Target             = 'Cni'
                Status                  = 'Aborted'
                Preflight               = [pscustomobject]@{ Passed = $false; PlannedCount = 9; Capacity = 1 }
                AddCount                = 9
                RemoveCount             = 0
                UnchangedCount          = 0
                UnmanagedMatchCount = 0
            }

            $written = Write-PreventKitRunLog -LogDirectory $logDir -Snapshots @() `
                -TargetOutcomes @($abortedOutcome) -Status 'Failed' -ErrorMessage 'Boom'

            $written.Status | Should -Be 'Failed'
            $written.ErrorMessage | Should -Be 'Boom'
        }
    }
}

Describe 'PreventKit scheduled wrapper script' {

    It 'the scheduled wrapper script exists at the expected path' {
        $scheduledScript | Should -Exist
    }

    It 'exits 0 after a successful scheduled Run' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $stateDir = Join-Path $TestDrive 'state'

        & pwsh -NoProfile -File $scheduledScript -CatalogueDirectory $cleanDir `
            -StateDirectory $stateDir -LogDirectory $logDir

        $LASTEXITCODE | Should -Be 0
        @(Get-ChildItem -LiteralPath $logDir -Filter '*.run.json').Count | Should -Be 1
    }

    It 'exits non-zero after a failing scheduled Run' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $stateDir = Join-Path $TestDrive 'state'
        $missingDir = Join-Path $TestDrive 'does-not-exist'

        & pwsh -NoProfile -File $scheduledScript -CatalogueDirectory $missingDir `
            -StateDirectory $stateDir -LogDirectory $logDir

        $LASTEXITCODE | Should -Be 1
        @(Get-ChildItem -LiteralPath $logDir -Filter '*.run.json').Count | Should -Be 1
    }
}