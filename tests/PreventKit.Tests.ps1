BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
    $dirtyDir    = Join-Path $fixtureRoot 'dirty'
    $emptyDir    = Join-Path $fixtureRoot 'empty'
    $disabledDir = Join-Path $fixtureRoot 'disabled'
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