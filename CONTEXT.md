# PreventKit

PreventKit manages blocking rules for frequently abused services in one Microsoft 365 tenant. It turns curated external catalogues into rules for Microsoft enforcement targets while preserving administrator control.

## Language

**Block catalogue**:
An external, curated list of services or addresses that PreventKit uses as blocking input. It is opinionated, meaning the choice of what to block is made before PreventKit runs rather than by PreventKit itself.
_Avoid_: Threat feed, intelligence feed, block list

**Catalogue source**:
The URL or local file that PreventKit reads a block catalogue from. Approving a source, and accepting the risk of tracking it directly, are operator responsibilities.
_Avoid_: Feed endpoint, input file

**Source adapter**:
A parser that converts one catalogue source's native format into PreventKit's canonical Service and Blockable Address model.
_Avoid_: Generic parser, CSV importer

**Catalogue declaration**:
A version-controlled definition that enables a block catalogue and sets its scope. Approval happens outside PreventKit; valid entries from an enabled catalogue are enforced automatically.
_Avoid_: In-service approval, feed configuration

**Catalogue directory**:
The version-controlled directory of catalogue declarations that a Run processes together.
_Avoid_: Source folder, configuration directory

**Catalogue snapshot**:
A successfully retrieved and validated current representation of a block catalogue.
_Avoid_: Download, feed response

**Last known good snapshot**:
The most recent catalogue snapshot that passed validation and stays authoritative while a newer retrieval fails or looks suspicious.
_Avoid_: Cache, stale data

**Service**:
A named, frequently abused capability that may be represented by one or more blockable addresses.
_Avoid_: Domain, indicator

**Blockable address**:
A URL, domain, or IP address that represents a Service, or that stands alone when no service identity is known.
_Avoid_: Indicator, IOC

**Covered address**:
An address that would be enforced anyway by a broader wildcard entry already in place, so the catalogue does not need to list it. A candidate is covered when its normalized domain tail equals the root of an existing wildcard domain entry, or ends with that root at a label boundary — so `help.example.com` is covered by `*.example.com`, but `badexample.com` is not. This is distinct from an address with no safe exact mapping, which is unrepresentable.
_Avoid_: Duplicate entry, redundant address

**Enforcement target**:
A Microsoft 365 control surface to which PreventKit can publish a blocking rule, such as the Tenant Allow/Block List, Custom Network Indicators, or Global Secure Access web controls.
_Avoid_: Output, sink, integration

**Target mapping**:
The compatible representation of a blockable address for one enforcement target. A mapping can be absent when that target cannot safely express the address.
_Avoid_: Conversion, format hack

**Exact mapping**:
A target mapping that blocks neither more nor less than the source blockable address intends. An address with no exact mapping is skipped and logged.
_Avoid_: Best-effort conversion, broadened block

**Approved broadening**:
An explicitly approved mapping that blocks more than its source address because a target cannot express the source semantics. For CNI, `*.example.com` becomes `example.com`, which blocks the root domain and all subdomains.
_Avoid_: Implicit broadening, exact mapping

**Capacity preflight**:
A check that the planned managed-entry count fits an enforcement target before PreventKit writes to that target.
_Avoid_: Partial import, capacity guess

**Managed entry**:
A rule at an enforcement target that carries an owner marker identifying PreventKit as the owner.
_Avoid_: Existing entry, synced entry

**Permanent managed entry**:
A managed entry without an expiry that stays at its enforcement target until reconciliation removes it.
_Avoid_: Expiring entry

**Owner marker**:
The recognizable identifiers PreventKit reserves at enforcement targets to find and reconcile managed entries without keeping local persistent state.
_Avoid_: Comment convention, tag

**Unmanaged match**:
An administrator-owned entry at an enforcement target that matches an address in the PreventKit desired state. It is never adopted or changed; an unmanaged block is reported as already enforced and an unmanaged allow is reported as a conflict.
_Avoid_: Duplicate, entry takeover

**Reconciliation**:
The update of managed entries to match trusted catalogue snapshots and exceptions, including removal of entries no longer desired. It never changes administrator-owned entries.
_Avoid_: Import, bulk update

**Exception**:
An explicit administrator-approved exemption from enforcement for an otherwise blockable service or address.
_Avoid_: Allow list, override

**Global exception**:
An exception that suppresses enforcement for its matching service or blockable address at every enforcement target.
_Avoid_: Target exception

**Permanent global exception**:
A global exception with no automatic expiry.
_Avoid_: Temporary exception

**Invocation exception**:
A managed-only exception supplied through the Run's parameters. It stays effective only when supplied to every Run.
_Avoid_: Stored exception, target allow rule

**Exception key**:
An exact namespaced identifier that an Invocation exception matches, such as `service:lolrmm/teamviewer` or `domain:teamviewer.com`.
_Avoid_: Display name, fuzzy exception

**Managed-only exception**:
An exception that removes or suppresses only PreventKit-managed entries; it never creates an allow rule or changes unrelated security controls.
_Avoid_: Allow rule

**Desired state**:
The union of all enabled catalogue entries after managed-only exceptions and compatible target mappings are applied.
_Avoid_: Per-source state, import result

**Run**:
One manual or scheduled invocation that retrieves catalogues, reconciles managed entries, and writes its outcome to the run log.
_Avoid_: Service execution, sync job

**Run log**:
The operational record of a Run, including the changes attempted and their outcomes.
_Avoid_: Audit trail, event store

**Source fingerprint**:
The source location, retrieval time, SHA-256 content hash, and parsed counts recorded for a catalogue during a Run.
_Avoid_: Stored snapshot, source version

**WhatIf run**:
A Run that retrieves, validates, maps, and reports planned reconciliation changes without modifying any enforcement target.
_Avoid_: Test run, partial dry run
