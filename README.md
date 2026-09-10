# PreventKit

PreventKit manages blocking rules for frequently abused services in one Microsoft 365 tenant. It turns curated "living off the land" catalogues into block rules for Microsoft 365 enforcement targets (i.e. CNI, TABL). It aims to be as non-intrusive as possible, using functionality you already pay for.

- [How it works](#how-it-works)
- [Catalogues](#catalogues)
- [Install](#install)
- [Usage](#usage)
- [Development](#development)

## How it works

A **Run** retrieves each enabled **catalogue source**, parses it with a **source adapter** into the canonical **Service** / **Blockable Address** model, validates the result, and computes the **desired state** as the union of all valid catalogue entries. The desired state is then reconciled to the selected **enforcement targets** — managed entries that are no longer desired are removed, and missing managed entries are added. Administrator-owned entries are never adopted or changed.

Every Run is either a manual invocation or a scheduled invocation; both drive the same engine.

```mermaid
flowchart LR
    A{Run} --> B[Retrieve and parse catalogue sources]
    Source1([LOLRMM]) -.- B
    B --> C[Apply exceptions]
    C --> D[Compute desired state]
    D --> E[Apply entries from catalogue sources to M365 services]
    Target1([Tenant Allow/Block List]) -.- E
    Target2([Custom Network Indicators]) -.- E
    E --> F{Done}
```

## Catalogues

A **catalogue declaration** enables a block catalogue and sets its scope. Declarations live in `catalogues/` and match `*.catalog.psd1`:

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
| `Source` | URL or local path the catalogue is read from. Approving the source is an operator responsibility. |

Built-in adapters:

| Adapter | Source format |
| --- | --- |
| `LolRmmCsv` | [lolrmm.io](https://lolrmm.io) RMM domains CSV |

Notes:

- A source that fails retrieval or validation is skipped in favour of its **last known good snapshot** when one exists; otherwise the Run still completes and records the failure.
- Additional catalogues are registered with `Register-CatalogueAdapter`, which takes a scriptblock receiving `-Content` and `-Scope` and returning `Services` and `BlockableAddresses`.
- To contribute a new catalogue, the source must present a natively ingestable format (CSV, JSON), and must come with a transformation script and tests. See [`docs/catalogues.md`](docs/catalogues.md).

## Install

Requirements:

- PowerShell 7+
- **TABL** target: the `ExchangeOnlineManagement` module and a connected Exchange Online session.
- **CNI** target: Defender for Endpoint, plus the Azure CLI signed in (or a token you supply — see [Authentication](#authentication)).

Clone the repository and import the module:

```powershell
git clone https://github.com/jeffreytigch/preventkit.git
Set-Location ./preventkit
Import-Module ./src/PreventKit/PreventKit.psd1
```

The module declares no `RequiredModules` and is self-contained.

## Usage

### Enforcement targets and capacity

Two enforcement targets are supported: **CNI** — Custom Network Indicators, and **TABL** — Tenant Allow/Block List. A Run reconciles **both targets by default**, so no target argument is required. Use `-Target` to narrow a Run to one destination (`-Target Tabl` or `-Target Cni`); `-Target` accepts both values together and rejects an empty selection.

Each destination has a **plan-default capacity**: TABL 1000 and CNI 15,000. The capacity is the preflight limit: the **capacity preflight** aborts a destination when the planned managed-entry count would exceed it, before any write. Supply `-TablCapacity` / `-CniCapacity` only to override the plan default for a destination that is selected; supplying a capacity for an unselected destination is an error.

| Target | Selected by | Licence | Block entry limit |
| --- | --- | --- | --- |
| **CNI** — Custom Network Indicators | `-Target Cni` | Defender for Endpoint Plan 1 / Plan 2 | 15,000 indicators per tenant |
| **TABL** — Tenant Allow/Block List | `-Target Tabl` | M365 without Defender for Office 365 | 500 |
| **TABL** — Tenant Allow/Block List | `-Target Tabl` | Defender for Office 365 Plan 1 (BP, E3) | 1,000 |
| **TABL** — Tenant Allow/Block List | `-Target Tabl` | Defender for Office 365 Plan 2 (E5, E7) | 10,000 |

The default 1,000 matches Defender for Office 365 Plan 1. Set `-TablCapacity 500` when your tenant has no Defender for Office 365, or `-TablCapacity 10000` on Plan 2.

### Authentication

Each destination authenticates its own connection:

- **TABL** writes through Exchange Online PowerShell, so run `Connect-ExchangeOnline` in the same PowerShell session before a Run that selects TABL. There is no token parameter.
- **CNI** authenticates automatically whenever selected: a caller-supplied `-CniToken` is used when provided, otherwise a token is acquired from the signed-in Azure CLI session. A Run with no token fails before any request is sent.

See [`docs/authentication.md`](docs/authentication.md) for Entra app registration and the interactive, client-certificate, and managed-identity token flows.

### Run over the repository catalogues

A Run with no target arguments reconciles both destinations using the plan-default capacities:

```powershell
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -StateDirectory ./state -LogDirectory ./logs
```

Narrow a Run to one destination, or override its capacity, and apply global exceptions:

```powershell
# TABL only, with the Plan 2 capacity
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -ExceptionDirectory ./exceptions `
  -StateDirectory ./state -LogDirectory ./logs -Target Tabl -TablCapacity 10000

# CNI only, overriding the capacity
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -Target Cni -CniCapacity 15000
```

A **WhatIf run** computes and reports the desired state without modifying any enforcement target:

```powershell
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -WhatIf
```

Supplying an explicit CNI token (interactive, client certificate, or managed identity) for a CNI-only Run:

```powershell
$token = (az account get-access-token --resource 'https://api.securitycenter.microsoft.com' | ConvertFrom-Json).accessToken
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -Target Cni -CniToken $token
```

### Exceptions

Exceptions are managed-only: matched entries leave the desired state and are never enforced. No allow rule is ever created.

- **Global exceptions** are version-controlled declarations in an exception directory (`*.exception.psd1`). Every enabled declaration contributes its keys to every Run; removing or disabling a declaration restores enforcement on the next Run.
- **Invocation exceptions** are supplied through `-ExceptionKey` and remain effective only while supplied to every Run.

Both match by **exception key**, such as `service:lolrmm/AnyDesk` or `domain:anydesk.com`. An example declaration is provided at [`exceptions/example.exception.psd1`](exceptions/example.exception.psd1):

```powershell
@{
    Name         = 'Example'
    Enabled      = $false
    ExceptionKey = @('service:lolrmm/Example')
}
```

### Scheduled runs

[`scheduled/Start-PreventKitScheduledRun.ps1`](scheduled/Start-PreventKitScheduledRun.ps1) runs a Run unattended and returns a process exit code a scheduler can observe (0 on success, 1 on failure). It accepts and forwards the same `-Target` selector, capacity overrides, and `-CniToken` as a manual Run; with no target arguments it reconciles both destinations using the plan defaults. A scheduled CNI Run supplies its token the same way a manual one does:

```powershell
$token = (az account get-access-token --resource 'https://api.securitycenter.microsoft.com' | ConvertFrom-Json).accessToken
& pwsh -NoProfile -File ./scheduled/Start-PreventKitScheduledRun.ps1 `
  -CatalogueDirectory ./catalogues -StateDirectory ./state -LogDirectory ./logs `
  -Target Cni -CniCapacity 15000 -CniToken $token
```

The script's comment-based help includes a Windows Task Scheduler registration example.

### Run log

Each Run writes a durable entry (`<run-id>.run.json`) capturing source fingerprints, exceptions applied, per-target outcomes, and status.

```powershell
# All entries, oldest first
Get-PreventKitRunLog -LogDirectory ./logs

# A readable report for one entry
$entry = Get-PreventKitRunLog -LogDirectory ./logs | Select-Object -First 1
New-PreventKitRunReport -LogEntry $entry
```

A Run that throws during reconciliation is logged as `Failed` with its error message; a Run whose target aborts (for example a capacity preflight failure) is logged as `Partial` while still recording the aborted target outcome.

## Development

### Layout

- `src/PreventKit/Public/` — exported commands: the Run engine (`Invoke-PreventKitRun`, `Start-PreventKitRun`), run-log helpers (`Get-PreventKitRunLog`, `New-PreventKitRunReport`), the adapter registry (`Register-CatalogueAdapter`, `Get-CatalogueAdapter`, `Get-CatalogueAdapterList`, `Unregister-CatalogueAdapter`), and integrity checks (`Get-PreventKitModuleIntegrity`, `New-PreventKitIntegrityBaseline`).
- `src/PreventKit/Private/` — retrieval, parsing, validation, exception, mapping, reconciliation, and run-log internals.
- `catalogues/` — version-controlled catalogue declarations.
- `exceptions/` — version-controlled global exception declarations.
- `scheduled/` — scheduled Run entry point.
- `docs/` — catalogue, authentication, and supply-chain guidance.
- `tests/` — Pester tests and fixtures.

### Tests

Run the test suite with Pester 5:

```powershell
Invoke-Pester -Path ./tests
```

### Module integrity

Verify the module files against the checked-in baseline, or regenerate it after intentional changes:

```powershell
Get-PreventKitModuleIntegrity -BaselineFile ./preventkit-baseline.json -FailOnMismatch
New-PreventKitIntegrityBaseline -OutputPath ./preventkit-baseline.json
```

See [`docs/supply-chain-security.md`](docs/supply-chain-security.md) for the threat model and secure-deployment checklist.
