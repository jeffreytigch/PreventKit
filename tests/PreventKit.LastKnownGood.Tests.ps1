BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
    $emptyDir    = Join-Path $fixtureRoot 'empty'
    $missingDir  = Join-Path $fixtureRoot 'missing-source'
}

Describe 'PreventKit target seams' {
    BeforeEach { . (Join-Path $PSScriptRoot '_PreventKitTargetSeams.ps1') }

Describe 'PreventKit last known good snapshot persistence' {

    It 'persists a last known good snapshot on successful retrieval and validation' {
        $stateDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -StateDirectory $stateDir)

        Test-Path -LiteralPath (Join-Path $stateDir 'lolrmm.lkg.json') | Should -BeTrue
        $snapshots[0].Fingerprint.UsedLastKnownGood | Should -BeFalse
        $snapshots[0].Fingerprint.FailureReason | Should -BeNullOrEmpty
    }

    It 'falls back to the last known good snapshot when retrieval fails' {
        $stateDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -StateDirectory $stateDir

        $fallback = @(Invoke-PreventKitRun -CatalogueDirectory $missingDir -StateDirectory $stateDir)

        $fallback.Count | Should -Be 1
        $fallback[0].CatalogueName | Should -Be 'lolrmm'
        $fallback[0].Validation.Status | Should -Be 'Success'
        $fallback[0].Fingerprint.UsedLastKnownGood | Should -BeTrue
        $fallback[0].Fingerprint.FailureReason | Should -Not -BeNullOrEmpty
        @($fallback[0].BlockableAddresses).Count | Should -Be 5
    }

    It 'falls back to the last known good snapshot when validation fails' {
        $stateDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -StateDirectory $stateDir

        $fallback = @(Invoke-PreventKitRun -CatalogueDirectory $emptyDir -StateDirectory $stateDir)

        $fallback.Count | Should -Be 1
        $fallback[0].Validation.Status | Should -Be 'Success'
        $fallback[0].Fingerprint.UsedLastKnownGood | Should -BeTrue
        @($fallback[0].BlockableAddresses).Count | Should -Be 5
    }

    It 'still completes with a failed snapshot when retrieval fails and no last known good exists' {
        $stateDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $missingDir -StateDirectory $stateDir)

        $snapshots.Count | Should -Be 1
        $snapshots[0].Validation.Status | Should -Be 'Failure'
        $snapshots[0].Fingerprint.UsedLastKnownGood | Should -BeFalse
        $snapshots[0].Fingerprint.FailureReason | Should -Not -BeNullOrEmpty
        @($snapshots[0].BlockableAddresses).Count | Should -Be 0
    }

    It 'a WhatIf run falls back and reports the last known good content with the fallback flagged' {
        $stateDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -StateDirectory $stateDir

        $report = @(Invoke-PreventKitRun -CatalogueDirectory $missingDir -StateDirectory $stateDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'Validation: Success'
        $text | Should -Match 'last known good'
        $text | Should -Match ([regex]::Escape('*.anydesk.com'))
    }
}
}
