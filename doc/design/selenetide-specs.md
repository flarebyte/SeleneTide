# SeleneTide Swift Library Specification

Requirements, architecture, persistence, and API contracts assembled from doc/design-meta/examples.

## 01 Overview

Purpose, Swift API conventions, and the relationship between the source artifacts.

### 01 Library Scope

#### Scope and Swift API Conventions

SeleneTide is a Swift library for macOS and iOS that brings IMAP message metadata into durable local storage. A macOS CLI exposes account, sync, fetch, and export operations for interactive and headless use.

The specification covers account isolation and Keychain credentials; metadata-only synchronization; resumable period workflows; versioned per-email transformers; Core Data to DuckDB projection; monthly Parquet archival; constrained analytics; and explicitly requested temporary content.

TypeScript files are language-neutral API sketches. The production Swift surface uses immutable Sendable values, async operations, AsyncSequence progress events, and cooperative cancellation. Swift examples define native transformer and exporter boundaries; they are design contracts rather than a complete library implementation.

This document is generated from `doc/design-meta/app.cue` and every source example. Edit those sources and regenerate with `flyb validate --config doc/design-meta` followed by `flyb generate markdown --config doc/design-meta`.

The [consistency review](../design-meta/consistency-review.md) records resolved contradictions and remaining implementation choices.

### 02 Architecture Summary

#### Storage and Workflow Boundaries

Core Data owns durable operational state, including plans, tasks, checkpoints, processing jobs, step results, and export claims. Keychain owns credentials. Each account has its own analytical files and DuckDB database; DuckDB is a replayable projection of operational results, while Parquet holds verified historical datasets.

A UTC period flows through planning, UID discovery, metadata fetch, per-email processing, DuckDB export and verification, then archive claim, write, publication, and finalization when eligible. Independent per-email work uses bounded concurrency. Archival normally applies to closed calendar months; open-period metadata remains queryable in DuckDB.

Message fetch identity is account plus mailbox plus UIDVALIDITY plus UID. Provider message identifiers correlate mailbox locations. Canonical UTC email dates, source versions, and schema versions connect the operational, live, and archived representations.

Queries resolve fixed logical datasets across live rows, queryable exporting snapshots, archives, and corrections. Select the newest source revision before removing tombstones. Downloaded message bodies and attachments belong to the separate on-demand content API and have explicit temporary retention.

The sections below preserve the detailed tables and API examples. Their rules and field definitions specify each subsystem's completion and recovery behavior.

## 02 Product Requirements

Library scope, platform requirements, and practical uses.

### 01 Feature Requirements

Required, recommended, and optional capabilities for the Swift library and macOS CLI. Source: [features.csv](../design-meta/examples/requirements/features.csv).

#### Feature Requirements

| area | capability | feature_id | platform | priority | requirement |
| --- | --- | --- | --- | --- | --- |
| Accounts | Multiple accounts | account.multiple | macOS+iOS | must | Keep each account's analytical files and temporary artifacts in its own stable subfolder, such as account1 or account3; isolate shared Core Data rows by accountID. |
| Accounts | Account settings | account.settings | macOS+iOS | must | Persist non-secret per-account configuration in the application-local Core Data store; UserDefaults is not an account data store. |
| Accounts | Credential storage | account.secrets | macOS+iOS | must | Store passwords, OAuth tokens, and other account secrets in Keychain; never write secrets to account files, logs, or exports. |
| Accounts | Global preferences | settings.global | macOS+iOS | should | Do not introduce UserDefaults until a truly global, non-sensitive, device-local preference is identified; if needed, keep it outside account and workflow state. |
| Authentication | Headless Keychain access | auth.keychain-headless | macOS | must | Configure Keychain access groups and item accessibility so an authorized signed macOS CLI, launchd service, or non-interactive SSH session can read credentials without an unexpected GUI prompt; fail deterministically when the Keychain is unavailable or locked. |
| Authentication | IMAP credentials | auth.imap-password | macOS+iOS | should | Support standards-based IMAP authentication for servers that permit username and password credentials. |
| Authentication | OAuth 2.0 | auth.oauth2 | macOS+iOS | must | Support OAuth 2.0 authorization and token refresh for IMAP providers that require it. |
| Authentication | Gmail | auth.gmail | macOS+iOS | must | Provide a Gmail account setup flow using Google's supported OAuth scopes and IMAP authentication mechanism. |
| Authentication | Provider extensibility | auth.provider-extensibility | macOS+iOS | should | Keep provider-specific authorization separate from the generic IMAP client so additional major providers can be added. |
| IMAP | Mailbox status | imap.status | macOS+iOS | should | Read mailbox message count and aggregate size information when exposed by the server. |
| IMAP | Message discovery | imap.search | macOS+iOS | must | Search a mailbox by date range and return stable message UIDs, not sequence numbers, for sync planning. |
| IMAP | Header fetch | imap.headers | macOS+iOS | must | Fetch selected RFC message headers, flags, internal date, size, UID, and provider metadata without downloading message bodies. |
| IMAP | MIME structure | imap.bodystructure | macOS+iOS | must | Fetch BODYSTRUCTURE independently of message content so callers can inspect available body parts and attachments. |
| IMAP | UID fetch | imap.fetch-uid | macOS+iOS | must | Fetch an individual message or MIME part by mailbox and UID. |
| IMAP | Sequence-number fetch | imap.fetch-sequence | macOS+iOS | could | Allow sequence-number fetches for immediate low-level operations but do not use sequence numbers as durable identifiers. |
| IMAP | Gmail cross-label identity | imap.gmail-identity | macOS+iOS | must | Keep account mailbox UIDVALIDITY and UID as the fetch identity, and use account plus X-GM-MSGID as a separate correlation key for the same Gmail message exposed under multiple labels. |
| Sync | Initial metadata sync | sync.initial | macOS+iOS | must | Discover and download headers and metadata without downloading full message bodies. |
| Sync | Incremental refresh | sync.refresh | macOS+iOS | must | Refresh local metadata for new, changed, moved, and expunged messages while minimizing network traffic. |
| Sync | Durable sync cursor | sync.cursor | macOS+iOS | must | Record per-account and per-mailbox checkpoints, including UIDVALIDITY and the highest observed UID or equivalent capability-specific state. |
| Sync | Mailbox reconciliation | sync.reconcile | macOS+iOS | must | Invalidate or reconcile local state safely when server identity or UIDVALIDITY changes. |
| Sync | Interruption recovery | sync.interruption | macOS+iOS | must | Resume an interrupted sync without silently skipping work or unnecessarily repeating completed downloads. |
| Workflow | Offline workflow store | workflow.database | macOS+iOS | must | Use one offline Core Data SQLite persistent store for accounts sync plans tasks attempts dependencies checkpoints and progress. |
| Workflow | Task lifecycle | workflow.lifecycle | macOS+iOS | must | Track pending, running, blocked, completed, failed, and cancelled task states. |
| Workflow | Retry policy | workflow.retry | macOS+iOS | must | Record retryable failures and schedule bounded retries with backoff while preserving the underlying error. |
| Workflow | Task audit trail | workflow.audit | macOS+iOS | should | Retain task attempts status transitions timestamps and diagnostic summaries for troubleshooting. |
| Workflow | Progress reporting | workflow.progress | macOS+iOS | should | Expose account mailbox and overall sync progress to library clients and the CLI. |
| Workflow | Period orchestration | workflow.period | macOS+iOS | must | Coordinate UID discovery metadata fetch per-email transformation DuckDB projection and Parquet archival for a UTC period, normally one calendar month. |
| Workflow | Durable per-email fan-out | workflow.fanout | macOS+iOS | must | Create idempotent persisted fetch and processing tasks for every discovered mailbox UID and run independent email work with bounded parallelism. |
| Workflow | Stage completion gates | workflow.stage-gates | macOS+iOS | must | Start period export only after all required per-email processing is terminal and start Parquet archival only after DuckDB projection is complete and verified. |
| Storage | Account layout | storage.account-layout | macOS+iOS | must | Place DuckDB Parquet exports intermediate files and temporary content beneath the owning account subfolder; account and workflow rows live in one shared application-local Core Data store with logical account isolation. |
| Storage | Parquet metadata | storage.parquet | macOS+iOS | must | Store normalized message headers and metadata in Parquet with one logical file per account, mailbox, and calendar month. |
| Storage | DuckDB hot store | storage.duckdb-hot | macOS+iOS | must | Keep recent unarchived headers and metadata in a mutable DuckDB database beneath each account folder, normally covering the open UTC calendar month, so frequent refreshes and queries do not rewrite Parquet. |
| Storage | Monthly archive | storage.monthly-archive | macOS+iOS | must | After a full UTC calendar month closes, transactionally move its live rows into durable queryable exporting snapshots; delete exporting rows only after verified atomic Parquet publication and manifest commit. |
| Storage | Archived-month corrections | storage.archive-overlay | macOS+iOS | must | Record changes and tombstones for already archived messages in a DuckDB overlay, merge that overlay when querying, and compact affected Parquet partitions atomically according to policy. |
| Storage | Monthly partitioning | storage.partition-key | macOS+iOS | must | Choose canonical email_date once per mailbox message identity from UTC INTERNALDATE, then an unambiguous Date header, then the first metadata_fetched_at; retain that timestamp and its YYYY-MM partition across refreshes. |
| Storage | Atomic publication | storage.atomicity | macOS+iOS | must | Write or replace Parquet partitions atomically so interruption cannot expose a partially written file. |
| Storage | Schema evolution | storage.schema | macOS+iOS | must | Version the metadata schema, preserve compatibility or provide an explicit migration path, and keep core columns identical between DuckDB and Parquet. |
| Storage | Core and extension fields | storage.schema-placement | macOS+iOS | must | Represent stable shared and frequently queried fields as core columns that always exist, while provider-specific customer-specific and evolving values use a stable extensions envelope: JSON in DuckDB and MAP<STRING, STRING> with canonical JSON values in Parquet. |
| Storage | Embedded Parquet engine | storage.parquet-engine | macOS+iOS | must | Embed a Parquet-capable native engine, expected to be DuckDB, and keep its C++ bridge or other FFI free of unsupported dynamic dependencies; compile and link it in CI for macOS and iOS arm64 device and simulator targets. |
| On-demand content | Message fetch | content.fetch | macOS+iOS | must | Download a complete message by account mailbox and UID only when explicitly requested. |
| On-demand content | Selective MIME fetch | content.parts | macOS+iOS | should | Download selected text HTML or attachment MIME parts without requiring the complete message when the server supports it. |
| On-demand content | Content extraction | content.transform | macOS+iOS | should | Extract text HTML and attachment metadata from downloaded MIME content. |
| On-demand content | HTML to Markdown | content.markdown | macOS+iOS | could | Optionally convert an HTML body to Markdown for downstream processing. |
| On-demand content | Temporary retention | content.temporary | macOS+iOS | must | Treat downloaded bodies and attachments as disposable cached artifacts that can be removed after use or by a cleanup policy. |
| Processing | Durable transformation pipeline | processing.pipeline | macOS+iOS | must | Process each email through a versioned code-defined dependency graph and persist every instantiated step state and output in Core Data. |
| Processing | Crash recovery | processing.resume | macOS+iOS | must | Resume incomplete email processing after termination without rerunning still-valid completed steps. |
| Processing | Bounded parallelism | processing.parallel | macOS+iOS | must | Run independent ready transformations concurrently with bounded limits for local CPU I/O and network work. |
| Processing | Result reuse | processing.reuse | macOS+iOS | must | Reuse successful persisted results only when email identity step version input fingerprint and output schema remain compatible. |
| Processing | Transformer registry | processing.transformers | macOS+iOS | must | Require uniquely named strongly typed Swift transformers, inject the complete registry at library initialization, and persist each exact transformer name for crash recovery. |
| Processing | DuckDB analytical projection | processing.duckdb-export | macOS+iOS | must | Export stable terminal processing results from authoritative Core Data into DuckDB using versioned idempotent transactional upserts. |
| Processing | Durable export checkpoint | processing.export-checkpoint | macOS+iOS | must | Track each result source version export state attempts lease exported version and exported timestamp in Core Data. |
| Processing | Dual-store recovery | processing.export-recovery | macOS+iOS | must | Replay an expired Core Data export claim safely when DuckDB may have committed before Core Data acknowledged it. |
| Export | CSV export | export.csv | macOS+iOS | must | Export a selected metadata scope or date range to CSV without requiring full message downloads. |
| Export | JSON export | export.json | macOS+iOS | must | Export a selected metadata scope or date range to JSON without requiring full message downloads. |
| Library API | Swift concurrency | library.async | macOS+iOS | must | Expose cancellable asynchronous operations compatible with Swift concurrency. |
| Library API | Structured events | library.observability | macOS+iOS | should | Expose structured progress warnings and errors without leaking message content or credentials. |
| CLI | Account commands | cli.accounts | macOS | must | Provide commands to configure list inspect and remove account configurations. |
| CLI | Sync commands | cli.sync | macOS | must | Provide commands to plan start resume inspect and refresh metadata synchronization. |
| CLI | Fetch commands | cli.fetch | macOS | must | Provide commands to fetch selected messages or MIME parts on demand and clean up temporary content. |
| CLI | Export commands | cli.export | macOS | must | Provide commands to export metadata to CSV or JSON. |
| CLI | Automation contract | cli.automation | macOS | should | Support deterministic machine-readable output, meaningful exit statuses, and non-interactive operation. |
| Query API | Constrained analytics DSL | query.constrained | macOS+iOS | must | Accept JSON query structure and a small literal-free expression language, validate against an allow-list, and compile only parameterized DuckDB SQL. |
| Query API | Logical analytical datasets | query.logical-datasets | macOS+iOS | must | Query fixed logical email and processing-result datasets combining DuckDB live rows queryable exporting snapshots Parquet archives and correction overlays with version deduplication and tombstones. |
| Query API | Counts and statistics | query.aggregates | macOS+iOS | must | Support first-class count and allow-listed statistics including min max avg stddev median quantile and approximate distinct. |

### 02 Practical Use Cases

User goals, inputs, outputs, and acceptance criteria. Source: [practical_use_cases.csv](../design-meta/examples/requirements/practical_use_cases.csv).

#### Practical Use Cases

| actor | expected_result | input | library_capabilities | platform | priority | related_feature_ids | scenario | trigger | use_case_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| App user | The account is securely configured and ready to sync | Email address, OAuth consent | Gmail OAuth setup and Keychain token storage | macOS+iOS | must | auth.gmail;auth.oauth2;account.secrets | Connect a Gmail mailbox for metadata analysis | The user adds a Gmail account | account.add-gmail |
| App user | The account is validated and ready to sync | Host, port, transport security, username, credentials | Generic IMAP configuration and secure credential storage | macOS+iOS | should | auth.imap-password;auth.provider-extensibility;account.settings | Connect a standards-based IMAP account | The user adds a non-Gmail provider | account.add-imap |
| App user | Operations and queries remain scoped to the selected accounts | Account identifiers and settings | Per-account configuration folders and isolated analytical stores | macOS+iOS | must | account.multiple;storage.account-layout | Work with several independent mail accounts | The user switches or compares accounts | account.manage-many |
| Operator | The job authenticates without unexpected GUI prompts or fails clearly | Configured account and unlocked authorized Keychain | Headless Keychain access and non-interactive CLI behavior | macOS | should | auth.keychain-headless;cli.automation | Run scheduled mailbox processing without an interactive session | launchd or SSH starts the CLI | account.headless |
| App user | The month becomes queryable in DuckDB and later archived to Parquet | Account, mailbox, YYYY-MM | Period planning UID discovery metadata fetch transformation and export | macOS+iOS | must | workflow.period;workflow.fanout;sync.initial | Ingest one calendar month of mailbox metadata | A month is selected | sync.month |
| Researcher | All matching metadata is processed without downloading bodies | Account, mailboxes, UTC start and end | Paged UID discovery and bounded per-email fan-out | macOS+iOS | must | imap.search;imap.headers;workflow.fanout | Backfill a historical date range | The user requests older mail | sync.historical-range |
| App user | New changed moved and expunged messages are reflected locally | Existing mailbox checkpoint | Incremental discovery reconciliation and idempotent upserts | macOS+iOS | must | sync.refresh;sync.cursor;sync.reconcile | Refresh recent metadata after new mail or flag changes | The app or scheduler starts an incremental refresh | sync.refresh |
| App user | Processing resumes without repeating valid completed work | Persisted workflow and processing state | Expired-lease recovery dependency scheduling and result reuse | macOS+iOS | must | sync.interruption;processing.resume;processing.reuse | Continue work after force-quit crash or device restart | The library initializes with unfinished tasks | sync.resume |
| App or CLI user | The caller can display progress and diagnose blocked work | Run identifier | Structured events counters stages warnings and failures | macOS+iOS | should | workflow.progress;library.observability | Observe a long-running sync and processing run | A period workflow is active | sync.monitor |
| App user | The workflow pauses and resumes without losing its checkpoint | Failure classification and retry-after data | Persisted bounded backoff and retry scheduling | macOS+iOS | must | workflow.retry;workflow.lifecycle | Recover from provider rate limiting or temporary network loss | IMAP returns a transient failure | sync.rate-limit |
| Analyst | Label copies can be joined without corrupting fetch identity | Account, mailbox identities, X-GM-MSGID | Mailbox-location keys plus account-wide Gmail correlation | macOS+iOS | must | imap.gmail-identity | Correlate one Gmail message exposed through several labels | Gmail returns the same X-GM-MSGID with different UIDs | gmail.labels |
| Library integrator | The transformer participates in durable per-email processing | A uniquely named Swift transformer | Typed transformer registration versioning retries and persisted output | macOS+iOS | must | processing.transformers;processing.pipeline | Add a domain-specific email transformation | The application initializes the library | processing.custom-transformer |
| Library integrator | Independent results complete faster while dependencies remain correct | Pipeline dependency graph and execution limits | Bounded local CPU I/O and network parallelism | macOS+iOS | must | processing.parallel | Run independent extraction and classification steps concurrently | A fetched message has several ready transformations | processing.parallel |
| Library integrator | The step eventually succeeds or reaches a stable failed state | Persisted attempts and idempotency key | Bounded backoff with crash-safe replay | macOS+iOS | must | processing.pipeline;workflow.retry | Retry a transient transformer failure | A transformer returns retry or throws a classified transient error | processing.retry |
| Library integrator | Required analytics remain available without hiding the optional failure | Requiredness and persisted failure result | Job completion with warnings and exportable failure metadata | macOS+iOS | should | processing.pipeline;processing.duckdb-export | Allow useful results when a nonessential transformer fails | An optional step exhausts retries | processing.optional |
| Library integrator | The step is marked reused without repeating computation or network calls | Transformer name, version, input fingerprint, output schema | Persisted result compatibility checks and reuse link | macOS+iOS | must | processing.reuse | Reuse an expensive valid transformation in a later run | A matching message is processed again | processing.reuse |
| Analyst | Titles, dates, domains, and mailboxes are returned | Domain, UTC start, UTC end | Constrained email_metadata query with bound variables | macOS+iOS | must | query.constrained;query.logical-datasets | List messages from a company during a date range | A user searches for correspondence | query.domain-period |
| Analyst | A chronological monthly count is returned | Domain, year | Virtual year and month dimensions with grouped count | macOS+iOS | must | query.aggregates | Count messages from one company per month | A user requests a yearly trend | query.domain-monthly |
| Analyst | Each year and sender domain has a message count | Optional account or period filters | Grouped counts over logical live and archived data | macOS+iOS | must | query.aggregates;query.logical-datasets | Compare sender-domain volumes by year | A user requests domain trends | query.domain-yearly |
| Analyst | A ranked domain list is returned | Optional period and account filters | Grouped count ordered by generated count alias | macOS+iOS | must | query.constrained;query.aggregates | Find the most frequent sender domains | A user requests a sender overview | query.all-domains |
| Analyst | Attachment frequency and size distributions can be reported | Optional domain mailbox or period filters | Count average median and quantile over attachment count and size columns | macOS+iOS | should | query.aggregates;imap.bodystructure | Measure attachment prevalence and storage impact | A user requests attachment statistics | query.attachment-stats |
| Analyst | Large-message patterns can be compared safely | Domain, percentile | Bound parameterized quantile and grouped statistics | macOS+iOS | should | query.aggregates | Identify unusually large email sources | A user requests message-size statistics | query.message-size |
| Analyst | The caller receives one current deduplicated result set | Constrained query request | Logical dataset merges DuckDB live and exporting snapshots Parquet archives and corrections | macOS+iOS | must | query.logical-datasets;storage.archive-overlay | Query recent and archived mail through one API | A query spans the current and earlier months | query.live-and-history |
| App user | The body is available temporarily without entering the metadata archive | Account, mailbox, UIDVALIDITY, UID | On-demand raw message fetch and temporary lease | macOS+iOS | must | content.fetch;content.temporary | Temporarily inspect a complete email body | A user explicitly opens a message | content.read-message |
| App user | Only requested attachments are atomically published for temporary use | Message identity and MIME part identifiers | Selective MIME fetch size limit progress and content lease | macOS+iOS | should | content.parts;content.temporary | Download selected attachments only | A user selects one or more attachments | content.fetch-attachment |
| App or automation | A temporary Markdown artifact is returned | Message identity and body selection | On-demand HTML fetch extraction and Markdown conversion | macOS+iOS | could | content.transform;content.markdown | Convert an HTML email into Markdown | A caller requests a Markdown representation | content.to-markdown |
| App or operator | Disposable content is removed without affecting metadata | Lease identifiers and cleanup policy | Explicit release expiry cleanup and abandoned-partial removal | macOS+iOS | must | content.temporary | Reclaim space used by downloaded bodies and attachments | A lease expires or cleanup is requested | content.cleanup |
| CLI user | A deterministic CSV file is produced without downloading bodies | Query request and destination | Safe analytical query and CSV serializer | macOS | must | export.csv;cli.export;query.constrained | Export filtered metadata for spreadsheet analysis | A constrained query has been defined | export.csv |
| Developer | A deterministic machine-readable JSON document is produced | Query request and destination | Safe analytical query and JSON serializer | macOS+iOS | must | export.json;query.constrained | Export filtered metadata for another local tool | A constrained query has been defined | export.json |
| Operator | Monthly email and processing datasets are durably archived | Verified DuckDB period and schema versions | Immutable staging write verification atomic publish and manifest commit | macOS+iOS | must | storage.monthly-archive;storage.atomicity | Archive a closed month to Parquet | A full UTC calendar month closes or a complete historical month is selected | archive.month |
| Operator | The archive completes without losing or duplicating rows | Persisted archive batch and manifest | DuckDB exporting snapshot retry and atomic publication | macOS+iOS | must | storage.atomicity;workflow.retry | Resume a failed Parquet publication | A write verification or process interruption occurs | archive.retry |
| App user | Queries immediately show current state and Parquet is eventually corrected | Logical key source version and change or tombstone | DuckDB correction overlay merged queries and later compaction | macOS+iOS | must | storage.archive-overlay;sync.reconcile | Reflect a late flag label move or expunge in an old month | Incremental sync detects a change to archived metadata | archive.correct |
| Operator | The month is synchronized processed projected verified and archived | Account, mailbox, month | Non-interactive CLI deterministic output exit status and resumable workflow | macOS | should | cli.sync;cli.automation;workflow.period | Run the complete monthly workflow from scripts or launchd | A scheduled command starts after month close | automation.monthly |
| Operator | The responsible stage and actionable failure are visible | Run, task, job, or message identity | Queryable attempts state transitions errors timestamps and progress | macOS+iOS | should | workflow.audit;library.observability | Investigate why an email or period did not complete | A workflow is failed blocked or unexpectedly slow | diagnostics.audit |

## 03 Architecture and Period Workflow

Storage authority and durable orchestration across subsystem boundaries.

### 01 Datastores and Authority

Physical layout, ownership, lifecycle, and recovery responsibilities. Source: [datastores.csv](../design-meta/examples/architecture/datastores.csv).

#### Datastores and Authority

| authority | datastore_id | layer | logical_contents | mutability | physical_scope | primary_input | primary_output | readers | retention_and_lifecycle | security_and_recovery_notes | technology | writers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Authoritative for secrets | secrets.keychain | Secrets | Passwords, OAuth tokens, refresh tokens, and credential material | Mutable | OS-managed keychain and configured access group | Provider authorization | Authenticated IMAP sessions | Authentication services and authorized headless CLI or daemon | Retain while the account exists and delete explicitly with account removal | Never copy secrets into Core Data, DuckDB, Parquet, logs, or exports; locked or unavailable access fails deterministically | Apple Keychain | Account and authentication services |
| Operational source of truth | operational.coredata | Operational | Account configuration, mailboxes, workflow plans/runs/tasks/attempts/dependencies, checkpoints, fetch operations, processing jobs/steps/results, leases, and DuckDB export checkpoints | Mutable transactional | One application-local persistent store with logical isolation by accountID | User configuration and workflow subsystem state | DuckDB projections and resumable work | App CLI scheduler and diagnostic views | Retain active state and reusable results; prune only through explicit versioned retention policies and Core Data migrations | Use one NSPersistentContainer with private-queue writer contexts indexed identities and an exclusive process writer lock; account rows are logically isolated and there is no direct SQLite access. | Apple Core Data SQLite store | Core Data contexts owned by account workflow processing fetch and exporter services |
| Replayable downstream projection | analytics.duckdb.email_live | Hot analytics | Recent normalized email headers metadata and promoted analytical fields following email_metadata_parquet_columns.csv | Mutable transactional upsert | One DuckDB database beneath each account folder | Durable metadata-fetch results | Email metadata Parquet archive and analytical queries | Library queries CLI exports and Parquet archiver | Keep open-period rows queryable until claimed for verified monthly archival | Upsert by the durable mailbox message key using persisted globally allocated source revisions; Core Data and IMAP remain authoritative. | DuckDB table group email_metadata_live | DuckDBExporter and metadata projector |
| Replayable downstream projection | analytics.duckdb.processing_live | Hot analytics | Stable terminal transformer results and typed analytical columns with transformer-specific JSON | Mutable transactional upsert | Same per-account DuckDB database | Core Data EmailProcessingStep plus ProcessingResultExportState | Processing-result Parquet archive and analytical queries | Library queries CLI exports and Parquet archiver | Keep recent rows until claimed for verified monthly archival | Conflict key includes durable message identity, transformerName, and transformerVersion; replay after dual-store commit gaps is safe | DuckDB table email_processing_results_live | DuckDBExporter |
| Durable staging copy but not operational authority | analytics.duckdb.exporting | Archive staging | Immutable email metadata and processing-result snapshots claimed for a specific archive batch | Append and delete by transaction | Same per-account DuckDB database | DuckDB live tables | Parquet writer | Parquet writer verifier diagnostics and logical analytical queries | Retain through failures and restarts; delete only after verified Parquet publication and archive-manifest commit | Archive batch IDs and source versions prevent live updates from mutating an in-flight snapshot | DuckDB exporting table groups | DuckDB archive coordinator |
| Authoritative local record of downstream archive publication | analytics.duckdb.archive_manifest | Archive control | Dataset name archive batch state partition identity schema version expected batch count verified file row count Parquet path digest and commit timestamp | Transactional state transitions | Same per-account DuckDB database | DuckDB archive coordinator | Archive verification and repair | Workflow coordinator diagnostics and repair tools | Retain committed manifests for audit and reconciliation | Commit manifest and delete exporting rows in one DuckDB transaction | DuckDB archive_manifest table | DuckDB archive coordinator |
| Replayable mutable overlay | analytics.duckdb.corrections | Archive overlay | Changes to metadata or processing results discovered after their monthly Parquet partition was sealed | Mutable transactional upsert | Same per-account DuckDB database | Incremental sync reconciliation and processing-result corrections | Queries merged with Parquet and later partition compaction | Analytical queries and Parquet compactor | Retain until atomically compacted into the affected Parquet partition; preserve newer changes arriving during compaction | Use source versions and tombstones so stale archive data is never returned as current | DuckDB correction and tombstone table groups | DuckDBExporter sync reconciler and correction projector |
| Durable historical analytical archive | archive.parquet.email_metadata | Historical analytics | Normalized email headers metadata MIME structure provider fields and derived statistics | Immutable between atomic compactions | One dataset partition per account mailbox and UTC calendar month | DuckDB immutable exporting batches | Long-term queries CSV or JSON exports and backup | DuckDB query layer CLI and external analytical tools | Retain according to user archive policy; replace only through verified atomic publication or correction compaction | Use schema_version, stable core columns, extensions MAP, verified row count, digest, and atomic rename | Parquet files on local filesystem | Parquet archiver and compactor |
| Durable historical analytical archive | archive.parquet.processing_results | Historical analytics | Stable per-transformer processing results keyed separately from one-row-per-message metadata | Immutable between atomic compactions | One processing-result dataset partition per account mailbox and UTC calendar month | DuckDB processing-result exporting batches | Long-term transformer analytics joined to email metadata | DuckDB query layer CLI and external analytical tools | Retain with the corresponding email-metadata period; replace only through verified correction compaction | Preserve message join keys transformerName transformerVersion globally allocated sourceVersion and output schema version; use typed core columns and a Parquet MAP of canonical JSON extension values. | Parquet files on local filesystem | Parquet archiver and compactor |
| Recoverable intermediate checkpoint | filesystem.intermediate | Workflow artifacts | Normalized metadata-fetch results and large transformation outputs referenced by Core Data | Write then publish atomically | Per-account versioned work directory | IMAP fetches and transformers | Email processing and DuckDB projection | Workflow coordinator transformers and DuckDBExporter | Retain while referenced by incomplete or reusable Core Data work; remove only after downstream acknowledgement and retention checks | Store only relative locators and integrity fingerprints in Core Data; never place credentials here | Managed local files beneath each account folder | IMAP metadata fetcher and processing pipeline |
| Disposable cache | filesystem.temporary_content | Disposable content | On-demand raw messages bodies MIME parts inline resources and attachments | Mutable lease-managed | Per-account leased temporary directory | On-demand IMAP content fetch | Caller-controlled short-lived processing | Authorized caller during an active content lease | Delete on explicit release TTL expiry or active-fetch cancellation; while-in-use leases survive only their owning process session; clean up abandoned partial files after restart. | Never treat as archive or processing source of truth; publish complete artifacts atomically and sanitize filenames | Managed local files beneath each account temporary-content folder | FetchEmailClient |

