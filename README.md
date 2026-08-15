# PreventKit

PreventKit manages blocking rules for frequently abused services in one Microsoft 365 tenant. It turns curated external block catalogues into rules for Microsoft enforcement destinations while preserving administrator control.

## How it works

A **Run** retrieves each enabled **catalogue source**, parses it with a **source adapter** into the canonical **Service** and **Blockable Address** model, validates the result, and computes the **desired state** as the union of all valid catalogue entries. The desired state is then reconciled to the **enforcement destinations** that were supplied with a capacity: managed entries that are no longer desired are removed, and missing managed entries are added. Administrator-owned entries are never adopted or changed.

Every Run is either a manual invocation or a scheduled invocation; both drive the same engine.

## Catalogue sources

A **catalogue declaration** enables a block catalogue and sets its scope. Declarations live in `catalogues/`:

- `lolrmm.catalog.psd1` — the lolrmm.io RMM domains CSV (`LolRmmCsv` adapter).
- `tunneling.catalog.psd1` — the Awesome Tunneling markdown (`AwesomeTunneling` adapter).

A catalogue source that fails retrieval or validation is skipped in favour of its **last known good snapshot** when one exists; otherwise the Run still completes and records the failure.

## Exceptions

Exceptions are non-overriding: matched entries leave the desired state and are never enforced. No allow rule is ever created.

- **Global exceptions** are stored, version-controlled declarations in an exception directory (`*.exception.psd1`). Every enabled declaration contributes its exception keys to every Run. Removing or disabling a declaration restores enforcement on the next Run.
- **Invocation exceptions** are supplied through the Run's parameters and remain effective only while supplied to every Run.

Both match by **exception key**, such as `service:lolrmm/AnyDesk` or `domain:anydesk.com`.

## Running

A manual Run over the repository catalogues:

```powershell
Import-Module ./src/PreventKit/PreventKit.psd1
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -StateDirectory ./state -LogDirectory ./logs
```

A **WhatIf run** computes and reports the desired state without modifying any enforcement destination:

```powershell
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -WhatIf
```

Apply global exceptions from a directory and reconcile the Tenant Allow/Block List and Custom Network Indicators:

```powershell
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -ExceptionDirectory ./exceptions `
  -StateDirectory ./state -LogDirectory ./logs `
  -TablCapacity 5000 -CniCapacity 15000
```

## Scheduled runs

`scheduled/Start-PreventKitScheduledRun.ps1` runs a Run unattended and returns a process exit code a scheduler can observe (0 on success, 1 on failure). Outcomes land in the run log, including a `Failed` entry with the error message for failing Runs. See the script's comment-based help for Windows Task Scheduler registration.

## Run log

Each Run writes a durable entry to the log directory (`<run-id>.run.json`) capturing source fingerprints, exceptions applied, per-destination reconciliation outcomes, and the Run status. Query entries with `Get-PreventKitRunLog` and print a per-run report with `New-PreventKitRunReport`.

## Module layout

- `src/PreventKit/Public/` — the exported commands (`Invoke-PreventKitRun`, `Start-PreventKitRun`).
- `src/PreventKit/Private/` — the retrieval, parsing, validation, exception, projection, reconciliation, and run-log internals.
- `catalogues/` — the version-controlled catalogue declarations.
- `scheduled/` — the scheduled Run entry point.
- `tests/` — Pester tests and fixtures.

## Development

Run the test suite with Pester 5:

```powershell
Invoke-Pester -Path ./tests
```
