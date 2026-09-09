BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force

    $fixtureRoot    = Join-Path $PSScriptRoot 'fixtures'
    $crossCoveredDir = Join-Path $fixtureRoot 'cross-covered'
}

Describe 'PreventKit shared covered-address classifier' {

    It 'classifies a candidate whose normalized tail ends in a wildcard root as covered' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = '*.example.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'foo.example.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 1
            $covered[0].Value | Should -Be 'foo.example.com'
        }
    }

    It 'classifies a candidate that equals the wildcard root as covered' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = '*.example.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'example.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 1
        }
    }

    It 'does not classify a candidate covered only by a narrower sibling entry as covered' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = 'cloud.example.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'agentsX-cloud.example.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 0
        }
    }

    It 'normalizes away scheme, port, and path before matching' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'relay-a1b2c3d4.net.anydesk.com:443'; Reason = 'Not representable' },
                [pscustomobject]@{ Value = 'https://download.anydesk.com/path?q=1'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 2
        }
    }

    It 'matches case-insensitively against a mixed-case wildcard root' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = '*.GoToMyPC.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'relay.gotomypc.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 1
        }
    }

    It 'does not cover a candidate that merely shares the wildcard root as a suffix at no label boundary' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = '*.anydesk.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'zz-anydesk.com'; Reason = 'Not representable' },
                [pscustomobject]@{ Value = 'badexample.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 0
        }
    }

    It 'leaves genuinely unrepresentable candidates out of the covered collection' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = '*.example.com'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'upload_data.qq.com'; Reason = 'Not representable' },
                [pscustomobject]@{ Value = 'agents*-cloud.acronis.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 0
        }
    }

    It 'returns an empty collection when there are no wildcard representable addresses' {
        InModuleScope PreventKit {
            $representable = @(
                [pscustomobject]@{ Value = 'cloud.example.com'; Type = 'Domain' },
                [pscustomobject]@{ Value = 'example.net'; Type = 'Domain' }
            )
            $candidates = @(
                [pscustomobject]@{ Value = 'foo.example.com'; Reason = 'Not representable' }
            )

            $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $representable -Candidates $candidates)

            $covered.Count | Should -Be 0
        }
    }
}

Describe 'PreventKit lolrmm source adapter covering' {

    It 'records wildcard-covered addresses as covered and keeps the rest unrepresentable' {
        InModuleScope PreventKit {
            $content = @'
URI,RMM_Tool
*.anydesk.com,AnyDesk
relay-[a-f0-9]{8}.net.anydesk.com:443,AnyDesk
upload_data.qq.com,QQ
agents*-cloud.acronis.com,Acronis
'@

            $parsed = ConvertFrom-LolRmmCsv -Content $content -Scope 'lolrmm'

            @($parsed.Covered).Count | Should -Be 1
            @($parsed.Covered | Where-Object { $_.Value -eq 'relay-[a-f0-9]{8}.net.anydesk.com:443' }).Count | Should -Be 1
            @($parsed.Unrepresentable).Count | Should -Be 2
            @($parsed.Unrepresentable | Where-Object { $_.Value -eq 'relay-[a-f0-9]{8}.net.anydesk.com:443' }).Count | Should -Be 0
        }
    }

    It 'does not warn for a covered address, only for genuinely unrepresentable ones' {
        InModuleScope PreventKit {
            $content = @'
URI,RMM_Tool
*.anydesk.com,AnyDesk
relay-[a-f0-9]{8}.net.anydesk.com:443,AnyDesk
upload_data.qq.com,QQ
'@

            $warnings = @()
            ConvertFrom-LolRmmCsv -Content $content -Scope 'lolrmm' -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Where-Object { $_ -match 'relay-' } | Should -BeNullOrEmpty
            $warnings | Where-Object { $_ -match 'upload_data.qq.com' } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'PreventKit covering is scoped to a catalogue source' {

    It 'does not treat an address covered by an entry from another catalogue as covered' {
        $snapshots = @(Invoke-PreventKitRun -CatalogueDirectory $crossCoveredDir)

        $lolrmm = $snapshots | Where-Object { $_.CatalogueName -eq 'lolrmm' }
        @($lolrmm.Covered).Count | Should -Be 0

        $other = $snapshots | Where-Object { $_.CatalogueName -eq 'other' }
        @($other.Covered).Count | Should -Be 0
        @($other.Unrepresentable | Where-Object { $_.Value -eq 'relay-[a-f0-9]{8}.net.anydesk.com:443' }).Count | Should -Be 1
    }
}
