@{
    Name    = 'lolrmm'
    Enabled = $true
    Adapter = 'LolRmmCsv'
    Scope   = 'lolrmm'
    Source  = 'lolrmm.csv'
    Destinations = @{
        Cni = @{
            AllowExpansion = $true
        }
    }
}
