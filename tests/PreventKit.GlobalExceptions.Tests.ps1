BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot      = Join-Path $PSScriptRoot 'fixtures'
    $cleanDir         = Join-Path $fixtureRoot 'clean'
    $exceptionsDir    = Join-Path $fixtureRoot 'exceptions'
    $disabledExcDir   = Join-Path $fixtureRoot 'exceptions-disabled'
    $emptyExcDir      = Join-Path $fixtureRoot 'exceptions-empty'
}

Describe 'PreventKit global exception declaration loading' {

    It 'reads exception keys from enabled global exception declarations' {
        InModuleScope PreventKit -Parameters @{ exceptionsDir = $exceptionsDir } {
            $keys = @(Get-GlobalExceptionKey -ExceptionDirectory $exceptionsDir)

            $keys | Should -Contain 'service:lolrmm/AnyDesk'
            $keys | Should -Contain 'domain:GetScreen.me'
        }
    }

    It 'skips disabled global exception declarations' {
        InModuleScope PreventKit -Parameters @{ disabledExcDir = $disabledExcDir } {
            $keys = @(Get-GlobalExceptionKey -ExceptionDirectory $disabledExcDir)

            $keys | Should -Not -Contain 'service:lolrmm/Absolute'
        }
    }

    It 'returns no keys for an empty exception directory' {
        InModuleScope PreventKit -Parameters @{ emptyExcDir = $emptyExcDir } {
            @(Get-GlobalExceptionKey -ExceptionDirectory $emptyExcDir).Count | Should -Be 0
        }
    }
}