### 02 Library Processing Flows

Initialization, recovery, and subsystem interaction sequences. Source: [library-processing-flows.ts](../design-meta/examples/architecture/library-processing-flows.ts).

#### Library Processing Flows

```ts
/** Sequence-diagram inputs for the principal SeleneTide workflows. */
export type FlowStep = {
  from: string;
  to: string;
  action: string;
  data?: string[];
  when?: string;
  notes?: string;
};

/** Library initialization and durable-work recovery. */
export const initializationFlow: FlowStep[] = [
  {
    from: "AppOrCLI",
    to: "SeleneTideLibrary",
    action: "initialize",
    data: ["configuration", "transformers"],
    notes: "Acquire exclusive process writer ownership for the shared Core Data store before starting recovery.",
  },
  {
    from: "SeleneTideLibrary",
    to: "TransformerRegistry",
    action: "registerAll",
    data: ["transformerName", "transformerVersion", "outputSchemaVersion"],
    notes: "Names must be non-empty and globally unique within the library instance.",
  },
  {
    from: "TransformerRegistry",
    to: "SeleneTideLibrary",
    action: "rejectInitialization",
    data: ["duplicateName", "invalidVersion", "pipelineMismatch"],
    when: "a transformer registration or current pipeline definition is invalid",
  },
  {
    from: "SeleneTideLibrary",
    to: "CoreDataStore",
    action: "loadPersistentStoresAndMigrate",
    data: ["coreDataModelVersion"],
  },
  {
    from: "SeleneTideLibrary",
    to: "DuckDBStore",
    action: "openAndMigrate",
    data: ["duckDBSchemaVersion"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "findRecoverableWork",
    data: ["expiredLeases", "pendingTasks", "retryDueTasks", "blockedTasks"],
  },
  {
    from: "WorkflowCoordinator",
    to: "TransformerRegistry",
    action: "resolvePersistedTransformerNames",
    data: ["transformerName"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "markBlocked",
    data: ["failureCode=transformer.missing"],
    when: "a historical persisted transformer name is not registered",
    notes: "The missing transformer does not consume an execution attempt.",
  },
  {
    from: "WorkflowCoordinator",
    to: "WorkflowCoordinator",
    action: "resumeEligibleWork",
    when: "stores and current pipeline definitions are valid",
  },
];

/** Complete account/mailbox/period workflow, normally for one UTC month. */
export const periodProcessingFlow: FlowStep[] = [
  {
    from: "AppOrCLI",
    to: "SyncClient",
    action: "plan",
    data: ["accountID", "mailboxes", "period", "mode"],
  },
  {
    from: "SyncClient",
    to: "CoreDataStore",
    action: "persistPeriodPlan",
    data: ["periodStart", "periodEndExclusive", "partitionMonth"],
  },
  {
    from: "AppOrCLI",
    to: "WorkflowCoordinator",
    action: "startPlan",
    data: ["planID"],
  },
  {
    from: "WorkflowCoordinator",
    to: "IMAPClient",
    action: "discoverUIDPage",
    data: ["accountID", "mailboxID", "period", "pageCursor"],
    notes: "These are IMAP UIDs, not UUIDs.",
  },
  {
    from: "IMAPClient",
    to: "WorkflowCoordinator",
    action: "returnUIDPage",
    data: ["uidValidity", "uids", "nextPageCursor"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "persistDiscoveryPageAndFanOut",
    data: ["discoveryCursor", "metadataFetchTasks"],
    notes: "Cursor and idempotent child tasks commit atomically; child tasks run immediately so bounded discovery can drain.",
  },
  {
    from: "WorkflowCoordinator",
    to: "IMAPClient",
    action: "fetchMessageMetadata",
    data: ["mailboxID", "uidValidity", "uid", "selectedHeaders", "bodyStructure"],
    when: "a metadata fetch task is ready",
  },
  {
    from: "IMAPClient",
    to: "IntermediateStore",
    action: "publishNormalizedMetadata",
    data: ["resultSchemaVersion", "resultFingerprint", "relativePath", "sourceVersion", "canonicalEmailDate"],
    notes: "No message body or attachment bytes are included.",
  },
  {
    from: "WorkflowCoordinator",
    to: "EmailProcessingPipeline",
    action: "startOrReuseJob",
    data: ["messageIdentity", "emailDate", "inputFingerprint", "pipelineVersion", "sourceRevision", "normalizedMetadata"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "persistTerminalJob",
    data: ["processingJobID", "jobState", "stepResults"],
    notes: "Per-email jobs may execute concurrently under configured limits.",
  },
  {
    from: "WorkflowCoordinator",
    to: "DuckDBExporter",
    action: "exportPeriod",
    data: ["accountID", "mailboxID", "period", "batchSize"],
    when: "discovery is complete and every included processing job succeeded or succeededWithWarnings",
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "upsertMetadataAndProcessingResults",
    data: ["messageKeys", "transformerKeys", "sourceVersions"],
    notes: "Each configurable batch is one DuckDB transaction.",
  },
  {
    from: "DuckDBExporter",
    to: "WorkflowCoordinator",
    action: "confirmPeriodProjection",
    data: ["expectedCounts", "acknowledgedSourceVersions"],
  },
  {
    from: "WorkflowCoordinator",
    to: "ParquetArchiver",
    action: "archivePeriod",
    data: ["accountID", "mailboxID", "partitionMonth"],
    when: "the plan covers exactly one complete closed UTC month",
  },
  {
    from: "ParquetArchiver",
    to: "WorkflowCoordinator",
    action: "confirmArchive",
    when: "archive stages were instantiated",
    data: ["datasetNames", "manifestIDs", "rowCounts", "relativePaths", "sha256"],
  },
  {
    from: "WorkflowCoordinator",
    to: "CoreDataStore",
    action: "completePeriodRun",
    data: ["finalCounters", "periodCheckpoint", "finishedAt"],
    notes: "Open-month and partial/multi-month range runs complete after projection verification without archive stages.",
  },
];

/** One email's dependency-aware transformation pipeline. */
export const emailTransformationFlow: FlowStep[] = [
  {
    from: "WorkflowCoordinator",
    to: "EmailProcessingPipeline",
    action: "startOrResume",
    data: ["processingJobID", "messageIdentity", "inputFingerprint"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "loadJobAndSteps",
    data: ["pipelineVersion", "stepStates", "dependencyOutputs"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "reuseCompatibleResults",
    data: ["transformerName", "transformerVersion", "inputFingerprint", "outputSchemaVersion"],
    when: "a valid succeeded result already exists",
  },
  {
    from: "EmailProcessingPipeline",
    to: "TransformerRegistry",
    action: "resolve",
    data: ["transformerName", "stepVersion", "outputSchemaVersion"],
    notes: "Missing or incompatible implementations block work before consuming an attempt.",
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "claimReadySteps",
    data: ["leaseOwner", "leaseExpiresAt", "attemptCount"],
    notes: "The scheduler serializes claims; independent claimed dependency branches execute concurrently.",
  },
  {
    from: "TransformerRegistry",
    to: "EmailTransformer",
    action: "transform",
    data: ["messageIdentity", "normalizedMetadata", "dependencyOutputs", "idempotencyKey"],
    notes: "Synchronous transformers use the same async erased call surface.",
  },
  {
    from: "EmailTransformer",
    to: "EmailProcessingPipeline",
    action: "returnResult",
    data: ["officialStatus", "customStatus", "message", "typedOutput"],
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "commitStepResultAtomically",
    data: ["stepState", "officialStatus", "customStatus", "statusMessage", "outputData", "timestamps"],
    notes: "The terminal state and persisted output become visible in the same save.",
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "scheduleRetry",
    data: ["nextAttemptAt", "attemptCount", "failureCode"],
    when: "officialStatus is retry and attempts remain",
  },
  {
    from: "EmailProcessingPipeline",
    to: "CoreDataStore",
    action: "finishJob",
    data: ["succeeded", "succeededWithWarnings", "failed"],
    when: "every instantiated step is terminal and required-step outcomes determine success or failure",
  },
];

/** Idempotent Core Data to DuckDB export, including the dual-commit crash gap. */
export const duckDBProjectionRecoveryFlow: FlowStep[] = [
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "prepareSchema",
    notes: "Open migrate and validate before claiming Core Data work; retain the in-flight gate across awaits.",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "claimStableResultBatch",
    data: ["batchID", "leaseOwner", "leaseExpiresAt", "sourceVersions"],
  },
  {
    from: "CoreDataStore",
    to: "DuckDBExporter",
    action: "returnImmutableRows",
    data: ["metadataRows", "processingResultRows"],
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "beginTransaction",
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "parameterizedUpsert",
    data: ["logicalKey", "sourceVersion", "analyticalColumns", "extensionsJSON"],
    notes: "Update only for strictly newer revisions; equal or newer destination versions are acknowledged no-ops.",
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "commitTransaction",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "acknowledgeExport",
    data: ["batchID", "claimedSourceVersions", "exportedAt", "duckDBSchemaVersion"],
    notes: "Fence by batchID and preserve newer source revisions as pending.",
  },
  {
    from: "System",
    to: "DuckDBExporter",
    action: "restartAfterCommitGap",
    when: "DuckDB committed but Core Data acknowledgement did not",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "reclaimExpiredBatch",
    data: ["batchID", "sourceVersions"],
  },
  {
    from: "DuckDBExporter",
    to: "DuckDBStore",
    action: "replayIdempotentUpsert",
    data: ["logicalKeys", "sourceVersions"],
    notes: "Equal or newer destination versions make the replay a successful no-op.",
  },
  {
    from: "DuckDBExporter",
    to: "CoreDataStore",
    action: "acknowledgeRecoveredExport",
  },
];

/** DuckDB live data to verified monthly Parquet archives. */
export const parquetArchiveFlow: FlowStep[] = [
  {
    from: "WorkflowCoordinator",
    to: "ParquetArchiver",
    action: "requestArchive",
    data: ["accountID", "mailboxID", "partitionMonth"],
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "claimArchiveBatch",
    data: ["dataset", "archiveBatchID", "sourceVersions"],
    notes: "One transaction claims a complete month per dataset; exporting remains queryable and dataset-specific manifests track separate paths and counts.",
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "readImmutableExportingBatch",
    data: ["emailMetadataRows", "processingResultRows", "schemaVersions"],
  },
  {
    from: "ParquetArchiver",
    to: "ParquetFileSystem",
    action: "writeTemporaryFiles",
    data: ["emailMetadataDataset", "processingResultDataset"],
  },
  {
    from: "ParquetArchiver",
    to: "ParquetFileSystem",
    action: "verifyAndPublishAtomically",
    notes: "Publish to immutable batch-specific paths; persist published state and verify the digest on restart before making a generation current.",
    data: ["rowCounts", "schemaVersions", "sha256", "relativePaths"],
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "commitManifestAndDeleteStaging",
    data: ["archiveBatchID", "manifest", "currentGeneration", "exportingRows"],
    when: "Parquet publication was verified",
  },
  {
    from: "ParquetArchiver",
    to: "DuckDBStore",
    action: "retainBatchForRetry",
    data: ["archiveBatchID", "failure"],
    when: "writing or verification failed",
  },
  {
    from: "SyncReconciler",
    to: "DuckDBCorrectionOverlay",
    action: "upsertArchivedPeriodCorrection",
    data: ["logicalKey", "sourceVersion", "changeOrTombstone"],
    when: "an already archived message changes",
  },
  {
    from: "ParquetCompactor",
    to: "ParquetFileSystem",
    action: "atomicallyReplaceCorrectedPartition",
    notes: "Merge the prior committed partition and fixed overlay revisions into a new generation; preserve newer corrections and retain old files until readers release them.",
    when: "correction compaction policy is satisfied",
  },
];

/** Explicit on-demand body or attachment retrieval. */
export const onDemandContentFlow: FlowStep[] = [
  {
    from: "AppOrCLI",
    to: "FetchEmailClient",
    action: "start",
    data: ["messageIdentity", "selection", "transform", "retention", "maximumBytes"],
  },
  {
    from: "FetchEmailClient",
    to: "CoreDataStore",
    action: "persistFetchOperation",
    data: ["fetchID", "state=pending"],
  },
  {
    from: "FetchEmailClient",
    to: "IMAPClient",
    action: "fetchSelectedContent",
    data: ["mailboxID", "uidValidity", "uid", "mimePartIDs"],
  },
  {
    from: "IMAPClient",
    to: "TemporaryContentStore",
    action: "writeUnpublishedPartialContent",
  },
  {
    from: "FetchEmailClient",
    to: "TemporaryContentStore",
    action: "publishCompleteArtifactsAtomically",
    data: ["relativePaths", "byteCounts", "sha256"],
  },
  {
    from: "FetchEmailClient",
    to: "CoreDataStore",
    action: "persistContentLeaseAndResult",
    data: ["leaseID", "ownerSessionID", "expiresAt", "artifacts", "state=completed"],
  },
  {
    from: "AppOrCLI",
    to: "FetchEmailClient",
    action: "release",
    data: ["leaseID"],
    when: "the caller has finished using the content",
  },
  {
    from: "FetchEmailClient",
    to: "TemporaryContentStore",
    action: "removeEligibleArtifacts",
    data: ["leaseID"],
  },
];

export const libraryProcessingFlows = {
  initialization: initializationFlow,
  periodProcessing: periodProcessingFlow,
  emailTransformation: emailTransformationFlow,
  duckDBProjectionRecovery: duckDBProjectionRecoveryFlow,
  parquetArchive: parquetArchiveFlow,
  onDemandContent: onDemandContentFlow,
};
```

### 03 Period Workflow Stages

The versioned task kinds, dependencies, fan-out, and durable completion gates. Source: [period_workflow_stages.csv](../design-meta/examples/sync/period_workflow_stages.csv).

#### Period Workflow Stages

| applies_when | depends_on | durable_success_condition | executor | fan_out | scope | stage_id | task_kind |
| --- | --- | --- | --- | --- | --- | --- | --- |
| always |  | UTC period boundaries mailbox scope and deterministic task identities are persisted | Workflow coordinator | one per plan | account+mailbox+period | period.plan | period.plan |
| always | period.plan | This page cursor and its child tasks commit atomically; the discovery stage completes only after the final page is consumed | IMAP client | one or more pages per mailbox | mailbox+period | uid.discover | imap.discover-uids |
| always | uid.discover | Normalized metadata file locator schema fingerprint and export checkpoint are persisted without body bytes | IMAP client | one per account+mailbox+UIDVALIDITY+UID | message emitted by one committed discovery page | metadata.fetch | imap.fetch-metadata |
| always | metadata.fetch | The linked job is succeeded or succeededWithWarnings with all instantiated steps terminal; required failure blocks the included message | EmailProcessingPipeline | one per message | message | email.process | email.process |
| always | email.process | All eligible metadata and stable processing source versions for the period are transactionally upserted and acknowledged | DuckDBExporter | configurable batches | account+mailbox+period | duckdb.export-period | duckdb.export-period |
| always | duckdb.export-period | Expected message and processing-result keys are present at equal or newer source versions and no export claims remain pending | DuckDBExporter | one per partition | account+mailbox+period | duckdb.verify-period | duckdb.verify-period |
| complete closed UTC calendar month | duckdb.verify-period | Eligible rows are moved to queryable immutable exporting snapshots with dataset-specific manifests | Parquet archiver | one per dataset and partition | account+mailbox+period | parquet.claim | parquet.claim-period |
| complete closed UTC calendar month | parquet.claim | Temporary Parquet output is complete with the expected schema version and row counts | Parquet archiver | one per archive batch | archive batch | parquet.write | parquet.write-period |
| complete closed UTC calendar month | parquet.write | Verified Parquet output is atomically published and manifest state is published with its path digest and verified file row count | Parquet archiver | one per archive batch | archive batch | parquet.publish | parquet.publish-period |
| complete closed UTC calendar month | parquet.publish | Exporting rows are deleted in the same DuckDB transaction that marks the archive manifest committed | Parquet archiver | one per archive batch | archive batch | parquet.finalize | parquet.finalize-period |
| always | duckdb.verify-period;parquet.finalize when instantiated | Every applicable stage is complete counters reconcile and SyncPeriodCheckpoint is persisted | Workflow coordinator | one per plan | account+mailbox+period | period.complete | period.complete |

### 04 Period Workflow Rules

UTC boundaries, stage gates, backpressure, retries, and completion. Source: [period_workflow_rules.csv](../design-meta/examples/sync/period_workflow_rules.csv).

#### Period Workflow Rules

| area | rationale | requirement | rule_id |
| --- | --- | --- | --- |
| Architecture | Avoids introducing another orchestration system | Use the existing persisted SyncPlan SyncRun SyncTask SyncAttempt and SyncTaskDependency model as the generic period coordinator. | workflow.scope |
| Architecture | Keeps task orchestration separate from domain implementation | Delegate IMAP transformation DuckDB and Parquet behavior to their dedicated components and persist only coordination state in the generic workflow. | workflow.specialists |
| Architecture | Keeps v1 pragmatic and testable | Use a versioned closed set of task kinds from period_workflow_stages.csv rather than runtime-defined arbitrary workflows. | workflow.closed_kinds |
| Period | Aligns orchestration with monthly Parquet partitions | Use one UTC calendar month as the normal workflow period while allowing an explicit UTC half-open date range. | period.default |
| Period | Eliminates overlap and timezone ambiguity | Represent every period as inclusive periodStart and exclusive periodEndExclusive instants in UTC. | period.boundaries |
| Period | Prevents incorrectly naming partial ranges as monthly archives | Set partitionMonth only when boundaries exactly match one UTC calendar month; v1 creates archive stages only for a complete closed month. | period.partition |
| Identity | Uses the durable server identity required for later fetches | Discover IMAP UIDs rather than UUIDs and persist account mailbox UIDVALIDITY and UID on every per-email task. | identity.uid |
| Identity | Makes dynamic fan-out idempotent after crashes | Derive a deterministic task identity from run stage mailbox UIDVALIDITY UID and relevant schema or pipeline version. | identity.task |
| Discovery | Avoids losing or duplicating fan-out work after interruption | Commit each discovery page and its newly created child tasks atomically before requesting the next page. | discover.pagination |
| Discovery | Provides a durable enumeration checkpoint | Do not complete UID discovery until all server result pages are consumed and child-task uniqueness conflicts are resolved as existing work. | discover.complete |
| Metadata | Preserves the metadata-only sync boundary | Fetch only headers flags dates size BODYSTRUCTURE and provider metadata during metadata.fetch. | fetch.metadata |
| Metadata | Allows transformations to resume without repeating a successful network fetch | Publish an integrity-checked normalized metadata file and persist its schema version fingerprint relative locator and MetadataExportState before completing metadata.fetch. | fetch.result |
| Processing | Connects generic orchestration to the durable transformation pipeline | Create or reuse one EmailProcessingJob for each successfully fetched message and persist its ID on the coordinating SyncTask. | process.link |
| Processing | Provides throughput without unbounded network CPU or I/O work | Allow per-email processing tasks and independent transformers to run concurrently under separate bounded limits. | process.parallel |
| Processing | Prevents optional work from blocking the whole period | Treat succeededWithWarnings as stable for period export while preserving optional transformer failures in analytical results. | process.optional |
| Processing | Prevents silent partial analytical datasets | Block period export when a required email-processing job failed unless policy explicitly excludes that message and records the exclusion. | process.required_failure |
| DuckDB | Defines a reproducible period snapshot | Create period export tasks only after discovery is complete and every included message has stable metadata and a succeeded or succeededWithWarnings processing job; required failures block the run unless an explicit persisted exclusion policy applies. | duckdb.gate |
| DuckDB | Produces a joinable analytical period | Upsert both email metadata using email_metadata_parquet_columns.csv and stable transformer results using duckdb_processing_export_tables.csv. | duckdb.contents |
| DuckDB | Allows restart without restarting the entire period | Run configurable idempotent batches until every eligible source version in the period is acknowledged in Core Data. | duckdb.batches |
| DuckDB | Prevents incomplete Parquet publication | Verify logical keys source versions expected counts and absence of pending export claims before allowing archival. | duckdb.verify |
| Parquet | Avoids racing normal changes in an open month | Instantiate archive stages only for one complete closed UTC calendar month; open months and partial or multi-month date ranges complete after DuckDB verification and retain unarchived rows for later full-month plans. | archive.eligibility |
| Parquet | Produces deterministic Parquet output | For initial monthly publication read only immutable exporting snapshots; correction compaction reads a fixed prior archive plus claimed overlay revisions and never changing live rows. | archive.snapshot |
| Parquet | Preserves their different row grains and join keys | Write compatible email metadata and processing-result Parquet datasets for the same account mailbox and period. | archive.contents |
| Parquet | Prevents data loss | Delete DuckDB exporting rows only after atomic Parquet publication verification and manifest commit. | archive.success |
| Parquet | Keeps old flags labels moves and expunges correct | Route changes discovered after archival into the DuckDB correction overlay and compact the affected monthly partition by policy. | archive.corrections |
| Recovery | Makes the whole multi-stage workflow crash-resumable | On restart schedule persisted incomplete tasks whose dependencies are satisfied and never recreate completed task output unnecessarily. | recovery.resume |
| Recovery | Lets subsystem idempotency close crash gaps | Inspect linked processing export and archive identifiers before retrying a coordinating task. | recovery.subsystems |
| Failure handling | Distinguishes transient IMAP processing storage and archive failures | Apply task-kind-specific bounded retry policies and retain attempts and sanitized errors. | failure.retry |
| Failure handling | Avoids destructive automatic guesses | Mark the run blocked when credentials transformers schema compatibility or operator policy prevents safe progress. | failure.blocked |
| Backpressure | Bounds Core Data rows memory and network pressure | Pause discovery fan-out when the number of unfinished per-email tasks exceeds a configured high-water mark. | backpressure.discovery |
| Completion | Provides one durable end-to-end outcome | Complete the run after DuckDB verification and every instantiated archive stage succeeds; reconcile counters and persist a SyncPeriodCheckpoint, without treating a period-limited UID cursor as complete mailbox coverage. | completion.run |
| Persistence | Maintains Core Data as an operational store | Keep task payloads small and versioned and never store message bodies credentials or large UID arrays in workflow rows. | payload.boundary |
| Discovery | Allows bounded fan-out to drain instead of deadlocking at the high-water mark | Each metadata.fetch child becomes runnable after its producing discovery page and task are committed; do not wait for all mailbox discovery pages before consuming children. | discover.child_gate |
| Discovery | Avoids skipping historical messages or boundary candidates | Treat server date searches and highestObservedUID as discovery aids; verify canonical UTC email_date against the requested half-open range and broaden discovery when fallback dates may lie outside the server candidate range. | discover.period_filter |
| Persistence | Prevents one partial-range sync from suppressing another | Persist completed coverage by account mailbox UIDVALIDITY periodStart and periodEndExclusive in SyncPeriodCheckpoint; highestObservedUID is a mailbox-wide hint and never proves range coverage. | checkpoint.period |
| Recovery | Makes generic workflow tasks as restart-safe as processing steps | Claim SyncTask with leaseOwner leaseExpiresAt and attemptCount atomically; fence completion by the current task claim and reclaim only expired unfinished work. | workflow.claim |
| Concurrency | An in-process actor alone cannot coordinate independent processes | Acquire exclusive process writer ownership for the shared Core Data store before initialization and hold it until shutdown; a competing app CLI or daemon fails with an actionable busy error. | workflow.writer |
| Recovery | Aligns durable cancellation with the public resumable API | Cancellation ends the current event stream and preserves completed work; explicit resume resets cancelled unfinished tasks to pending clears cancellation and retains attempt ceilings. | workflow.cancel |
| Progress | Keeps progress stable across replay and partition replacement | Count distinct durable task message and result-version completions; replay acknowledgements do not increment counters twice and archivedRecords counts newly finalized batch rows across both datasets. | progress.idempotent |
| Persistence | Fallback dates and first-seen timestamps must not change when a metadata file or old run is pruned | Copy canonical emailDate emailDateSource and firstSeenAt from the latest MetadataExportState when refreshing an existing message; retain that checkpoint and its owning task while the message identity is retained and prune only superseded snapshots. | metadata.identity_retention |

