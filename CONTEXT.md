# PreventKit

PreventKit manages blocking rules for frequently abused services in one Microsoft 365 tenant. It turns curated external catalogues into rules for Microsoft enforcement destinations while preserving administrator control.

## Language

**Block catalogue**:
A configured, opinionated external list of services or addresses that PreventKit uses as a blocking input.
_Avoid_: Threat feed, intelligence feed, block list

**Catalogue source**:
The URL or local file from which PreventKit reads a block catalogue. Approval of a source and the risk of tracking it directly are operator responsibilities.
_Avoid_: Feed endpoint, input file

**Source adapter**:
A parser that turns one catalogue source's native representation into PreventKit's canonical Service and Blockable Address model.
_Avoid_: Generic parser, CSV importer

**Catalogue declaration**:
A version-controlled definition that enables a block catalogue and sets its scope. It is approved outside PreventKit; valid entries from an enabled catalogue are enforced automatically.
_Avoid_: In-service approval, feed configuration

**Catalogue directory**:
The version-controlled directory of catalogue declarations that a Run processes together.
_Avoid_: Source folder, configuration directory

**Catalogue snapshot**:
A successfully retrieved and validated current representation of a block catalogue.
_Avoid_: Download, feed response

**Last known good snapshot**:
The most recent catalogue snapshot that passed validation and remains authoritative while a newer retrieval is failed or suspicious.
_Avoid_: Cache, stale data

**Service**:
A named, frequently abused capability that may be represented by one or more blockable addresses.
_Avoid_: Domain, indicator

**Blockable address**:
A URL, domain, or IP address that represents a Service or stands alone when no service identity is known.
_Avoid_: Indicator, IOC

**Enforcement destination**:
A Microsoft 365 control surface to which PreventKit can publish a blocking rule, such as the Tenant Allow/Block List, Custom Network Indicators, or Global Secure Access web controls.
_Avoid_: Output, sink, integration

**Destination projection**:
The compatible representation of a blockable address for one enforcement destination. A projection can be absent when that destination cannot safely express the address.
_Avoid_: Conversion, format hack

**Semantics-preserving projection**:
A destination projection that blocks neither more nor less than the source blockable address intends. An address with no such projection is skipped and logged.
_Avoid_: Best-effort conversion, broadened block

**Controlled destination expansion**:
An explicitly approved projection that blocks more than its source address because a destination cannot express the source semantics. For CNI, `*.example.com` becomes `example.com`, which blocks the root domain and all subdomains.
_Avoid_: Implicit broadening, semantics-preserving projection

**Capacity preflight**:
A check that the planned managed-entry count fits an enforcement destination before PreventKit writes to that destination.
_Avoid_: Partial import, capacity guess

**Managed entry**:
A rule at an enforcement destination that carries provenance identifying PreventKit as its owner.
_Avoid_: Existing entry, synced entry

**Permanent managed entry**:
A managed entry without expiry that remains in its destination until reconciliation removes it.
_Avoid_: Expiring entry

**Provenance namespace**:
The recognisable identifiers PreventKit reserves at enforcement destinations to find and reconcile managed entries without local persistent state.
_Avoid_: Comment convention, tag

**Unmanaged collision**:
An administrator-owned destination entry that matches a PreventKit desired address. It is never adopted or changed; an unmanaged block is reported as already enforced and an unmanaged allow is reported as a conflict.
_Avoid_: Duplicate, entry takeover

**Reconciliation**:
The update of managed entries to match trusted catalogue snapshots and exceptions, including removal of entries no longer desired. It never changes administrator-owned entries.
_Avoid_: Import, bulk update

**Exception**:
An explicit administrator-approved exemption from enforcement for an otherwise blockable service or address.
_Avoid_: Allow list, override

**Global exception**:
An exception that suppresses enforcement for its matching service or blockable address at every enforcement destination.
_Avoid_: Destination exception

**Permanent global exception**:
A global exception with no automatic expiry.
_Avoid_: Temporary exception

**Invocation exception**:
A non-overriding exception supplied through the Run's parameters. It remains effective only when supplied to every Run.
_Avoid_: Stored exception, destination allow rule

**Exception key**:
An exact namespaced identifier that an Invocation exception matches, such as `service:lolrmm/teamviewer` or `domain:teamviewer.com`.
_Avoid_: Display name, fuzzy exception

**Non-overriding exception**:
An exception that removes or suppresses only PreventKit-managed entries; it never creates an allow rule or changes unrelated security controls.
_Avoid_: Allow rule

**Desired state**:
The union of all enabled catalogue entries after non-overriding exceptions and compatible destination projections are applied.
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
A Run that retrieves, validates, projects, and reports planned reconciliation changes without modifying any enforcement destination.
_Avoid_: Test run, partial dry run
