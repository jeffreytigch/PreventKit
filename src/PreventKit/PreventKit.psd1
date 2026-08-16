@{
    RootModule           = 'PreventKit.psm1'
    ModuleVersion        = '0.6.0'
    GUID                 = '2174ebab-52f3-4ddc-a486-7945c3f2d62f'
    Author               = 'PreventKit'
    CompanyName          = 'PreventKit'
    Copyright            = '(c) PreventKit. All rights reserved.'
    Description          = 'PreventKit manages blocking rules for frequently abused services in Microsoft 365.'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @('Invoke-PreventKitRun', 'Start-PreventKitRun', 'Get-PreventKitRunLog', 'New-PreventKitRunReport')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        ProvenanceNamespace = 'PreventKit'
        PSData = @{
            Tags                       = @('Security', 'Microsoft365', 'Catalogue')
            ReleaseNotes               = ''
        }
    }
}