### 05 Account and Workflow Persistence Fields

Swift-facing field shapes for accounts, plans, runs, tasks, checkpoints, and temporary content; Core Data storage follows the datastore and pipeline rules. Source: [coredata_workflow_fields.csv](../design-meta/examples/sync/coredata_workflow_fields.csv).

#### Account and Workflow Persistence Fields

| default_value | description | entity | field | field_id | indexed | relationship | required | swift_type | unique |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  | Stable local account identifier | Account | id | account.id | yes |  | yes | UUID | yes |
|  | User-visible account name | Account | displayName | account.display_name | no |  | yes | String | no |
|  | Normalized primary email address | Account | emailAddress | account.email_address | yes |  | yes | String | no |
| imap | Raw provider enum such as gmail or imap | Account | providerKind | account.provider_kind | no |  | yes | String | no |
|  | IMAP server hostname | Account | imapHost | account.imap_host | no |  | yes | String | no |
| 993 | IMAP server port | Account | imapPort | account.imap_port | no |  | yes | Int | no |
| tls | Raw transport-security enum | Account | transportSecurity | account.transport_security | no |  | yes | String | no |
|  | IMAP login identity; not a secret | Account | username | account.username | no |  | yes | String | no |
|  | Opaque lookup identifier for credentials held only in Keychain | Account | keychainCredentialID | account.keychain_credential_id | yes |  | yes | String | yes |
|  | Stable filesystem subfolder name such as account1 | Account | folderName | account.folder_name | yes |  | yes | String | yes |
| true | Whether scheduled and manual sync may run | Account | isEnabled | account.is_enabled | yes |  | yes | Bool | no |
|  | Creation timestamp | Account | createdAt | account.created_at | no |  | yes | Date | no |
|  | Last configuration-change timestamp | Account | updatedAt | account.updated_at | no |  | yes | Date | no |
| [] | Known mailboxes for this account | Account | mailboxes | account.mailboxes | no | one-to-many; inverse=account; delete=cascade | yes | [Mailbox] | no |
| [] | Durable sync plans owned by this account | Account | syncPlans | account.sync_plans | no | one-to-many; inverse=account; delete=cascade | yes | [SyncPlan] | no |
| [] | On-demand fetch operations owned by this account | Account | fetchOperations | account.fetch_operations | no | one-to-many; inverse=account; delete=cascade | yes | [FetchOperation] | no |
|  | Stable local mailbox identifier | Mailbox | id | mailbox.id | yes |  | yes | UUID | yes |
|  | Owning account | Mailbox | account | mailbox.account | yes | many-to-one; inverse=mailboxes | yes | Account | no |
|  | Exact server mailbox name; unique within an account | Mailbox | serverName | mailbox.server_name | yes |  | yes | String | no |
|  | Decoded user-visible mailbox name | Mailbox | displayName | mailbox.display_name | no |  | yes | String | no |
|  | Server hierarchy delimiter when advertised | Mailbox | delimiter | mailbox.delimiter | no |  | no | String | no |
| [] | Normalized IMAP mailbox attributes | Mailbox | attributes | mailbox.attributes | no |  | yes | [String] | no |
| true | Whether the mailbox may be selected | Mailbox | isSelectable | mailbox.is_selectable | no |  | yes | Bool | no |
|  | First discovery timestamp | Mailbox | discoveredAt | mailbox.discovered_at | no |  | yes | Date | no |
|  | Last discovery or attribute-update timestamp | Mailbox | updatedAt | mailbox.updated_at | no |  | yes | Date | no |
|  | Durable incremental-sync cursor | Mailbox | checkpoint | mailbox.checkpoint | no | one-to-one; inverse=mailbox; delete=cascade | no | MailboxCheckpoint | yes |
|  | Stable plan identifier | SyncPlan | id | sync_plan.id | yes |  | yes | UUID | yes |
|  | Account to synchronize | SyncPlan | account | sync_plan.account | yes | many-to-one; inverse=syncPlans | yes | Account | no |
|  | Raw mode enum: initial incremental or reconcile | SyncPlan | mode | sync_plan.mode | yes |  | yes | String | no |
| calendar-month | Raw period enum: calendar-month or date-range, matching the API discriminators | SyncPlan | periodKind | sync_plan.period_kind | no |  | yes | String | no |
|  | Inclusive UTC period boundary | SyncPlan | periodStart | sync_plan.period_start | yes |  | yes | Date | no |
|  | Exclusive UTC period boundary | SyncPlan | periodEndExclusive | sync_plan.period_end_exclusive | yes |  | yes | Date | no |
|  | YYYY-MM when the plan covers exactly one UTC calendar month | SyncPlan | partitionMonth | sync_plan.partition_month | yes |  | no | String | no |
| true | Invariant preventing content downloads during sync | SyncPlan | metadataOnly | sync_plan.metadata_only | no |  | yes | Bool | no |
| ready | Raw state enum: ready or superseded | SyncPlan | state | sync_plan.state | yes |  | yes | String | no |
|  | Plan creation timestamp | SyncPlan | createdAt | sync_plan.created_at | no |  | yes | Date | no |
| [] | Empty means all; include selection must contain at least one unique mailbox ID owned by this account | SyncPlan | mailboxSelections | sync_plan.mailbox_selections | no | one-to-many; inverse=plan; delete=cascade | yes | [SyncPlanMailbox] | no |
| [] | Execution history for the plan | SyncPlan | runs | sync_plan.runs | no | one-to-many; inverse=plan; delete=cascade | yes | [SyncRun] | no |
|  | Stable selection-row identifier | SyncPlanMailbox | id | sync_plan_mailbox.id | yes |  | yes | UUID | yes |
|  | Owning plan | SyncPlanMailbox | plan | sync_plan_mailbox.plan | yes | many-to-one; inverse=mailboxSelections | yes | SyncPlan | no |
|  | Selected mailbox; unique with plan | SyncPlanMailbox | mailbox | sync_plan_mailbox.mailbox | yes | many-to-one | yes | Mailbox | no |
|  | Stable run identifier | SyncRun | id | sync_run.id | yes |  | yes | UUID | yes |
|  | Plan being executed | SyncRun | plan | sync_run.plan | yes | many-to-one; inverse=runs | yes | SyncPlan | no |
| pending | Raw workflow-state enum | SyncRun | state | sync_run.state | yes |  | yes | String | no |
| 0 | Completed task count | SyncRun | completedTasks | sync_run.completed_tasks | no |  | yes | Int64 | no |
| 0 | Total planned task count | SyncRun | totalTasks | sync_run.total_tasks | no |  | yes | Int64 | no |
| 0 | Messages discovered during this run | SyncRun | discoveredMessages | sync_run.discovered_messages | no |  | yes | Int64 | no |
| 0 | Metadata records fetched from IMAP | SyncRun | fetchedMetadataRecords | sync_run.fetched_metadata_records | no |  | yes | Int64 | no |
| 0 | Metadata records upserted into the DuckDB live store | SyncRun | updatedMetadataRecords | sync_run.updated_metadata_records | no |  | yes | Int64 | no |
| 0 | Metadata records removed during reconciliation | SyncRun | removedMetadataRecords | sync_run.removed_metadata_records | no |  | yes | Int64 | no |
| 0 | Messages whose required transformation pipeline completed | SyncRun | processedMessages | sync_run.processed_messages | no |  | yes | Int64 | no |
| 0 | Stable transformation results acknowledged in DuckDB | SyncRun | exportedProcessingResults | sync_run.exported_processing_results | no |  | yes | Int64 | no |
| 0 | DuckDB rows verified and published to Parquet | SyncRun | archivedRecords | sync_run.archived_records | no |  | yes | Int64 | no |
|  | Raw blocking-reason enum | SyncRun | blockingKind | sync_run.blocking_kind | yes |  | no | String | no |
|  | Non-secret diagnostic detail | SyncRun | blockingDetail | sync_run.blocking_detail | no |  | no | String | no |
|  | Stable failure code | SyncRun | failureCode | sync_run.failure_code | yes |  | no | String | no |
|  | Sanitized failure summary without message content or credentials | SyncRun | failureMessage | sync_run.failure_message | no |  | no | String | no |
|  | Run creation timestamp | SyncRun | createdAt | sync_run.created_at | no |  | yes | Date | no |
|  | First start timestamp | SyncRun | startedAt | sync_run.started_at | no |  | no | Date | no |
|  | Terminal-state timestamp | SyncRun | finishedAt | sync_run.finished_at | no |  | no | Date | no |
| [] | Durable task graph for this run | SyncRun | tasks | sync_run.tasks | no | one-to-many; inverse=run; delete=cascade | yes | [SyncTask] | no |
| false | Retryability of the latest run failure | SyncRun | failureRetryable | sync_run.failure_retryable | no |  | yes | Bool | no |
|  | Stable task identifier | SyncTask | id | sync_task.id | yes |  | yes | UUID | yes |
|  | Owning run | SyncTask | run | sync_task.run | yes | many-to-one; inverse=tasks | yes | SyncRun | no |
|  | Mailbox scope when applicable | SyncTask | mailbox | sync_task.mailbox | yes | many-to-one | no | Mailbox | no |
|  | Stable task-kind identifier | SyncTask | kind | sync_task.kind | yes |  | yes | String | no |
|  | Stable period-workflow stage identifier | SyncTask | stage | sync_task.stage | yes |  | yes | String | no |
|  | Message UIDVALIDITY for per-email tasks | SyncTask | uidValidity | sync_task.uid_validity | yes |  | no | Int64 | no |
|  | Message IMAP UID for per-email tasks | SyncTask | emailUID | sync_task.email_uid | yes |  | no | Int64 | no |
|  | Linked EmailProcessingJob identifier for transformation tasks | SyncTask | processingJobID | sync_task.processing_job_id | yes |  | no | UUID | no |
|  | Linked Core Data to DuckDB export batch | SyncTask | exportBatchID | sync_task.export_batch_id | yes |  | no | UUID | no |
|  | Linked DuckDB to Parquet archive batch | SyncTask | archiveBatchID | sync_task.archive_batch_id | yes |  | no | UUID | no |
| 1 | Schema version for the task payload | SyncTask | payloadVersion | sync_task.payload_version | no |  | yes | Int | no |
|  | Small versioned Codable parameters; never message content or credentials | SyncTask | payload | sync_task.payload | no |  | no | Data | no |
|  | Version of a durable intermediate task result | SyncTask | resultSchemaVersion | sync_task.result_schema_version | no |  | no | Int | no |
|  | Integrity and reuse digest for the intermediate result | SyncTask | resultFingerprint | sync_task.result_fingerprint | yes |  | no | String | no |
|  | Integrity-checked normalized result path beneath the account folder; mandatory before metadata.fetch completion | SyncTask | resultRelativePath | sync_task.result_relative_path | no |  | no | String | no |
| pending | Raw workflow-state enum | SyncTask | state | sync_task.state | yes |  | yes | String | no |
| 0 | Deterministic execution and display ordering | SyncTask | sequence | sync_task.sequence | yes |  | yes | Int64 | no |
| 0 | Number of attempts started | SyncTask | attemptCount | sync_task.attempt_count | no |  | yes | Int | no |
| 3 | Retry ceiling | SyncTask | maximumAttempts | sync_task.maximum_attempts | no |  | yes | Int | no |
|  | Backoff deadline for a retryable task | SyncTask | nextAttemptAt | sync_task.next_attempt_at | yes |  | no | Date | no |
| 0 | Task-specific completed work units | SyncTask | completedUnits | sync_task.completed_units | no |  | yes | Int64 | no |
|  | Task-specific total when known | SyncTask | totalUnits | sync_task.total_units | no |  | no | Int64 | no |
|  | Task creation timestamp | SyncTask | createdAt | sync_task.created_at | no |  | yes | Date | no |
|  | Most recent start timestamp | SyncTask | startedAt | sync_task.started_at | no |  | no | Date | no |
|  | Terminal-state timestamp | SyncTask | finishedAt | sync_task.finished_at | no |  | no | Date | no |
| [] | Attempt history | SyncTask | attempts | sync_task.attempts | no | one-to-many; inverse=task; delete=cascade | yes | [SyncAttempt] | no |
| [] | Dependency edges entering this task | SyncTask | prerequisites | sync_task.prerequisites | no | one-to-many; inverse=task; delete=cascade | yes | [SyncTaskDependency] | no |
|  | Deterministic key over run stage mailbox UIDVALIDITY UID and relevant contract version | SyncTask | taskKey | sync_task.task_key | yes |  | yes | String | yes |
|  | Current claim identifier; fence task completion by this owner and lease | SyncTask | leaseOwner | sync_task.lease_owner | yes |  | no | String | no |
|  | Expired unfinished task claims may be reclaimed | SyncTask | leaseExpiresAt | sync_task.lease_expires_at | yes |  | no | Date | no |
|  | Small durable page cursor saved atomically with emitted child tasks; never a UID array | SyncTask | discoveryCursor | sync_task.discovery_cursor | no |  | no | String | no |
|  | Versioned normalized metadata projection checkpoint | SyncTask | metadataExportState | sync_task.metadata_export_state | no | one-to-one; inverse=task; delete=cascade | no | MetadataExportState | no |
|  | Stable dependency-edge identifier | SyncTaskDependency | id | sync_task_dependency.id | yes |  | yes | UUID | yes |
|  | Task that must wait | SyncTaskDependency | task | sync_task_dependency.task | yes | many-to-one; inverse=prerequisites | yes | SyncTask | no |
|  | Task that must complete first; pair must be unique | SyncTaskDependency | prerequisite | sync_task_dependency.prerequisite | yes | many-to-one | yes | SyncTask | no |
|  | Stable attempt identifier | SyncAttempt | id | sync_attempt.id | yes |  | yes | UUID | yes |
|  | Task being attempted | SyncAttempt | task | sync_attempt.task | yes | many-to-one; inverse=attempts | yes | SyncTask | no |
|  | Monotonic attempt number unique within a task | SyncAttempt | ordinal | sync_attempt.ordinal | no |  | yes | Int | no |
| running | Raw attempt-state enum | SyncAttempt | state | sync_attempt.state | yes |  | yes | String | no |
|  | Attempt start timestamp | SyncAttempt | startedAt | sync_attempt.started_at | no |  | yes | Date | no |
|  | Attempt finish timestamp | SyncAttempt | finishedAt | sync_attempt.finished_at | no |  | no | Date | no |
|  | Stable failure code | SyncAttempt | failureCode | sync_attempt.failure_code | yes |  | no | String | no |
|  | Sanitized diagnostic summary | SyncAttempt | failureMessage | sync_attempt.failure_message | no |  | no | String | no |
| false | Whether policy permits another attempt | SyncAttempt | retryable | sync_attempt.retryable | no |  | yes | Bool | no |
|  | Stable checkpoint identifier | MailboxCheckpoint | id | mailbox_checkpoint.id | yes |  | yes | UUID | yes |
|  | Mailbox owning the checkpoint | MailboxCheckpoint | mailbox | mailbox_checkpoint.mailbox | yes | one-to-one; inverse=checkpoint | yes | Mailbox | yes |
|  | Current IMAP UIDVALIDITY value | MailboxCheckpoint | uidValidity | mailbox_checkpoint.uid_validity | yes |  | yes | Int64 | no |
|  | Highest UID observed for incremental discovery | MailboxCheckpoint | highestObservedUID | mailbox_checkpoint.highest_observed_uid | no |  | no | Int64 | no |
|  | Most recent fully committed mailbox sync | MailboxCheckpoint | lastSuccessfulSyncAt | mailbox_checkpoint.last_successful_sync_at | no |  | no | Date | no |
| false | Whether incremental state must be rebuilt | MailboxCheckpoint | requiresReconciliation | mailbox_checkpoint.requires_reconciliation | yes |  | yes | Bool | no |
|  | Last checkpoint mutation timestamp | MailboxCheckpoint | updatedAt | mailbox_checkpoint.updated_at | no |  | yes | Date | no |
|  | Stable completed-range checkpoint identifier | SyncPeriodCheckpoint | id | period_checkpoint.id | yes |  | yes | UUID | yes |
|  | Deterministic account mailbox UIDVALIDITY periodStart periodEndExclusive key | SyncPeriodCheckpoint | scopeKey | period_checkpoint.scope_key | yes |  | yes | String | yes |
|  | Owning account; encode UUID as canonical string at the API boundary | SyncPeriodCheckpoint | accountID | period_checkpoint.account_id | yes |  | yes | UUID | no |
|  | Covered mailbox | SyncPeriodCheckpoint | mailboxID | period_checkpoint.mailbox_id | yes |  | yes | UUID | no |
|  | Mailbox generation covered by the completed range | SyncPeriodCheckpoint | uidValidity | period_checkpoint.uid_validity | no |  | yes | Int64 | no |
|  | Inclusive UTC coverage boundary | SyncPeriodCheckpoint | periodStart | period_checkpoint.period_start | no |  | yes | Date | no |
|  | Exclusive UTC coverage boundary | SyncPeriodCheckpoint | periodEndExclusive | period_checkpoint.period_end_exclusive | no |  | yes | Date | no |
|  | Last successfully completed run for this scope | SyncPeriodCheckpoint | runID | period_checkpoint.run_id | no |  | yes | UUID | no |
|  | Last verified completion timestamp | SyncPeriodCheckpoint | completedAt | period_checkpoint.completed_at | no |  | yes | Date | no |
|  | Stable fetch identifier | FetchOperation | id | fetch_operation.id | yes |  | yes | UUID | yes |
|  | Owning account | FetchOperation | account | fetch_operation.account | yes | many-to-one; inverse=fetchOperations | yes | Account | no |
|  | Mailbox containing the message | FetchOperation | mailbox | fetch_operation.mailbox | yes | many-to-one | yes | Mailbox | no |
|  | UIDVALIDITY captured when requested | FetchOperation | uidValidity | fetch_operation.uid_validity | yes |  | yes | Int64 | no |
|  | Stable mailbox-local message UID | FetchOperation | uid | fetch_operation.uid | yes |  | yes | Int64 | no |
|  | Raw content-selection enum | FetchOperation | selectionKind | fetch_operation.selection_kind | yes |  | yes | String | no |
| [] | Requested MIME part identifiers | FetchOperation | selectedPartIDs | fetch_operation.selected_part_ids | no |  | yes | [String] | no |
| none | Raw transform enum | FetchOperation | transformKind | fetch_operation.transform_kind | no |  | yes | String | no |
|  | Raw retention enum | FetchOperation | retentionKind | fetch_operation.retention_kind | no |  | yes | String | no |
|  | TTL when retention kind is time-to-live | FetchOperation | retentionSeconds | fetch_operation.retention_seconds | no |  | no | Int64 | no |
|  | Optional transfer limit | FetchOperation | maximumBytes | fetch_operation.maximum_bytes | no |  | no | Int64 | no |
| pending | Raw fetch-state enum | FetchOperation | state | fetch_operation.state | yes |  | yes | String | no |
| 0 | Downloaded bytes so far | FetchOperation | receivedBytes | fetch_operation.received_bytes | no |  | yes | Int64 | no |
|  | Expected bytes when known | FetchOperation | expectedBytes | fetch_operation.expected_bytes | no |  | no | Int64 | no |
|  | Stable failure code | FetchOperation | failureCode | fetch_operation.failure_code | yes |  | no | String | no |
|  | Sanitized failure summary | FetchOperation | failureMessage | fetch_operation.failure_message | no |  | no | String | no |
|  | Fetch creation timestamp | FetchOperation | createdAt | fetch_operation.created_at | no |  | yes | Date | no |
|  | Fetch start timestamp | FetchOperation | startedAt | fetch_operation.started_at | no |  | no | Date | no |
|  | Terminal-state timestamp | FetchOperation | finishedAt | fetch_operation.finished_at | no |  | no | Date | no |
|  | Lease created after successful publication | FetchOperation | lease | fetch_operation.lease | no | one-to-one; inverse=fetchOperation; delete=cascade | no | ContentLease | yes |
|  | Versioned Codable complete FetchEmailRequest including body preference inline resources part selection and transform output; no body bytes or secrets | FetchOperation | requestPayload | fetch_operation.request_payload | no |  | yes | Data | no |
| 1 | Schema version of requestPayload | FetchOperation | requestVersion | fetch_operation.request_version | no |  | yes | Int | no |
| connecting | connecting downloading processing or publishing; matches FetchProgress.phase | FetchOperation | progressPhase | fetch_operation.progress_phase | no |  | yes | String | no |
| false | Retryability of the latest fetch failure | FetchOperation | failureRetryable | fetch_operation.failure_retryable | no |  | yes | Bool | no |
|  | Stable lease identifier | ContentLease | id | content_lease.id | yes |  | yes | UUID | yes |
|  | Fetch operation that produced the content | ContentLease | fetchOperation | content_lease.fetch_operation | yes | one-to-one; inverse=lease | yes | FetchOperation | yes |
|  | TTL expiry from successful publication; absent for while-in-use retention, which ends with release or owner-session shutdown | ContentLease | expiresAt | content_lease.expires_at | yes |  | no | Date | no |
|  | Explicit release timestamp | ContentLease | releasedAt | content_lease.released_at | yes |  | no | Date | no |
|  | Lease creation timestamp | ContentLease | createdAt | content_lease.created_at | no |  | yes | Date | no |
| [] | Published temporary artifacts | ContentLease | artifacts | content_lease.artifacts | no | one-to-many; inverse=lease; delete=cascade | yes | [TemporaryArtifact] | no |
|  | Process session owning a while-in-use lease; prior-session while-in-use leases are released on recovery | ContentLease | ownerSessionID | content_lease.owner_session_id | yes |  | yes | String | no |
|  | Stable artifact identifier | TemporaryArtifact | id | temporary_artifact.id | yes |  | yes | UUID | yes |
|  | Owning content lease | TemporaryArtifact | lease | temporary_artifact.lease | yes | many-to-one; inverse=artifacts | yes | ContentLease | no |
|  | Raw artifact-role enum | TemporaryArtifact | role | temporary_artifact.role | yes |  | yes | String | no |
|  | Normalized MIME type/subtype string; parameters are stored separately | TemporaryArtifact | mimeType | temporary_artifact.mime_type | no |  | yes | String | no |
|  | Sanitized suggested filename | TemporaryArtifact | filename | temporary_artifact.filename | no |  | no | String | no |
|  | Published file size | TemporaryArtifact | byteCount | temporary_artifact.byte_count | no |  | yes | Int64 | no |
|  | Path relative to the account temporary-content folder | TemporaryArtifact | relativePath | temporary_artifact.relative_path | yes |  | yes | String | yes |
|  | IMAP MIME section identifier | TemporaryArtifact | partID | temporary_artifact.part_id | no |  | no | String | no |
|  | MIME Content-ID for inline resources | TemporaryArtifact | contentID | temporary_artifact.content_id | no |  | no | String | no |
|  | Optional integrity digest | TemporaryArtifact | sha256 | temporary_artifact.sha256 | no |  | no | String | no |
|  | Artifact publication timestamp | TemporaryArtifact | createdAt | temporary_artifact.created_at | no |  | yes | Date | no |
| {} | Versioned canonical JSON string map retaining MIMEType.parameters | TemporaryArtifact | mimeParameters | temporary_artifact.mime_parameters | no |  | yes | Data | no |

### 06 Sync API Contract

Planning, execution, resumption, cancellation, checkpoints, and progress events. Source: [sync-api.ts](../design-meta/examples/sync/sync-api.ts).

#### Sync API Contract

