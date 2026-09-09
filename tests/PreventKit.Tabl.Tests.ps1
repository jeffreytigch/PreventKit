BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'PreventKit owner marker configuration' {

    It 'freezes the owner marker from module config at load' {
        InModuleScope PreventKit -Parameters @{ modulePath = $modulePath } {
            $manifest = Import-PowerShellDataFile -LiteralPath $modulePath
            $script:ownerMarker | Should -Be $manifest.PrivateData.OwnerMarker
        }
    }

    It 'classifies entries carrying the configured owner marker as managed' {
        InModuleScope PreventKit {
            $entry = [pscustomobject]@{ Value = 'evil.example.com'; Notes = "$($script:ownerMarker) managed entry" }

            (Get-EntryClassification -Entry $entry -Field 'Notes') | Should -Be 'Managed'
        }
    }
}

Describe 'PreventKit TABL block entry read and classification' {

    Context 'Read-TablBlockEntry' {

        It 'lists all supplied entries as normalized objects' {
            InModuleScope PreventKit {
                $entries = @(
                    [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed entry' }
                    [pscustomobject]@{ Value = 'bad.example.net'; Identity = '2'; Notes = 'administrator note' }
                )

                $normalized = @(Read-TablBlockEntry -Entries $entries)

                $normalized.Count | Should -Be 2
                $normalized[0].Value | Should -Be 'evil.example.com'
                $normalized[0].Identity | Should -Be '1'
                $normalized[0].Notes | Should -Be 'PreventKit managed entry'
                $normalized[1].Value | Should -Be 'bad.example.net'
            }
        }

        It 'classifies an entry carrying the owner marker in Notes as Managed' {
            InModuleScope PreventKit {
                $entry = [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed entry' }

                $normalized = @(Read-TablBlockEntry -Entries $entry)

                $normalized[0].Classification | Should -Be 'Managed'
            }
        }

        It 'classifies an entry without the owner marker as UnmanagedMatch' {
            InModuleScope PreventKit {
                $entry = [pscustomobject]@{ Value = 'bad.example.net'; Identity = '2'; Notes = 'administrator note' }

                $normalized = @(Read-TablBlockEntry -Entries $entry)

                $normalized[0].Classification | Should -Be 'UnmanagedMatch'
            }
        }

        It 'classifies entries with empty or missing Notes as UnmanagedMatch' {
            InModuleScope PreventKit {
                $emptyNotes  = [pscustomobject]@{ Value = 'a.example.org'; Identity = '3'; Notes = '' }
                $missingNotes = [pscustomobject]@{ Value = 'b.example.org'; Identity = '4' }

                $normalized = @(Read-TablBlockEntry -Entries @($emptyNotes, $missingNotes))

                $normalized[0].Classification | Should -Be 'UnmanagedMatch'
                $normalized[1].Classification | Should -Be 'UnmanagedMatch'
                $normalized[1].Notes | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Get-TablBlockReport' {

        It 'reports correct counts of managed entries and unmanaged matches' {
            InModuleScope PreventKit {
                $entries = @(
                    [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed entry' }
                    [pscustomobject]@{ Value = 'bad.example.net'; Identity = '2'; Notes = 'PreventKit managed' }
                    [pscustomobject]@{ Value = 'worse.example.org'; Identity = '3'; Notes = 'administrator note' }
                )

                $report = Get-TablBlockReport -Entries $entries

                $report.TotalCount | Should -Be 3
                $report.ManagedCount | Should -Be 2
                $report.UnmanagedMatchCount | Should -Be 1
                @($report.Entries).Count | Should -Be 3
            }
        }

        It 'carries the classified entries on the report' {
            InModuleScope PreventKit {
                $entries = @(
                    [pscustomobject]@{ Value = 'evil.example.com'; Identity = '1'; Notes = 'PreventKit managed entry' }
                    [pscustomobject]@{ Value = 'bad.example.net'; Identity = '2'; Notes = 'administrator note' }
                )

                $report = Get-TablBlockReport -Entries $entries

                @($report.Entries | Where-Object { $_.Classification -eq 'Managed' }).Count | Should -Be 1
                @($report.Entries | Where-Object { $_.Classification -eq 'UnmanagedMatch' }).Count | Should -Be 1
            }
        }

        It 'empty input yields zero counts' {
            InModuleScope PreventKit {
                $report = Get-TablBlockReport -Entries @()

                $report.TotalCount | Should -Be 0
                $report.ManagedCount | Should -Be 0
                $report.UnmanagedMatchCount | Should -Be 0
                @($report.Entries).Count | Should -Be 0
            }
        }
    }

    Context 'Get-ClassificationReport' {

        It 'aggregates already classified entries into counts' {
            InModuleScope PreventKit {
                $classified = @(
                    [pscustomobject]@{ Classification = 'Managed' }
                    [pscustomobject]@{ Classification = 'Managed' }
                    [pscustomobject]@{ Classification = 'UnmanagedMatch' }
                )

                $report = Get-ClassificationReport -ClassifiedEntries $classified

                $report.TotalCount | Should -Be 3
                $report.ManagedCount | Should -Be 2
                $report.UnmanagedMatchCount | Should -Be 1
                @($report.Entries).Count | Should -Be 3
            }
        }

        It 'handles empty input' {
            InModuleScope PreventKit {
                $report = Get-ClassificationReport -ClassifiedEntries @()

                $report.TotalCount | Should -Be 0
                $report.ManagedCount | Should -Be 0
                $report.UnmanagedMatchCount | Should -Be 0
            }
        }
    }
}