Describe 'PreventKit global exception suppression in desired state' {

    It 'suppresses a matching service and its addresses, tracked as global' {
        InModuleScope PreventKit -Parameters @{ exceptionsDir = $exceptionsDir } {
            $globalKeys = @(Get-GlobalExceptionKey -ExceptionDirectory $exceptionsDir)
            $snapshot = [pscustomobject]@{
                CatalogueName      = 'lolrmm'
                Scope              = 'lolrmm'
                Validation         = [pscustomobject]@{ Status = 'Success' }
                Services           = @(
                    [pscustomobject]@{ Id = 'lolrmm/AnyDesk'; Scope = 'lolrmm'; Name = 'AnyDesk' },
                    [pscustomobject]@{ Id = 'lolrmm/Other'; Scope = 'lolrmm'; Name = 'Other' }
                )
                BlockableAddresses = @(
                    [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                    [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Other' }
                )
                Unrepresentable    = @()
            }

            $desired = Get-DesiredState -Snapshot $snapshot -GlobalExceptionKey $globalKeys

            @($desired.Services).Count | Should -Be 1
            $desired.Services[0].Id | Should -Be 'lolrmm/Other'
            @($desired.BlockableAddresses).Count | Should -Be 1
            $desired.BlockableAddresses[0].Value | Should -Be 'example.com'

            @($desired.Suppressed | Where-Object { $_.ExceptionType -eq 'Global' }).Count | Should -Be 2
        }
    }

    It 'an invocation exception still suppresses independently of global exceptions' {
        InModuleScope PreventKit {
            $snapshot = [pscustomobject]@{
                CatalogueName      = 'lolrmm'
                Scope              = 'lolrmm'
                Validation         = [pscustomobject]@{ Status = 'Success' }
                Services           = @(
                    [pscustomobject]@{ Id = 'lolrmm/AnyDesk'; Scope = 'lolrmm'; Name = 'AnyDesk' },
                    [pscustomobject]@{ Id = 'lolrmm/Other'; Scope = 'lolrmm'; Name = 'Other' }
                )
                BlockableAddresses = @(
                    [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain'; ServiceId = 'lolrmm/AnyDesk' },
                    [pscustomobject]@{ Value = 'example.com'; Type = 'Domain'; ServiceId = 'lolrmm/Other' }
                )
                Unrepresentable    = @()
            }

            $desired = Get-DesiredState -Snapshot $snapshot -ExceptionKey @('domain:example.com') -GlobalExceptionKey @()

            @($desired.BlockableAddresses).Count | Should -Be 1
            @($desired.Suppressed | Where-Object { $_.ExceptionType -eq 'Invocation' }).Count | Should -Be 1
        }
    }
}

Describe 'PreventKit global exceptions in a full run' {

    It 'a WhatIf run reports what global exceptions suppressed' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $exceptionsDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'Suppressed by global exceptions'
        $text | Should -Match ([regex]::Escape('lolrmm/AnyDesk (AnyDesk)'))
        $text | Should -Match ([regex]::Escape('GetScreen.me (Domain)'))
    }

    It 'an exception declaration still applies alongside invocation exceptions' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $exceptionsDir `
            -ExceptionKey @('service:lolrmm/Absolute (Computrace)') -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'Suppressed by global exceptions'
        $text | Should -Match 'Suppressed by invocation exceptions'
        $text | Should -Match 'Blockable addresses \(1\):'
    }

    It 'global exceptions suppress at the TABL destination: no add for them, remove enforced managed entries' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir; exceptionsDir = $exceptionsDir } {
            $currentTabl = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'boot.net.anydesk.com'; Identity = '2'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'server.absolute.com'; Identity = '3'; Notes = 'PreventKit managed entry' }
            )

            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $exceptionsDir `
                -TablCapacity 10 -TablCurrentEntries $currentTabl

            Assert-MockCalled Add-TablManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Values | Where-Object { $_ -match 'anydesk|GetScreen' }).Count -gt 0
            }
            Assert-MockCalled Remove-TablManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Identities | Where-Object { $_ -in @('1', '2') }).Count -gt 0
            }
            Assert-MockCalled Remove-TablManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Identities | Where-Object { $_ -eq '3' }).Count -gt 0
            }
        }
    }

    It 'global exceptions suppress at the CNI destination' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir; exceptionsDir = $exceptionsDir } {
            $currentCni = @(
                [pscustomobject]@{ indicatorValue = 'boot.net.anydesk.com'; indicatorType = 'DomainName'; description = 'PreventKit managed entry'; id = 'c1'; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'server.absolute.com'; indicatorType = 'DomainName'; description = 'PreventKit managed entry'; id = 'c2'; action = 'Block' }
            )

            Mock Add-CniManagedEntry { return $Projections }
            Mock Remove-CniManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $exceptionsDir `
                -CniCapacity 10 -CniCurrentEntries $currentCni -CniToken 'test-token'

            Assert-MockCalled Add-CniManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Projections | Where-Object { $_.Value -match 'anydesk' }).Count -gt 0
            }
            Assert-MockCalled Remove-CniManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Id | Where-Object { $_ -eq 'c1' }).Count -gt 0
            }
            Assert-MockCalled Remove-CniManagedEntry -Times 0 -Exactly -ParameterFilter {
                @($Id | Where-Object { $_ -eq 'c2' }).Count -gt 0
            }
        }
    }

    It 'records the global exceptions applied in the run log' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        InModuleScope PreventKit -Parameters @{ logDir = $logDir; cleanDir = $cleanDir; exceptionsDir = $exceptionsDir } {
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $exceptionsDir -LogDirectory $logDir

            $entry = @(Get-PreventKitRunLog -LogDirectory $logDir)[0]
            @($entry.GlobalExceptions).Count | Should -Be 2
            @($entry.GlobalExceptions) | Should -Contain 'service:lolrmm/AnyDesk'
        }
    }

    It 'removing the declaration restores enforcement on the next Run' {
        InModuleScope PreventKit -Parameters @{ cleanDir = $cleanDir } {
            $excDir = Join-Path $TestDrive 'exceptions'
            $null = New-Item -ItemType Directory -Path $excDir -Force

            $declaration = @'
@{
    Name         = 'AnyDesk'
    Enabled      = $true
    ExceptionKey = @('service:lolrmm/AnyDesk')
}
'@
            Set-Content -LiteralPath (Join-Path $excDir 'anydesk.exception.psd1') -Value $declaration -Encoding utf8

            $script:anydeskAdds = 0
            Mock Add-TablManagedEntry {
                if (@($Values | Where-Object { $_ -match 'anydesk' }).Count -gt 0) {
                    $script:anydeskAdds++
                }
                return $Values
            }
            Mock Remove-TablManagedEntry { }

            $currentTabl = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = 'boot.net.anydesk.com'; Identity = '2'; Notes = 'PreventKit managed entry' }
            )

            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $excDir `
                -TablCapacity 10 -TablCurrentEntries $currentTabl

            $script:anydeskAdds | Should -Be 0

            Remove-Item -LiteralPath (Join-Path $excDir 'anydesk.exception.psd1') -Force

            $script:anydeskAdds = 0
            $null = Invoke-PreventKitRun -CatalogueDirectory $cleanDir -ExceptionDirectory $excDir `
                -TablCapacity 10 -TablCurrentEntries @()

            $script:anydeskAdds | Should -Be 1
        }
    }
}