```ts
/**
 * Language-neutral design reference for the SeleneTide sync API.
 *
 * TypeScript is used to make the contract concise. The production library will
 * expose equivalent Swift Sendable values, async functions, AsyncSequence
 * progress events, and cooperative cancellation.
 */

/** Canonical string encodings of local UUIDs, distinct from provider IDs. */
export type AccountID = string;
export type MailboxID = string;
export type SyncPlanID = string;
export type SyncRunID = string;
export type SyncTaskID = string;
export type ISO8601DateTime = string;

export type ProviderMessageIdentity = {
  kind: "gmail";
  /** Decimal representation of Gmail X-GM-MSGID. */
  messageID: string;
};

/**
 * Durable mailbox-location identity. Sequence numbers must never be persisted.
 * A provider identity correlates locations but never replaces mailboxID,
 * UIDVALIDITY, and UID when fetching through IMAP.
 */
export interface MessageIdentity {
  accountID: AccountID;
  mailboxID: MailboxID;
  /** Nonzero unsigned 32-bit IMAP values, represented losslessly as numbers. */
  uidValidity: number;
  uid: number;
  providerIdentity?: ProviderMessageIdentity;
}

export type MailboxSelection =
  | { kind: "all" }
  /** Include requires a non-empty unique list owned by the selected account. */
  | { kind: "include"; mailboxIDs: readonly MailboxID[] };

export type SyncMode =
  | "initial"
  | "incremental"
  | "reconcile";

export type SyncPeriod =
  | { kind: "calendar-month"; month: string }
  | {
      kind: "date-range";
      start: ISO8601DateTime;
      endExclusive: ISO8601DateTime;
    };

/** Input used to produce a durable, inspectable sync plan. */
export interface PlanSyncRequest {
  accountID: AccountID;
  mailboxes: MailboxSelection;
  mode: SyncMode;
  /** UTC half-open period; calendar months use YYYY-MM. */
  period: SyncPeriod;

  /**
   * Metadata-only is the normal mode. This flag does not permit fetching
   * bodies or attachments; those belong to the separate on-demand API.
   */
  metadataOnly: true;
}

export interface SyncPlanSummary {
  planID: SyncPlanID;
  accountID: AccountID;
  mode: SyncMode;
  period: SyncPeriod;
  createdAt: ISO8601DateTime;
  mailboxCount: number;
  estimatedTaskCount: number;
  state: "ready" | "superseded";
}

export type SyncRunState =
  | "pending"
  | "running"
  | "blocked"
  | "completed"
  | "failed"
  | "cancelled";

export type SyncTaskState =
  | "pending"
  | "running"
  | "blocked"
  | "completed"
  | "failed"
  | "cancelled";

export interface SyncProgress {
  completedTasks: number;
  totalTasks: number;
  discoveredMessages: number;
  fetchedMetadataRecords: number;
  updatedMetadataRecords: number;
  removedMetadataRecords: number;
  processedMessages: number;
  exportedProcessingResults: number;
  /** Newly finalized batch rows across both datasets; replays add nothing. */
  archivedRecords: number;
}

/** Public snapshot backed by the offline Core Data workflow store. */
export interface SyncRunSnapshot {
  runID: SyncRunID;
  planID: SyncPlanID;
  accountID: AccountID;
  state: SyncRunState;
  progress: SyncProgress;
  createdAt: ISO8601DateTime;
  startedAt?: ISO8601DateTime;
  finishedAt?: ISO8601DateTime;
  blockingReason?: SyncBlockingReason;
  failure?: SyncFailure;
}

export type SyncBlockingReason =
  | { kind: "authentication-required"; accountID: AccountID }
  | { kind: "network-unavailable" }
  | { kind: "rate-limited"; retryAfter?: ISO8601DateTime }
  | { kind: "storage-unavailable"; detail: string }
  | { kind: "transformer-missing"; transformerName: string }
  | { kind: "transformer-incompatible"; transformerName: string }
  | { kind: "schema-incompatible"; detail: string }
  | { kind: "policy-required"; detail: string };

export interface SyncFailure {
  code:
    | "authentication-failed"
    | "imap-protocol-error"
    | "checkpoint-invalid"
    | "processing-failed"
    | "duckdb-export-failed"
    | "parquet-archive-failed"
    | "storage-error"
    | "cancelled"
    | "unexpected";
  message: string;
  retryable: boolean;
  taskID?: SyncTaskID;
}

/** Per-mailbox durable state used for interruption recovery and reconciliation. */
export interface MailboxCheckpoint {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  /** Discovery hint only; does not prove coverage of another date range. */
  highestObservedUID?: number;
  lastSuccessfulSyncAt?: ISO8601DateTime;
  requiresReconciliation: boolean;
}

export interface SyncPeriodCheckpoint {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  periodStart: ISO8601DateTime;
  periodEndExclusive: ISO8601DateTime;
  runID: SyncRunID;
  completedAt: ISO8601DateTime;
}

export type SyncEvent =
  | { kind: "run-state-changed"; snapshot: SyncRunSnapshot }
  | {
      kind: "task-state-changed";
      runID: SyncRunID;
      taskID: SyncTaskID;
      state: SyncTaskState;
    }
  | {
      kind: "mailbox-progress";
      runID: SyncRunID;
      mailboxID: MailboxID;
      progress: SyncProgress;
    }
  | {
      kind: "checkpoint-saved";
      runID: SyncRunID;
      checkpoint: MailboxCheckpoint;
    }
  | {
      kind: "period-checkpoint-saved";
      runID: SyncRunID;
      checkpoint: SyncPeriodCheckpoint;
    }
  | {
      kind: "duckdb-batch-committed";
      runID: SyncRunID;
      batchID: string;
      recordCount: number;
    }
  | {
      kind: "partition-published";
      runID: SyncRunID;
      mailboxID: MailboxID;
      dataset: "email_metadata" | "processing_results";
      /** UTC calendar month of the fixed canonical email_date, as YYYY-MM. */
      month: string;
      relativePath: string;
      recordCount: number;
    }
  | { kind: "warning"; runID: SyncRunID; code: string; message: string };

export interface StartSyncOptions {
  /** Return an existing active run for this plan instead of duplicating it. */
  idempotency: "reuse-active-run";
}

/**
 * Primary sync boundary.
 *
 * Planning and execution are separate so the CLI or an app can inspect work
 * before starting it. Plans, runs, tasks, attempts, and checkpoints survive
 * process termination in the offline Core Data store. Open-month and arbitrary
 * date-range plans complete after DuckDB verification; only complete closed
 * month plans instantiate archive stages.
 */
export interface SyncClient {
  plan(request: PlanSyncRequest): Promise<SyncPlanSummary>;

  start(
    planID: SyncPlanID,
    options?: StartSyncOptions,
  ): Promise<SyncRunSnapshot>;

  /** Resume pending and retryable work; completed tasks are not repeated. */
  resume(runID: SyncRunID): Promise<SyncRunSnapshot>;

  /** Cooperative cancellation leaves the run in a resumable durable state. */
  cancel(runID: SyncRunID): Promise<SyncRunSnapshot>;

  status(runID: SyncRunID): Promise<SyncRunSnapshot>;

  /** Emits an initial snapshot followed by ordered events until termination. */
  events(runID: SyncRunID): AsyncIterable<SyncEvent>;

  checkpoint(
    accountID: AccountID,
    mailboxID: MailboxID,
  ): Promise<MailboxCheckpoint | undefined>;

  periodCheckpoint(
    accountID: AccountID,
    mailboxID: MailboxID,
    period: SyncPeriod,
  ): Promise<SyncPeriodCheckpoint | undefined>;
}

// Example: plan an incremental metadata refresh and observe it to completion.
export async function refreshAccount(
  sync: SyncClient,
  accountID: AccountID,
  period: SyncPeriod,
): Promise<SyncRunSnapshot> {
  const plan = await sync.plan({
    accountID,
    mailboxes: { kind: "all" },
    mode: "incremental",
    period,
    metadataOnly: true,
  });

  const run = await sync.start(plan.planID, {
    idempotency: "reuse-active-run",
  });

  for await (const event of sync.events(run.runID)) {
    if (event.kind !== "run-state-changed") continue;

    const { snapshot } = event;
    if (
      snapshot.state === "completed" ||
      snapshot.state === "failed" ||
      snapshot.state === "cancelled"
    ) {
      return snapshot;
    }
  }

  return sync.status(run.runID);
}
```

## 04 IMAP Metadata and Schema

Stable message identity and the shared live/archive metadata representation.

### 01 IMAP Email Metadata

Header, MIME, provider, and derived metadata available without downloading bodies. Source: [imap_email_metadata.csv](../design-meta/examples/metadata/imap_email_metadata.csv).

#### IMAP Email Metadata

| availability | example | how_to_capture_via_imap | how_to_extract_or_parse | information | notes | what_it_is | why_or_when_useful |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Very easy | 12345 | UID FETCH 12345 (UID) | Read the numeric UID returned by the server | UID | Core IMAP metadata | Mailbox-local stable identifier assigned by IMAP | Incremental sync, deduplication within a mailbox, change tracking |
| Very easy | 427 | FETCH 427 (UID) | Use the message sequence number in the FETCH response | Sequence number | Can change when mailbox contents change | Transient position of a message in the currently selected mailbox | Useful only during the current IMAP session; do not persist as a durable ID |
| Very easy | \Seen \Answered \Flagged | UID FETCH 12345 (FLAGS) | Parse the FLAGS list | FLAGS | Provider/user-defined keywords may also appear | IMAP state flags such as seen, answered, flagged, deleted and draft | Read rate, reply rate, starred/flagged rate, mailbox-state statistics |
| Very easy | 02-Oct-2026 07:21:18 +0000 | UID FETCH 12345 (INTERNALDATE) | Parse IMAP INTERNALDATE as a timezone-aware timestamp | INTERNALDATE | Generally better than Date for mailbox arrival chronology | Server-side date/time associated with delivery/storage of the message | Volume by hour/day/week, mailbox chronology, comparison with sender Date |
| Very easy | 184532 | UID FETCH 12345 (RFC822.SIZE) | Parse integer byte count | RFC822.SIZE | Includes headers/body/attachments as encoded | Approximate full RFC message size in bytes | Average message size, large-message detection, storage statistics |
| Very easy | Fri, 2 Oct 2026 08:18:04 +0100 | UID FETCH 12345 (ENVELOPE) | Parse the first ENVELOPE field | ENVELOPE Date | Sender-controlled and may be inaccurate | Parsed Date header supplied by the sender | Sender-time statistics and comparison with INTERNALDATE |
| Very easy | Quarterly invoice | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (SUBJECT)] | Decode RFC 2047 encoded words where necessary | Subject | ENVELOPE is usually sufficient | Message subject | Topic analysis, subject-length stats, thread heuristics, classification |
| Very easy | Alice Example <alice@example.com> | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (FROM)] | Parse mailbox/name/address fields; normalize domain casing | From | A message can contain multiple From addresses in unusual cases | Author/sender identity from the From header | Top senders, sender-domain concentration, internal/external ratios |
| Easy | mailer@example.net | BODY.PEEK[HEADER.FIELDS (SENDER)] | Parse as an RFC mailbox | Sender | Often absent | Agent that actually sent the message when different from From | Automated platform identification and delegated-sender analysis |
| Easy | support@example.com | BODY.PEEK[HEADER.FIELDS (REPLY-TO)] | Parse one or more mailboxes | Reply-To | Often absent | Address replies should be directed to | Detecting platforms, aliases and From/Reply-To mismatch |
| Very easy | bob@example.org, team@example.org | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (TO)] | Parse all recipients | To | Does not necessarily reveal SMTP envelope recipients | Primary recipients listed in the message | Recipient counts, direct-mail analysis, communication-network stats |
| Very easy | manager@example.org | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (CC)] | Parse all Cc recipients | Cc | May be empty | Carbon-copy recipients | CC rate, recipient breadth, direct-vs-copied analysis |
| Easy but rarely populated | audit@example.org | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (BCC)] | Parse if present | Bcc | Usually removed during delivery, so often unavailable | Bcc header retained in the stored message | Occasional recipient statistics |
| Very easy | <20261002071804.12345@example.com> | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)] | Trim whitespace; retain canonical bracketed value | Message-ID | Not guaranteed unique or even present, though normally available | Sender-generated identifier for the message | Cross-folder/provider deduplication, threading, uniqueness statistics |
| Very easy | <previous@example.com> | UID FETCH 12345 (ENVELOPE) or BODY.PEEK[HEADER.FIELDS (IN-REPLY-TO)] | Extract referenced Message-ID(s) | In-Reply-To | Absent for root messages | Identifies the message being replied to | Conversation linkage, reply rates, thread reconstruction |
| Easy | <root@example.com> <previous@example.com> | BODY.PEEK[HEADER.FIELDS (REFERENCES)] | Tokenize referenced Message-IDs in order | References | One of the most useful threading headers | Chain of ancestor Message-IDs | Thread depth, conversation reconstruction, messages-per-thread metrics |
| Very easy | multipart/mixed: text/plain + text/html + application/pdf | UID FETCH 12345 (BODYSTRUCTURE) | Recursively parse MIME parts, types, parameters, encodings and sizes | BODYSTRUCTURE | Does not require downloading MIME part contents | Server-provided structural description of the MIME message | Attachment rate/count, HTML-vs-text rate, MIME-type distribution |
| Easy | invoice-2026-10.pdf | UID FETCH 12345 (BODYSTRUCTURE) | Read filename/name parameters from MIME part disposition/type | Attachment filename | Filename can be missing, malformed or encoded | Declared filename of a MIME part | Attachment-type statistics, filename-extension analysis |
| Very easy | application/pdf | UID FETCH 12345 (BODYSTRUCTURE) | Combine part media type and subtype | Attachment MIME type | Declared type may not match actual file bytes | Declared content type of a MIME part | PDF/image/document/calendar attachment distributions |
| Easy | 182304 | UID FETCH 12345 (BODYSTRUCTURE) | Read the MIME part octet size from BODYSTRUCTURE | Attachment encoded size | Exact semantics can depend on MIME encoding/part type | Size reported for an individual MIME part | Attachment-size distributions and large-attachment statistics |
| Easy | 4 | UID FETCH 12345 (BODYSTRUCTURE) | Recursively count leaf MIME parts | MIME part count | Derived locally from BODYSTRUCTURE | Number of individual MIME entities in the message | Complexity metrics, inline-image/attachment prevalence |
| Very easy | multipart/mixed; boundary=abc123 | BODY.PEEK[HEADER.FIELDS (CONTENT-TYPE)] or BODYSTRUCTURE | Parse media type and parameters | Top-level Content-Type | BODYSTRUCTURE normally provides richer information | Top-level MIME content type | HTML/plain/multipart/calendar/message-format statistics |
| Easy | attachment; filename=invoice.pdf | BODYSTRUCTURE or selective MIME-part header fetch | Parse disposition and parameters | Content-Disposition | Best obtained through BODYSTRUCTURE for each part | Whether MIME content is inline, attachment, etc. | Attachment-vs-inline statistics |
| Easy but sparse | en-GB | BODY.PEEK[HEADER.FIELDS (CONTENT-LANGUAGE)] | Split language tags | Content-Language | Many messages omit it | Declared language(s) of the content | Language distribution where populated |
| Easy | <bounce+123@example.net> | BODY.PEEK[HEADER.FIELDS (RETURN-PATH)] | Parse mailbox/path value | Return-Path | Semantics depend on receiving system | Recorded envelope-return/bounce address added during delivery | Sending-platform/domain analysis, bounce-system identification |
| Provider-dependent | user+sales@gmail.com | BODY.PEEK[HEADER.FIELDS (DELIVERED-TO)] | Parse address; provider may add several instances | Delivered-To | Not standardized consistently across providers | Mailbox or alias to which a provider says it delivered the message | Alias usage and mailbox-routing statistics |
| Easy to fetch; harder to analyze | from mx1.example.net ...; Fri, 2 Oct 2026 07:20:55 +0000 | BODY.PEEK[HEADER.FIELDS (RECEIVED)] | Preserve all occurrences and parse hops/timestamps carefully | Received | Multiple headers; untrusted earlier hops may be forged | Trace headers added by mail servers along the delivery path | Transit-time estimates, route/hop counts, infrastructure/domain stats |
| Provider-dependent but common | mx.google.com; dkim=pass; spf=pass; dmarc=pass | BODY.PEEK[HEADER.FIELDS (AUTHENTICATION-RESULTS)] | Parse method=result pairs and authserv-id | Authentication-Results | Trust the header added by the authoritative receiving system, not arbitrary copies | Receiving system's recorded email-authentication outcomes | SPF/DKIM/DMARC pass/fail rates and suspicious-mail statistics |
| Provider-dependent | pass (google.com: domain ... designates ...) | BODY.PEEK[HEADER.FIELDS (RECEIVED-SPF)] | Parse result token and optional details | Received-SPF | Less comprehensive than Authentication-Results | SPF evaluation recorded by a receiving server | SPF pass/fail statistics when Authentication-Results is unavailable |
| Easy | example.com | BODY.PEEK[HEADER.FIELDS (DKIM-SIGNATURE)] | Parse DKIM tag-value pairs; extract d= and optionally s=, a= | DKIM-Signature d= | Presence does not mean the signature validated | Domain claiming responsibility for the DKIM signature | Signing-domain concentration and platform/security statistics |
| Easy | s2026 | BODY.PEEK[HEADER.FIELDS (DKIM-SIGNATURE)] | Extract s= from DKIM tag-value pairs | DKIM selector | Most useful at scale | DNS selector used for DKIM key lookup | Mail-infrastructure/provider migration statistics |
| Easy | Example Newsletter <newsletter.example.com> | BODY.PEEK[HEADER.FIELDS (LIST-ID)] | Parse display text and list identifier | List-ID | Strong signal when present | Identifier for a mailing list | Newsletter/list volume, top-list statistics, bulk-mail categorization |
| Easy | <mailto:unsubscribe@example.com>, <https://example.com/unsub/123> | BODY.PEEK[HEADER.FIELDS (LIST-UNSUBSCRIBE)] | Parse URI values | List-Unsubscribe | Common in legitimate bulk mail | Mechanisms offered for unsubscribing from a list | Newsletter/bulk-mail detection and unsubscribe-capability statistics |
| Easy | List-Unsubscribe=One-Click | BODY.PEEK[HEADER.FIELDS (LIST-UNSUBSCRIBE-POST)] | Check for One-Click token | List-Unsubscribe-Post | Only relevant for mailing-list/bulk messages | Indicates RFC-style one-click list unsubscribe support | One-click unsubscribe adoption statistics |
| Easy but sparse | <mailto:list@example.com> | BODY.PEEK[HEADER.FIELDS (LIST-POST)] | Parse URI(s) | List-Post | Often absent from commercial newsletters | How to submit messages to a mailing list | Mailing-list identification and classification |
| Easy | auto-generated | BODY.PEEK[HEADER.FIELDS (AUTO-SUBMITTED)] | Normalize token such as no, auto-generated or auto-replied | Auto-Submitted | Useful standardized automation signal | Indicates automatically generated/submitted mail | Automated-message and autoresponder rates |
| Easy but inconsistent | bulk | BODY.PEEK[HEADER.FIELDS (PRECEDENCE)] | Normalize token | Precedence | Not a reliable signal on its own | Legacy/non-standard signal such as bulk, list or junk | Bulk/list classification statistics |
| Easy but sparse | Microsoft Outlook 16.0 | BODY.PEEK[HEADER.FIELDS (X-MAILER)] | Store normalized product string | X-Mailer | Can be absent or spoofed | Non-standard header identifying sending software | Mail-client/software distribution |
| Easy but sparse | Mozilla Thunderbird 128.0 | BODY.PEEK[HEADER.FIELDS (USER-AGENT)] | Store normalized product string | User-Agent | More common in some clients than others | Alternative header identifying composing/sending software | Mail-client/software distribution |
| Easy but sparse | high | BODY.PEEK[HEADER.FIELDS (IMPORTANCE)] | Normalize high/normal/low | Importance | Sender-controlled | Declared importance level | Priority-tag usage statistics |
| Easy but sparse | urgent | BODY.PEEK[HEADER.FIELDS (PRIORITY)] | Normalize value | Priority | Different clients use different headers | Declared message priority | Priority-tag usage statistics |
| Easy but sparse | 1 (Highest) | BODY.PEEK[HEADER.FIELDS (X-PRIORITY)] | Parse numeric priority where possible | X-Priority | Usually 1-5 when present | Legacy/non-standard priority indicator | Priority statistics across legacy clients |
| Easy but very sparse | Example Ltd | BODY.PEEK[HEADER.FIELDS (ORGANIZATION)] | Decode header text | Organization | Non-standard and not trustworthy for identity | Optional organization declared by sender/client | Organization statistics in datasets where populated |
| Very easy on Gmail | 1842456789012345678 | UID FETCH 12345 (X-GM-MSGID) | Parse unsigned 64-bit identity and serialize as decimal text; never a floating-point number | Gmail X-GM-MSGID | Requires Gmail IMAP extension | Gmail-specific globally stable message identifier | Reliable Gmail-side deduplication and API/IMAP correlation |
| Very easy on Gmail | 1842456000012345678 | UID FETCH 12345 (X-GM-THRID) | Parse unsigned 64-bit identity and serialize as decimal text; never a floating-point number | Gmail X-GM-THRID | Requires Gmail IMAP extension | Gmail's native conversation/thread identifier | Thread counts and messages-per-thread without reconstructing References |
| Very easy on Gmail | \Inbox \Important Work | UID FETCH 12345 (X-GM-LABELS) | Parse Gmail label list and modified UTF-7/UTF-8 as appropriate | Gmail X-GM-LABELS | Requires Gmail IMAP extension | Gmail labels associated with a message | Inbox/category/workflow/label distribution statistics |
| Very easy | example.com | From/Sender | Use the first valid From address in header order otherwise Sender; lowercase its domain | Derived sender domain | Derived field | Domain component of sender identity | Top domains, internal-vs-external mail, concentration metrics |
| Very easy | 6 | To + Cc (+ Bcc if actually present) | Count normalized unique recipient mailboxes | Derived recipient count | Visible headers do not reveal hidden SMTP recipients | Number of visible recipients | Distribution-list behavior, broad-vs-direct communication |
| Very easy | 2 | BODYSTRUCTURE | Count non-multipart parts with attachment disposition or a filename and no inline disposition | Derived attachment count | Classification requires a consistent heuristic | Number of attachments in a message | Attachment rate and attachments-per-message statistics |
| Easy | 5 | References | Count ordered valid References Message-ID tokens; use zero when absent | Derived thread depth | Malformed/missing References can reduce accuracy | Approximate depth of a reply chain | Conversation-depth and engagement statistics |
| Easy to compute; interpret carefully | 00:02:51 | Unambiguous Date header + INTERNALDATE | Compute internal_date minus sent_at in milliseconds; null if either timestamp is unavailable | Derived delivery delay | Sender clocks/timezones may be wrong, so outliers need care | Approximate time between sender timestamp and mailbox arrival | Latency distributions and unusual-delivery detection |
| Very easy | read | FLAGS | Check presence of \Seen | Derived read status | Not equivalent to proving the human actually read it | Whether IMAP considers the message seen | Read/unread rates by sender, folder or time period |
| Very easy | replied | FLAGS | Check presence of \Answered | Derived replied status | Clients/providers do not always maintain it perfectly | Whether the message has the IMAP answered flag | Reply-rate statistics |
| Easy | newsletter | List-ID + List-Unsubscribe + Precedence + Auto-Submitted | Combine multiple headers into a documented classification rule | Derived mailing-list/bulk signal | Use multiple signals rather than treating one header as definitive | Locally-derived indicator that a message is list/bulk/automated mail | Newsletter share, automated-vs-personal volume, sender segmentation |

### 02 Email Metadata Columns

Core columns, extensions, normalization, and compatible DuckDB/Parquet types. Source: [email_metadata_parquet_columns.csv](../design-meta/examples/metadata/email_metadata_parquet_columns.csv).

#### Email Metadata Columns

