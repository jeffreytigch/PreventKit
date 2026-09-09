BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $allowDir    = Join-Path $fixtureRoot 'mapping' 'allow'
    $denyDir     = Join-Path $fixtureRoot 'mapping' 'deny'
}

Describe 'PreventKit CNI target mapping' {

    It 'maps a bare domain as a non-broadened DomainName indicator' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = 'example.com'
                Type      = 'Domain'
                ServiceId = 'lolrmm/SomeTool'
            }

            $mapping = Get-CniMapping -Address $address

            $mapping.Value | Should -Be 'example.com'
            $mapping.SourceValue | Should -Be 'example.com'
            $mapping.IndicatorType | Should -Be 'DomainName'
            $mapping.Broadened | Should -BeFalse
            $mapping.ServiceId | Should -Be 'lolrmm/SomeTool'
        }
    }

    It 'maps a wildcard domain as a broadened DomainName indicator when approved' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = '*.example.com'
                Type      = 'Domain'
                ServiceId = 'lolrmm/SomeTool'
            }

            $mapping = Get-CniMapping -Address $address -AllowBroadening

            $mapping.Value | Should -Be 'example.com'
            $mapping.SourceValue | Should -Be '*.example.com'
            $mapping.IndicatorType | Should -Be 'DomainName'
            $mapping.Broadened | Should -BeTrue
        }
    }

    It 'returns nothing for a wildcard domain when broadening is not approved' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = '*.example.com'
                Type      = 'Domain'
                ServiceId = 'lolrmm/SomeTool'
            }

            $mapping = Get-CniMapping -Address $address

            $mapping | Should -BeNullOrEmpty
        }
    }

    It 'maps an IP address as an IpAddress indicator' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = '136.243.104.235'
                Type      = 'IpAddress'
                ServiceId = 'lolrmm/SomeTool'
            }

            $mapping = Get-CniMapping -Address $address

            $mapping.Value | Should -Be '136.243.104.235'
            $mapping.IndicatorType | Should -Be 'IpAddress'
            $mapping.Broadened | Should -BeFalse
        }
    }

    It 'maps a URL as a Url indicator' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = 'https://tele.example.net'
                Type      = 'Url'
                ServiceId = 'lolrmm/SomeTool'
            }

            $mapping = Get-CniMapping -Address $address

            $mapping.Value | Should -Be 'https://tele.example.net'
            $mapping.IndicatorType | Should -Be 'Url'
            $mapping.Broadened | Should -BeFalse
        }
    }

    It 'returns nothing for an unknown address type' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = 'something'
                Type      = 'Fancy'
                ServiceId = 'lolrmm/SomeTool'
            }

            $mapping = Get-CniMapping -Address $address

            $mapping | Should -BeNullOrEmpty
        }
    }
}

Describe 'PreventKit CNI mapping table and broadening approval' {

    It 'produces a mapping table with broadenings explicitly flagged and counted' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                Scope               = 'lolrmm'
                BlockableAddresses  = @(
                    [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                    [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/SomeTool' },
                    [pscustomobject]@{ Value = '136.243.104.235'; Type = 'IpAddress'; ServiceId = 'lolrmm/SomeTool' },
                    [pscustomobject]@{ Value = 'https://tele.example.net'; Type = 'Url'; ServiceId = 'lolrmm/SomeTool' }
                )
                TargetSettings = @{ Cni = @{ AllowBroadening = $true } }
            }

            $table = Get-CniMappingTable -Snapshot $snapshot

            $table.Scope | Should -Be 'lolrmm'
            $table.AllowBroadening | Should -BeTrue
            @($table.Mappings).Count | Should -Be 4
            $table.BroadeningCount | Should -Be 1
            @($table.Mappings | Where-Object { $_.Broadened }).Value | Should -Be 'anydesk.com'
            @($table.Unmappable).Count | Should -Be 0
        }
    }

    It 'defaults to no broadening approval and records the wildcard as unmappable when approval is absent' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                Scope              = 'lolrmm'
                BlockableAddresses = @(
                    [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                    [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/SomeTool' }
                )
            }

            $table = Get-CniMappingTable -Snapshot $snapshot

            $table.AllowBroadening | Should -BeFalse
            $table.BroadeningCount | Should -Be 0
            @($table.Mappings).Count | Should -Be 1
            @($table.Unmappable).Count | Should -Be 1
            $table.Unmappable[0].Value | Should -Be '*.anydesk.com'
            $table.Unmappable[0].Reason | Should -Be 'Wildcard domain requires broadening approval'
        }
    }

    It 'records an unknown type as unmappable with a reason' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                Scope               = 'lolrmm'
                BlockableAddresses  = @(
                    [pscustomobject]@{ Value = 'something'; Type = 'Fancy'; ServiceId = 'lolrmm/SomeTool' }
                )
                TargetSettings = @{}
            }

            $table = Get-CniMappingTable -Snapshot $snapshot

            @($table.Mappings).Count | Should -Be 0
            @($table.Unmappable).Count | Should -Be 1
            $table.Unmappable[0].Value | Should -Be 'something'
            $table.Unmappable[0].Reason | Should -Match 'Fancy'
        }
    }
}

