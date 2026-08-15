BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
    $awesomeDir  = Join-Path $fixtureRoot 'awesome'
    $cleanDir    = Join-Path $fixtureRoot 'clean'
}

Describe 'PreventKit Awesome Tunneling source adapter' {

    It 'parses markdown bullets into services scoped to the catalogue scope' {
        InModuleScope PreventKit {
            $markdown = @'
# Open source
* [Telebit](https://telebit.cloud/) - Written in JS.
* [PageKite](https://pagekite.net/) - Comprehensive open source solution.
'@

            $parsed = ConvertFrom-AwesomeTunneling -Content $markdown -Scope 'tunneling'

            @($parsed.Services).Count | Should -Be 2
            $telebit = $parsed.Services | Where-Object { $_.Id -eq 'tunneling/Telebit' }
            $telebit.Scope | Should -Be 'tunneling'
            $telebit.Name | Should -Be 'Telebit'
        }
    }

    It 'extracts the URL host as the blockable address' {
        InModuleScope PreventKit {
            $markdown = '* [Telebit](https://telebit.cloud/) - Written in JS.' + "`n" +
                '* [PageKite](https://pagekite.net/) - Comprehensive solution.' + "`n" +
                '* [gost](https://latest.gost.run/en/) - Load balancing.' + "`n" +
                '* [zrok](https://zrok.io/) - Aims for effortless sharing.'

            $parsed = ConvertFrom-AwesomeTunneling -Content $markdown -Scope 'tunneling'

            @($parsed.BlockableAddresses | Where-Object { $_.Value -eq 'telebit.cloud' }).Count | Should -Be 1
            @($parsed.BlockableAddresses | Where-Object { $_.Value -eq 'pagekite.net' }).Count | Should -Be 1
            @($parsed.BlockableAddresses | Where-Object { $_.Value -eq 'latest.gost.run' }).Count | Should -Be 1
            @($parsed.BlockableAddresses | Where-Object { $_.Value -eq 'zrok.io' }).Count | Should -Be 1
        }
    }

    It 'does not treat a code repository host as a blockable address' {
        InModuleScope PreventKit {
            $markdown = '* [frp](https://github.com/fatedier/frp) - Open alternative to ngrok.' + "`n" +
                '* [SSH-J.com](https://bitbucket.org/ValdikSS/dropbear-sshj/) - Public SSH jump server.'

            $parsed = ConvertFrom-AwesomeTunneling -Content $markdown -Scope 'tunneling'

            @($parsed.BlockableAddresses).Count | Should -Be 0
            @($parsed.Unrepresentable).Count | Should -Be 2
        }
    }

    It 'records a skipped code repository host as unrepresentable' {
        InModuleScope PreventKit {
            $markdown = '* [frp](https://github.com/fatedier/frp) - Open alternative to ngrok.'

            $parsed = ConvertFrom-AwesomeTunneling -Content $markdown -Scope 'tunneling'

            @($parsed.Services).Count | Should -Be 0
            $skipped = $parsed.Unrepresentable | Where-Object { $_.Value -eq 'github.com' }
            $skipped | Should -Not -BeNullOrEmpty
        }
    }

    It 'ignores non-bullet markdown content' {
        InModuleScope PreventKit {
            $markdown = '# Heading' + "`n" +
                'Some paragraph text with [a link](https://example.com).' + "`n" +
                '* [Telebit](https://telebit.cloud/) - Written in JS.'

            $parsed = ConvertFrom-AwesomeTunneling -Content $markdown -Scope 'tunneling'

            @($parsed.Services).Count | Should -Be 1
            @($parsed.BlockableAddresses | Where-Object { $_.Value -eq 'telebit.cloud' }).Count | Should -Be 1
        }
    }
}

Describe 'PreventKit Awesome Tunneling as a second catalogue source' {

    It 'a Run over a catalogue directory processes both catalogue declarations' {
        $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $awesomeDir)

        @($snapshots).Count | Should -Be 2
        @($snapshots | Where-Object { $_.CatalogueName -eq 'lolrmm' }).Count | Should -Be 1
        @($snapshots | Where-Object { $_.CatalogueName -eq 'tunneling' }).Count | Should -Be 1
    }

    It 'desired state is the union of both catalogues' {
        InModuleScope PreventKit -Parameters @{ awesomeDir = $awesomeDir } {
            $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $awesomeDir)
            $desiredState = Get-DesiredState -Snapshot $snapshots

            @($desiredState.Contributions).Count | Should -Be 2
            @($desiredState.BlockableAddresses | Where-Object { $_.Value -eq 'telebit.cloud' }).Count | Should -Be 1
            @($desiredState.BlockableAddresses | Where-Object { $_.Value -eq '*.anydesk.com' }).Count | Should -Be 1
        }
    }

    It 'reconciliation treats the second source identically to the first' {
        InModuleScope PreventKit -Parameters @{ awesomeDir = $awesomeDir } {
            $currentTabl = @(
                [pscustomobject]@{ Value = 'telebit.cloud'; Identity = '1'; Notes = 'PreventKit managed entry' },
                [pscustomobject]@{ Value = '*.anydesk.com'; Identity = '2'; Notes = 'PreventKit managed entry' }
            )
            Mock Add-TablManagedEntry { return $Values }
            Mock Remove-TablManagedEntry { }

            $null = Invoke-PreventKitRun -CatalogueDirectory $awesomeDir `
                -TablCapacity 10 -TablCurrentEntries $currentTabl

            Assert-MockCalled Add-TablManagedEntry -Times 1 -Exactly -ParameterFilter {
                @($Values | Where-Object { $_ -eq 'pagekite.net' }).Count -gt 0
            }
        }
    }

    It 'a WhatIf run reports both catalogues as contributions' {
        $report = @(Invoke-PreventKitRun -CatalogueDirectory $awesomeDir -WhatIf)
        $text = $report -join "`n"

        $text | Should -Match 'Catalogue contributions'
        $text | Should -Match ([regex]::Escape('[lolrmm]'))
        $text | Should -Match ([regex]::Escape('[tunneling]'))
        $text | Should -Match ([regex]::Escape('telebit.cloud'))
    }
}