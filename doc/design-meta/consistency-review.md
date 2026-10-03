# Design example consistency review

All 23 original artifacts were read and cross-checked. The examples now live in eight subsystem folders; source links, TypeScript imports, and flyb rendering symlinks follow their new locations. This review checks design contracts and executable sketches, not a production library implementation.

## Resolved cross-file conflicts

1. **Storage ownership.** Requirements placed workflow files beneath each account, while the datastore table and processing rules specified one application-local Core Data store. The selected design uses shared operational rows isolated by accountID and separate per-account analytical/artifact folders. An exclusive process writer lock is required because an actor only coordinates one process.
2. **Analytical revisions and keys.** A new processing step originally started at sourceVersion 1 even though its DuckDB key could match an older job. Inputs and corrections now reserve globally increasing Int64 revisions in Core Data. An older accepted job finishing later cannot overwrite a newer result. Each pipeline uses a transformer name at most once, and analytics retain the latest result per message/name/version rather than all execution history.
3. **Archive query visibility.** Claiming an archive moved live rows into exporting tables that queries did not include. Both logical datasets now include exporting snapshots and correction overlays, choose the newest revision, and only then remove tombstones. Processing deletions must be reconciled as well as metadata deletions.
4. **Archive publication and replacement.** Metadata and processing results had one manifest shape without a dataset key. Their manifests now have separate paths, versions, and counts. Published and committed are distinct states. Immutable batch-specific file generations preserve the prior committed partition until the new manifest becomes current; old files remain until readers release them. Partial batches cannot replace a complete monthly archive.
5. **Period completion.** Every run previously depended on archive finalization even though an open month could not be archived. Only complete closed-month plans instantiate archive stages. Open-month and arbitrary partial/multi-month ranges complete after DuckDB verification; a later complete-month plan can archive their rows.
6. **Discovery and range checkpoints.** Waiting for whole-mailbox discovery before consuming children could prevent the backpressure queue from draining. Children now depend on their committed producing page. Per-period coverage is stored separately from the mailbox UID hint so one range does not silently suppress another.
7. **Persisted operation inputs.** Generic tasks lacked claims and page cursors; fetch records lacked body preference, inline-resource/transform options, progress phase, and failure retryability. Those fields now exist. Metadata export has durable versioned claims and acknowledgements just like processing export.
8. **Transformer inputs and completion.** The first transformer had no metadata input, and a job could succeed with optional work still running. Both native and language-neutral contracts now supply a verified persisted metadata envelope. Every instantiated step is terminal before publishing a terminal job, and optional no-output dependencies are explicit.
9. **Transformer compatibility and reuse.** Name-only resolution could run a persisted old version with a new implementation. Registry resolution validates version and output schema before claiming an attempt. Reused output is copied into the new step so its analytical export does not depend solely on a historical pointer.
10. **Swift exporter behavior.** Actor suspension allowed overlapping batches. An explicit gate now spans all awaits, schema preparation precedes a Core Data claim, no-op replays are acknowledged, and a failure to save diagnostics does not mask the primary export error. Store protocol comments fence saves by batch and claimed revision.
11. **Canonical metadata.** Recomputing a fallback from the latest fetch time could move an unchanged message into another month. Canonical email_date and its provenance are chosen once and retained with firstSeenAt in the latest checkpoint. Sender domain, attachment count, thread depth, and delay derivations use matching rules.
12. **Query contracts.** Fixed the processing dataset spelling and physical field mappings. Defined typed UTC timestamp bindings for the existing date-range examples, safe default projections, grouped rows, local aggregate aliases, relationship namespaces, and malformed collection handling. Repeatable exports require explicit ordering and stable tie-breakers.
13. **Content lifetime.** Finite-lease prose contradicted while-in-use leases without expiresAt. TTL expiry and owner-session release are now separate. Transfer limits apply during streaming, and cancelling a completed fetch does not implicitly release its result.
14. **Priorities and terminology.** Kept existing feature priorities as the scope baseline and aligned the corresponding optional use cases. Removed mixed SwiftData/Core Data architecture wording and renamed the workflow field table to reflect the chosen persistence layer.

## File-by-file ledger

