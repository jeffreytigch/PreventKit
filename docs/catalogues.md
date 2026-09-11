# Catalogues

A **catalogue declaration** enables a block catalogue and sets its scope. Declarations live in a catalogue directory (by convention `catalogues/`) and match `*.catalog.psd1`. Each Run processes every enabled declaration in that directory together.

```powershell
@{
    Name    = 'lolrmm'
    Enabled = $true
    Adapter = 'LolRmmCsv'
    Scope   = 'lolrmm'
    Source  = 'https://lolrmm.io/api/rmm_domains.csv'
}
```

| Field | Meaning |
| --- | --- |
| `Name` | Identifier for the catalogue, used in logs and reports. |
| `Enabled` | Whether this declaration contributes to every Run. Disabled declarations are skipped. |
| `Adapter` | The **source adapter** that parses the source's native format. |
| `Scope` | Prefix applied to the service identifiers parsed from this source. |
| `Source` | URL or local path the catalogue is read from. A relative path is resolved against the declaration file; approving the source is an operator responsibility. |

An optional `Targets` block carries per-target settings for a catalogue. The only setting currently read is `Cni.AllowBroadening`, which approves mapping a wildcard address to a broader CNI entry:

```powershell
@{
    Name    = 'lolrmm'
    Enabled = $true
    Adapter = 'LolRmmCsv'
    Scope   = 'lolrmm'
    Source  = 'lolrmm.csv'
    Targets = @{
        Cni = @{
            AllowBroadening = $true
        }
    }
}
```

Built-in adapters:

| Adapter | Source format |
| --- | --- |
| `LolRmmCsv` | [lolrmm.io](https://lolrmm.io) RMM domains CSV (`URI`, `RMM_Tool` columns) |

## Snapshots and failures

Retrieval, parsing, and validation produce a **catalogue snapshot** carrying a source fingerprint (source location, retrieval time, SHA-256 content hash, and parsed counts).

Validation runs a fixed set of checks over the retrieved content and parsed model:

- `SourceRetrievalSucceeded` — the source returned content.
- `AtLeastOneService` — at least one service was parsed.
- `AtLeastOneBlockableAddress` — at least one blockable address was parsed.

A source that fails retrieval or validation is skipped in favour of its **last known good snapshot** when one exists; otherwise the Run still completes and records the failure. A snapshot that passes validation is persisted as the catalogue's last known good snapshot under the state directory, one JSON file per catalogue.

A source whose content is empty, or whose adapter parses no services or no blockable addresses, is treated as a validation failure and its entries are not trusted.

## Registering a custom adapter

Additional catalogues are registered with `Register-CatalogueAdapter`, which takes a scriptblock receiving `-Content` and `-Scope` and returning `Services` and `BlockableAddresses`:

```powershell
Register-CatalogueAdapter -Name 'MyCsv' -ParseScriptBlock {
    param($Content, $Scope)
    $rows = $Content | ConvertFrom-Csv
    [pscustomobject]@{
        Services = @()
        BlockableAddresses = $rows | ForEach-Object {
            [pscustomobject]@{
                Value     = $_.Url
                Type      = $_.Type
                ServiceId = "$Scope/$($_.Service)"
            }
        }
    }
} -Description 'Custom CSV adapter for my threat intel feed'
```

Use `Get-CatalogueAdapter`, `Get-CatalogueAdapterList`, and `Unregister-CatalogueAdapter` to inspect or remove registered adapters.

## Catalogue requirements

- The source should present its list in a format that is natively ingestable by PowerShell (i.e. CSV, JSON).
- The catalogue should be accompanied by a transformation script and tests, to adapt the source format into the canonical **Service** and **Blockable address** model.
- Addresses that cannot be represented (not a URL, domain, or IP address) are logged and skipped; addresses already covered by a broader wildcard entry are recorded as covered without warning.

See [`tests/PreventKit.Tests.ps1`](../tests/PreventKit.Tests.ps1) and the fixtures under [`tests/fixtures/`](../tests/fixtures/) for examples of catalogue declarations and adapters exercised by the test suite.