| category | column_id | column_name | description | duckdb_type | notes | nullable | parquet_type | schema_placement | source_information |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Schema | schema.version | schema_version | Schema version used to decode and migrate the row | INTEGER | Start at 1 and increment only for incompatible evolution | no | INT32 | core_column | Local |
| Schema | extensions.values | extensions | Stable envelope for provider-specific customer-specific and evolving metadata | JSON | Use an empty object or map when absent; keys are extension_key column_name values and values use canonical JSON encoding | no | MAP<STRING (UTF8), STRING (UTF8)> | core_column | Local |
| Identity | identity.account_id | account_id | Stable Core Data account UUID | VARCHAR | Part of both the mailbox-location key and provider correlation keys | no | STRING (UTF8) | core_column | Local |
| Identity | identity.mailbox_id | mailbox_id | Stable Core Data mailbox UUID | VARCHAR | The mailbox-location key is account_id, mailbox_id, uid_validity, and uid | no | STRING (UTF8) | core_column | Local |
| Identity | identity.mailbox_name | mailbox_name | IMAP mailbox name captured when the row is written | VARCHAR | Useful when files are inspected without the model store | no | STRING (UTF8) | core_column | Local |
| Identity | identity.uid_validity | uid_validity | IMAP UIDVALIDITY for the containing mailbox | BIGINT | Part of the durable message identity | no | INT64 | core_column | UIDVALIDITY |
| Identity | identity.uid | uid | Mailbox-local stable IMAP UID | BIGINT | Sequence number is intentionally excluded because it is transient | no | INT64 | core_column | UID |
| Partition | partition.month | partition_month | Calendar partition formatted as YYYY-MM | VARCHAR | Derive UTC YYYY-MM from the persisted canonical email_date; preserve it across metadata refreshes. | no | STRING (UTF8) | core_column | Canonical email_date |
| Capture | capture.fetched_at | metadata_fetched_at | When this metadata was most recently fetched from IMAP | TIMESTAMPTZ | Store UTC | no | TIMESTAMP(MICROS, isAdjustedToUTC=true) | core_column | Local |
| Capture | capture.first_seen_at | first_seen_at | When the message was first observed by SeleneTide | TIMESTAMPTZ | Store UTC and preserve across refreshes | no | TIMESTAMP(MICROS, isAdjustedToUTC=true) | core_column | Local |
| Capture | capture.updated_at | metadata_updated_at | When this Parquet row was most recently changed | TIMESTAMPTZ | Store UTC | no | TIMESTAMP(MICROS, isAdjustedToUTC=true) | core_column | Local |
| IMAP | imap.flags | flags | Normalized system flags and provider or user keywords | VARCHAR[] | Use an empty list rather than null | no | LIST<STRING (UTF8)> | core_column | FLAGS |
| IMAP | imap.internal_date | internal_date | Server delivery or storage timestamp normalized to UTC | TIMESTAMPTZ | Retain the original offset separately; null only when the server value is unavailable or invalid | yes | TIMESTAMP(MICROS, isAdjustedToUTC=true) | core_column | INTERNALDATE |
| IMAP | imap.internal_date_offset | internal_date_utc_offset_minutes | Original INTERNALDATE offset from UTC in minutes | INTEGER | Supports display and forensic analysis | yes | INT32 | core_column | INTERNALDATE |
| IMAP | imap.message_size | message_size_bytes | Approximate encoded RFC message size in bytes | BIGINT | May include headers body and encoded attachments | yes | INT64 | core_column | RFC822.SIZE |
| Envelope | envelope.sent_at | sent_at | Sender-supplied Date header normalized to UTC | TIMESTAMPTZ | Null when missing, invalid, or timezone-ambiguous; never assume the device timezone | yes | TIMESTAMP(MICROS, isAdjustedToUTC=true) | core_column | ENVELOPE Date |
| Envelope | envelope.sent_at_offset | sent_at_utc_offset_minutes | Original Date-header offset from UTC in minutes | INTEGER | Preserves the sender timezone offset | yes | INT32 | core_column | ENVELOPE Date |
| Envelope | envelope.subject | subject | Decoded message subject | VARCHAR | Decode RFC 2047 encoded words | yes | STRING (UTF8) | core_column | Subject |
| Envelope | envelope.from | from_addresses | Normalized author addresses | STRUCT(name VARCHAR, address VARCHAR)[] | Use an empty list when malformed or unavailable | no | LIST<STRUCT<name: STRING, address: STRING>> | core_column | From |
| Envelope | envelope.sender | sender_address | Agent that sent the message when distinct from From | STRUCT(name VARCHAR, address VARCHAR) | Often absent | yes | STRUCT<name: STRING, address: STRING> | core_column | Sender |
| Envelope | envelope.reply_to | reply_to_addresses | Normalized reply destination addresses | STRUCT(name VARCHAR, address VARCHAR)[] | Use an empty list when absent | no | LIST<STRUCT<name: STRING, address: STRING>> | core_column | Reply-To |
| Envelope | envelope.to | to_addresses | Normalized primary recipient addresses | STRUCT(name VARCHAR, address VARCHAR)[] | Does not expose hidden SMTP envelope recipients | no | LIST<STRUCT<name: STRING, address: STRING>> | core_column | To |
| Envelope | envelope.cc | cc_addresses | Normalized carbon-copy recipient addresses | STRUCT(name VARCHAR, address VARCHAR)[] | Use an empty list when absent | no | LIST<STRUCT<name: STRING, address: STRING>> | core_column | Cc |
| Envelope | envelope.bcc | bcc_addresses | Normalized Bcc addresses retained in the stored message | STRUCT(name VARCHAR, address VARCHAR)[] | Usually empty because delivery commonly removes this header | no | LIST<STRUCT<name: STRING, address: STRING>> | core_column | Bcc |
| Threading | thread.message_id | message_id | Canonical bracketed sender-generated message identifier | VARCHAR | Not guaranteed present or globally unique | yes | STRING (UTF8) | core_column | Message-ID |
| Threading | thread.in_reply_to | in_reply_to_message_ids | Referenced parent Message-ID values | VARCHAR[] | Use an empty list for root messages | no | LIST<STRING (UTF8)> | core_column | In-Reply-To |
| Threading | thread.references | reference_message_ids | Ordered ancestor Message-ID values | VARCHAR[] | Preserve header order | no | LIST<STRING (UTF8)> | core_column | References |
| MIME | mime.body_structure_raw | body_structure_raw | Original server BODYSTRUCTURE representation | VARCHAR | Optional diagnostic source for parser evolution | yes | STRING (UTF8) | extension_key | BODYSTRUCTURE |
| MIME | mime.parts | mime_parts | Normalized MIME tree nodes | STRUCT(part_id VARCHAR, parent_part_id VARCHAR, media_type VARCHAR, media_subtype VARCHAR, parameters MAP(VARCHAR, VARCHAR), disposition VARCHAR, filename VARCHAR, content_id VARCHAR, content_languages VARCHAR[], transfer_encoding VARCHAR, encoded_size_bytes BIGINT, is_multipart BOOLEAN, is_attachment BOOLEAN, is_inline BOOLEAN)[] | Parent identifiers preserve hierarchy; contains attachment metadata without content bytes | no | LIST<STRUCT<part_id: STRING, parent_part_id: STRING, media_type: STRING, media_subtype: STRING, parameters: MAP<STRING, STRING>, disposition: STRING, filename: STRING, content_id: STRING, content_languages: LIST<STRING>, transfer_encoding: STRING, encoded_size_bytes: INT64, is_multipart: BOOLEAN, is_attachment: BOOLEAN, is_inline: BOOLEAN>> | core_column | BODYSTRUCTURE |
| MIME | mime.part_count | mime_part_count | Number of MIME leaf parts | INTEGER | Derived from mime_parts | no | INT32 | core_column | BODYSTRUCTURE |
| MIME | mime.top_level_type | top_level_media_type | Normalized top-level media type such as multipart/mixed | VARCHAR | Exclude parameters from this value | yes | STRING (UTF8) | core_column | Top-level Content-Type |
| MIME | mime.top_level_parameters | top_level_content_parameters | Normalized top-level content-type parameters | MAP(VARCHAR, VARCHAR) | May include a boundary value; use an empty map when absent | no | MAP<STRING (UTF8), STRING (UTF8)> | core_column | Top-level Content-Type |
| MIME | mime.content_disposition | content_disposition | Normalized top-level disposition | VARCHAR | Part-level dispositions live in mime_parts | yes | STRING (UTF8) | core_column | Content-Disposition |
| MIME | mime.content_languages | content_languages | Normalized BCP 47 language tags | VARCHAR[] | Use an empty list when absent | no | LIST<STRING (UTF8)> | core_column | Content-Language |
| Routing | routing.return_path | return_path | Recorded envelope-return or bounce address | STRUCT(name VARCHAR, address VARCHAR) | Semantics depend on the receiving system | yes | STRUCT<name: STRING, address: STRING> | core_column | Return-Path |
| Routing | routing.delivered_to | delivered_to_addresses | Provider-recorded delivery aliases or mailbox addresses | STRUCT(name VARCHAR, address VARCHAR)[] | Provider-dependent and potentially repeated | no | LIST<STRUCT<name: STRING, address: STRING>> | extension_key | Delivered-To |
| Routing | routing.received | received_headers | Raw Received headers in message order | VARCHAR[] | Earlier hops are untrusted and may be forged | no | LIST<STRING (UTF8)> | core_column | Received |
| Routing | routing.received_hops | received_hops | Best-effort parsed delivery hops in message order | STRUCT(from_host VARCHAR, by_host VARCHAR, protocol VARCHAR, message_id VARCHAR, for_address VARCHAR, received_at TIMESTAMPTZ, raw_value VARCHAR)[] | Keep raw_value because Received syntax and trust vary | no | LIST<STRUCT<from_host: STRING, by_host: STRING, protocol: STRING, message_id: STRING, for_address: STRING, received_at: TIMESTAMP(MICROS, true), raw_value: STRING>> | extension_key | Received |
| Authentication | auth.results | authentication_results | Parsed email-authentication outcomes plus their raw values | STRUCT(authserv_id VARCHAR, method VARCHAR, result VARCHAR, properties MAP(VARCHAR, VARCHAR), raw_value VARCHAR)[] | Trust policy must identify the authoritative receiving server | no | LIST<STRUCT<authserv_id: STRING, method: STRING, result: STRING, properties: MAP<STRING, STRING>, raw_value: STRING>> | core_column | Authentication-Results |
| Authentication | auth.received_spf | received_spf | Parsed SPF result and original field value | STRUCT(result VARCHAR, raw_value VARCHAR) | Provider-dependent fallback when Authentication-Results is absent | yes | STRUCT<result: STRING, raw_value: STRING> | extension_key | Received-SPF |
| Authentication | auth.dkim | dkim_signatures | DKIM signing domains selectors algorithms identities and raw values | STRUCT(domain VARCHAR, selector VARCHAR, algorithm VARCHAR, identity VARCHAR, raw_value VARCHAR)[] | Signature presence does not prove successful validation | no | LIST<STRUCT<domain: STRING, selector: STRING, algorithm: STRING, identity: STRING, raw_value: STRING>> | core_column | DKIM-Signature |
| Mailing list | list.id | list_id | Mailing-list display name and identifier | STRUCT(name VARCHAR, identifier VARCHAR) | Strong list signal when present | yes | STRUCT<name: STRING, identifier: STRING> | core_column | List-ID |
| Mailing list | list.unsubscribe | list_unsubscribe_uris | Ordered mailto and HTTPS unsubscribe URIs | VARCHAR[] | Use an empty list when absent | no | LIST<STRING (UTF8)> | core_column | List-Unsubscribe |
| Mailing list | list.unsubscribe_post | list_unsubscribe_one_click | Whether RFC-style one-click unsubscribe is declared | BOOLEAN | False when absent | no | BOOLEAN | core_column | List-Unsubscribe-Post |
| Mailing list | list.post | list_post_uris | URIs used to submit mail to a list | VARCHAR[] | Use an empty list when absent | no | LIST<STRING (UTF8)> | extension_key | List-Post |
| Automation | automation.auto_submitted | auto_submitted | Normalized auto-submission token | VARCHAR | Examples include no auto-generated and auto-replied | yes | STRING (UTF8) | core_column | Auto-Submitted |
| Automation | automation.precedence | precedence | Normalized legacy precedence token | VARCHAR | Non-standard and insufficient alone for classification | yes | STRING (UTF8) | extension_key | Precedence |
| Client | client.x_mailer | x_mailer | Decoded sending-software identifier | VARCHAR | Untrusted and often absent | yes | STRING (UTF8) | extension_key | X-Mailer |
| Client | client.user_agent | user_agent | Decoded composing or sending client identifier | VARCHAR | Untrusted and often absent | yes | STRING (UTF8) | extension_key | User-Agent |
| Priority | priority.importance | importance | Normalized importance value | VARCHAR | Prefer high normal or low when recognizable | yes | STRING (UTF8) | core_column | Importance |
| Priority | priority.priority | priority | Normalized declared priority value | VARCHAR | Different clients use different vocabularies | yes | STRING (UTF8) | extension_key | Priority |
| Priority | priority.x_priority | x_priority | Parsed legacy numeric priority | INTEGER | Normally 1 through 5 when parseable | yes | INT32 | extension_key | X-Priority |
| Organization | organization.name | organization | Decoded sender-declared organization | VARCHAR | Non-standard sparse and untrusted | yes | STRING (UTF8) | extension_key | Organization |
| Provider | gmail.message_id | gmail_message_id | Gmail account-wide message correlation identifier | VARCHAR | Promoted to core because account_id plus gmail_message_id is an important cross-label join key; it does not replace the mailbox-location key | yes | STRING (UTF8) | core_column | Gmail X-GM-MSGID |
| Provider | gmail.thread_id | gmail_thread_id | Gmail native thread identifier | VARCHAR | Store as decimal text for lossless cross-tool compatibility | yes | STRING (UTF8) | extension_key | Gmail X-GM-THRID |
| Provider | gmail.labels | gmail_labels | Decoded Gmail labels | VARCHAR[] | Use an empty list for non-Gmail accounts | no | LIST<STRING (UTF8)> | extension_key | Gmail X-GM-LABELS |
| Derived | derived.sender_domain | sender_domain | Lowercased domain from normalized From or Sender address | VARCHAR | Use the first valid From address in header order, otherwise Sender; lowercase the domain and return null if neither has a valid domain. | yes | STRING (UTF8) | core_column | Derived sender domain |
| Derived | derived.recipient_domains | recipient_domains | Sorted unique lowercased domains from visible normalized recipient addresses | VARCHAR[] | Use an empty list when no valid recipient domain is available | no | LIST<STRING (UTF8)> | core_column | To + Cc + Bcc |
| Derived | derived.sent_hour_local | sent_hour_local | Hour of day from sent_at using the original sender offset | INTEGER | Range 0 through 23; null when Date or its offset is unavailable | yes | INT32 | core_column | ENVELOPE Date |
| Derived | derived.sent_weekday_local | sent_weekday_local | ISO weekday from sent_at using the original sender offset | INTEGER | Range 1 Monday through 7 Sunday | yes | INT32 | core_column | ENVELOPE Date |
| Derived | derived.arrival_hour_utc | arrival_hour_utc | Hour of day from internal_date normalized to UTC | INTEGER | Range 0 through 23; null when internal_date is unavailable | yes | INT32 | core_column | INTERNALDATE |
| Derived | derived.arrival_weekday_utc | arrival_weekday_utc | ISO weekday from internal_date normalized to UTC | INTEGER | Range 1 Monday through 7 Sunday; null when internal_date is unavailable | yes | INT32 | core_column | INTERNALDATE |
| Derived | derived.direction | message_direction | Message relationship to the account: inbound outbound self or unknown | VARCHAR | Compare normalized addresses with the configured primary account address; observed Delivered-To values are metadata and do not become trusted account aliases. | no | STRING (UTF8) | core_column | From + recipients + account identity |
| Derived | derived.recipient_count | recipient_count | Count of unique normalized visible To Cc and retained Bcc addresses | INTEGER | Does not include hidden SMTP recipients | no | INT32 | core_column | Derived recipient count |
| Derived | derived.to_recipient_count | to_recipient_count | Count of unique normalized To addresses | INTEGER | Useful for direct-versus-broadcast analysis | no | INT32 | core_column | To |
| Derived | derived.cc_recipient_count | cc_recipient_count | Count of unique normalized Cc addresses | INTEGER | Use zero when Cc is absent | no | INT32 | core_column | Cc |
| Derived | derived.attachment_count | attachment_count | Count of MIME parts classified as attachments | INTEGER | Count non-multipart parts with attachment disposition or a filename and no inline disposition; inline resources are excluded. | no | INT32 | core_column | Derived attachment count |
| Derived | derived.has_attachments | has_attachments | Whether attachment_count is greater than zero | BOOLEAN | Convenient for grouping and CSV exports | no | BOOLEAN | core_column | BODYSTRUCTURE |
| Derived | derived.attachment_size | attachment_encoded_size_bytes | Sum of encoded_size_bytes for parts classified as attachments | BIGINT | Use zero when none exist and null when any attachment size is unknown | yes | INT64 | core_column | BODYSTRUCTURE |
| Derived | derived.body_format | body_format | Primary body shape: plain html alternative mixed or other | VARCHAR | Classify top-level multipart/alternative as alternative and other multipart as mixed; otherwise text/plain as plain text/html as html and any other type as other. | no | STRING (UTF8) | core_column | BODYSTRUCTURE |
| Derived | derived.subject_length | subject_length_characters | Unicode character count of the decoded subject | INTEGER | Null when Subject is absent and zero when it is present but empty | yes | INT32 | core_column | Subject |
| Derived | derived.thread_depth | thread_depth | Approximate depth derived from ordered References | INTEGER | Count ordered valid References Message-ID tokens; use zero when absent. | no | INT32 | core_column | Derived thread depth |
| Derived | derived.delivery_delay | delivery_delay_milliseconds | internal_date minus sent_at in milliseconds | BIGINT | May be negative because sender clocks can be wrong | yes | INT64 | core_column | Derived delivery delay |
| Derived | derived.read_status | is_read | Whether FLAGS contains Seen | BOOLEAN | Does not prove that a human read the message | no | BOOLEAN | core_column | Derived read status |
| Derived | derived.replied_status | is_replied | Whether FLAGS contains Answered | BOOLEAN | Provider and client behavior may be imperfect | no | BOOLEAN | core_column | Derived replied status |
| Derived | derived.flagged_status | is_flagged | Whether FLAGS contains Flagged | BOOLEAN | Useful for measuring user-marked importance | no | BOOLEAN | core_column | FLAGS |
| Derived | derived.bulk_signal | bulk_classification | Documented classification from list and automation headers | VARCHAR | Use a versioned deterministic classifier | yes | STRING (UTF8) | core_column | Derived mailing-list/bulk signal |
| Derived | derived.bulk_signal_version | bulk_classification_version | Version of the bulk-classification rule | INTEGER | Required whenever bulk_classification is populated | yes | INT32 | core_column | Local |
| Capture | capture.source_version | source_version | Globally allocated immutable input snapshot revision | BIGINT | Allocate from AnalyticalRevisionSequence; preserve on replay and increase for new input or a correction. | no | INT64 | core_column | Core Data MetadataExportState |
| Partition | identity.email_date | email_date | Canonical UTC email date fixed on first successful capture | TIMESTAMPTZ | Choose INTERNALDATE then unambiguous sent_at then first metadata_fetched_at; preserve for the durable mailbox message identity. | no | TIMESTAMP(MICROS, isAdjustedToUTC=true) | core_column | INTERNALDATE + Date + first metadata_fetched_at |
| Partition | identity.email_date_source | email_date_source | Provenance of the fixed canonical UTC date | VARCHAR | internal_date sent_at or first_metadata_fetched_at | no | STRING (UTF8) | core_column | Local |

## 05 Email Processing and Swift Transformers

Code-defined processing graphs with durable results and restart recovery.

### 01 Email Processing Pipeline Rules

Dependency scheduling, official outcomes, retries, registry lookup, and result reuse. Source: [email_processing_pipeline_rules.csv](../design-meta/examples/processing/email_processing_pipeline_rules.csv).

#### Email Processing Pipeline Rules

| area | rationale | requirement | rule_id |
| --- | --- | --- | --- |
| Scope | Keeps the first version small and aligned with known transformations | Implement a fixed email-processing pipeline abstraction rather than a general-purpose workflow engine. | pipeline.scope |
| Pipeline | Avoids a dynamic workflow-definition database and makes invalid cycles testable before release | Declare the pipeline graph and step definitions in versioned Swift code and bind each step to one persisted transformerName. | pipeline.definition |
| Pipeline | Makes pending work and overall completion durable and inspectable | Create one EmailProcessingStep row for every step in the selected pipeline version when creating a job. | pipeline.instantiate |
| Dependencies | Provides explicit sequencing without persisting redundant graph definitions | Each code-defined step lists stable prerequisite step IDs and the pipeline definition must be acyclic. | pipeline.dependencies |
| Dependencies | Prevents consumers from observing missing inputs | A pending step becomes ready only after all declared prerequisites reach stable terminal outcomes and every required predecessor succeeded or reused a valid result; optional failed or skipped predecessors are allowed only by an explicit no-output input contract. | pipeline.ready |
| Dependencies | Supports parallel work without an external queue | Run independent ready steps concurrently subject to small execution-kind concurrency limits. | pipeline.parallel |
| Dependencies | Ensures the job reaches a deterministic terminal state | When a required prerequisite fails permanently mark dependent steps skipped with a dependency-failed reason. | pipeline.failure_propagation |
| Dependencies | Avoids accidental execution with incomplete inputs | A step may depend on an optional predecessor only when its input contract explicitly handles that predecessor producing no output. | pipeline.optional_dependency |
| State | Keeps overall state compact and represents missing implementations without treating them as execution failures | Use pending, running, blocked, succeeded, succeededWithWarnings, failed, and cancelled as job states. | state.job |
| State | Separates schedulable retry blocked configuration and terminal outcomes | Use pending, ready, running, retryWaiting, blocked, succeeded, failed, skipped, cancelled, and reused as step states. | state.step |
| Completion | Defines completion independently of optional failures | A job succeeds only when every instantiated step is terminal, every required step is succeeded or reused, and no optional step failed permanently. | state.success |
| Completion | Allows best-effort transformations without hiding their failures | A job succeedsWithWarnings only after every instantiated step is terminal, all required steps succeeded or reused, and one or more optional steps failed permanently. | state.warning |
| Completion | Provides a clear terminal rule | A required permanent failure prevents job success; skip failed dependents and cancel other unfinished work cooperatively before publishing the terminal failed job. | state.failure |
| Persistence | Prevents a terminal outcome from becoming visible without its complete result | Commit officialStatus customStatus statusMessage outputData output metadata timestamps and the resulting step state in one background-context save. | result.atomic_commit |
| Persistence | Keeps variable outputs flexible without adding a column for every transformation | Store small transformation-specific output as versioned canonical JSON or binary Data and enable Core Data external binary storage when appropriate. | result.encoding |
| Persistence | Keeps lifecycle fields queryable and migration-friendly | Store scheduler state official status transformer name attempts versions and timestamps as normal Core Data attributes rather than JSON or Data. | result.core_state |
| Persistence | Preserves efficient filtering joining and date-range queries | Do not hide accountID emailUID or emailDate inside JSON or Data. | result.query_boundary |
| Persistence | Keeps date-range queries deterministic when the Date header is missing or ambiguous | Copy the persisted canonical UTC email_date into emailDate; choose it once from INTERNALDATE, then unambiguous Date, then the first metadata_fetched_at and preserve it across refreshes. | result.email_date |
| Persistence | Avoids oversized database rows while keeping recovery explicit | Store very large disposable artifacts in managed files and persist only an integrity-checked relative locator when Core Data external binary storage is unsuitable. | result.large_artifacts |
| Retries | Custom statuses never control retry behavior | Treat the official retry status as retryable and the official failed status as permanent; map thrown infrastructure errors through the library failure classifier. | retry.classification |
| Retries | Survives restart and avoids synchronized retry storms | Apply bounded exponential backoff with jitter and persist attemptCount maximumAttempts and nextAttemptAt. | retry.policy |
| Retries | Prevents optional from meaning silently ignored | Apply the same bounded retry policy to optional steps before allowing succeededWithWarnings. | retry.optional |
| Idempotency | Makes replay safe | Local transformations must be deterministic for their declared input fingerprint and step version. | idempotency.local |
| Idempotency | Reduces duplicate external effects after a crash | Network or side-effecting steps must pass their persisted idempotencyKey when the remote system supports it and reconcile ambiguous outcomes before retrying. | idempotency.external |
| Crash recovery | Prevents concurrent execution in the normal single-process design | Resolve the persisted transformer name version and output schema before claiming; a scheduler actor sets running leaseOwner leaseExpiresAt and attemptCount in one Core Data save, and result commits are fenced by that claim. | recovery.lease |
| Crash recovery | Prevents healthy network or I/O work from being reclaimed | Long-running executors renew their lease before expiry while short transformations use a conservative fixed lease duration. | recovery.lease_renewal |
| Crash recovery | Makes interrupted work resumable | On startup return running steps with expired leases to ready or retryWaiting according to retry policy. | recovery.expired |
| Crash recovery | Avoids unnecessary repeated work | Never rerun a succeeded or reused step unless its step version input fingerprint or output schema is no longer valid. | recovery.completed |
| Crash recovery | Prevents partial data from being mistaken for a valid result | Discard or overwrite unpublished partial output before retry and expose output only after the atomic success save. | recovery.partial_output |
| Versioning | Identifies which orchestration contract created a job | Increment pipelineVersion when graph membership dependencies requiredness or overall completion semantics change. | version.pipeline |
| Versioning | Invalidates stale persisted results precisely | Increment stepVersion when transformation behavior or its output contract changes incompatibly. | version.step |
| Versioning | Separates storage compatibility from implementation changes | Increment outputSchemaVersion when the serialized output representation changes and provide decoding migration when reuse is allowed. | version.output |
| Result reuse | Prevents cross-message renamed-transformer or stale-input reuse | Reuse only a succeeded result matching account mailbox UIDVALIDITY UID transformerName stepVersion inputFingerprint and a supported outputSchemaVersion. | reuse.match |
| Result reuse | Keeps every pipeline execution complete and auditable | Create the new step row in reused state and link reusedFrom to the prior result rather than silently omitting the step. | reuse.record |
| Result reuse | Avoids references to missing or corrupted artifacts | Verify externally stored output still exists and matches its recorded integrity information before reuse. | reuse.validation |
| Core Data | Uses Apple-supported persistence without extra infrastructure | Use one NSPersistentContainer configured with the SQLite store and lightweight migration where compatible. | coredata.container |
| Core Data | Avoids blocking callers and respects managed-object queue confinement | Perform scheduler writes in private-queue background contexts and UI or CLI reads in separate contexts. | coredata.contexts |
| Core Data | Prevents Core Data concurrency violations | Pass NSManagedObjectID or immutable Sendable values across tasks and never pass NSManagedObject instances between queues. | coredata.objects |
| Core Data | Makes queue ownership explicit | Execute every managed-object access through its context perform or performAndWait API. | coredata.perform |
| Core Data | Keeps observers consistent when parallel steps finish | Use an explicit merge policy and automatically merge background saves into read contexts. | coredata.merge |
| Core Data | Avoids distributed locking complexity in v1 | Use a single in-process scheduler actor to select and claim work while allowing claimed transformations to execute concurrently. | coredata.scheduler |
| Indexes | Supports account-scoped and global date-range queries | Create a composite fetch index beginning with accountID and emailDate plus a standalone emailDate index. | index.date |
| Indexes | Supports joins and durable IMAP lookup | Index accountID plus emailUID and the full message identity on EmailProcessingJob and denormalized EmailProcessingStep fields; reuse indexes include transformerName stepVersion and inputFingerprint. | index.identity |
| Indexes | Keeps ready retry and expired-lease scans efficient | Index step state and nextAttemptAt, and index leaseExpiresAt for startup recovery. | index.scheduling |
| Uniqueness | Makes job creation idempotent | Apply one job uniqueness constraint over accountID mailboxID uidValidity emailUID pipelineID pipelineVersion and inputFingerprint. | constraint.job |
| Uniqueness | Prevents duplicate instantiated steps without relying on relationship constraints | Apply one step uniqueness constraint over denormalized jobID and stepID. | constraint.step |
| Uniqueness | Prevents duplicate claims for the same logical side effect | Make idempotencyKey unique and derive it deterministically from job identity step ID step version and input fingerprint. | constraint.idempotency |
| Transformers | Lets synchronous and asynchronous implementations share one scheduler path | Require every transformer to conform to the library EmailTransformer protocol with a unique non-empty stable string name and one consistent async callable surface. | transformer.interface |
| Transformers | Makes runtime resolution deterministic | Inject the complete transformer collection when initializing the library and build an immutable name-indexed registry before starting Core Data work. | transformer.registration |
| Transformers | Catches incomplete dependency injection before new jobs are accepted | At library initialization validate the pipeline DAG unique step IDs unique transformer names per pipeline positive Int32 versions and exact registered transformer version and output schema matches. | transformer.pipeline_validation |
| Transformers | Prevents ambiguous resume behavior | Reject library initialization when two registrations use the same transformer name or a name is empty or invalid. | transformer.duplicate |
| Transformers | Makes the Core Data row sufficient to locate executable code | Resolve every ready or resumed step solely by its exact persisted transformerName. | transformer.resolve |
| Transformers | Treats deployment or configuration drift as actionable rather than retryable work | When a persisted transformerName is not registered mark the step and job blocked with failureCode transformer.missing without incrementing attemptCount. | transformer.missing |
| Transformers | Prevents silent loss of resumability and accidental result reuse | Treat transformer names as durable identifiers that must not be renamed after release; an unavoidable rename requires an explicit Core Data migration from old name to new name before resuming. | transformer.rename |
| Transformers | Keeps lifecycle logic controlled by the library | Allow only succeeded, retry, failed, and skipped as official statuses; persist customStatus and statusMessage as optional annotations that never alter scheduling semantics. | transformer.status |
| Transformers | Makes every official result deterministic for the scheduler | Map succeeded to succeeded, retry to retryWaiting until attempts are exhausted, failed to failed, and skipped to skipped; treat skipped from a required step as a permanent transformer contract failure. | transformer.status_mapping |
| Transformers | Keeps registration and execution APIs uniform | Adapt synchronous transformers to the same async erased callable used by native async transformers. | transformer.sync |
| Maintenance | Bounds storage without breaking reuse links | Prune superseded jobs and unreferenced outputs only with an explicit retention policy after preserving the newest valid reusable results. | maintenance.history |
| Maintenance | Keeps deployment and recovery behavior local and understandable | Do not add CloudKit persistent history tracking an external broker or a separate workflow service in v1 unless a concrete requirement appears. | maintenance.no_extra_infra |
| Transformers | Never execute an old persisted contract with a new implementation | ProcessingStepDefinition.version and persisted stepVersion equal EmailTransformer.version; a resumed step whose registered version or output schema differs is blocked before claiming with transformer.version_mismatch or transformer.schema_mismatch. | transformer.version |
| Persistence | Avoids empty analytical output and broken reuse links | Copy the compatible reused output encoding schema and data or validated locator into the new step and retain reusedFrom for audit; a reused step remains self-contained for export. | result.reuse_copy |
| Persistence | An older job finishing later must not overwrite a newer accepted result | Reserve a globally increasing analytical revision when accepting new job inputs; carry that revision into their stable result export states and allocate a newer revision for explicit corrections. | result.revision |
| Scope | Keeps custom transformers compatible with metadataOnly sync | Automatic metadata workflows supply only normalized metadata and dependency outputs to transformers; fetching message bodies requires a separate explicit caller request. | result.metadata_boundary |
| Persistence | Identity and dependency outputs alone cannot supply headers to the first transformer | Accept a versioned immutable normalized metadata envelope with each job; persist its schema source revision managed relative locator and fingerprint before scheduling, verify the file before each execution, and supply it to every TransformerInput and StepExecutionContext. | input.metadata_snapshot |

### 02 Core Data Processing and Export Fields

Jobs, steps, persisted outputs, leases, and versioned export checkpoints. Source: [coredata_email_pipeline_fields.csv](../design-meta/examples/processing/coredata_email_pipeline_fields.csv).

#### Core Data Processing and Export Fields

