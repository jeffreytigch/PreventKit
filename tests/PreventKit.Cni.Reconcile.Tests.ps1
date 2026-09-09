BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'PreventKit reconcile diff (CNI)' {

    It 'diffs by IndicatorValue and treats current indicators as desired when present' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = '136.243.104.235'; IndicatorType = 'IpAddress'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ IndicatorValue = '136.243.104.235'; IndicatorType = 'IpAddress'; Id = '42'; Description = 'PreventKit managed'; Classification = 'Managed' },
                [pscustomobject]@{ IndicatorValue = 'admin.example.org'; IndicatorType = 'DomainName'; Id = '43'; Description = 'administrator'; Classification = 'UnmanagedMatch' }
            )

            $diff = Get-ReconcileDiff -DesiredEntries $desired -CurrentEntries $current -CurrentValueProperty 'IndicatorValue'

            @($diff.Adds).Count | Should -Be 1
            $diff.Adds[0].Value | Should -Be 'evil.example.com'
            @($diff.Removes).Count | Should -Be 0
            @($diff.Unchanged).Count | Should -Be 1
            $diff.UnmanagedMatchCount | Should -Be 1
        }
    }

    It 'marks a stale managed indicator for removal and leaves the unmanaged match alone' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ IndicatorValue = 'stale.example.org'; IndicatorType = 'DomainName'; Id = '9'; Description = 'PreventKit managed'; Classification = 'Managed' },
                [pscustomobject]@{ IndicatorValue = 'old.example.net'; IndicatorType = 'DomainName'; Id = '8'; Description = 'administrator'; Classification = 'UnmanagedMatch' }
            )

            $diff = Get-ReconcileDiff -DesiredEntries $desired -CurrentEntries $current -CurrentValueProperty 'IndicatorValue'

            @($diff.Adds).Count | Should -Be 1
            @($diff.Removes).Count | Should -Be 1
            $diff.Removes[0].Id | Should -Be '9'
            $diff.UnmanagedMatchCount | Should -Be 1
        }
    }
}

