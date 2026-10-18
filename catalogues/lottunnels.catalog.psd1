@{
    Name    = 'lottunnels'
    Enabled = $true
    Adapter = 'LotTunnelsCsv'
    Scope   = 'lottunnels'
    Source  = 'https://lottunnels.github.io/domains.csv'
    Targets = @{
        Cni = @{
            AllowBroadening = $true
        }
    }
    Normalization = @{
        RecoverDerivedWildcards = $true
    }
}
