# Codebase review — 2026-08-20

Scope: security, efficiency, code clarity, and PowerShell practices across the
PreventKit module and scheduled entry point. No code was changed by this
review.

## Findings

### Critical — default Runs fail while loading the example exception declaration

`exceptions/example.exception.psd1` is an intentionally empty template, but
`Get-GlobalExceptionKey` unconditionally reads `$declaration.Enabled`.
`Set-StrictMode -Version Latest` turns that missing property into a terminating
error. Because `Invoke-PreventKitRun` defaults `ExceptionDirectory` to
`./exceptions`, the documented default Run fails before processing a catalogue.

Evidence:

- `exceptions/example.exception.psd1:1-13`
- `src/PreventKit/Private/Get-GlobalExceptionKey.ps1:29-34`
- `src/PreventKit/Public/Invoke-PreventKitRun.ps1:92-93,137-139`

The review test run found 47 failing tests, all rooted in this exception:
`The property 'Enabled' cannot be found on this object.`

Suggested fix:

- Treat a missing `Enabled` property as disabled, using
  `$declaration.ContainsKey('Enabled') -and $declaration.Enabled -eq $true`.
- Validate the declaration schema and issue a useful warning for malformed
  declarations.
- Alternatively, move the template outside the discovered `*.exception.psd1`
  pattern.
- Add a regression test for an empty template in the default exception
  directory.

### High — scheduled Runs do not obtain current destination state

Both reconciliation inputs default to empty collections. The scheduled wrapper
does not accept or populate either input. Consequently, every scheduled Run
plans additions as though there are no existing TABL or CNI entries. This breaks
idempotency, risks duplicate or rejected API writes, and lets capacity preflight
under-count existing managed entries.

Evidence:

- `src/PreventKit/Public/Invoke-PreventKitRun.ps1:112-118,176-187`
- `src/PreventKit/Public/Start-PreventKitRun.ps1:90-96,113-119`
- `scheduled/Start-PreventKitScheduledRun.ps1:31-57,70-86`

Suggested fix:

- Make the Run own the destination read phase: query TABL before TABL
  reconciliation and query CNI with the supplied token before CNI
  reconciliation.
- Keep injectable current-entry inputs only as explicit test seams, rather
  than public defaults used in production.
- Fail closed when a requested destination cannot be read; do not reconcile
  against an implicit empty state.
- Add an end-to-end scheduled-Run test proving a second Run produces no writes.

### High — CNI matching ignores indicator type

The CNI reconciliation diff compares current and desired entries by value only.
An existing `Url` indicator with value `example.com`, for example, suppresses a
desired `DomainName` indicator with the same value. The intended enforcement can
therefore be missing despite the Run reporting no addition.

Evidence:

- `src/PreventKit/Private/Get-ReconcileDiff.ps1:46-67`
- `src/PreventKit/Private/Invoke-CniReconciliation.ps1:82-85`
- `src/PreventKit/Private/Get-CniDesiredProjections.ps1:40-44`

Suggested fix:

- Give CNI entries a normalized composite identity, such as
  `"$IndicatorType`0$Value"`, and compare that identity in both desired-state
  de-duplication and reconciliation.
- Preserve the value-only identity for TABL, whose entry model differs.
- Add tests for same-value, different-type managed and unmanaged CNI entries.

### High — provenance matching can claim administrator-owned entries

An entry is treated as managed when its Notes or Description merely contains
the provenance namespace string, case-insensitively. An administrator-owned
entry that mentions `PreventKit` can consequently be removed by reconciliation,
contradicting the guarantee that administrator-owned entries are never changed.

Evidence:

- `src/PreventKit/Private/Test-EntryProvenance.ps1:24-35`
- `src/PreventKit/Private/Get-EntryClassification.ps1:25-29`

Suggested fix:

- Stamp and require an exact, versioned marker, for example
  `[PreventKit:v1:managed]`, rather than a substring.
- Centralize marker creation and matching in one helper.
- Consider a format that includes a generated ownership identifier where the
  destination supports it.
- Add tests for administrator notes/descriptions containing the word
  `PreventKit` without the marker.

