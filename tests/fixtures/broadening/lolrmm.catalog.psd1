@{
    Name          = 'lolrmm'
    Enabled       = $true
    Adapter       = 'LolRmmCsv'
    Scope         = 'lolrmm'
    Source        = 'lolrmm.csv'
    Normalization = @{ RecoverDerivedWildcards = $true }
}
