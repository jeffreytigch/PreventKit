BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
}

Describe 'PreventKit invocation exception key matching' {

    BeforeAll {
        $script:exceptionSnapshot = [pscustomobject]@{
            CatalogueName      = 'lolrmm'
            Scope              = 'lolrmm'
            Validation         = [pscustomobject]@{ Status = 'Success' }
            Services           = @(
                [pscustomobject]@{ Id = 'lolrmm/AnyDesk'; Scope = 'lolrmm'; Name = 'AnyDesk' },
                [pscustomobject]@{ Id = 'lolrmm/SomeTool'; Scope = 'lolrmm'; Name = 'SomeTool' }
            )
            BlockableAddresses = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                [pscustomobject]@{ Value = 'boot.net.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/SomeTool' }
            )
            Unrepresentable    = @()
        }
    }

    It 'suppresses a service and every address of that service with a service key' {
        InModuleScope PreventKit -Parameters @{ exceptionSnapshot = $script:exceptionSnapshot } {
            $desired = Get-DesiredState -Snapshot $exceptionSnapshot -ExceptionKey @('service:lolrmm/AnyDesk')

            @($desired.Services).Count | Should -Be 1
            $desired.Services[0].Id | Should -Be 'lolrmm/SomeTool'
            @($desired.BlockableAddresses).Count | Should -Be 1
            $desired.BlockableAddresses[0].Value | Should -Be 'example.com'
        }
    }

    It 'suppresses a single blockable address with a domain key' {
        InModuleScope PreventKit -Parameters @{ exceptionSnapshot = $script:exceptionSnapshot } {
            $desired = Get-DesiredState -Snapshot $exceptionSnapshot -ExceptionKey @('domain:*.anydesk.com')

            @($desired.Services).Count | Should -Be 2
            @($desired.BlockableAddresses).Count | Should -Be 2
            @($desired.BlockableAddresses | Where-Object { $_.Value -eq '*.anydesk.com' }).Count | Should -Be 0
            @($desired.BlockableAddresses | Where-Object { $_.Value -eq 'boot.net.anydesk.com' }).Count | Should -Be 1
        }
    }

    It 'records the suppressed entries with their kind for reporting' {
        InModuleScope PreventKit -Parameters @{ exceptionSnapshot = $script:exceptionSnapshot } {
            $desired = Get-DesiredState -Snapshot $exceptionSnapshot -ExceptionKey @('service:lolrmm/AnyDesk')

            @($desired.Suppressed).Count | Should -Be 3
            @($desired.Suppressed | Where-Object { $_.Kind -eq 'Service' }).Count | Should -Be 1
            @($desired.Suppressed | Where-Object { $_.Kind -eq 'BlockableAddress' }).Count | Should -Be 2
        }
    }

    It 'leaves desired state untouched when no exception keys are given' {
        InModuleScope PreventKit -Parameters @{ exceptionSnapshot = $script:exceptionSnapshot } {
            $desired = Get-DesiredState -Snapshot $exceptionSnapshot

            @($desired.Services).Count | Should -Be 2
            @($desired.BlockableAddresses).Count | Should -Be 3
            @($desired.Suppressed).Count | Should -Be 0
        }
    }

    It 'matches exception keys case-insensitively' {
        InModuleScope PreventKit -Parameters @{ exceptionSnapshot = $script:exceptionSnapshot } {
            $desired = Get-DesiredState -Snapshot $exceptionSnapshot -ExceptionKey @('SERVICE:lolrmm/anydesk', 'domain:EXAMPLE.com')

            @($desired.Services).Count | Should -Be 1
            @($desired.BlockableAddresses).Count | Should -Be 0
        }
    }

    It 'a WhatIf run reports what was suppressed and excludes it from desired state' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -WhatIf -ExceptionKey @('domain:GetScreen.me'))
        $text = $report -join "`n"

        $text | Should -Match 'Suppressed by invocation exceptions'
        $text | Should -Match 'Blockable addresses \(4\):'
        $text | Should -Match 'Services \(4\):'
        $text | Should -Match ([regex]::Escape('GetScreen.me'))
    }

    It 'a WhatIf run suppressing a service also drops its addresses from desired state' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -WhatIf -ExceptionKey @('service:lolrmm/AnyDesk'))
        $text = $report -join "`n"

        $text | Should -Match 'Blockable addresses \(3\):'
        $text | Should -Match 'Services \(3\):'
    }

    It 'warns on an unrecognised exception key and suppresses nothing for it' {
        $output = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -WhatIf -ExceptionKey @('domain:GetScreen.me', 'domian:example.com') 3>&1)
        $text = $output | Out-String

        $text | Should -Match 'Ignoring exception key'
        $text | Should -Match ([regex]::Escape('domian:example.com'))
        $text | Should -Match 'Blockable addresses \(4\):'
    }
}

Describe 'PreventKit invocation exceptions are managed-only in reconciliation' {

    It 'removes already-enforced managed entries for suppressed keys and adds none for them' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $currentTabl = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'boot.net.anydesk.com'; Identity = '2'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = '136.243.104.235'; Identity = '3'; Notes = 'PreventKit managed entry' }
            )

            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -TablCapacity 10 -TablCurrentEntries $currentTabl `
                -ExceptionKey @('service:lolrmm/AnyDesk')

            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Values | Where-Object { $_ -match 'anydesk' }).Count -gt 0
            }
            Assert-MockCalled Remove-TablManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Identities | Where-Object { $_ -in @('1', '2') }).Count -gt 0
            }
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Identities | Where-Object { $_ -eq '3' }).Count -gt 0
            }
        }
    }

    It 'never creates an allow rule or any entry for a suppressed key' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $currentTabl = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '1'; Notes = 'PreventKit managed entry' }
            )

            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -TablCapacity 10 -TablCurrentEntries $currentTabl `
                -ExceptionKey @('service:lolrmm/AnyDesk')

            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Values | Where-Object { $_ -eq '*.anydesk.com' }).Count -gt 0
            }
            Assert-MockCalled Remove-TablManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Identities | Where-Object { $_ -eq '1' }).Count -gt 0
            }
        }
    }

    It 'suppressed keys are also excluded from CNI reconciliation' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $currentCni = @(
                [pscustomobject]@{ indicatorValue = 'boot.net.anydesk.com'; indicatorType = 'DomainName'; description = 'PreventKit managed entry'; id = 'c1'; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'server.absolute.com'; indicatorType = 'DomainName'; description = 'PreventKit managed entry'; id = 'c2'; action = 'Block' }
            )

            Mock Add-CniManagedEntry { return $Mappings }
            Mock Remove-CniManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -CniCapacity 10 -CniCurrentEntries $currentCni `
                -ExceptionKey @('service:lolrmm/AnyDesk') -CniToken 'test-token'

            Assert-MockCalled Add-CniManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Mappings | Where-Object { $_.Value -match 'anydesk' }).Count -gt 0
            }
            Assert-MockCalled Remove-CniManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Id | Where-Object { $_ -eq 'c1' }).Count -gt 0
            }
            Assert-MockCalled Remove-CniManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Id | Where-Object { $_ -eq 'c2' }).Count -gt 0
            }
        }
    }
}
