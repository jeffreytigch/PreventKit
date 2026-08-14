BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $allowDir    = Join-Path $fixtureRoot 'projection' 'allow'
    $denyDir     = Join-Path $fixtureRoot 'projection' 'deny'
}

Describe 'PreventKit CNI destination projection' {

    It 'projects a bare domain as a non-expanded DomainName indicator' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = 'example.com'
                Type      = 'Domain'
                ServiceId = 'lolrmm/SomeTool'
            }

            $projection = Get-CniProjection -Address $address

            $projection.Value | Should -Be 'example.com'
            $projection.SourceValue | Should -Be 'example.com'
            $projection.IndicatorType | Should -Be 'DomainName'
            $projection.Expanded | Should -BeFalse
            $projection.ServiceId | Should -Be 'lolrmm/SomeTool'
        }
    }

    It 'projects a wildcard domain as an expanded DomainName indicator when approved' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = '*.example.com'
                Type      = 'Domain'
                ServiceId = 'lolrmm/SomeTool'
            }

            $projection = Get-CniProjection -Address $address -AllowExpansion

            $projection.Value | Should -Be 'example.com'
            $projection.SourceValue | Should -Be '*.example.com'
            $projection.IndicatorType | Should -Be 'DomainName'
            $projection.Expanded | Should -BeTrue
        }
    }

    It 'returns nothing for a wildcard domain when expansion is not approved' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = '*.example.com'
                Type      = 'Domain'
                ServiceId = 'lolrmm/SomeTool'
            }

            $projection = Get-CniProjection -Address $address

            $projection | Should -BeNullOrEmpty
        }
    }

    It 'projects an IP address as an IpAddress indicator' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = '136.243.104.235'
                Type      = 'IpAddress'
                ServiceId = 'lolrmm/SomeTool'
            }

            $projection = Get-CniProjection -Address $address

            $projection.Value | Should -Be '136.243.104.235'
            $projection.IndicatorType | Should -Be 'IpAddress'
            $projection.Expanded | Should -BeFalse
        }
    }

    It 'projects a URL as a Url indicator' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = 'https://tele.example.net'
                Type      = 'Url'
                ServiceId = 'lolrmm/SomeTool'
            }

            $projection = Get-CniProjection -Address $address

            $projection.Value | Should -Be 'https://tele.example.net'
            $projection.IndicatorType | Should -Be 'Url'
            $projection.Expanded | Should -BeFalse
        }
    }

    It 'returns nothing for an unknown address type' {
        InModuleScope PreventKit {
            $address = [pscustomobject]@{
                Value     = 'something'
                Type      = 'Fancy'
                ServiceId = 'lolrmm/SomeTool'
            }

            $projection = Get-CniProjection -Address $address

            $projection | Should -BeNullOrEmpty
        }
    }
}

Describe 'PreventKit CNI projection table and expansion approval' {

    It 'produces a projection table with expansions explicitly flagged and counted' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                Scope               = 'lolrmm'
                BlockableAddresses  = @(
                    [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                    [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/SomeTool' },
                    [pscustomobject]@{ Value = '136.243.104.235'; Type = 'IpAddress'; ServiceId = 'lolrmm/SomeTool' },
                    [pscustomobject]@{ Value = 'https://tele.example.net'; Type = 'Url'; ServiceId = 'lolrmm/SomeTool' }
                )
                DestinationSettings = @{ Cni = @{ AllowExpansion = $true } }
            }

            $table = Get-CniProjectionTable -Snapshot $snapshot

            $table.Scope | Should -Be 'lolrmm'
            $table.AllowExpansion | Should -BeTrue
            @($table.Projections).Count | Should -Be 4
            $table.ExpansionCount | Should -Be 1
            @($table.Projections | Where-Object { $_.Expanded }).Value | Should -Be 'anydesk.com'
            @($table.Unprojectable).Count | Should -Be 0
        }
    }

    It 'defaults to no expansion approval and records the wildcard as unprojectable when approval is absent' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                Scope              = 'lolrmm'
                BlockableAddresses = @(
                    [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                    [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/SomeTool' }
                )
            }

            $table = Get-CniProjectionTable -Snapshot $snapshot

            $table.AllowExpansion | Should -BeFalse
            $table.ExpansionCount | Should -Be 0
            @($table.Projections).Count | Should -Be 1
            @($table.Unprojectable).Count | Should -Be 1
            $table.Unprojectable[0].Value | Should -Be '*.anydesk.com'
            $table.Unprojectable[0].Reason | Should -Be 'Wildcard domain requires expansion approval'
        }
    }

    It 'records an unknown type as unprojectable with a reason' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                Scope               = 'lolrmm'
                BlockableAddresses  = @(
                    [pscustomobject]@{ Value = 'something'; Type = 'Fancy'; ServiceId = 'lolrmm/SomeTool' }
                )
                DestinationSettings = @{}
            }

            $table = Get-CniProjectionTable -Snapshot $snapshot

            @($table.Projections).Count | Should -Be 0
            @($table.Unprojectable).Count | Should -Be 1
            $table.Unprojectable[0].Value | Should -Be 'something'
            $table.Unprojectable[0].Reason | Should -Match 'Fancy'
        }
    }
}

