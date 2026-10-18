BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'PreventKit normalized blockable address' {

    It 'returns an already-representable value unchanged' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value 'GetScreen.me'            | Should -Be 'GetScreen.me'
            Get-NormalizedBlockableAddress -Value '*.example.com'           | Should -Be '*.example.com'
            Get-NormalizedBlockableAddress -Value '136.243.104.235'         | Should -Be '136.243.104.235'
            Get-NormalizedBlockableAddress -Value 'https://example.com/x'   | Should -Be 'https://example.com/x'
        }
    }

    It 'drops a trailing port, including the wildcard port form' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value 'bore.pub:*'           | Should -Be 'bore.pub'
            Get-NormalizedBlockableAddress -Value 'host.example.com:8443' | Should -Be 'host.example.com'
        }
    }

    It 'drops a trailing pattern wildcard' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value '*.shellhub.io*'  | Should -Be '*.shellhub.io'
            Get-NormalizedBlockableAddress -Value '*tunnel.pyjam.as*' | Should -Be '*.tunnel.pyjam.as'
        }
    }

    It 'turns a leading wildcard without a separating dot into a subdomain wildcard' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value '*pitunnel.com' | Should -Be '*.pitunnel.com'
        }
    }

    It 'does not derive a wildcard parent from an embedded wildcard label by default' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value 'agents*-cloud.acronis.com'         | Should -Be 'agents*-cloud.acronis.com'
            Get-NormalizedBlockableAddress -Value 'rescue-list.*.logmein-gateway.com' | Should -Be 'rescue-list.*.logmein-gateway.com'
        }
    }

    It 'derives a wildcard parent from an embedded wildcard label when asked to recover derived wildcards' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value 'agents*-cloud.acronis.com' -RecoverDerivedWildcards         | Should -Be '*.acronis.com'
            Get-NormalizedBlockableAddress -Value 'rescue-list.*.logmein-gateway.com' -RecoverDerivedWildcards | Should -Be '*.logmein-gateway.com'
        }
    }

    It 'does not derive a wildcard parent when the parent would have fewer than two labels' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value 'rescue-list.*.com' -RecoverDerivedWildcards | Should -Be 'rescue-list.*.com'
        }
    }

    It 'leaves genuinely unrecoverable values unchanged' {
        InModuleScope PreventKit {
            Get-NormalizedBlockableAddress -Value 'upload_data.qq.com'                            | Should -Be 'upload_data.qq.com'
            Get-NormalizedBlockableAddress -Value '_v2-origintunneld._tcp.argotunnel.com'         | Should -Be '_v2-origintunneld._tcp.argotunnel.com'
            Get-NormalizedBlockableAddress -Value '*.*.amazonaws.com/public.pinggy.binaries/*'     | Should -Be '*.*.amazonaws.com/public.pinggy.binaries/*'
        }
    }
}