| core_data_type | default_value | description | entity | field | field_id | indexes | relationship | required | uniqueness_group |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| UUID |  | Stable job identifier | EmailProcessingJob | id | processing_job.id | job_id |  | yes | job_id |
| String |  | Stable account identifier and first-class query field | EmailProcessingJob | accountID | processing_job.account_id | job_identity;account_email_date |  | yes | job_identity |
| String |  | Stable mailbox identifier because an IMAP UID is mailbox-local | EmailProcessingJob | mailboxID | processing_job.mailbox_id | job_identity |  | yes | job_identity |
| Integer 64 |  | IMAP UIDVALIDITY paired with the UID | EmailProcessingJob | uidValidity | processing_job.uid_validity | job_identity |  | yes | job_identity |
| Integer 64 |  | IMAP UID and first-class query field | EmailProcessingJob | emailUID | processing_job.email_uid | job_identity;account_uid |  | yes | job_identity |
| Date |  | Normalized UTC message date used for efficient date-range queries | EmailProcessingJob | emailDate | processing_job.email_date | account_email_date;email_date |  | yes |  |
| String | email-processing-v1 | Stable code-defined pipeline identifier | EmailProcessingJob | pipelineID | processing_job.pipeline_id | job_identity |  | yes | job_identity |
| Integer 32 | 1 | Version of the pipeline graph and completion rules | EmailProcessingJob | pipelineVersion | processing_job.pipeline_version | job_identity |  | yes | job_identity |
| String |  | Digest of the source inputs relevant to the pipeline | EmailProcessingJob | inputFingerprint | processing_job.input_fingerprint | job_identity |  | yes | job_identity |
| String | pending | Raw job-state enum | EmailProcessingJob | state | processing_job.state | job_state |  | yes |  |
| Integer 32 | 0 | Number of required steps instantiated for this job | EmailProcessingJob | requiredStepCount | processing_job.required_step_count |  |  | yes |  |
| Integer 32 | 0 | Required steps in a successful or valid reused state | EmailProcessingJob | completedRequiredStepCount | processing_job.completed_required_step_count |  |  | yes |  |
| Integer 32 | 0 | Optional steps that failed permanently, including non-retryable failures | EmailProcessingJob | failedOptionalStepCount | processing_job.failed_optional_step_count |  |  | yes |  |
| Date |  | Creation timestamp | EmailProcessingJob | createdAt | processing_job.created_at | created_at |  | yes |  |
| Date |  | Last durable state-change timestamp | EmailProcessingJob | updatedAt | processing_job.updated_at | updated_at |  | yes |  |
| Date |  | First execution timestamp | EmailProcessingJob | startedAt | processing_job.started_at |  |  | no |  |
| Date |  | Terminal completion timestamp | EmailProcessingJob | completedAt | processing_job.completed_at | completed_at |  | no |  |
| To-many EmailProcessingStep | [] | Instantiated transformation steps and their persisted outputs | EmailProcessingJob | steps | processing_job.steps |  | one-to-many; inverse=job; delete=cascade | yes |  |
| Integer 64 |  | Globally reserved revision allocated when accepting this job input snapshot before execution | EmailProcessingJob | sourceRevision | processing_job.source_revision |  |  | yes |  |
| Integer 32 |  | Schema used to decode the immutable normalized metadata input | EmailProcessingJob | metadataSchemaVersion | processing_job.metadata_schema_version |  |  | yes |  |
| Integer 64 |  | Globally allocated revision of the consumed metadata snapshot | EmailProcessingJob | metadataSourceVersion | processing_job.metadata_source_version |  |  | yes |  |
| String |  | Managed immutable metadata file retained while this job or its results can be resumed or reused | EmailProcessingJob | metadataRelativePath | processing_job.metadata_relative_path |  |  | yes |  |
| String |  | Digest verified before constructing TransformerInput.metadata | EmailProcessingJob | metadataFingerprint | processing_job.metadata_fingerprint |  |  | yes |  |
| UUID |  | Stable step-result identifier | EmailProcessingStep | id | processing_step.id | step_id |  | yes | step_id |
| To-one EmailProcessingJob |  | Owning email-processing job | EmailProcessingStep | job | processing_step.job |  | many-to-one; inverse=steps | yes |  |
| UUID |  | Denormalized job ID used by the Core Data uniqueness constraint | EmailProcessingStep | jobID | processing_step.job_id | step_identity |  | yes | step_identity |
| String |  | Stable code-defined transformation identifier | EmailProcessingStep | stepID | processing_step.step_id | step_identity;step_state |  | yes | step_identity |
| String |  | Exact unique registry name used to resolve the transformer after restart | EmailProcessingStep | transformerName | processing_step.transformer_name | transformer_name;result_reuse |  | yes |  |
| Integer 32 | 1 | Version declared by the registered transformer implementation | EmailProcessingStep | stepVersion | processing_step.step_version | result_reuse |  | yes |  |
| Boolean | true | Whether final job success requires this step | EmailProcessingStep | isRequired | processing_step.is_required |  |  | yes |  |
| String | local | Raw execution classification: local cpu io or network | EmailProcessingStep | executionKind | processing_step.execution_kind |  |  | yes |  |
| String | pending | Raw step-state enum | EmailProcessingStep | state | processing_step.state | step_state;retry_due |  | yes |  |
| String |  | Library-defined transformer outcome: succeeded retry failed or skipped | EmailProcessingStep | officialStatus | processing_step.official_status | official_status |  | no |  |
| String |  | Optional transformer-defined status for diagnostics and reporting only | EmailProcessingStep | customStatus | processing_step.custom_status | custom_status |  | no |  |
| String |  | Optional human-readable message returned by the transformer | EmailProcessingStep | statusMessage | processing_step.status_message |  |  | no |  |
| Integer 32 | 0 | Number of attempts claimed | EmailProcessingStep | attemptCount | processing_step.attempt_count |  |  | yes |  |
| Integer 32 | 1 | Maximum attempts including the first attempt | EmailProcessingStep | maximumAttempts | processing_step.maximum_attempts |  |  | yes |  |
| Date |  | Earliest retry time after backoff | EmailProcessingStep | nextAttemptAt | processing_step.next_attempt_at | retry_due |  | no |  |
| String |  | Identifier of the process currently executing the step | EmailProcessingStep | leaseOwner | processing_step.lease_owner |  |  | no |  |
| Date |  | Deadline after which a running step may be reclaimed | EmailProcessingStep | leaseExpiresAt | processing_step.lease_expires_at | expired_lease |  | no |  |
| String |  | Digest of the exact inputs consumed by this step | EmailProcessingStep | inputFingerprint | processing_step.input_fingerprint | result_reuse |  | yes |  |
| String |  | Stable key supplied to idempotent external side effects | EmailProcessingStep | idempotencyKey | processing_step.idempotency_key | idempotency_key |  | yes | idempotency_key |
| String |  | Raw enum such as json binary utf8 or none | EmailProcessingStep | outputEncoding | processing_step.output_encoding |  |  | no |  |
| Integer 32 |  | Version used to decode outputData | EmailProcessingStep | outputSchemaVersion | processing_step.output_schema_version |  |  | no |  |
| Binary Data |  | Persisted transformation output; enable external binary storage for larger values | EmailProcessingStep | outputData | processing_step.output_data |  |  | no |  |
| To-one EmailProcessingStep |  | Audit link to the original succeeded step; output is copied into the new step so export is self-contained | EmailProcessingStep | reusedFrom | processing_step.reused_from |  | self-reference; delete=nullify | no |  |
| String |  | Stable machine-readable failure code | EmailProcessingStep | failureCode | processing_step.failure_code | failure_code |  | no |  |
| String |  | Sanitized diagnostic message without credentials or unnecessary message content | EmailProcessingStep | failureMessage | processing_step.failure_message |  |  | no |  |
| Boolean | false | Whether policy permits another attempt | EmailProcessingStep | failureIsRetryable | processing_step.failure_is_retryable |  |  | yes |  |
| Date |  | Step creation timestamp | EmailProcessingStep | createdAt | processing_step.created_at |  |  | yes |  |
| Date |  | Last durable state-change timestamp | EmailProcessingStep | updatedAt | processing_step.updated_at | updated_at |  | yes |  |
| Date |  | Most recent attempt start timestamp | EmailProcessingStep | startedAt | processing_step.started_at |  |  | no |  |
| Date |  | Successful skipped or final-failure timestamp | EmailProcessingStep | finishedAt | processing_step.finished_at |  |  | no |  |
| To-one ProcessingResultExportState |  | Durable downstream-export checkpoint for this result | EmailProcessingStep | exportState | processing_step.export_state |  | one-to-one; inverse=step; delete=cascade | no |  |
| String |  | Denormalized immutable job field for direct identity date and reuse indexing; maintained in the same save | EmailProcessingStep | accountID | processing_step.account_id | step_message;step_account_date;result_reuse |  | yes |  |
| String |  | Denormalized immutable job field for direct identity date and reuse indexing; maintained in the same save | EmailProcessingStep | mailboxID | processing_step.mailbox_id | step_message;result_reuse |  | yes |  |
| Integer 64 |  | Denormalized immutable job field for direct identity date and reuse indexing; maintained in the same save | EmailProcessingStep | uidValidity | processing_step.uid_validity | step_message;result_reuse |  | yes |  |
| Integer 64 |  | Denormalized immutable job field for direct identity date and reuse indexing; maintained in the same save | EmailProcessingStep | emailUID | processing_step.email_uid | step_message;step_account_uid;result_reuse |  | yes |  |
| Date |  | Denormalized immutable job field for direct identity date and reuse indexing; maintained in the same save | EmailProcessingStep | emailDate | processing_step.email_date | step_account_date;step_email_date |  | yes |  |
| UUID |  | Stable export-state identifier | ProcessingResultExportState | id | result_export.id | result_export_id |  | yes | result_export_id |
| To-one EmailProcessingStep |  | Operational result being exported | ProcessingResultExportState | step | result_export.step |  | one-to-one; inverse=exportState | yes |  |
| URI |  | Permanent Core Data object URI for idempotent lookup and uniqueness | ProcessingResultExportState | stepObjectID | result_export.step_object_id | result_export_step |  | yes | result_export_step |
| String |  | Denormalized account key for efficient batch selection | ProcessingResultExportState | accountID | result_export.account_id | result_export_ready;result_export_identity |  | yes |  |
| String |  | Denormalized mailbox key because an IMAP UID is mailbox-local | ProcessingResultExportState | mailboxID | result_export.mailbox_id | result_export_identity |  | yes |  |
| Integer 64 |  | Denormalized IMAP UIDVALIDITY | ProcessingResultExportState | uidValidity | result_export.uid_validity | result_export_identity |  | yes |  |
| Integer 64 |  | Denormalized IMAP UID | ProcessingResultExportState | emailUID | result_export.email_uid | result_export_identity |  | yes |  |
| Date |  | Denormalized canonical UTC email date | ProcessingResultExportState | emailDate | result_export.email_date | result_export_ready |  | yes |  |
| String |  | Persisted transformer lookup and destination-key component | ProcessingResultExportState | transformerName | result_export.transformer_name | result_export_identity |  | yes |  |
| Integer 32 |  | Destination-key component and transformer contract version | ProcessingResultExportState | transformerVersion | result_export.transformer_version | result_export_identity |  | yes |  |
| Integer 64 |  | Reserved positive globally allocated revision of accepted job inputs or an explicit result correction; never reset across jobs | ProcessingResultExportState | sourceVersion | result_export.source_version | result_export_ready |  | yes |  |
| Integer 64 |  | Highest sourceVersion acknowledged after a DuckDB commit | ProcessingResultExportState | exportedVersion | result_export.exported_version |  |  | no |  |
| Integer 32 |  | Destination schema version used for the acknowledged export | ProcessingResultExportState | duckDBSchemaVersion | result_export.duckdb_schema_version |  |  | no |  |
| String | pending | Raw export state: pending exporting retryWaiting exported or blocked | ProcessingResultExportState | state | result_export.state | result_export_ready |  | yes |  |
| UUID |  | Current export batch claim identifier | ProcessingResultExportState | batchID | result_export.batch_id | result_export_batch |  | no |  |
| Integer 32 | 0 | Number of DuckDB export attempts | ProcessingResultExportState | attemptCount | result_export.attempt_count |  |  | yes |  |
| Integer 32 | 5 | Retry ceiling before manual intervention | ProcessingResultExportState | maximumAttempts | result_export.maximum_attempts |  |  | yes |  |
| Date |  | Earliest time for the next retry | ProcessingResultExportState | nextAttemptAt | result_export.next_attempt_at | result_export_ready |  | no |  |
| String |  | Exporter process currently owning the claim | ProcessingResultExportState | leaseOwner | result_export.lease_owner |  |  | no |  |
| Date |  | Deadline after which an unfinished claim may be replayed | ProcessingResultExportState | leaseExpiresAt | result_export.lease_expires_at | result_export_lease |  | no |  |
| Date |  | Timestamp of the latest acknowledged DuckDB commit | ProcessingResultExportState | exportedAt | result_export.exported_at | result_exported_at |  | no |  |
| String |  | Stable exporter failure code | ProcessingResultExportState | lastErrorCode | result_export.last_error_code | result_export_error |  | no |  |
| String |  | Sanitized exporter diagnostic | ProcessingResultExportState | lastErrorMessage | result_export.last_error_message |  |  | no |  |
| Date |  | Export-state creation timestamp | ProcessingResultExportState | createdAt | result_export.created_at |  |  | yes |  |
| Date |  | Last export-state mutation timestamp | ProcessingResultExportState | updatedAt | result_export.updated_at | result_export_updated |  | yes |  |
| UUID |  | Stable metadata-export checkpoint | MetadataExportState | id | metadata_export.id | metadata_export_id |  | yes | metadata_export_id |
| To-one SyncTask |  | Metadata fetch task that owns this immutable normalized snapshot | MetadataExportState | task | metadata_export.task |  | one-to-one; inverse=metadataExportState | yes |  |
| String |  | Owning account UUID encoded as a string | MetadataExportState | accountID | metadata_export.account_id | metadata_export_ready;metadata_export_identity |  | yes |  |
| String |  | Owning mailbox UUID encoded as a string | MetadataExportState | mailboxID | metadata_export.mailbox_id | metadata_export_identity |  | yes |  |
| Integer 64 |  | Mailbox generation | MetadataExportState | uidValidity | metadata_export.uid_validity | metadata_export_identity |  | yes |  |
| Integer 64 |  | Mailbox-local IMAP UID | MetadataExportState | uid | metadata_export.uid | metadata_export_identity |  | yes |  |
| Date |  | Persisted canonical UTC email date | MetadataExportState | emailDate | metadata_export.email_date | metadata_export_ready |  | yes |  |
| Integer 64 |  | Globally allocated revision reserved when accepting the fetched input snapshot | MetadataExportState | sourceVersion | metadata_export.source_version | metadata_export_ready |  | yes |  |
| Integer 32 | 1 | Normalized metadata file schema version | MetadataExportState | resultSchemaVersion | metadata_export.result_schema_version |  |  | yes |  |
| String |  | Integrity-checked file beneath the account intermediate directory | MetadataExportState | resultRelativePath | metadata_export.result_relative_path |  |  | yes |  |
| String |  | Digest of the immutable normalized metadata file | MetadataExportState | resultFingerprint | metadata_export.result_fingerprint |  |  | yes |  |
| String | pending | pending exporting retryWaiting exported or blocked | MetadataExportState | state | metadata_export.state | metadata_export_ready |  | yes |  |
| UUID |  | Current claim token used to fence acknowledgement and failure saves | MetadataExportState | batchID | metadata_export.batch_id | metadata_export_batch |  | no |  |
| Integer 32 | 0 | Claimed export attempts for this revision | MetadataExportState | attemptCount | metadata_export.attempt_count |  |  | yes |  |
| Integer 32 | 5 | Bounded retry ceiling | MetadataExportState | maximumAttempts | metadata_export.maximum_attempts |  |  | yes |  |
| Date |  | Backoff deadline | MetadataExportState | nextAttemptAt | metadata_export.next_attempt_at | metadata_export_ready |  | no |  |
| String |  | Owning exporter process session | MetadataExportState | leaseOwner | metadata_export.lease_owner |  |  | no |  |
| Date |  | Expired claim may be replayed | MetadataExportState | leaseExpiresAt | metadata_export.lease_expires_at | metadata_export_lease |  | no |  |
| Integer 64 |  | Highest acknowledged claimed revision | MetadataExportState | exportedVersion | metadata_export.exported_version |  |  | no |  |
| Integer 32 |  | Acknowledged email-metadata DuckDB schema version | MetadataExportState | duckDBSchemaVersion | metadata_export.duckdb_schema_version |  |  | no |  |
| Date |  | Core Data acknowledgement time following the DuckDB commit | MetadataExportState | exportedAt | metadata_export.exported_at |  |  | no |  |
| String |  | Stable metadata exporter error | MetadataExportState | lastErrorCode | metadata_export.last_error_code |  |  | no |  |
| String |  | Sanitized diagnostic | MetadataExportState | lastErrorMessage | metadata_export.last_error_message |  |  | no |  |
| Date |  | Checkpoint creation timestamp | MetadataExportState | createdAt | metadata_export.created_at |  |  | yes |  |
| Date |  | Last durable checkpoint mutation | MetadataExportState | updatedAt | metadata_export.updated_at |  |  | yes |  |
| Date |  | Initial metadata observation timestamp retained across refreshes | MetadataExportState | firstSeenAt | metadata_export.first_seen_at |  |  | yes |  |
| String |  | Canonical date provenance retained across refreshes: internal_date sent_at or first_metadata_fetched_at | MetadataExportState | emailDateSource | metadata_export.email_date_source |  |  | yes |  |
| String | analytics | Singleton shared Core Data analytical revision allocator | AnalyticalRevisionSequence | name | revision_sequence.name | revision_sequence |  | yes | revision_sequence |
| Integer 64 | 1 | Reserve and increment atomically with accepted inputs or corrections; block on Int64 exhaustion | AnalyticalRevisionSequence | nextValue | revision_sequence.next_value |  |  | yes |  |

### 03 Email Processing API Contract

Language-neutral pipeline definitions, requests, snapshots, and events. Source: [email-processing-pipeline-api.ts](../design-meta/examples/processing/email-processing-pipeline-api.ts).

#### Email Processing API Contract

```ts
/**
 * Language-neutral design reference for the Core Data email-processing
 * pipeline. Production code uses equivalent Swift Sendable values, actors,
 * async functions, and NSManagedObjectID boundaries.
 */

export type AccountID = string;
export type MailboxID = string;
export type ProcessingJobID = string;
export type ProcessingStepID = string;
export type ISO8601DateTime = string;

/** Same metadata-only envelope as the Swift transformer input. */
export interface NormalizedEmailMetadata {
  schemaVersion: number;
  /** Positive Int64 decimal string; identifies the accepted metadata snapshot. */
  sourceVersion: string;
  canonicalJSON: Uint8Array;
}

export interface ProcessableEmail {
  accountID: AccountID;
  mailboxID: MailboxID;
  uidValidity: number;
  emailUID: number;
  /** Persisted canonical UTC email_date; unchanged across metadata refreshes. */
  emailDate: ISO8601DateTime;
  /** Digest of the source data visible to the pipeline. */
  inputFingerprint: string;
}

export type ExecutionKind = "local" | "cpu" | "io" | "network";

export interface RetryPolicy {
  maximumAttempts: number;
  initialDelaySeconds: number;
  maximumDelaySeconds: number;
  multiplier: number;
  jitter: "full";
}

/** Static, code-defined configuration; this is not stored as dynamic workflow data. */
export interface ProcessingStepDefinition {
  id: ProcessingStepID;
  /** Exact durable lookup key in the injected transformer registry. */
  transformerName: string;
  /** Positive Int32; must equal the registered EmailTransformer.version. */
  version: number;
  outputSchemaVersion: number;
  required: boolean;
  executionKind: ExecutionKind;
  dependencyIDs: readonly ProcessingStepID[];
  retry: RetryPolicy;
}

export interface EmailPipelineDefinition {
  id: string;
  version: number;
  steps: readonly ProcessingStepDefinition[];
}

export type ProcessingJobState =
  | "pending"
  | "running"
  | "blocked"
  | "succeeded"
  | "succeededWithWarnings"
  | "failed"
  | "cancelled";

export type ProcessingStepState =
  | "pending"
  | "ready"
  | "running"
  | "retryWaiting"
  | "blocked"
  | "succeeded"
  | "failed"
  | "skipped"
  | "cancelled"
  | "reused";

export interface ProcessingJobSnapshot {
  jobID: ProcessingJobID;
  email: ProcessableEmail;
  pipelineID: string;
  pipelineVersion: number;
  /** Positive Int64 decimal string reserved before execution; never reset across jobs. */
  sourceRevision: string;
  state: ProcessingJobState;
  requiredStepCount: number;
  completedRequiredStepCount: number;
  failedOptionalStepCount: number;
  createdAt: ISO8601DateTime;
  updatedAt: ISO8601DateTime;
  completedAt?: ISO8601DateTime;
}

export interface ProcessingStepSnapshot {
  stepObjectID: string;
  jobID: ProcessingJobID;
  stepID: ProcessingStepID;
  transformerName: string;
  stepVersion: number;
  state: ProcessingStepState;
  required: boolean;
  attemptCount: number;
  maximumAttempts: number;
  nextAttemptAt?: ISO8601DateTime;
  reusedFromObjectID?: string;
  officialStatus?: TransformerOfficialStatus;
  customStatus?: string;
  statusMessage?: string;
  failureCode?: string;
  failureMessage?: string;
}

export type PersistedStepOutput =
  | { encoding: "none"; schemaVersion: number }
  | { encoding: "json"; schemaVersion: number; data: Uint8Array }
  | { encoding: "binary"; schemaVersion: number; data: Uint8Array }
  | { encoding: "utf8"; schemaVersion: number; data: Uint8Array };

export interface StepExecutionContext {
  job: ProcessingJobSnapshot;
  step: ProcessingStepSnapshot;
  idempotencyKey: string;
  metadata: NormalizedEmailMetadata;
  /**
   * Outputs for declared dependencies only. An optional failed/skipped
   * predecessor is absent only when the consumer explicitly allows no output.
   */
  dependencyOutputs: ReadonlyMap<ProcessingStepID, PersistedStepOutput>;
}

export type TransformerOfficialStatus =
  | "succeeded"
  | "retry"
  | "failed"
  | "skipped";

export interface TransformerExecutionResult {
  officialStatus: TransformerOfficialStatus;
  customStatus?: string;
  message?: string;
  output?: PersistedStepOutput;
}

export type ProcessingEvent =
  | { kind: "job-changed"; job: ProcessingJobSnapshot }
  | { kind: "step-changed"; step: ProcessingStepSnapshot };

export interface StartProcessingRequest {
  email: ProcessableEmail;
  /** Persist a verified managed-file locator before accepting the job. */
  metadata: NormalizedEmailMetadata;
  pipelineID: string;
  /** Reuse a matching existing job or create one idempotently. */
  ifExists: "reuse";
}

/**
 * A small actor-backed coordinator. Core Data remains the source of truth;
 * this interface does not imply an external queue or general workflow engine.
 */
export interface EmailProcessingPipeline {
  start(request: StartProcessingRequest): Promise<ProcessingJobSnapshot>;
  resume(jobID: ProcessingJobID): Promise<ProcessingJobSnapshot>;
  cancel(jobID: ProcessingJobID): Promise<ProcessingJobSnapshot>;
  status(jobID: ProcessingJobID): Promise<ProcessingJobSnapshot>;
  steps(jobID: ProcessingJobID): Promise<readonly ProcessingStepSnapshot[]>;
  events(jobID: ProcessingJobID): AsyncIterable<ProcessingEvent>;
}
```

### 04 Swift Transformer Contract

Typed Sendable transformers, erased registration, and official versus custom status. Source: [email-transformer.swift](../design-meta/examples/processing/email-transformer.swift).

#### Swift Transformer Contract

```txt
import Foundation

/// The only transformer outcomes that affect pipeline scheduling.
public enum TransformerOfficialStatus: String, Codable, Sendable {
    case succeeded
    case retry
    case failed
    case skipped
}

public enum PersistedTransformerOutput: Sendable {
    case none
    case json(Data)
    case binary(Data)
    case utf8(Data)
}

public struct TransformerResult<Output: Sendable>: Sendable {
    public let status: TransformerOfficialStatus
    public let customStatus: String?
    public let message: String?
    public let output: Output?

    public init(
        status: TransformerOfficialStatus,
        customStatus: String? = nil,
        message: String? = nil,
        output: Output? = nil
    ) {
        self.status = status
        self.customStatus = customStatus
        self.message = message
        self.output = output
    }
}

/// Normalized metadata only; message bodies and attachment bytes are excluded.
public struct NormalizedEmailMetadata: Sendable {
    public let schemaVersion: Int32
    public let sourceVersion: Int64
    public let canonicalJSON: Data
}

/// Immutable Sendable input assembled from Core Data and a verified metadata file.
public struct TransformerInput: Sendable {
    public let accountID: String
    public let mailboxID: String
    public let uidValidity: Int64
    public let emailUID: Int64
    public let emailDate: Date
    public let metadata: NormalizedEmailMetadata
    public let idempotencyKey: String
    public let dependencyOutputs: [String: PersistedTransformerOutput]
}

/// Strongly typed implementation interface.
public protocol EmailTransformer: Sendable {
    associatedtype Output: Sendable

    /// Durable identifier. Once released, changing this requires data migration.
    static var name: String { get }
    static var version: Int { get }
    static var outputSchemaVersion: Int { get }

    func transform(_ input: TransformerInput) async throws -> TransformerResult<Output>

    /// Converts typed output into the only transformer-specific persisted field.
    func encodeForPersistence(_ output: Output) throws -> PersistedTransformerOutput
}

/// Optional convenience protocol for implementations that do not suspend.
public protocol SynchronousEmailTransformer: EmailTransformer {
    func transformSynchronously(
        _ input: TransformerInput
    ) throws -> TransformerResult<Output>
}

public extension SynchronousEmailTransformer {
    func transform(_ input: TransformerInput) async throws -> TransformerResult<Output> {
        try transformSynchronously(input)
    }
}

/// Library-internal normalized result returned through the registry boundary.
public struct EncodedTransformerResult: Sendable {
    public let status: TransformerOfficialStatus
    public let customStatus: String?
    public let message: String?
    public let output: PersistedTransformerOutput
    public let outputSchemaVersion: Int
}

/// Type erasure keeps implementations strongly typed while allowing one registry.
public struct AnyEmailTransformer: Sendable {
    public let name: String
    public let version: Int
    public let outputSchemaVersion: Int

    private let run: @Sendable (TransformerInput) async throws -> EncodedTransformerResult

    public init<T: EmailTransformer>(_ transformer: T) {
        name = T.name
        version = T.version
        outputSchemaVersion = T.outputSchemaVersion
        run = { input in
            let result = try await transformer.transform(input)
            let output = try result.output.map(transformer.encodeForPersistence) ?? .none
            return EncodedTransformerResult(
                status: result.status,
                customStatus: result.customStatus,
                message: result.message,
                output: output,
                outputSchemaVersion: T.outputSchemaVersion
            )
        }
    }

    public func transform(_ input: TransformerInput) async throws -> EncodedTransformerResult {
        try await run(input)
    }
}

public enum TransformerRegistryError: Error, Equatable {
    case invalidName(String)
    case invalidVersion(String)
    case duplicateName(String)
    case missingTransformer(String)
    case incompatibleVersion(String, expected: Int, actual: Int)
    case incompatibleOutputSchema(String, expected: Int, actual: Int)
}

/// Immutable registry injected when the library is initialized.
public struct TransformerRegistry: Sendable {
    private let transformersByName: [String: AnyEmailTransformer]

    public init(_ transformers: [AnyEmailTransformer]) throws {
        var indexed: [String: AnyEmailTransformer] = [:]

        for transformer in transformers {
            let name = transformer.name
            guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TransformerRegistryError.invalidName(name)
            }
            guard transformer.version > 0, transformer.version <= Int(Int32.max),
                  transformer.outputSchemaVersion > 0,
                  transformer.outputSchemaVersion <= Int(Int32.max) else {
                throw TransformerRegistryError.invalidVersion(name)
            }
            guard indexed[name] == nil else {
                throw TransformerRegistryError.duplicateName(name)
            }
            indexed[name] = transformer
        }

        transformersByName = indexed
    }

    /// Resolve before claiming work; incompatible persisted contracts are blocked.
    public func resolve(
        name: String,
        version: Int,
        outputSchemaVersion: Int
    ) throws -> AnyEmailTransformer {
        guard let transformer = transformersByName[name] else {
            throw TransformerRegistryError.missingTransformer(name)
        }
        guard transformer.version == version else {
            throw TransformerRegistryError.incompatibleVersion(
                name, expected: version, actual: transformer.version
            )
        }
        guard transformer.outputSchemaVersion == outputSchemaVersion else {
            throw TransformerRegistryError.incompatibleOutputSchema(
                name, expected: outputSchemaVersion, actual: transformer.outputSchemaVersion
            )
        }
        return transformer
    }
}
```