Describe 'PreventKit CNI entry classification' {

    It 'normalizes raw entries and classifies by provenance in the description field' {
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
            $classified[1].Classification | Should -Be 'UnmanagedCollision'
        }
    }

    It 'produces a report with total, managed and unmanaged collision counts' {
        InModuleScope PreventKit {
            $entries = @(
                [pscustomobject]@{ indicatorValue = 'a.com'; indicatorType = 'DomainName'; title = 'a'; description = 'PreventKit managed'; id = 1; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'b.com'; indicatorType = 'DomainName'; title = 'b'; description = 'PreventKit managed'; id = 2; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'c.com'; indicatorType = 'DomainName'; title = 'c'; description = 'admin owned'; id = 3; action = 'Block' }
            )

            $report = Get-CniReport -Entries $entries

            $report.TotalCount | Should -Be 3
            $report.ManagedCount | Should -Be 2
            $report.UnmanagedCollisionCount | Should -Be 1
            @($report.Entries).Count | Should -Be 3
        }
    }

    It 'returns zero counts for empty input' {
        InModuleScope PreventKit {
            $report = Get-CniReport -Entries @()

            $report.TotalCount | Should -Be 0
            $report.ManagedCount | Should -Be 0
            $report.UnmanagedCollisionCount | Should -Be 0
            @($report.Entries).Count | Should -Be 0
        }
    }
}

Describe 'PreventKit CNI full-run projection' {

    It 'projects each address per declaration scope with expansion approved' {
        InModuleScope PreventKit -Parameters @{ allowDir = $allowDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $allowDir)

            $snapshots.Count | Should -Be 1
            $table = Get-CniProjectionTable -Snapshot $snapshots[0]

            $table.Scope | Should -Be 'lolrmm'
            $table.AllowExpansion | Should -BeTrue
            @($table.Projections).Count | Should -Be 4
            $table.ExpansionCount | Should -Be 1
            @($table.Unprojectable).Count | Should -Be 0

            $expanded = $table.Projections | Where-Object { $_.Expanded }
            $expanded.Value | Should -Be 'anydesk.com'
            $expanded.IndicatorType | Should -Be 'DomainName'
        }
    }

    It 'reports the CNI projection section with the expansion flagged in a WhatIf run' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $allowDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'CNI projections'
        $text | Should -Match ([regex]::Escape('- anydesk.com (DomainName) [expansion]'))
        $text | Should -Match ([regex]::Escape('- example.com (DomainName)'))
        $text | Should -Match ([regex]::Escape('- 136.243.104.235 (IpAddress)'))
        $text | Should -Match 'ExpansionCount: 1'
    }

    It 'skips and logs the wildcard domain when expansion is not approved' {
        InModuleScope PreventKit -Parameters @{ denyDir = $denyDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $denyDir)

            $table = Get-CniProjectionTable -Snapshot $snapshots[0]

            $table.AllowExpansion | Should -BeFalse
            $table.ExpansionCount | Should -Be 0
            @($table.Projections).Count | Should -Be 3
            @($table.Unprojectable).Count | Should -Be 1
            $table.Unprojectable[0].Value | Should -Be '*.anydesk.com'
        }
    }

    It 'a deny WhatIf run reports the skipped wildcard as unprojectable' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $denyDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'CNI projections'
        $text | Should -Match ([regex]::Escape('skipped: *.anydesk.com'))
        $text | Should -Match 'ExpansionCount: 0'
        $text | Should -Match 'Unprojectable: 1'
    }
}