@{
    RootModule           = 'PreventKit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '2174ebab-52f3-4ddc-a486-7945c3f2d62f'
    Author               = 'PreventKit'
    CompanyName          = 'PreventKit'
    Copyright            = '(c) PreventKit. All rights reserved.'
    Description          = 'PreventKit manages blocking rules for frequently abused services in Microsoft 365.'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @('Invoke-PreventKitRun')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags                       = @('Security', 'Microsoft365', 'Catalogue')
            ReleaseNotes               = 'Issue 1: Catalogue retrieval and validation (read side of a Run).'
        }
    }
}