## 06 DuckDB Projection and Parquet Archival

Transactional projections, commit-gap recovery, and verified archive publication.

### 01 DuckDB Exporter Rules

Eligibility, claims, idempotent upserts, acknowledgements, and archival recovery. Source: [duckdb_exporter_rules.csv](../design-meta/examples/storage/duckdb_exporter_rules.csv).

#### DuckDB Exporter Rules

| area | rationale | requirement | rule_id |
| --- | --- | --- | --- |
| Architecture | Prevents transformation code from owning analytical persistence or transaction policy | Implement DuckDBExporter as a dedicated actor or service that is separate from all transformers. | exporter.boundary |
| Architecture | Makes dual-store recovery deterministic | Keep Core Data as the operational source of truth and treat DuckDB rows as replayable downstream projections. | exporter.source_of_truth |
| Architecture | Keeps live analytics aligned with future Parquet files | Use the core and extension columns in email_metadata_parquet_columns.csv for the email_metadata_live DuckDB table. | exporter.metadata_schema |
| Architecture | Avoids changing the one-row-per-message grain of email metadata | Store processing results in a separate row-per-transformer table defined by duckdb_processing_export_tables.csv. | exporter.result_schema |
| Eligibility | Prevents analysis of results that may still change during ordinary execution | Export steps only after their parent job reaches succeeded succeededWithWarnings or failed. | eligibility.job |
| Eligibility | Limits exports to stable completed outcomes | Export terminal step states succeeded, reused, failed, and skipped; exclude pending running retryWaiting blocked and cancelled by default. | eligibility.step |
| Eligibility | Allows explicit corrections while retaining idempotency | Create or reset export state to pending whenever a stable step result receives a higher sourceVersion. | eligibility.version |
| Identity | Avoids collisions between mailboxes | Always use accountID mailboxID UIDVALIDITY and emailUID as the durable IMAP message key. | identity.message |
| Identity | Supports deterministic per-transformer upserts | Use the durable message key plus transformerName and transformerVersion as the processing-result conflict key. | identity.result |
| Batching | Bounds Core Data memory and DuckDB transaction duration | Make batch size configurable with a conservative default such as 250 results. | batch.configuration |
| Batching | Makes retries and diagnostics reproducible | Select eligible export states by emailDate accountID mailboxID uidValidity emailUID transformerName transformerVersion and sourceVersion. | batch.ordering |
| Batching | Prevents duplicate normal scheduling and makes claims recoverable | Claim a batch in one Core Data background-context save by setting exporting batchID leaseOwner leaseExpiresAt and incrementing attemptCount. | batch.claim |
| Batching | Prevents managed objects from crossing concurrency boundaries | Convert claimed managed objects into immutable Sendable row values inside their Core Data context before calling DuckDB. | batch.snapshot |
| Transactions | Avoids partially committed analytical batches | Execute all parameterized upserts for one batch inside a single DuckDB transaction and roll back the entire batch on any row failure. | transaction.duckdb |
| Transactions | Makes replay safe and prevents stale overwrites | Upsert only if the incoming sourceVersion is strictly newer; equal or newer destination versions are acknowledged no-ops, and equal versions must represent the same immutable snapshot. | transaction.conflict |
| Transactions | Records the downstream checkpoint only after durable destination success | After DuckDB commits acknowledge only the claimed source versions whose batchID still matches; leave a newer Core Data revision pending and never clear a replacement claim or correction. | transaction.ack |
| Crash recovery | Closes the unavoidable two-database commit gap without distributed transactions | If DuckDB commits but the Core Data acknowledgement does not then reclaim the expired Core Data batch and replay the same upserts. | recovery.commit_gap |
| Crash recovery | Allows recovery after the commit gap | Treat a replayed no-op upsert with an equal or newer destination sourceVersion as success and acknowledge it in Core Data. | recovery.verify |
| Crash recovery | Preserves the source-of-truth boundary | Never infer Core Data operational state from DuckDB and never roll Core Data back because DuckDB is unavailable. | recovery.no_reverse |
| Retries | Separates transient availability from operator-required failures | Retry DuckDB busy I/O interruption and transient filesystem failures with bounded exponential backoff; block schema corruption incompatible schema and invalid rows. | retry.classification |
| Retries | Allows other valid rows to progress without silently dropping data | When a deterministic row error prevents a batch commit isolate the bad row by splitting the batch and record its stable error. | retry.batch_split |
| Writing | Provides safe simple writes for v1 | Use prepared parameterized insert-on-conflict statements for normal batches and never construct SQL by interpolating values. | write.parameterized |
| Writing | Avoids premature bulk-ingestion complexity | Allow a future DuckDB appender path only after measured batch volume justifies it and preserve identical transaction and conflict semantics. | write.appender |
| Payloads | Balances queryability and output flexibility | Persist stable common analytical values as typed DuckDB columns and transformer-specific output as JSON when it is useful for analysis. | payload.columns |
| Payloads | Prevents unnecessary analytical database growth | Avoid exporting opaque binary output by default; include output_binary only when configured and analytically justified. | payload.binary |
| Concurrency | Matches DuckDB write behavior and simplifies ordering | Use one DuckDBExporter actor per account database with an explicit in-flight batch gate across awaits; the destination serializes writer transactions including metadata projection migrations and archive claims. | concurrency.actor |
| Concurrency | Preserves Core Data queue confinement | Use private-queue Core Data contexts and exchange only object IDs or immutable Sendable snapshots. | concurrency.coredata |
| Concurrency | Avoids readers observing half-applied maintenance | Allow DuckDB analytical readers while coordinating schema migration archive claims and writer transactions through the exporter layer. | concurrency.readers |
| Archive | Preserves recent queryability | Keep successfully projected rows in the live DuckDB tables until they are eligible for monthly Parquet archival. | archive.live |
| Archive | Creates a durable immutable archive snapshot | In one DuckDB transaction copy eligible live rows into the exporting table with an archive batch ID and remove those exact source versions from live. | archive.claim |
| Archive | Prevents archival from losing a concurrent correction | Upsert newer versions into live while an older snapshot is exporting; after a partition is committed route new revisions to correction overlays and preserve any newer live revisions until reconciled into that overlay. | archive.concurrent_update |
| Archive | Makes restart behavior independent of changing live rows | Write and verify Parquet exclusively from one archive batch in the exporting table. | archive.write |
| Archive | Ensures only successfully archived staging rows are deleted | After verified atomic Parquet publication commit the archive manifest and delete the corresponding exporting rows in one DuckDB transaction. | archive.success |
| Archive | Prevents data loss | On Parquet failure retain exporting rows and the batch manifest for retry. | archive.failure |
| Archive | Clarifies that deletion belongs to successful DuckDB to Parquet archival | Never delete newly projected live rows merely because the Core Data to DuckDB export succeeded. | archive.deletion_scope |
| Schema evolution | Makes migrations and replay compatibility observable | Version the DuckDB processing-result schema independently and store the applied version with each Core Data acknowledgement and archive manifest. | schema.version |
| Schema evolution | Prevents mixed-schema batches | Apply ordered transactional DuckDB migrations before claiming export work and stop export when the destination version is unsupported. | schema.migration |
| Schema evolution | Keeps the analytical schema stable | Prefer additive nullable analytical columns and keep transformer-specific evolution inside versioned JSON until a field is promoted. | schema.additive |
| Schema evolution | Allows direct DuckDB to Parquet projection | Preserve compatible core names and types in DuckDB and Parquet; convert extensions JSON into MAP<STRING, STRING> entries containing canonical JSON values, as for email metadata. | schema.parquet |
| Identity | Makes the existing row-per-transformer result key unambiguous | A pipeline uses each transformer name at most once; the analytical dataset keeps the latest accepted result for each message transformerName and transformerVersion rather than every historical pipeline execution. | identity.transformer |
| Versioning | Destination conflict keys can span multiple operational jobs | Allocate positive Int64 source revisions from the shared durable AnalyticalRevisionSequence before accepting a new input snapshot or correction; never reset the revision when a new job or step is created. | version.sequence |
| Batching | Prevents expired executors from clearing newer work | Claim leases cover all work in the batch or are renewed before expiry; acknowledgements and failure updates are fenced by batchID and claimed sourceVersion. | batch.lease |
| Retries | A secondary Core Data failure must not hide the primary export error | Attempt to persist the export failure without replacing the original error if that save fails; retain the durable claim for expiry-based recovery. | retry.failure_record |
| Archive | Moving rows to staging must not make queries lose messages | Include exporting snapshots in both logical datasets until Parquet is committed; deduplicate by complete logical key and newest sourceVersion across live exporting archive and correction rows. | archive.query_visibility |
| Archive | The two row grains cannot share one manifest path or schema field | Use separate dataset-specific archive batches manifests paths schema versions and counts for email_metadata and processing_results. | archive.dataset |
| Archive | Atomic filesystem publication and a DuckDB transaction are separate commits | Track exporting published committed and failed manifest states; after restart verify an already published file by digest schema and counts before committing its manifest and deleting staging. | archive.publish_gap |
| Archive | Prevents replacing a monthly file with only a subset of its rows | Initial archival publishes the complete claimed month per dataset; later replacement is correction compaction of the prior committed partition plus fixed overlay revisions, never a partial batch overwriting the full month. | archive.replace |
| Architecture | Separates the sample scope from the required complete period projection | Use MetadataExportState checkpoints for normalized metadata rows with the same claim revision acknowledgement and replay rules as ProcessingResultExportState; the Swift sample below demonstrates only processing-result export. | projection.metadata |
| Archive | One logical monthly file must not expose a replacement through an old committed manifest during the filesystem commit gap | Publish each archive or compaction to an immutable batch-specific Parquet path; in the manifest commit transaction mark exactly one generation current per dataset account mailbox month and retire the previous generation only after its readers release it. | archive.generations |

### 02 DuckDB Processing Export Tables

Live results, immutable exporting snapshots, and archive manifests. Source: [duckdb_processing_export_tables.csv](../design-meta/examples/storage/duckdb_processing_export_tables.csv).

#### DuckDB Processing Export Tables

| column_id | column_name | description | duckdb_type | key_role | nullable | source | tables |
| --- | --- | --- | --- | --- | --- | --- | --- |
| result.schema_version | schema_version | Destination processing-result schema version | INTEGER |  | no | Exporter | live\|exporting |
| result.account_id | account_id | Stable account identifier | VARCHAR | message_key;result_key | no | Core Data EmailProcessingJob | live\|exporting |
| result.mailbox_id | mailbox_id | Stable mailbox identifier required for IMAP UID identity | VARCHAR | message_key;result_key | no | Core Data EmailProcessingJob | live\|exporting |
| result.uid_validity | uid_validity | IMAP UIDVALIDITY | BIGINT | message_key;result_key | no | Core Data EmailProcessingJob | live\|exporting |
| result.email_uid | email_uid | Mailbox-local IMAP UID | BIGINT | message_key;result_key | no | Core Data EmailProcessingJob | live\|exporting |
| result.email_date | email_date | Canonical UTC email date for filtering and monthly archival | TIMESTAMPTZ |  | no | Core Data EmailProcessingJob | live\|exporting |
| result.pipeline_id | pipeline_id | Pipeline identifier that produced the result | VARCHAR |  | no | Core Data EmailProcessingJob | live\|exporting |
| result.pipeline_version | pipeline_version | Pipeline graph version | INTEGER |  | no | Core Data EmailProcessingJob | live\|exporting |
| result.job_id | job_id | Operational job identifier for traceability | UUID |  | no | Core Data EmailProcessingJob | live\|exporting |
| result.job_state | job_state | Stable terminal job state | VARCHAR |  | no | Core Data EmailProcessingJob | live\|exporting |
| result.job_completed_at | job_completed_at | Job terminal timestamp | TIMESTAMPTZ |  | no | Core Data EmailProcessingJob | live\|exporting |
| result.step_id | step_id | Pipeline node identifier | VARCHAR |  | no | Core Data EmailProcessingStep | live\|exporting |
| result.transformer_name | transformer_name | Durable transformer name | VARCHAR | result_key | no | Core Data EmailProcessingStep | live\|exporting |
| result.transformer_version | transformer_version | Transformer implementation version | INTEGER | result_key | no | Core Data EmailProcessingStep | live\|exporting |
| result.step_state | step_state | Stable terminal step state | VARCHAR |  | no | Core Data EmailProcessingStep | live\|exporting |
| result.official_status | official_status | Library-defined transformer status | VARCHAR |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.custom_status | custom_status | Optional transformer-defined analytical status | VARCHAR |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.status_message | status_message | Optional human-readable transformer message | VARCHAR |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.attempt_count | attempt_count | Attempts consumed by the stable result | INTEGER |  | no | Core Data EmailProcessingStep | live\|exporting |
| result.output_encoding | output_encoding | Persisted output encoding | VARCHAR |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.output_schema_version | output_schema_version | Transformer-specific output schema version | INTEGER |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.output_json | output_json | Transformer-specific JSON payload; core analytical state never belongs here | JSON |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.output_binary | output_binary | Non-JSON payload retained only when analytically justified | BLOB |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.failure_code | failure_code | Stable processing failure code | VARCHAR |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.failure_message | failure_message | Sanitized processing failure summary | VARCHAR |  | yes | Core Data EmailProcessingStep | live\|exporting |
| result.input_fingerprint | input_fingerprint | Digest of inputs consumed by the transformer | VARCHAR |  | no | Core Data EmailProcessingStep | live\|exporting |
| result.output_fingerprint | output_fingerprint | Digest of the exported payload | VARCHAR |  | yes | Exporter | live\|exporting |
| result.source_version | source_version | Globally allocated immutable accepted-result revision; shared sequence prevents resets across jobs | BIGINT | conflict_version | no | Core Data ProcessingResultExportState | live\|exporting |
| result.source_updated_at | source_updated_at | Last Core Data result update timestamp | TIMESTAMPTZ |  | no | Core Data EmailProcessingStep | live\|exporting |
| result.exported_from_core_data_at | exported_from_core_data_at | Exporter timestamp bound once for the batch before its upsert transaction; not the exact commit time | TIMESTAMPTZ |  | no | Exporter | live\|exporting |
| result.extensions | extensions | Future values as DuckDB JSON; Parquet uses a MAP of string keys to canonical JSON values | JSON |  | no | Exporter | live\|exporting |
| archive.batch_id | archive_batch_id | Stable DuckDB to Parquet archive batch identifier | UUID | archive_batch | no | Archive coordinator | exporting |
| archive.partition_month | archive_partition_month | UTC YYYY-MM target partition | VARCHAR | archive_partition | no | Archive coordinator | exporting |
| archive.claimed_at | archive_claimed_at | Time the live row was moved into the exporting table | TIMESTAMPTZ |  | no | Archive coordinator | exporting |
| archive.attempt_count | archive_attempt_count | Parquet archive attempts for this snapshot | INTEGER |  | no | Archive coordinator | exporting |
| archive.last_error | archive_last_error | Sanitized most recent archive failure | VARCHAR |  | yes | Archive coordinator | exporting |
| manifest.batch_id | batch_id | Stable archive batch identifier | UUID | primary_key | no | Archive coordinator | archive_manifest |
| manifest.account_id | account_id | Owning account | VARCHAR | partition_key | no | Archive coordinator | archive_manifest |
| manifest.mailbox_id | mailbox_id | Owning mailbox | VARCHAR | partition_key | no | Archive coordinator | archive_manifest |
| manifest.partition_month | partition_month | UTC YYYY-MM partition | VARCHAR | partition_key | no | Archive coordinator | archive_manifest |
| manifest.schema_version | schema_version | Parquet schema version | INTEGER |  | no | Archive coordinator | archive_manifest |
| manifest.state | state | Archive state: exporting published committed or failed | VARCHAR |  | no | Archive coordinator | archive_manifest |
| manifest.row_count | row_count | Verified complete output file row count; absent until write verification | BIGINT |  | yes | Archive coordinator | archive_manifest |
| manifest.parquet_relative_path | parquet_relative_path | Published path relative to the account folder | VARCHAR |  | yes | Archive coordinator | archive_manifest |
| manifest.parquet_sha256 | parquet_sha256 | Integrity digest of the published Parquet file | VARCHAR |  | yes | Archive coordinator | archive_manifest |
| manifest.created_at | created_at | Batch creation timestamp | TIMESTAMPTZ |  | no | Archive coordinator | archive_manifest |
| manifest.committed_at | committed_at | Verified publication timestamp | TIMESTAMPTZ |  | yes | Archive coordinator | archive_manifest |
| manifest.dataset | dataset | email_metadata or processing_results; each dataset has a separate manifest and path | VARCHAR | partition_key | no | Archive coordinator | archive_manifest |
| manifest.expected_batch_row_count | expected_batch_row_count | Claimed source rows expected in this batch; distinct from verified complete file row_count | BIGINT |  | no | Archive coordinator | archive_manifest |
| manifest.is_current | is_current | False until commit; exactly one committed manifest is current per dataset account mailbox month | BOOLEAN |  | no | Archive coordinator | archive_manifest |
| manifest.supersedes_batch_id | supersedes_batch_id | Previous current generation replaced by verified correction compaction; null for initial publication | UUID |  | yes | Archive coordinator | archive_manifest |

### 03 Swift DuckDB Exporter Contract

Actor boundary, immutable row snapshots, store protocols, and batch acknowledgements. Source: [duckdb-exporter.swift](../design-meta/examples/storage/duckdb-exporter.swift).

#### Swift DuckDB Exporter Contract

```txt
import CoreData
import Foundation

public struct DuckDBExporterConfiguration: Sendable {
    public let batchSize: Int
    public let maximumAttempts: Int
    public let leaseDuration: Duration

    public init(
        batchSize: Int = 250,
        maximumAttempts: Int = 5,
        leaseDuration: Duration = .seconds(120)
    ) {
        precondition(batchSize > 0)
        precondition(maximumAttempts > 0)
        precondition(leaseDuration > .zero)
        self.batchSize = batchSize
        self.maximumAttempts = maximumAttempts
        self.leaseDuration = leaseDuration
    }
}

/// Immutable projection assembled inside a Core Data context.
public struct DuckDBProcessingResultRow: Sendable {
    public let accountID: String
    public let mailboxID: String
    public let uidValidity: Int64
    public let emailUID: Int64
    public let emailDate: Date
    public let pipelineID: String
    public let pipelineVersion: Int32
    public let jobID: UUID
    public let jobState: String
    public let jobCompletedAt: Date
    public let stepID: String
    public let transformerName: String
    public let transformerVersion: Int32
    public let stepState: String
    public let officialStatus: String?
    public let customStatus: String?
    public let statusMessage: String?
    public let attemptCount: Int32
    public let outputEncoding: String?
    public let outputSchemaVersion: Int32?
    public let outputJSON: Data?
    public let outputBinary: Data?
    public let failureCode: String?
    public let failureMessage: String?
    public let inputFingerprint: String
    public let outputFingerprint: String?
    public let sourceVersion: Int64
    public let sourceUpdatedAt: Date
    public let extensionsJSON: Data
}

public struct DuckDBExportBatch: Sendable {
    public let id: UUID
    public let rows: [DuckDBProcessingResultRow]
}

public struct DuckDBExportReport: Sendable {
    public let batchID: UUID?
    public let selectedCount: Int
    public let committedCount: Int
    public let replayedCount: Int
}

/// Adapter implemented by the embedded DuckDB bridge.
public protocol DuckDBExportDestination: Sendable {
    /// Open/migrate/validate the destination before an operational claim is made.
    func prepareSchema() async throws -> Int32

    /// One parameterized transaction; return the number of inserted/changed rows.
    /// Equal/newer destination revisions are successful no-ops. Every row is
    /// acknowledged only after the transaction commits. The adapter serializes
    /// this writer with metadata projection, migrations, and archive claims.
    func upsertProcessingResults(
        _ rows: [DuckDBProcessingResultRow]
    ) async throws -> Int
}

/// Core Data remains authoritative; this store only manages export checkpoints.
public protocol ProcessingExportStateStore: Sendable {
    func claimBatch(
        limit: Int,
        maximumAttempts: Int,
        leaseDuration: Duration
    ) async throws -> DuckDBExportBatch?

    /// Acknowledge only batch.id and its immutable claimed source versions;
    /// preserve a newer revision as pending and never clear another batch claim.
    func acknowledge(
        batch: DuckDBExportBatch,
        duckDBSchemaVersion: Int32,
        exportedAt: Date
    ) async throws

    /// Fence by batch.id and sourceVersion; never overwrite a replacement claim.
    func recordFailure(
        batch: DuckDBExportBatch,
        error: Error
    ) async throws
}

public enum DuckDBExporterError: Error, Equatable {
    case batchInProgress
    case invalidDestinationCount(Int)
}

/// Processing-result export sketch. Period metadata export uses its own
/// MetadataExportState adapter with identical checkpoint and replay semantics.
public actor DuckDBExporter {
    private let stateStore: any ProcessingExportStateStore
    private let destination: any DuckDBExportDestination
    private let configuration: DuckDBExporterConfiguration
    private var batchInProgress = false

    public init(
        stateStore: any ProcessingExportStateStore,
        destination: any DuckDBExportDestination,
        configuration: DuckDBExporterConfiguration = .init()
    ) {
        self.stateStore = stateStore
        self.destination = destination
        self.configuration = configuration
    }

    /// Exports at most one batch. Replaying a claimed batch is always safe.
    public func exportNextBatch() async throws -> DuckDBExportReport {
        // An actor can reenter during awaits; retain this gate for the whole batch.
        guard !batchInProgress else { throw DuckDBExporterError.batchInProgress }
        batchInProgress = true
        defer { batchInProgress = false }

        let schemaVersion = try await destination.prepareSchema()
        guard let batch = try await stateStore.claimBatch(
            limit: configuration.batchSize,
            maximumAttempts: configuration.maximumAttempts,
            leaseDuration: configuration.leaseDuration
        ) else {
            return DuckDBExportReport(
                batchID: nil,
                selectedCount: 0,
                committedCount: 0,
                replayedCount: 0
            )
        }

        do {
            let committed = try await destination.upsertProcessingResults(batch.rows)
            guard (0...batch.rows.count).contains(committed) else {
                throw DuckDBExporterError.invalidDestinationCount(committed)
            }
            try await stateStore.acknowledge(
                batch: batch,
                duckDBSchemaVersion: schemaVersion,
                exportedAt: Date()
            )
            return DuckDBExportReport(
                batchID: batch.id,
                selectedCount: batch.rows.count,
                committedCount: committed,
                replayedCount: batch.rows.count - committed
            )
        } catch {
            let originalError = error
            do {
                try await stateStore.recordFailure(batch: batch, error: originalError)
            } catch {
                // The durable claim remains recoverable after lease expiry.
                // A failure to save diagnostics must not replace the primary error.
            }
            throw originalError
        }
    }
}
```

## 07 Constrained Analytics Queries

Logical datasets and a validated expression language compiled to parameterized SQL.

### 01 Query API Rules

Parsing, type checking, identifiers, bindings, aggregation, execution, and errors. Source: [query_api_rules.csv](../design-meta/examples/query/query_api_rules.csv).

#### Query API Rules

