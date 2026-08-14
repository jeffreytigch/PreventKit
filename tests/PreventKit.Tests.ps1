BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
    $dirtyDir    = Join-Path $fixtureRoot 'dirty'
    $emptyDir    = Join-Path $fixtureRoot 'empty'
    $disabledDir = Join-Path $fixtureRoot 'disabled'
    $multiDir    = Join-Path $fixtureRoot 'multi'
}

Describe 'PreventKit catalogue retrieval and validation' {

    It 'produces a snapshot for an enabled lolrmm declaration without touching any enforcement destination' {
        $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir)

        $snapshots.Count | Should -Be 1
        $snapshot = $snapshots[0]
        $snapshot.CatalogueName | Should -Be 'lolrmm'
        $snapshot.Scope | Should -Be 'lolrmm'
        $snapshot.Validation.Status | Should -Be 'Success'
    }

    It 'parses the CSV into canonical Service entries' {
        $snapshot = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir)[0]

        @($snapshot.Services).Count | Should -Be 4

        $anyDesk = $snapshot.Services | Where-Object { $_.Name -eq 'AnyDesk' }
        $anyDesk.Id | Should -Be 'lolrmm/AnyDesk'
        $anyDesk.Scope | Should -Be 'lolrmm'

        $absolute = $snapshot.Services | Where-Object { $_.Name -eq 'Absolute (Computrace)' }
        $absolute | Should -Not -BeNullOrEmpty
    }

    It 'parses the CSV into canonical Blockable Address entries with a type and service' {
        $snapshot = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir)[0]

        @($snapshot.BlockableAddresses).Count | Should -Be 5

        $wildcard = $snapshot.BlockableAddresses | Where-Object { $_.Value -eq '*.anydesk.com' }
        $wildcard.Type | Should -Be 'Domain'
        $wildcard.ServiceId | Should -Be 'lolrmm/AnyDesk'

        $ip = $snapshot.BlockableAddresses | Where-Object { $_.Value -eq '136.243.104.235' }
        $ip.Type | Should -Be 'IpAddress'
        $ip.ServiceId | Should -Be 'lolrmm/Ammyy Admin'
    }

    It 'logs and counts entries the adapter cannot represent' {
        $snapshot = @(Invoke-PreventKitRun -CatalogueDirectory $dirtyDir)[0]

        $snapshot.Fingerprint.ParsedCounts.Unrepresentable | Should -Be 3
        $snapshot.Fingerprint.ParsedCounts.BlockableAddresses | Should -Be 4

        $unrepresentableValues = @($snapshot.Unrepresentable | ForEach-Object { $_.Value })
        $unrepresentableValues | Should -Contain 'relay-[a-f0-9]{8}.net.anydesk.com:443'
        $unrepresentableValues | Should -Contain 'upload_data.qq.com'
        $unrepresentableValues | Should -Contain 'agents*-cloud.acronis.com'

        $snapshot.Validation.Status | Should -Be 'Success'
    }

    It 'reports a fingerprint with source location, retrieval time, SHA-256 hash and parsed counts' {
        $snapshot = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir)[0]

        $fingerprint = $snapshot.Fingerprint
        $fingerprint.SourceLocation | Should -Be (Join-Path $cleanDir 'lolrmm.csv')
        $fingerprint.RetrievedAt | Should -BeOfType [datetime]
        ($fingerprint.RetrievedAt - [datetime]::UtcNow).TotalMinutes | Should -BeLessThan 5

        $expectedHash = (Get-FileHash -LiteralPath (Join-Path $cleanDir 'lolrmm.csv') -Algorithm SHA256).Hash.ToLowerInvariant()
        $fingerprint.ContentHash | Should -Be $expectedHash

        $fingerprint.ParsedCounts.Services | Should -Be 4
        $fingerprint.ParsedCounts.BlockableAddresses | Should -Be 5
        $fingerprint.ParsedCounts.Unrepresentable | Should -Be 0
    }

    It 'is explicit about validation failure for an empty catalogue' {
        $snapshot = @(Invoke-PreventKitRun -CatalogueDirectory $emptyDir)[0]

        $snapshot.Validation.Status | Should -Be 'Failure'
        @($snapshot.Validation.Checks | Where-Object { $_.Passed }).Count | Should -BeGreaterThan 0
        @($snapshot.Validation.Checks | Where-Object { -not $_.Passed }).Count | Should -BeGreaterThan 0
    }

    It 'skips disabled catalogue declarations' {
        $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $disabledDir)

        $snapshots.Count | Should -Be 0
    }

    It 'does not export any enforcement destination functions' {
        $exported = @(Get-Command -Module PreventKit | Select-Object -ExpandProperty Name)
        $exported | Should -Contain 'Invoke-PreventKitRun'
        $exported | Where-Object { $_ -match 'Tabl|Indicator|GetTenant|New-Tenant|Invoke-RestMethod|CustomNetwork' } | Should -BeNullOrEmpty
    }
}