### Medium — `-Confirm` is advertised but has no effect

`Invoke-PreventKitRun` declares `SupportsShouldProcess = $true`, but it never
calls `$PSCmdlet.ShouldProcess()`. `-Confirm` therefore does not prompt before
state-changing operations. PSScriptAnalyzer reports `PSShouldProcess` for this
function.

Evidence:

- `src/PreventKit/Public/Invoke-PreventKitRun.ps1:82`
- `src/PreventKit/Public/Invoke-PreventKitRun.ps1:176-195`

Suggested fix:

- Call `ShouldProcess` immediately before each destination reconciliation and
  before durable state/log writes, with meaningful target and action text.
- Route `-WhatIf` through the same decision path instead of relying only on
  `$WhatIfPreference`.
- Document whether a WhatIf Run is intended to write an operational log; the
  current implementation temporarily disables WhatIf to do so.
- Add tests for both `-WhatIf` and `-Confirm` behaviour.

### Medium — reconciliation does not scale well to CNI capacity

The CNI capacity documented by the project is 15,000 entries. Reconciliation
repeatedly scans arrays with `-contains`/`-notcontains`, making comparison
quadratic in the number of desired and current entries. Projection building also
uses array `+=` inside its loop, which repeatedly copies growing arrays.

Evidence:

- `src/PreventKit/Private/Get-ReconcileDiff.ps1:61-67`
- `src/PreventKit/Private/Get-CniDesiredProjections.ps1:23,40-44`
- `src/PreventKit/Private/ConvertFrom-LolRmmCsv.ps1:30-32,57`

Suggested fix:

- Build `HashSet[string]` or hashtable indexes for desired and current identity
  keys, then calculate adds, removes, and unchanged entries through lookups.
- Use `System.Collections.Generic.List[object]` while accumulating projections,
  blockable addresses, and suppressed entries; convert to arrays once at the
  boundary.
- Benchmark the full diff at 15,000 desired and current CNI entries, and make
  the benchmark part of a performance check if this is a scheduled workload.

### Low — HTTP content fingerprint is not based on raw response bytes

The help states that the SHA-256 fingerprint is calculated over raw bytes.
For HTTP sources, the code instead reads decoded response text and encodes it as
UTF-8 before hashing. A non-UTF-8 response, or a response whose decoding is
lossy, produces a fingerprint different from the retrieved bytes.

Evidence:

- `src/PreventKit/Private/Get-CatalogueSource.ps1:6-8,28-31,47-60`

Suggested fix:

- Read and hash the HTTP response byte stream, then decode those same bytes
  using the response charset (with a documented fallback) for parsing.
- If byte-level retrieval is not required, amend the help and documentation to
  state that the fingerprint covers normalized UTF-8 text.
- Add a test using non-UTF-8 catalogue content.

### Low — network operations have no explicit time bounds

Catalogue retrieval and CNI writes do not set connection or operation timeouts.
A stalled endpoint can leave an unattended Run running until the host or task
scheduler terminates it.

Evidence:

- `src/PreventKit/Private/Get-CatalogueSource.ps1:27-31`
- `src/PreventKit/Private/Invoke-CniApiRequest.ps1:57-72`

Suggested fix:

- Add bounded, configurable `ConnectionTimeoutSeconds` and
  `OperationTimeoutSeconds` parameters to both HTTP call paths.
- Set safe defaults appropriate for scheduled execution.
- Include timeout failures in the Run log with the source or destination that
  timed out.

## Tooling observations

PSScriptAnalyzer also reports a plural cmdlet noun for
`Get-CniDesiredProjections` and a missing BOM in that file. The former is worth
correcting during API cleanup (`Get-CniDesiredProjection`), while the encoding
warning depends on the repository's chosen encoding policy. Warnings that ask
pure object-construction helpers named `New-*` to support ShouldProcess are not
actionable state-change findings.

## Review result

Fix the critical default-Run failure and the three high-severity reconciliation
issues before using PreventKit for unattended enforcement. Then address
ShouldProcess semantics and the 15,000-entry performance path.
