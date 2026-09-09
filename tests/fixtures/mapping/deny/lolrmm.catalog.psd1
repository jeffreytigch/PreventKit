@{
    Name    = 'lolrmm'
    Enabled = $true
    Adapter = 'LolRmmCsv'
    Scope   = 'lolrmm'
    Source  = 'lolrmm.csv'
    Targets = @{
        Cni = @{
            AllowBroadening = $false
        }
    }
}