| Source | Outcome | Review and correction |
| --- | --- | --- |
| [features.csv](examples/requirements/features.csv) | Corrected | Storage scope now distinguishes shared Core Data rows from per-account files; archive staging, canonical dates, and query visibility agree with subsystem rules. |
| [practical_use_cases.csv](examples/requirements/practical_use_cases.csv) | Corrected | Aligned optional IMAP setup, headless automation, and selective-content scenarios with existing feature priorities; updated archive eligibility and live/history query wording. |
| [datastores.csv](examples/architecture/datastores.csv) | Corrected | Core Data owns a single shared operational store with exclusive process writer ownership; exporting snapshots are queryable and lease ownership is explicit. |
| [library-processing-flows.ts](examples/architecture/library-processing-flows.ts) | Corrected | Resolve compatible transformers before claiming; metadata is supplied to transformers; page children can drain; open periods complete without archives; projection and manifest commit gaps match their rules. |
| [sync-api.ts](examples/sync/sync-api.ts) | Corrected | Added period checkpoints, dataset-qualified publication events, missing blocking reasons, UUID/UID encoding, and explicit open-period completion semantics. |
| [period_workflow_stages.csv](examples/sync/period_workflow_stages.csv) | Corrected | Page-level completion enables child consumption; archive stages apply only to complete closed months; dataset-specific manifests distinguish published from committed state. |
| [period_workflow_rules.csv](examples/sync/period_workflow_rules.csv) | Corrected | Added range coverage, claim fencing, page backpressure semantics, metadata checkpoints, process ownership, cancellation/resume, and replay-safe progress. |
| [coredata_workflow_fields.csv](examples/sync/coredata_workflow_fields.csv) | Corrected; renamed | Formerly swiftdata_coredata_fields.csv. Selected Core Data architecture; added task keys/leases/cursors, period coverage, fetch request/progress/failure fields, session-owned leases, and MIME parameters. |
| [imap_email_metadata.csv](examples/metadata/imap_email_metadata.csv) | Corrected | Removed the UTF-8 BOM and normalized line endings; preserved Gmail IDs as decimal text and matched sender, attachment, thread-depth, and delay derivations to the storage schema. |
| [email_metadata_parquet_columns.csv](examples/metadata/email_metadata_parquet_columns.csv) | Corrected | Added source_version, fixed canonical email_date, and date provenance; defined stable derivation heuristics and preserved date/partition identity across refreshes. |
| [email-processing-pipeline-api.ts](examples/processing/email-processing-pipeline-api.ts) | Corrected | Persisted state spellings match rules; revisions use Int64 decimal strings; normalized metadata appears in both job requests and execution context. |
| [email-transformer.swift](examples/processing/email-transformer.swift) | Corrected | Added a metadata-only input envelope; registry checks positive Int32 versions and rejects incompatible persisted transformer/output-schema contracts. |
| [email_processing_pipeline_rules.csv](examples/processing/email_processing_pipeline_rules.csv) | Corrected | Jobs become exportable only after all steps are terminal; optional dependencies are explicit; reuse copies output; metadata snapshots and accepted-input revisions survive restart. |
| [coredata_email_pipeline_fields.csv](examples/processing/coredata_email_pipeline_fields.csv) | Corrected | Added indexed step identities, job metadata locators, job source revisions, a shared revision allocator, and complete metadata export checkpoints; grouped fields by entity. |
| [duckdb-exporter.swift](examples/storage/duckdb-exporter.swift) | Corrected | An in-flight gate survives actor reentrancy; schema preparation precedes claims; acknowledgements are revision-fenced and secondary diagnostic failures preserve the original error. Sample scope is processing-result export. |
| [duckdb_exporter_rules.csv](examples/storage/duckdb_exporter_rules.csv) | Corrected | Revisions never reset across jobs; equal versions are no-ops; queryable snapshots and dataset-specific immutable archive generations close commit gaps; metadata follows the same checkpoint semantics. |
| [duckdb_processing_export_tables.csv](examples/storage/duckdb_processing_export_tables.csv) | Corrected | Manifest dataset, expected batch count, verified file count, published state, current generation, and superseded batch are explicit; extension conversion and exporter timestamps match their actual meanings. |
| [query-api.ts](examples/query/query-api.ts) | Corrected | The bridge binding type represents validated UTC timestamps explicitly; JSON query values remain separate from internal typed parameters. |
| [query_api_rules.csv](examples/query/query_api_rules.csv) | Corrected | Logical relations include staging/corrections; choose winning versions before removing tombstones; documented defaults, grouped projections, aliases, timestamp bindings, malformed collections, and deterministic exports. |
| [query_catalog.csv](examples/query/query_catalog.csv) | Corrected | Fixed singular processing_result dataset name; email_date resolves to a persisted column; added processing UIDVALIDITY and matched physical catalogue columns to both schemas. |
| [email_query_examples.json](examples/query/email_query_examples.json) | Consistent; unchanged | All six requests use allowed fields/aggregates, output-local aliases, correctly referenced variables, and valid result modes. Their timestamp strings now have a defined typed-binding policy. |
| [fetch-email-api.ts](examples/content/fetch-email-api.ts) | Corrected | Updated the moved import; distinguished TTL from session-owned while-in-use leases; defined streaming transfer limits, expired/released results, and cancellation of active versus completed operations. |
| [simple_email_with_html.eml](examples/content/simple_email_with_html.eml) | Consistent; unchanged | Parsed successfully as multipart/alternative with plain-text and HTML parts, no MIME defects, and no attachments; metadata and on-demand APIs support this shape. |