Describe 'PreventKit desired state and WhatIf report' {

    It 'computes the desired state as the union of all enabled catalogue services' {
        InModuleScope PreventKit -Parameters @{ multiDir = $multiDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $multiDir)
            $desiredState = Get-DesiredState -Snapshot $snapshots

            @($desiredState.Services).Count | Should -Be 4
        }
    }

    It 'computes the desired state as the union of all enabled catalogue blockable addresses' {
        InModuleScope PreventKit -Parameters @{ multiDir = $multiDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $multiDir)
            $desiredState = Get-DesiredState -Snapshot $snapshots

            @($desiredState.BlockableAddresses).Count | Should -Be 4
        }
    }

    It 'deduplicates a blockable address shared between catalogues' {
        InModuleScope PreventKit -Parameters @{ multiDir = $multiDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $multiDir)
            $desiredState = Get-DesiredState -Snapshot $snapshots

            @($desiredState.BlockableAddresses | Where-Object { $_.Value -eq '*.anydesk.com' }).Count | Should -Be 1
        }
    }

    It 'tracks each catalogue contribution with its scope, source and entries' {
        InModuleScope PreventKit -Parameters @{ multiDir = $multiDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $multiDir)
            $desiredState = Get-DesiredState -Snapshot $snapshots

            @($desiredState.Contributions).Count | Should -Be 2

            $lolrmm = $desiredState.Contributions | Where-Object { $_.CatalogueName -eq 'lolrmm' }
            $lolrmm.Scope | Should -Be 'lolrmm'
            $lolrmm.Fingerprint.SourceLocation | Should -Be (Join-Path $multiDir 'lolrmm.csv')
            @($lolrmm.Services).Count | Should -Be 2
            @($lolrmm.BlockableAddresses).Count | Should -Be 3

            $tunneling = $desiredState.Contributions | Where-Object { $_.CatalogueName -eq 'tunneling' }
            $tunneling.Scope | Should -Be 'tunneling'
            @($tunneling.Services).Count | Should -Be 2
            @($tunneling.BlockableAddresses).Count | Should -Be 2
        }
    }

    It 'a failed-validation snapshot contributes no entries but is still reported as a contribution' {
        InModuleScope PreventKit -Parameters @{ emptyDir = $emptyDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $emptyDir)
            $desiredState = Get-DesiredState -Snapshot $snapshots

            @($desiredState.Services).Count | Should -Be 0
            @($desiredState.BlockableAddresses).Count | Should -Be 0
            @($desiredState.Contributions).Count | Should -Be 1
            $desiredState.Contributions[0].Validation.Status | Should -Be 'Failure'
        }
    }

    It 'a WhatIf run reads snapshots and prints the desired state as services and blockable addresses' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -WhatIf)

        $report | Should -Not -BeNullOrEmpty
        $text = $report -join "`n"

        $text | Should -Match 'Desired state'
        $text | Should -Match 'Services \(4\):'
        $text | Should -Match 'Blockable addresses \(5\):'
        $text | Should -Match ([regex]::Escape('*.anydesk.com'))
        $text | Should -Match ([regex]::Escape('lolrmm/AnyDesk'))
    }

    It 'a WhatIf report shows each catalogue contribution' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $multiDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'Catalogue contributions'
        $text | Should -Match ([regex]::Escape('lolrmm'))
        $text | Should -Match ([regex]::Escape('tunneling'))
        $text | Should -Match ([regex]::Escape('cloudflare.com'))
    }

    It 'a WhatIf report renders a failed-validation catalogue with zero entries' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $emptyDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'Desired state'
        $text | Should -Match 'Services \(0\):'
        $text | Should -Match 'Blockable addresses \(0\):'
        $text | Should -Match 'Validation: Failure'
    }

    It 'a WhatIf run completes without modifying any enforcement destination' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -WhatIf)

        $report | Should -Not -BeNullOrEmpty

        $exported = @(Get-Command -Module PreventKit | Select-Object -ExpandProperty Name)
        $exported | Where-Object { $_ -match 'Tabl|Indicator|GetTenant|New-Tenant|Invoke-RestMethod|CustomNetwork' } | Should -BeNullOrEmpty
    }
}