Describe 'PreventKit CNI entry classification' {

    It 'normalizes raw entries and classifies by owner marker in the description field' {
        InModuleScope PreventKit {
            $entries = @(
                [pscustomobject]@{
                    indicatorValue = 'example.com'
                    indicatorType  = 'DomainName'
                    title          = 'Example'
                    description    = 'PreventKit managed entry'
                    id             = 42
                    action         = 'Block'
                },
                [pscustomobject]@{
                    indicatorValue = '136.243.104.235'
                    indicatorType  = 'IpAddress'
                    title          = 'Admin rule'
                    description    = 'administrator note'
                    id             = 43
                    action         = 'Block'
                }
            )

            $classified = @(Read-CniEntry -Entries $entries)

            @($classified).Count | Should -Be 2
            $classified[0].IndicatorValue | Should -Be 'example.com'
            $classified[0].IndicatorType | Should -Be 'DomainName'
            $classified[0].Title | Should -Be 'Example'
            $classified[0].Description | Should -Be 'PreventKit managed entry'
            $classified[0].Classification | Should -Be 'Managed'
            $classified[1].Classification | Should -Be 'UnmanagedMatch'
        }
    }

    It 'produces a report with total, managed and unmanaged match counts' {
        InModuleScope PreventKit {
            $entries = @(
                [pscustomobject]@{ indicatorValue = 'a.com'; indicatorType = 'DomainName'; title = 'a'; description = 'PreventKit managed'; id = 1; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'b.com'; indicatorType = 'DomainName'; title = 'b'; description = 'PreventKit managed'; id = 2; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'c.com'; indicatorType = 'DomainName'; title = 'c'; description = 'admin owned'; id = 3; action = 'Block' }
            )

            $report = Get-CniReport -Entries $entries

            $report.TotalCount | Should -Be 3
            $report.ManagedCount | Should -Be 2
            $report.UnmanagedMatchCount | Should -Be 1
            @($report.Entries).Count | Should -Be 3
        }
    }

    It 'returns zero counts for empty input' {
        InModuleScope PreventKit {
            $report = Get-CniReport -Entries @()

            $report.TotalCount | Should -Be 0
            $report.ManagedCount | Should -Be 0
            $report.UnmanagedMatchCount | Should -Be 0
            @($report.Entries).Count | Should -Be 0
        }
    }
}

Describe 'PreventKit CNI full-run mapping' {

    It 'maps each address per declaration scope with broadening approved' {
        InModuleScope PreventKit -Parameters @{ allowDir = $allowDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $allowDir)

            $snapshots.Count | Should -Be 1
            $table = Get-CniMappingTable -Snapshot $snapshots[0]

            $table.Scope | Should -Be 'lolrmm'
            $table.AllowBroadening | Should -BeTrue
            @($table.Mappings).Count | Should -Be 4
            $table.BroadeningCount | Should -Be 1
            @($table.Unmappable).Count | Should -Be 0

            $broadened = $table.Mappings | Where-Object { $_.Broadened }
            $broadened.Value | Should -Be 'anydesk.com'
            $broadened.IndicatorType | Should -Be 'DomainName'
        }
    }

    It 'reports the CNI mapping section with the broadening flagged in a WhatIf run' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $allowDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'CNI mappings'
        $text | Should -Match ([regex]::Escape('- anydesk.com (DomainName) [broadened]'))
        $text | Should -Match ([regex]::Escape('- example.com (DomainName)'))
        $text | Should -Match ([regex]::Escape('- 136.243.104.235 (IpAddress)'))
        $text | Should -Match 'BroadeningCount: 1'
    }

    It 'skips and logs the wildcard domain when broadening is not approved' {
        InModuleScope PreventKit -Parameters @{ denyDir = $denyDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $denyDir)

            $table = Get-CniMappingTable -Snapshot $snapshots[0]

            $table.AllowBroadening | Should -BeFalse
            $table.BroadeningCount | Should -Be 0
            @($table.Mappings).Count | Should -Be 3
            @($table.Unmappable).Count | Should -Be 1
            $table.Unmappable[0].Value | Should -Be '*.anydesk.com'
        }
    }

    It 'a deny WhatIf run reports the skipped wildcard as unmappable' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $denyDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'CNI mappings'
        $text | Should -Match ([regex]::Escape('skipped: *.anydesk.com'))
        $text | Should -Match 'BroadeningCount: 0'
        $text | Should -Match 'Unmappable: 1'
    }
}