## Remaining implementation choices

These are missing implementation decisions, rather than contradictory examples. They should be resolved before treating the design as an implementation-complete library contract.

- Minimum macOS/iOS and Swift versions, Swift Package layout, a pinned embedded DuckDB version, and the native bridge/build arrangement remain unspecified.
- Provider OAuth scopes, credential-item/access-group/accessibility settings, and the concrete exclusive process writer lock need implementation designs and platform verification.
- Concrete concurrency, retry, query token/depth, value-size, row-limit, and output-expansion ceilings are not all assigned defaults. Only the Swift processing-export sketch has batch/attempt/lease defaults.
- Physical correction/tombstone tables and the complete processing-result Parquet type table are not provided. Their logical keys, revision precedence, deletion semantics, and extension conversion are defined; migrations and physical mappings still need their own artifacts.
- Bulk-classification labels and heuristics are still deliberately versioned but unspecified. Address normalization, malformed MIME handling, and metadata decoding limits need concrete policies.
- Retention durations, account deletion cleanup, incompatible-store migrations, and support/migration of historical pipeline definitions require explicit policies. The latest metadata identity checkpoint and referenced inputs must survive any pruning policy.
- A required-processing-failure exclusion mechanism has no request or persistence artifact. Default behavior is to block period export; enable exclusions only after their policy and durable record format are designed.

## Validation evidence

- `flyb validate`, name lint, and example orphan lint pass with no diagnostics.
- `scripts/check-design-examples.py` checks all source registrations, generated source links/content, CSV IDs/widths, feature references, entity inverses, stage dependencies/applicability, physical query column mappings, all six supplied requests, and the MIME fixture. It is a structural consistency check, not a production query parser or executor.
- Both Swift sketches type-check together in Swift 6 mode. `scratch/design-review/SwiftContractProbe.swift` exercises registry version/schema rejection, duplicate registration, synchronous type erasure, reentrancy gating and gate release, schema preparation before claims, preservation of both upsert and acknowledgement errors, and no-op replay acknowledgement.
- All five TypeScript artifacts pass strict type checking with an ES2022 target, including the relocated cross-folder import.
- Repeated flyb Markdown generation produces identical bytes. The full specification includes all 23 examples; the executive overview links to detailed sections and these remaining implementation choices. The checker validates both reports, section anchors, and the overview's 500–700 word budget.

## Repeatable checks

```sh
flyb validate --config doc/design-meta
flyb lint names --config doc/design-meta
flyb lint orphans --config doc/design-meta --subject-label example
flyb generate markdown --config doc/design-meta
python3 scripts/check-design-examples.py
```

For Swift verification, keep the compiler cache and executable in the ignored scratch paths:

```sh
swiftc -swift-version 6 \
  -module-cache-path scratch/design-review/swift-module-cache \
  doc/design-meta/examples/processing/email-transformer.swift \
  doc/design-meta/examples/storage/duckdb-exporter.swift \
  scratch/design-review/SwiftContractProbe.swift \
  -o scratch/design-review/swift-contract-probe
scratch/design-review/swift-contract-probe
```

For TypeScript, run an installed compiler without fetching dependencies:

```sh
tsc --noEmit --strict --target es2022 --module commonjs \
  doc/design-meta/examples/sync/sync-api.ts \
  doc/design-meta/examples/content/fetch-email-api.ts \
  doc/design-meta/examples/processing/email-processing-pipeline-api.ts \
  doc/design-meta/examples/query/query-api.ts \
  doc/design-meta/examples/architecture/library-processing-flows.ts
```

This review used an existing locally installed TypeScript compiler and did not add dependencies to SeleneTide.
