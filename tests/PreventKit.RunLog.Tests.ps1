BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
}

Describe 'PreventKit run log' {

    It 'a Run writes a log entry with source fingerprints and exceptions applied' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -ExceptionKey @('domain:GetScreen.me')

            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)

            $entries.Count | Should -Be 1
            $entries[0].Exceptions | Should -Contain 'domain:GetScreen.me'
            @($entries[0].SourceFingerprints).Count | Should -Be 1
            $entries[0].SourceFingerprints[0].CatalogueName | Should -Be 'lolrmm'
            $entries[0].SourceFingerprints[0].ContentHash | Should -Match '^[0-9a-f]{64}$'
            @($entries[0].DestinationOutcomes).Count | Should -Be 0
        }
    }

    It 'records reconciliation changes and their outcomes per destination' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $currentTabl = @(
                [pscustomobject]@{ Value = 'server.absolute.com'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'stale.example.org'; Identity = '2'; Notes = 'PreventKit managed entry' }
            )

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 10 -TablCurrentEntries $currentTabl

            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)
            $entries[0].DestinationOutcomes.Count | Should -Be 1
            $outcome = $entries[0].DestinationOutcomes[0]
            $outcome.Destination | Should -Be 'Tabl'
            $outcome.Status | Should -Be 'Reconciled'
            $outcome.AddCount | Should -Be 4
            $outcome.RemoveCount | Should -Be 1
            $outcome.Preflight.Passed | Should -BeTrue
        }
    }

    It 'a per-run report can be printed or queried from the log' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -ExceptionKey @('service:lolrmm/AnyDesk')

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $report = @(New-PreventKitRunReport -LogEntry $entry)
            $text = $report -join "`n"

            $text | Should -Match 'PreventKit run'
            $text | Should -Match 'Source fingerprints'
            $text | Should -Match 'lolrmm'
            $text | Should -Match ([regex]::Escape('service:lolrmm/AnyDesk'))
        }
    }

    It 'a per-run report surfaces the run status so a Partial run is visible' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 0

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            $report = @(New-PreventKitRunReport -LogEntry $entry)
            $text = $report -join "`n"

            $text | Should -Match 'Status: Partial'
            $text | Should -Match 'Tabl: Aborted'
        }
    }

    It 'queries a single run by its run id' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir } {
            $written = Write-PreventKitRunLog -LogDirectory $logDir -ExceptionKey @('domain:x.com') -Snapshots @()

            $entry = Get-PreventKitRunLog -LogDirectory $logDir -RunId $written.RunId

            $entry.RunId.ToString() | Should -Be $written.RunId.ToString()
            $entry.Exceptions | Should -Contain 'domain:x.com'
        }
    }

    It 'a WhatIf run logs fingerprints and exceptions without destination outcomes' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -WhatIf -ExceptionKey @('domain:GetScreen.me')

            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)

            $entries[0].Exceptions | Should -Contain 'domain:GetScreen.me'
            @($entries[0].SourceFingerprints).Count | Should -Be 1
            @($entries[0].DestinationOutcomes).Count | Should -Be 0
        }
    }

    It 'a Run that fails during reconciliation writes a Failed entry with the error and partial outcomes' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }
            Mock Invoke-CniReconciliation { throw 'CNI API unavailable' }

            { Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir `
                -TablCapacity 10 -CniCapacity 10 -CniToken 'test-token' } | Should -Throw

            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)

            $entries.Count | Should -Be 1
            $entries[0].Status | Should -Be 'Failed'
            $entries[0].ErrorMessage | Should -Match 'CNI API unavailable'
            @($entries[0].DestinationOutcomes).Count | Should -Be 1
            $entries[0].DestinationOutcomes[0].Destination | Should -Be 'Tabl'
        }
    }

    It 'a Run whose destination aborts on capacity preflight is logged as Partial with the Aborted outcome' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir } {
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir -TablCapacity 0

            $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)

            $entries.Count | Should -Be 1
            $entries[0].Status | Should -Be 'Partial'
            @($entries[0].DestinationOutcomes).Count | Should -Be 1
            $entries[0].DestinationOutcomes[0].Destination | Should -Be 'Tabl'
            $entries[0].DestinationOutcomes[0].Status | Should -Be 'Aborted'
        }
    }
}

Describe 'PreventKit exported run-log helpers' {

    It 'Get-PreventKitRunLog is callable from an imported module instance' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir

        $entries = @(Get-PreventKitRunLog -LogDirectory $logDir)

        $entries.Count | Should -Be 1
        $entries[0].Status | Should -Be 'Completed'
    }

    It 'New-PreventKitRunReport is callable from an imported module instance and renders a report' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -LogDirectory $logDir

        $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
        $report = @(New-PreventKitRunReport -LogEntry $entry)

        $text = $report -join "`n"
        $text | Should -Match 'PreventKit run'
        $text | Should -Match 'lolrmm'
    }

    It 'the public module manifest exports both helpers' {
        $module = Get-Module PreventKit
        $module.ExportedFunctions.Keys | Should -Contain 'Get-PreventKitRunLog'
        $module.ExportedFunctions.Keys | Should -Contain 'New-PreventKitRunReport'
    }
}