Describe 'PreventKit CNI managed entry submission' {

    It 'posts one import batch per BatchSize, carrying owner marker in description with no expiry' {
        InModuleScope PreventKit {
            $mappings = @(
                [pscustomobject]@{ Value = 'evil.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = '136.243.104.235'; IndicatorType = 'IpAddress'; ServiceId = 'lolrmm/Tool' }
            )

            $script:captured = @()
            Mock Invoke-CniApiRequest {
                param($Uri, $Body, $Token)
                $script:captured += [pscustomobject]@{ Uri = $Uri; Body = $Body; Token = $Token }
                return $null
            }
            Mock Start-Sleep { }

            Add-CniManagedEntry -Mappings $mappings -BatchSize 1 -RateLimitPerMinute 0 -Token 'test-token'

            $script:captured.Count | Should -Be 2
            $first = $script:captured[0].Body.Indicators[0]
            $first.indicatorValue | Should -Be 'evil.example.com'
            $first.indicatorType | Should -Be 'DomainName'
            $first.action | Should -Be 'Block'
            $first.title | Should -Be 'lolrmm/Tool'
            $first.description | Should -Match $script:ownerMarker
            $first.PSObject.Properties.Name | Should -Not -Contain 'expirationTime'
            $script:captured[0].Token | Should -Be 'test-token'
            $script:captured[1].Token | Should -Be 'test-token'
        }
    }

    It 'paces batches to respect the rate limit' {
        InModuleScope PreventKit {
            $mappings = @(
                [pscustomobject]@{ Value = 'a.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'b.example.net'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'c.example.org'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' }
            )

            Mock Invoke-CniApiRequest { return $null }
            Mock Start-Sleep { }

            Add-CniManagedEntry -Mappings $mappings -BatchSize 1 -RateLimitPerMinute 60 -Token 'test-token'

            Assert-MockCalled Invoke-CniApiRequest -Times 3 -Exactly
            Assert-MockCalled Start-Sleep -Times 2 -Exactly
        }
    }

    It 'does not sleep when the rate limit is disabled' {
        InModuleScope PreventKit {
            $mappings = @(
                [pscustomobject]@{ Value = 'a.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'b.example.net'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' }
            )

            Mock Invoke-CniApiRequest { return $null }
            Mock Start-Sleep { }

            Add-CniManagedEntry -Mappings $mappings -BatchSize 1 -RateLimitPerMinute 0 -Token 'test-token'

            Assert-MockCalled Start-Sleep -Times 0 -Exactly
        }
    }

    It 'returns no entry when given no mappings' {
        InModuleScope PreventKit {
            Mock Invoke-CniApiRequest { return $null }
            Mock Start-Sleep { }

            $result = Add-CniManagedEntry -Mappings @() -BatchSize 1 -RateLimitPerMinute 0 -Token 'test-token'

            Assert-MockCalled Invoke-CniApiRequest -Times 0 -Exactly
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'PreventKit CNI rate-limited API request' {

    It 'sends the caller-supplied token as an Authorization Bearer header' {
        InModuleScope PreventKit {
            $script:capturedHeaders = $null
            Mock Invoke-RestMethod {
                $script:capturedHeaders = $Headers
                return @{ results = @() }
            }

            $null = Invoke-CniApiRequest -Uri 'https://api.security.microsoft.com/api/indicators/import' `
                -Body @{ Indicators = @() } -Token 'test-token'

            $script:capturedHeaders['Authorization'] | Should -Be 'Bearer test-token'
        }
    }

    It 'keeps the Authorization Bearer header across 429 retries' {
        InModuleScope PreventKit {
            $script:headers = @()
            Mock Invoke-RestMethod {
                $script:headers += $Headers['Authorization']
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $resp)
            }
            Mock Start-Sleep { }

            { Invoke-CniApiRequest -Uri 'https://api.security.microsoft.com/api/indicators/import' `
                -Body @{ Indicators = @() } -Token 'test-token' -MaxRetries 2 -BackoffSeconds 0 } | Should -Throw

            @($script:headers) | Should -Be @('Bearer test-token', 'Bearer test-token', 'Bearer test-token')
        }
    }

    It 'retries with backoff on a 429 and succeeds' {
        InModuleScope PreventKit {
            $script:calls = 0
            Mock Invoke-RestMethod {
                $script:calls++
                if ($script:calls -eq 1) {
                    $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    throw [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $resp)
                }
                return @{ results = @() }
            }
            Mock Start-Sleep { }

            $result = Invoke-CniApiRequest -Uri 'https://api.security.microsoft.com/api/indicators/import' -Body @{ Indicators = @() } -Token 'test-token' -MaxRetries 3 -BackoffSeconds 1

            $script:calls | Should -Be 2
            Assert-MockCalled Start-Sleep -Times 1 -Exactly
        }
    }

    It 'gives up after MaxRetries on persistent 429' {
        InModuleScope PreventKit {
            Mock Invoke-RestMethod {
                $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $resp)
            }
            Mock Start-Sleep { }

            { Invoke-CniApiRequest -Uri 'https://api.security.microsoft.com/api/indicators/import' -Body @{ Indicators = @() } -Token 'test-token' -MaxRetries 2 -BackoffSeconds 0 } | Should -Throw

            Assert-MockCalled Invoke-RestMethod -Times 3 -Exactly
        }
    }
}

Describe 'PreventKit CNI managed entry removal' {

    It 'posts batched indicator ids to the BatchDelete endpoint' {
        InModuleScope PreventKit {
            $script:captured = @()
            Mock Invoke-CniApiRequest {
                param($Uri, $Body, $Token)
                $script:captured += [pscustomobject]@{ Uri = $Uri; Body = $Body; Token = $Token }
                return $null
            }
            Mock Start-Sleep { }

            Remove-CniManagedEntry -Id @('1', '2', '3') -BatchSize 2 -RateLimitPerMinute 0 -Token 'test-token'

            $script:captured.Count | Should -Be 2
            $script:captured[0].Uri | Should -Match 'BatchDelete'
            @($script:captured[0].Body.IndicatorIds) | Should -Be @('1', '2')
            @($script:captured[1].Body.IndicatorIds) | Should -Be @('3')
            $script:captured[0].Token | Should -Be 'test-token'
            $script:captured[1].Token | Should -Be 'test-token'
        }
    }
    It 'paces remove batches to respect the rate limit' {
        InModuleScope PreventKit {
            Mock Invoke-CniApiRequest { return $null }
            Mock Start-Sleep { }

            Remove-CniManagedEntry -Id @('1', '2', '3') -BatchSize 1 -RateLimitPerMinute 60 -Token 'test-token'

            Assert-MockCalled Invoke-CniApiRequest -Times 3 -Exactly
            Assert-MockCalled Start-Sleep -Times 2 -Exactly
        }
    }

    It 'does not sleep when the remove rate limit is disabled' {
        InModuleScope PreventKit {
            Mock Invoke-CniApiRequest { return $null }
            Mock Start-Sleep { }

            Remove-CniManagedEntry -Id @('1', '2') -BatchSize 1 -RateLimitPerMinute 0 -Token 'test-token'

            Assert-MockCalled Start-Sleep -Times 0 -Exactly
        }
    }
}

Describe 'PreventKit CNI reconciliation' {

    It 'adds missing mappings and removes stale managed indicators, leaving unmanaged alone' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' },
                [pscustomobject]@{ Value = 'keep.example.net'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' }
            )
            $current = @(
                [pscustomobject]@{ indicatorValue = 'keep.example.net'; indicatorType = 'DomainName'; description = 'PreventKit managed'; id = '1'; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'stale.example.org'; indicatorType = 'DomainName'; description = 'PreventKit managed'; id = '2'; action = 'Block' },
                [pscustomobject]@{ indicatorValue = 'admin.example.org'; indicatorType = 'DomainName'; description = 'administrator'; id = '3'; action = 'Block' }
            )

            Mock Add-CniManagedEntry { return $Mappings }
            Mock Remove-CniManagedEntry { }

            $result = Invoke-CniReconciliation -DesiredEntries $desired -CurrentEntries $current -Capacity 10 -Token 'test-token'

            $result.Status | Should -Be 'Reconciled'
            Assert-MockCalled Add-CniManagedEntry -Times 1 -Exactly -ParameterFilter { @($Mappings | Where-Object { $_.Value -eq 'evil.example.com' }).Count -eq 1 }
            Assert-MockCalled Remove-CniManagedEntry -Times 1 -Exactly -ParameterFilter { @($Id | Where-Object { $_ -eq '2' }).Count -eq 1 }
            Assert-MockCalled Remove-CniManagedEntry -Times 0 -Exactly -ParameterFilter { @($Id | Where-Object { $_ -eq '3' }).Count -eq 1 }
            Assert-MockCalled Add-CniManagedEntry -Times 1 -Exactly -ParameterFilter { $Token -eq 'test-token' }
            Assert-MockCalled Remove-CniManagedEntry -Times 1 -Exactly -ParameterFilter { $Token -eq 'test-token' }
        }
    }

    It 'aborts without any write when capacity preflight fails' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' }
            )

            Mock Add-CniManagedEntry { }
            Mock Remove-CniManagedEntry { }

            $result = Invoke-CniReconciliation -DesiredEntries $desired -CurrentEntries @() -Capacity 0 -Token 'test-token'

            $result.Status | Should -Be 'Aborted'
            $result.Preflight.Passed | Should -BeFalse
            Assert-MockCalled Add-CniManagedEntry -Times 0 -Exactly
            Assert-MockCalled Remove-CniManagedEntry -Times 0 -Exactly
        }
    }

    It 'a second run against the reconciled target makes no changes' {
        InModuleScope PreventKit {
            $desired = @(
                [pscustomobject]@{ Value = 'evil.example.com'; IndicatorType = 'DomainName'; ServiceId = 'lolrmm/Tool' }
            )
            $afterFirstRun = @(
                [pscustomobject]@{ indicatorValue = 'evil.example.com'; indicatorType = 'DomainName'; description = 'PreventKit managed entry'; id = '1'; action = 'Block' }
            )

            Mock Add-CniManagedEntry { }
            Mock Remove-CniManagedEntry { }

            $result = Invoke-CniReconciliation -DesiredEntries $desired -CurrentEntries $afterFirstRun -Capacity 10 -Token 'test-token'

            $result.Status | Should -Be 'NoChanges'
            Assert-MockCalled Add-CniManagedEntry -Times 0 -Exactly
            Assert-MockCalled Remove-CniManagedEntry -Times 0 -Exactly
        }
    }
}
