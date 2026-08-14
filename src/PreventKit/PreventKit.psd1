@{
    RootModule           = 'PreventKit.psm1'
    ModuleVersion        = '0.5.0'
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
        ProvenanceNamespace = 'PreventKit'
        PSData = @{
            Tags                       = @('Security', 'Microsoft365', 'Catalogue')
            ReleaseNotes               = 'Issue 1: Catalogue retrieval and validation (read side of a Run). Issue 2: Desired state and WhatIf report. Issue 3: TABL read and provenance classification. Issue 5: CNI projection, read and provenance classification. Provenance namespace is now a module-config value, frozen at load. Issue 4: TABL reconciliation (diff, capacity preflight, batched add/remove of managed entries). Issue 6: CNI reconciliation (rate-limited, backoff-on-429 writes, batched add/remove of managed indicators). Issue 7: Invocation exceptions (non-overriding exception keys that drop entries from desired state). Issue 8: Last known good snapshots (persisted on success, fallback on retrieval/validation failure). Issue 9: Durable run log (source fingerprints, exceptions applied, per-destination reconciliation outcomes).'
        }
    }
}