| area | rationale | requirement | rule_id |
| --- | --- | --- | --- |
| Request | Keeps the outer protocol deterministic | Accept exactly one JSON object and reject duplicate object keys trailing data and non-JSON numbers. | request.json |
| Request | Rejects accidental or future-unsafe behavior | Allow only from, select, where, group_by, having, order_by, limit, offset, values, relationships, count, and stats. | request.keys |
| Request | Makes projection semantics unambiguous | Choose exactly one result mode: rows through select or its safe default, count through count=true, or aggregate statistics through stats. | request.mode |
| Request | Prevents accidental exposure of large nested or extension columns | When rows mode omits select use the dataset's small configured default projection rather than SELECT *. | request.default_select |
| Identifiers | Provides one predictable lexical form | Require every dataset column alias relationship function aggregate and variable name to match [A-Za-z_][A-Za-z0-9_]*. | request.identifier |
| Identifiers | Prevents arbitrary SQL identifiers | Resolve every identifier through query_catalog.csv in the context where it appears. | request.catalog |
| Separation | Keeps validation responsibilities distinct | Treat JSON properties as query structure expression strings as logic catalog names as identifiers and values entries as literal data. | request.structure |
| Expressions | Defines a deliberately small language | Support identifiers, $variables, allow-listed function calls, not, and, or, comparisons, and parentheses only. | expression.grammar |
| Expressions | Makes expressions deterministic | Parse function calls and parentheses first, then comparisons, then not, then and, then or. | expression.precedence |
| Expressions | Excludes SQL fragments pattern syntax and implicit operators | Support only ==, !=, <, <=, >, >=, and in. | expression.comparisons |
| Expressions | Forces all literal data through values | Reject quoted strings numeric tokens boolean tokens null tokens array syntax and object syntax inside expressions. | expression.no_literals |
| Expressions | Separates bound data from identifiers | Parse $name as a variable node and require name to satisfy the identifier grammar. | expression.variable |
| Expressions | Avoids expression list literals and unbounded placeholder expansion | Require the right operand of in to be an array-valued variable with at least one value and a configured maximum length. | expression.in |
| Expressions | Prevents arbitrary DuckDB function execution | Allow function calls only when name arity argument types and expression context match the catalogue. | expression.function |
| Expressions | Bounds parser and compiler resource use | Reject expressions exceeding configured token node nesting or function-call limits. | expression.depth |
| AST | Makes accidental literal interpolation structurally difficult | Do not define a literal AST node. | ast.no_literal |
| AST | Supports precise safe diagnostics | Retain byte spans on every expression node. | ast.span |
| Validation | Catches misspellings and stale caller data | Require every referenced variable to exist in values and reject unused values by default. | validation.variables |
| Validation | Avoids relying on implicit DuckDB casts | Type-check comparisons functions and in arrays against catalog column types before SQL compilation. | validation.types |
| Validation | Keeps null semantics explicit | Use is_null(column) and is_not_null(column) for null tests because null literals are prohibited. | validation.null |
| Validation | Preserves SQL grouping correctness | In grouped queries require every non-aggregate output and order field to be a group_by field. | validation.group |
| Validation | Prevents row-level columns leaking into aggregate filters | Allow having to reference grouped identifiers and generated or explicit aggregate aliases only. | validation.having |
| Validation | Prevents hidden expensive sort expressions | Allow order_by fields only when they are selected grouped or produced aggregate aliases. | validation.order |
| Validation | Keeps joins reviewed and bounded | Accept only named catalog relationships and reject arbitrary join keys predicates and relationship cycles. | validation.relationship |
| Validation | Avoids accidental aggregate multiplication | Require explicit acknowledgement in configuration before count or stats traverses a one-to-many relationship. | validation.cardinality |
| Validation | Prevents nonsensical or unsupported aggregation | Validate every requested aggregate against the input column type and catalogue permissions. | validation.stats |
| Validation | Keeps aggregate literals parameterized | Require quantile probability to be a variable reference bound to one finite number between 0 and 1. | validation.quantile |
| Validation | Bounds output and avoids literal SQL interpolation | Bind limit and offset as non-negative safe integers, enforce configured maxima, and apply a default result-row limit to all modes. | validation.limit |
| Validation | Bounds memory and keeps bind types simple | Limit value count string length and in-array length and reject nested objects or arrays of arrays. | validation.values |
| Datasets | Prevents access outside fixed datasets | Never accept table names file paths glob patterns URLs or SQL in from. | dataset.logical |
| Datasets | Presents one current logical dataset | Resolve email_metadata across live exporting archived and correction rows; choose the newest sourceVersion per full message key before removing tombstones. | dataset.email |
| Datasets | Presents one stable transformer-result dataset | Resolve processing_results across live exporting archived and processing correction rows; choose newest sourceVersion per result key before removing tombstones. | dataset.processing |
| Datasets | Prevents path traversal and arbitrary file reads | Validate Parquet roots internally at initialization and read only paths from current committed manifests; pin file generations for active readers and never accept paths from query requests. | dataset.files |
| SQL compilation | Identifiers cannot be DuckDB parameters but remain safe through the catalogue | Emit only pre-resolved quoted column aliases fixed SQL mappings dataset relations aggregate mappings and relationship templates. | compile.identifiers |
| SQL compilation | Never interpolates literal values | Emit a positional placeholder for every scalar variable occurrence and append its typed value to bindings. | compile.variables |
| SQL compilation | Keeps in queries parameterized | Expand a validated array variable to positional placeholders or a bound DuckDB list operation without embedding its elements. | compile.in |
| SQL compilation | Applies the no-literal-interpolation rule consistently | Emit positional placeholders for limit and offset. | compile.limit |
| SQL compilation | Makes row count a first-class operation | Compile count=true to COUNT(*) AS count and include group_by dimensions ahead of it. | compile.count |
| SQL compilation | Makes result columns stable | Compile stats through fixed aggregate mappings with aliases column_function or a validated caller alias; aliases must match the identifier grammar and must not collide with grouped fields or other outputs. | compile.stats |
| SQL compilation | Prevents quantile arguments becoming SQL text | Compile quantile to quantile_cont(resolved_column, ?) with the probability supplied as a binding. | compile.quantile |
| SQL compilation | Prevents arbitrary order expressions | Emit only validated output identifiers and fixed ASC DESC NULLS FIRST LAST keywords. | compile.order |
| SQL compilation | Makes SQL semantics follow the validated tree | Parenthesize emitted logical and comparison nodes according to the AST rather than preserving user whitespace. | compile.parentheses |
| Execution | Reduces operational impact | Execute through a read-only analytical connection with statement timeout cancellation and result-row limits. | execute.readonly |
| Execution | Preserves confidentiality | Pass SQL and bindings separately through the DuckDB bridge and never log raw bound values by default. | execute.parameters |
| Errors | Supports programmatic handling and precise client feedback | Return a stable code stage safe message retryable flag and optional JSON Pointer expression name and byte span. | error.shape |
| Errors | Avoids leaking implementation details | Use query.syntax for invalid tokens grammar or prohibited literals and do not include generated SQL. | error.syntax |
| Errors | Keeps the allow-list boundary clear | Use query.unknown_identifier or query.disallowed_identifier without suggesting arbitrary database names. | error.identifier |
| Errors | Makes literal-data errors distinct from expression errors | Use query.missing_value query.unused_value query.value_type or query.value_limit for values failures. | error.binding |
| Errors | Separates transient execution from configuration faults | Map interruption and timeout to retryable errors and database corruption schema mismatch or invalid catalog state to non-retryable errors. | error.execution |
| Request | Documents the small implicit projection for both datasets | Define email_metadata default select as account_id mailbox_id uid_validity uid subject email_date; define processing_results default select as account_id mailbox_id uid_validity email_uid transformer_name transformer_version official_status. | request.defaults |
| Request | Avoids a default projection that cannot satisfy grouped-query validation | Grouped rows mode requires an explicit non-empty select containing only group_by fields; having is accepted only with non-empty group_by or an aggregate result mode. | request.grouped_rows |
| Validation | Makes the supplied JSON date-range examples type-correct | For a timestamp comparison parse the bound string as an unambiguous ISO 8601 instant, normalize to UTC and bind a typed timestamp; reject missing offsets rather than relying on DuckDB implicit casts. | validation.timestamp |
| Validation | Allows the supplied message_size_p95 alias without weakening column lookup | Caller aggregate aliases are output-local identifiers rather than permanent catalogue entries; resolve them only in having and order_by after checking collisions and identifier grammar. | validation.alias |
| Validation | Defines name resolution when both joined relations have account and mailbox fields | Relationship traversal retains the base dataset identifier namespace; v1 projects or filters only base catalogue fields and does not accept qualified or arbitrary joined-column names. | validation.relationship_scope |
| Datasets | An old archive row must not reappear after deletion | Select the winning version before testing its tombstone flag; do not remove deletion rows before deduplication, and reconcile message deletion into both email and processing overlays. | dataset.tombstone |
| Execution | Separates database row order from deterministic serializers | For repeatable exports require order_by and append full logical keys or grouped dimensions as stable tie-breakers; unspecified query order is not an export ordering guarantee. | result.order |
| Request | Defines invalid collection shapes that the language-neutral type sketches cannot exclude | Reject explicit empty select, empty stats, empty aggregate lists, duplicate projection or group fields, duplicate relationship names, count other than true, and colliding aggregate aliases. | request.collections |

### 02 Query Catalogue

Allowed datasets, fields, relationships, functions, and aggregates. Source: [query_catalog.csv](../design-meta/examples/query/query_catalog.csv).

#### Query Catalogue

| allowed_in | catalog_id | dataset | item_kind | name | notes | sql_mapping | value_type |
| --- | --- | --- | --- | --- | --- | --- | --- |
| from | dataset.email_metadata | email_metadata | dataset | email_metadata | Logical union of live and exporting snapshots archived Parquet and correction overlays; choose newest versions by message key before removing tombstones | registered_email_metadata_relation | row |
| from | dataset.processing_results | processing_results | dataset | processing_results | Logical union of live and exporting snapshots archived Parquet and processing correction overlays; newest versions selected and tombstones removed | registered_processing_results_relation | row |
| select\|where\|group_by\|having\|order_by | column.account_id | email_metadata | column | account_id | Stable account identifier | account_id | string |
| select\|where\|group_by\|having\|order_by | column.mailbox_id | email_metadata | column | mailbox_id | Stable mailbox identifier | mailbox_id | string |
| select\|where\|group_by\|order_by | column.mailbox_name | email_metadata | column | mailbox_name | User-visible mailbox name | mailbox_name | string |
| select\|where\|order_by | column.uid | email_metadata | column | uid | Mailbox-local IMAP UID | uid | integer |
| select\|where | column.uid_validity | email_metadata | column | uid_validity | IMAP UIDVALIDITY | uid_validity | integer |
| select\|where\|group_by\|having\|order_by | column.email_date | email_metadata | column | email_date | Persisted canonical UTC timestamp chosen once per message identity | email_date | timestamp |
| select\|where\|group_by\|having\|order_by | column.email_year | email_metadata | virtual_column | email_year | UTC calendar year of persisted email_date | year_of_canonical_email_date | integer |
| select\|where\|group_by\|having\|order_by | column.email_month | email_metadata | virtual_column | email_month | UTC YYYY-MM of persisted email_date | yyyy_mm_of_canonical_email_date | string |
| select\|where\|order_by | column.sent_at | email_metadata | column | sent_at | Parsed unambiguous sender Date | sent_at | timestamp |
| select\|where\|order_by | column.subject | email_metadata | column | subject | Decoded message subject | subject | string |
| select\|where\|group_by\|having\|order_by | column.sender_domain | email_metadata | column | sender_domain | Normalized lowercased sender domain | sender_domain | string |
| select\|where\|group_by\|having\|order_by\|stats | column.message_size | email_metadata | column | message_size_bytes | Encoded RFC message size | message_size_bytes | integer |
| select\|where\|group_by\|having\|order_by\|stats | column.attachment_count | email_metadata | column | attachment_count | Derived attachment count | attachment_count | integer |
| select\|where\|group_by\|having\|order_by\|stats | column.attachment_size | email_metadata | column | attachment_encoded_size_bytes | Total known encoded attachment size | attachment_encoded_size_bytes | integer |
| select\|where\|group_by\|having\|order_by | column.has_attachments | email_metadata | column | has_attachments | Whether the message has attachments | has_attachments | boolean |
| select\|where\|group_by\|having\|order_by\|stats | column.recipient_count | email_metadata | column | recipient_count | Unique visible recipient count | recipient_count | integer |
| select\|where\|group_by\|having\|order_by | column.message_direction | email_metadata | column | message_direction | inbound outbound self or unknown | message_direction | string |
| select\|where\|group_by\|having\|order_by | column.body_format | email_metadata | column | body_format | plain html alternative mixed or other | body_format | string |
| select\|where\|group_by\|having\|order_by | column.is_read | email_metadata | column | is_read | Derived Seen flag | is_read | boolean |
| select\|where\|group_by\|having\|order_by | column.is_replied | email_metadata | column | is_replied | Derived Answered flag | is_replied | boolean |
| select\|where\|group_by\|having\|order_by | column.is_flagged | email_metadata | column | is_flagged | Derived Flagged flag | is_flagged | boolean |
| select\|where\|group_by\|having\|order_by | column.bulk_classification | email_metadata | column | bulk_classification | Versioned bulk or mailing-list classification | bulk_classification | string |
| select\|where\|group_by\|having\|order_by\|stats | column.sent_hour | email_metadata | column | sent_hour_local | Sender-local hour 0 through 23 | sent_hour_local | integer |
| select\|where\|group_by\|having\|order_by\|stats | column.sent_weekday | email_metadata | column | sent_weekday_local | Sender-local ISO weekday 1 through 7 | sent_weekday_local | integer |
| select\|where\|group_by\|having\|order_by\|stats | column.delivery_delay | email_metadata | column | delivery_delay_milliseconds | Approximate delivery delay | delivery_delay_milliseconds | integer |
| select\|where\|group_by\|having\|order_by | processing.account_id | processing_results | column | account_id | Stable account identifier | account_id | string |
| select\|where\|group_by\|having\|order_by | processing.mailbox_id | processing_results | column | mailbox_id | Stable mailbox identifier | mailbox_id | string |
| select\|where\|order_by | processing.uid | processing_results | column | email_uid | Mailbox-local IMAP UID | email_uid | integer |
| select\|where\|group_by\|having\|order_by | processing.email_date | processing_results | column | email_date | Canonical UTC email date | email_date | timestamp |
| select\|where\|group_by\|having\|order_by | processing.transformer | processing_results | column | transformer_name | Durable transformer identifier | transformer_name | string |
| select\|where\|group_by\|having\|order_by | processing.transformer_version | processing_results | column | transformer_version | Transformer contract version | transformer_version | integer |
| select\|where\|group_by\|having\|order_by | processing.official_status | processing_results | column | official_status | Library-defined transformer status | official_status | string |
| select\|where\|group_by\|having\|order_by | processing.custom_status | processing_results | column | custom_status | Transformer-defined analytical status | custom_status | string |
| select\|where\|group_by\|having\|order_by\|stats | processing.attempt_count | processing_results | column | attempt_count | Attempts consumed by the stable result | attempt_count | integer |
| relationships | relationship.processing | email_metadata | relationship | processing_results | Named join on account_id, mailbox_id, uid_validity, and UID; may multiply email rows | fixed_message_key_join | one_to_many |
| relationships | relationship.email | processing_results | relationship | email_metadata | Named join back to the logical email dataset | fixed_message_key_join | many_to_one |
| where\|having | function.lower | * | function | lower | Exactly one string expression argument | lower | string |
| where\|having | function.is_null | * | function | is_null | Exactly one expression argument | is_null | boolean |
| where\|having | function.is_not_null | * | function | is_not_null | Exactly one expression argument | is_not_null | boolean |
| stats | aggregate.count | * | aggregate | count | Counts non-null column values; top-level count true uses COUNT(*) | count | integer |
| stats | aggregate.min | * | aggregate | min | Numeric timestamp or string where catalog permits | min | same_as_input |
| stats | aggregate.max | * | aggregate | max | Numeric timestamp or string where catalog permits | max | same_as_input |
| stats | aggregate.avg | * | aggregate | avg | Numeric columns only | avg | number |
| stats | aggregate.stddev | * | aggregate | stddev | Numeric columns only | stddev_samp | number |
| stats | aggregate.median | * | aggregate | median | Numeric columns only | median | number |
| stats | aggregate.quantile | * | aggregate | quantile | Numeric column plus a bound probability variable between 0 and 1 | quantile_cont | number |
| stats | aggregate.approx_distinct | * | aggregate | approx_distinct | Any scalar column | approx_count_distinct | integer |
| select\|where | processing.uid_validity | processing_results | column | uid_validity | IMAP UIDVALIDITY needed for durable message joins | uid_validity | integer |

### 03 Query API Contract

JSON requests, count/statistics modes, validation results, and execution errors. Source: [query-api.ts](../design-meta/examples/query/query-api.ts).

#### Query API Contract

```ts
/** JSON request contract for constrained DuckDB analytics. */

export type JSONScalar = string | number | boolean | null;
export type QueryValue = JSONScalar | readonly JSONScalar[];
export type QueryValues = Readonly<Record<string, QueryValue>>;

export type DatasetName = "email_metadata" | "processing_results";
export type SortDirection = "asc" | "desc";
export type NullOrdering = "first" | "last";

export interface OrderByItem {
  field: string;
  direction: SortDirection;
  nulls?: NullOrdering;
}

export type SimpleStat =
  | "count"
  | "min"
  | "max"
  | "avg"
  | "stddev"
  | "median"
  | "approx_distinct";

export type StatRequest =
  | SimpleStat
  | {
      function: SimpleStat;
      as?: string;
    }
  | {
      function: "quantile";
      /** Variable reference such as "$percentile"; never a literal. */
      probability: string;
      as?: string;
    };

export interface QueryBase {
  from: DatasetName;
  where?: string;
  group_by?: readonly string[];
  having?: string;
  order_by?: readonly OrderByItem[];
  /** Structural controls are bound as parameters, not interpolated into SQL. */
  limit?: number;
  offset?: number;
  values?: QueryValues;
  /** Optional allow-listed relationships; arbitrary join predicates do not exist. */
  relationships?: readonly string[];
}

export interface RowsQuery extends QueryBase {
  select?: readonly string[];
  count?: never;
  stats?: never;
}

export interface CountQuery extends QueryBase {
  count: true;
  select?: never;
  stats?: never;
}

export interface StatsQuery extends QueryBase {
  stats: Readonly<Record<string, readonly StatRequest[]>>;
  select?: never;
  count?: never;
}

export type QueryRequest = RowsQuery | CountQuery | StatsQuery;

export type SourceSpan = {
  start: number;
  end: number;
};

/** Expressions intentionally have no literal node. */
export type ExpressionAST =
  | { kind: "identifier"; name: string; span: SourceSpan }
  | { kind: "variable"; name: string; span: SourceSpan }
  | {
      kind: "function";
      name: string;
      arguments: readonly ExpressionAST[];
      span: SourceSpan;
    }
  | {
      kind: "not";
      operand: ExpressionAST;
      span: SourceSpan;
    }
  | {
      kind: "logical";
      operator: "and" | "or";
      left: ExpressionAST;
      right: ExpressionAST;
      span: SourceSpan;
    }
  | {
      kind: "comparison";
      operator: "==" | "!=" | "<" | "<=" | ">" | ">=" | "in";
      left: ExpressionAST;
      right: ExpressionAST;
      span: SourceSpan;
    };

export interface ValidatedQuery {
  request: QueryRequest;
  where?: ExpressionAST;
  having?: ExpressionAST;
  resolvedDataset: string;
  resolvedRelationships: readonly string[];
}

export interface CompiledDuckDBQuery {
  sql: string;
  /** Ordered values corresponding to DuckDB positional placeholders. */
  bindings: readonly DuckDBBindValue[];
  outputColumns: readonly string[];
}

/** Internal bridge values; timestamp strings are validated and tagged explicitly. */
export type DuckDBBindValue =
  | QueryValue
  | { kind: "timestamp"; utcISO8601: string };

export type QueryErrorStage =
  | "request"
  | "parse"
  | "validate"
  | "compile"
  | "execute";

export interface QueryError {
  code: string;
  stage: QueryErrorStage;
  message: string;
  /** JSON Pointer for structure errors, such as /values/year. */
  path?: string;
  expression?: "where" | "having";
  span?: SourceSpan;
  retryable: boolean;
}

export type QueryResult =
  | {
      ok: true;
      columns: readonly string[];
      rows: readonly Readonly<Record<string, JSONScalar | object>>[];
    }
  | { ok: false; error: QueryError };

export interface EmailAnalyticsQueryAPI {
  query(requestJSON: string): Promise<QueryResult>;
}
```

### 04 Email Query Examples

Concrete query requests and expected query behavior. Source: [email_query_examples.json](../design-meta/examples/query/email_query_examples.json).

#### Email Query Examples

```json
[
  {
    "name": "monthly_count_from_domain_this_year",
    "request": {
      "from": "email_metadata",
      "count": true,
      "where": "sender_domain == $domain and email_year == $year",
      "group_by": ["email_month"],
      "order_by": [{"field": "email_month", "direction": "asc"}],
      "values": {"domain": "company.com", "year": 2026}
    }
  },
  {
    "name": "emails_from_domain_in_period",
    "request": {
      "from": "email_metadata",
      "select": ["subject", "email_date", "sender_domain", "mailbox_name"],
      "where": "sender_domain == $domain and email_date >= $start and email_date < $end",
      "order_by": [{"field": "email_date", "direction": "desc"}],
      "limit": 100,
      "values": {
        "domain": "company.com",
        "start": "2026-01-01T00:00:00Z",
        "end": "2027-01-01T00:00:00Z"
      }
    }
  },
  {
    "name": "all_time_emails_from_domain",
    "request": {
      "from": "email_metadata",
      "select": ["subject", "email_date", "sender_domain", "mailbox_name"],
      "where": "sender_domain == $domain",
      "order_by": [{"field": "email_date", "direction": "desc"}],
      "limit": 100,
      "values": {"domain": "company.com"}
    }
  },
  {
    "name": "all_sender_domains",
    "request": {
      "from": "email_metadata",
      "count": true,
      "group_by": ["sender_domain"],
      "order_by": [{"field": "count", "direction": "desc"}],
      "limit": 1000,
      "values": {}
    }
  },
  {
    "name": "domain_counts_per_year",
    "request": {
      "from": "email_metadata",
      "count": true,
      "group_by": ["email_year", "sender_domain"],
      "order_by": [
        {"field": "email_year", "direction": "asc"},
        {"field": "count", "direction": "desc"}
      ],
      "limit": 10000,
      "values": {}
    }
  },
  {
    "name": "message_size_stats_for_domain",
    "request": {
      "from": "email_metadata",
      "stats": {
        "message_size_bytes": [
          "count",
          "min",
          "max",
          "avg",
          "stddev",
          "median",
          {"function": "quantile", "probability": "$percentile", "as": "message_size_p95"}
        ]
      },
      "where": "sender_domain == $domain",
      "values": {"domain": "company.com", "percentile": 0.95}
    }
  }
]
```

## 08 On-Demand Content

Explicit content downloads and disposable artifact retention.

### 01 On-Demand Email Fetch API

Message/MIME-part selection, transformation, progress, content leases, and cleanup. Source: [fetch-email-api.ts](../design-meta/examples/content/fetch-email-api.ts).

#### On-Demand Email Fetch API

```ts
/**
 * Language-neutral design reference for SeleneTide on-demand email fetching.
 *
 * TypeScript keeps the contract concise. The production API will use
 * equivalent Swift Sendable values, async functions, AsyncSequence events,
 * file URLs, and cooperative cancellation.
 */

import type {
  ISO8601DateTime,
  MessageIdentity,
} from "../sync/sync-api";

export type FetchID = string;
export type ContentLeaseID = string;
export type MIMEPartID = string;

/** Selection is explicit so metadata sync can never fetch content by accident. */
export type EmailContentSelection =
  | { kind: "raw-message" }
  | {
      kind: "body";
      preference: "plain-text" | "html" | "best-available";
      includeInlineResources: boolean;
    }
  | { kind: "mime-parts"; partIDs: readonly MIMEPartID[] }
  | { kind: "attachments"; attachmentIDs: readonly MIMEPartID[] | "all" };

export type ContentTransform =
  | { kind: "none" }
  | { kind: "extract-body"; output: "plain-text" | "html" }
  | { kind: "html-to-markdown" };

/**
 * TTL leases expire a positive number of seconds after successful publication.
 * While-in-use leases have no wall-clock expiry: callers release them, and
 * shutdown or recovery releases those owned by a terminated process session.
 */
export type TemporaryRetention =
  | { kind: "while-in-use" }
  | { kind: "time-to-live"; seconds: number };

export interface FetchEmailRequest {
  message: MessageIdentity;
  selection: EmailContentSelection;
  transform?: ContentTransform;
  retention: TemporaryRetention;

  /**
   * Positive safe-integer aggregate transfer limit. Reject known oversized
   * selections before transfer; enforce the same limit while streaming when
   * sizes are unknown, and remove unpublished files after exceeding it.
   */
  maximumBytes?: number;
}

export type FetchState =
  | "pending"
  | "fetching"
  | "processing"
  | "completed"
  | "failed"
  | "cancelled";

export interface FetchProgress {
  phase: "connecting" | "downloading" | "processing" | "publishing";
  receivedBytes: number;
  expectedBytes?: number;
}

export interface FetchSnapshot {
  fetchID: FetchID;
  message: MessageIdentity;
  state: FetchState;
  progress: FetchProgress;
  createdAt: ISO8601DateTime;
  startedAt?: ISO8601DateTime;
  finishedAt?: ISO8601DateTime;
  failure?: FetchFailure;
}

export interface FetchFailure {
  code:
    | "message-not-found"
    | "mailbox-identity-changed"
    | "part-not-found"
    | "size-limit-exceeded"
    | "authentication-failed"
    | "imap-protocol-error"
    | "network-error"
    | "storage-error"
    | "transform-error"
    | "content-expired"
    | "content-released"
    | "cancelled"
    | "unexpected";
  message: string;
  retryable: boolean;
}

export interface MIMEType {
  type: string;
  subtype: string;
  parameters: Readonly<Record<string, string>>;
}

export interface TemporaryArtifact {
  artifactID: string;
  role:
    | "raw-message"
    | "plain-text-body"
    | "html-body"
    | "markdown-body"
    | "inline-resource"
    | "attachment";
  mimeType: MIMEType;
  filename?: string;
  byteCount: number;

  /** Path relative to the owning account's temporary-content directory. */
  relativePath: string;

  /** IMAP section identifier when the artifact represents a MIME part. */
  partID?: MIMEPartID;
  contentID?: string;
  sha256?: string;
}

/**
 * A result owns a lease over published artifacts. Artifacts are complete and
 * atomically visible; partial downloads are never returned.
 */
export interface FetchedEmailContent {
  fetchID: FetchID;
  message: MessageIdentity;
  leaseID: ContentLeaseID;
  expiresAt?: ISO8601DateTime;
  artifacts: readonly TemporaryArtifact[];
}

export type FetchEvent =
  | { kind: "state-changed"; snapshot: FetchSnapshot }
  | { kind: "progress"; fetchID: FetchID; progress: FetchProgress }
  | {
      kind: "artifact-published";
      fetchID: FetchID;
      artifact: TemporaryArtifact;
    }
  | { kind: "warning"; fetchID: FetchID; code: string; message: string };

export interface CleanupReport {
  releasedLeaseIDs: readonly ContentLeaseID[];
  removedArtifactCount: number;
  reclaimedBytes: number;
}

export interface CleanupExpiredOptions {
  /** Also remove abandoned partial downloads older than this duration. */
  partialDownloadAgeSeconds: number;
}

export interface FetchEmailClient {
  /**
   * Starts a fetch and returns once its durable operation record exists in the
   * offline Core Data workflow store.
   */
  start(request: FetchEmailRequest): Promise<FetchSnapshot>;

  status(fetchID: FetchID): Promise<FetchSnapshot>;

  /** Emits the current snapshot followed by ordered events until termination. */
  events(fetchID: FetchID): AsyncIterable<FetchEvent>;

  /**
   * Returns content only after successful completion and while its lease is
   * active; throws content-expired/content-released for unavailable artifacts.
   */
  result(fetchID: FetchID): Promise<FetchedEmailContent>;

  /**
   * Cooperative cancellation discards unpublished partial content. Completed
   * operations remain completed; their published lease is released explicitly.
   */
  cancel(fetchID: FetchID): Promise<FetchSnapshot>;

  /** Releases one result and makes its artifacts eligible for removal. */
  release(leaseID: ContentLeaseID): Promise<CleanupReport>;

  /** Removes TTL-expired/prior-session while-in-use leases and abandoned partials. */
  cleanupExpired(options: CleanupExpiredOptions): Promise<CleanupReport>;
}

// Example: fetch selected attachments and release them after processing.
export async function withAttachments<T>(
  client: FetchEmailClient,
  message: MessageIdentity,
  attachmentIDs: readonly MIMEPartID[],
  use: (artifacts: readonly TemporaryArtifact[]) => Promise<T>,
): Promise<T> {
  const fetch = await client.start({
    message,
    selection: { kind: "attachments", attachmentIDs },
    transform: { kind: "none" },
    retention: { kind: "while-in-use" },
  });

  for await (const event of client.events(fetch.fetchID)) {
    if (event.kind !== "state-changed") continue;
    if (event.snapshot.state === "failed") {
      throw new Error(event.snapshot.failure?.message ?? "Fetch failed");
    }
    if (event.snapshot.state === "cancelled") {
      throw new Error("Fetch cancelled");
    }
    if (event.snapshot.state !== "completed") continue;

    const content = await client.result(fetch.fetchID);
    try {
      return await use(content.artifacts);
    } finally {
      await client.release(content.leaseID);
    }
  }

  throw new Error("Fetch event stream ended before completion");
}
```

### 02 Multipart Email Fixture

A complete sample email with plain text and HTML alternatives. Source: [simple_email_with_html.eml](../design-meta/examples/content/simple_email_with_html.eml).

#### Multipart Email Fixture

```txt
Delivered-To: bob@example.com
Return-Path: <alice@example.com>
From: Alice Example <alice@example.com>
To: Bob Example <bob@example.com>
Cc: team@example.com
Reply-To: alice@example.com
Subject: Hello
Date: Sun, 27 Sep 2026 09:34:00 +0100
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="gmail-boundary-001"

--gmail-boundary-001
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: 7bit

Hi Bob,

Just a quick hello.

Best,
Alice

--gmail-boundary-001
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: 7bit

<html>
  <body>
    <p>Hi Bob,</p>
    <p>Just a quick hello.</p>
    <p>Best,<br>Alice</p>
  </body>
</html>

--gmail-boundary-001--
```

