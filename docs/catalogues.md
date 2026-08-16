# Catalogues

As stated in README.md:
> A **catalogue declaration** enables a block catalogue and sets its scope. Declarations live in `catalogues/`:
>
> - `lolrmm.catalog.psd1` — the lolrmm.io RMM domains CSV (`LolRmmCsv` adapter).
> A catalogue source that fails retrieval or validation is skipped in favour of its **last known good snapshot** when one exists; otherwise the Run still completes and records the failure.

## Catalogue requirements

- The source of the catalogue should present their list in a format that is natively ingestable by PowerShell (i.e. CSV, JSON).
- The catalogue should be accompanied by an transformation script and tests, to adapt the source format into the native format for PreventKit.
- The source of the catalogue is assumed to be moderated by the installer. No checks need to be done in PreventKit to mitigate risks.