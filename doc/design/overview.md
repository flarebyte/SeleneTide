# SeleneTide Executive Overview

Start here for the design, its essential rules, and links to implementation detail.

## 01 Purpose and Scope

SeleneTide is a portable Rust library that brings IMAP message metadata into durable local storage. A frontend backend retains a stateful session through a C ABI; CLI features are deferred.

The design supports multiple accounts, local metadata analytics, and resumable processing. Normal synchronization fetches headers, flags, dates, sizes, and MIME structure. Message bodies and attachments require an explicit on-demand request and remain disposable content. Session handles, JSON requests, operation IDs, and event polling form the C ABI model; the code examples describe contracts for the future implementation.

[Requirements and use cases](selenetide-specs.md#02-product-requirements).

## 02 Architecture and Ownership

SQLite owns durable operational state, including plans, tasks, checkpoints, processing jobs, step results, and export claims. The caller supplies credentials, held only in session memory. Each account has its own analytical files and DuckDB database; DuckDB is a replayable projection of operational results, while Parquet holds verified historical datasets.

One application-local SQLite store isolates operational rows by account ID. Each account has separate analytical and artifact folders. An exclusive portable process writer lock coordinates backend processes; Rust workers coordinate concurrent work within the owning process. Temporary content has a separate lease-managed lifecycle.

[Datastores and authority](selenetide-specs.md#01-datastores-and-authority).

## 03 Main Workflow

**Plan → discover UIDs → fetch metadata → transform → project to DuckDB → verify → archive eligible months.**

Plans, tasks, page cursors, leases, attempts, and results are durable. Independent message work runs with bounded concurrency. Required processing failures block period export. Open months and partial or multi-month date ranges complete after DuckDB verification; only complete closed UTC months instantiate archive stages. Archival claims immutable, queryable snapshots, verifies Parquet files, then commits manifests and finalizes staging.

[Workflow stages](selenetide-specs.md#03-period-workflow-stages), [recovery rules](selenetide-specs.md#04-period-workflow-rules), and [archival](selenetide-specs.md#06-duckdb-projection-and-parquet-archival).

## 04 Critical Invariants

- Message identity is account + mailbox + UIDVALIDITY + UID. Provider IDs correlate locations; sequence numbers never identify durable work.
- Canonical UTC email dates and monthly partitions stay stable across refreshes, including fallback dates.
- Transformers have durable names and compatible versions. Reuse requires matching inputs and supported outputs; terminal jobs have no unfinished steps.
- Globally increasing source revisions prevent stale overwrites. Claims fence completion, and replay never loses newer work or double-counts progress.
- Queries combine live rows, exporting snapshots, archives, and corrections. Choose the newest revision before removing tombstones.
- Publish verified immutable file generations; retain the previous generation until replacement commits and readers release it. Secrets remain only in session memory.

[Metadata schema](selenetide-specs.md#04-imap-metadata-and-schema), [processing rules](selenetide-specs.md#01-email-processing-pipeline-rules), and [export rules](selenetide-specs.md#01-duckdb-exporter-rules).

## 05 Public API Boundaries

[Sync](selenetide-specs.md#06-sync-api-contract) separates planning, execution, resumption, cancellation, status, and events. [Processing](selenetide-specs.md#03-email-processing-api-contract) supplies immutable metadata to registered Rust transformers and persists their versioned outputs. [Queries](selenetide-specs.md#07-constrained-analytics-queries) accept fixed logical datasets and a constrained expression language, compiled to parameterized SQL. [Content fetching](selenetide-specs.md#01-on-demand-email-fetch-api) explicitly selects messages or MIME parts and owns their temporary leases.

The backend opens one session, supplies configuration and account authentication, then reuses its handle for JSON calls. The session owns runtime workers, database connections, and IMAP authentication state. Long operations return IDs for polling, paginated results, and cooperative cancellation. Close drains workers, releases connections, and clears secrets; reopening retains durable work but requires fresh authentication. Optional UniFFI bindings may provide typed host conveniences over the same Rust model.

## 06 Open Decisions and Next Reading

Implementation choices still include the minimum Rust version and target matrix, the embedded SQLite/DuckDB adapters and versions, optional UniFFI target bindings, resource ceilings, physical correction schemas, classification rules, retention, and migrations. Required-failure exclusions need a durable policy before being enabled.

Use the [full specification](selenetide-specs.md) for implementation details and the [consistency review](../design-meta/consistency-review.md#remaining-implementation-choices) for unresolved decisions. This overview guides navigation; detailed rules, tables, and examples define the contract. Both reports are generated from the same flyb configuration.

