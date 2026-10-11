package flyb

// Canonical design model for the detailed specification and executive overview.
// Unsupported C-header/EML extensions use text symlinks in render-inputs/.
source: "selenetide-design"
name:   "SeleneTide Rust Library"
modules: ["core"]

// Shared statements keep the overview and detailed report aligned.
_libraryPurpose:   "SeleneTide is a portable Rust library that brings IMAP message metadata into durable local storage. A frontend backend retains a stateful session through a C ABI; CLI features are deferred."
_storageAuthority: "SQLite owns durable operational state, including plans, tasks, checkpoints, processing jobs, step results, and export claims. The caller supplies credentials, held only in session memory. Each account has its own analytical files and DuckDB database; DuckDB is a replayable projection of operational results, while Parquet holds verified historical datasets."

argumentRegistry: {
	version: "1"
	arguments: [{
		name:      "format-csv"
		valueType: "enum"
		scopes: ["note"]
		allowedValues: ["table", "raw"]
		defaultValue: "table"
	}]
}

reports: [{
	title:       "SeleneTide Rust Library Specification"
	filepath:    "../design/selenetide-specs.md"
	description: "Requirements, architecture, persistence, and API contracts assembled from doc/design-meta/examples."
	sections: [{
		title:       "01 Overview"
		description: "Purpose, Rust and C ABI conventions, and the relationship between the source artifacts."
		sections: [{
			title: "01 Library Scope"
			notes: ["selenetide.overview.scope"]
		}, {
			title: "02 Architecture Summary"
			notes: ["selenetide.overview.architecture"]
		}, {
			title: "03 Stateful Session and Authentication"
			description: "JSON payload contracts and exactly-one mechanism examples. Source: [session-api.ts](../design-meta/examples/api/session-api.ts)."
			notes: ["selenetide.api.session"]
		}, {
			title: "04 C ABI Contract"
			description: "Public handle and buffer ownership contract. Source: [selenetide.h](../design-meta/examples/api/selenetide.h)."
			notes: ["selenetide.api.c"]
		}, {
			title: "05 Session and Interop Rules"
			description: "Lifecycle, concurrency, authentication, ABI, and SQL mappings. Source: [session_rules.csv](../design-meta/examples/api/session_rules.csv)."
			notes: ["selenetide.api.rules"]
		}, {
			title: "06 Concept Registry and Selective Retrieval"
			description: "Canonical concepts shared across CSV rules, schemas, requirements, and tests. Source: [concepts.csv](../design-meta/examples/concepts.csv). See the [retrieval convention](../design-meta/README.md#selective-csv-retrieval) for rg commands; concept and optional tags columns render alongside existing fields."
			notes: ["selenetide.spec.concepts"]
		}]
	}, {
		title:       "02 Product Requirements"
		description: "Library scope, platform requirements, and practical uses."
		sections: [
			{
				title:       "01 Feature Requirements"
				description: "Required, recommended, and optional capabilities for the portable Rust library. Source: [features.csv](../design-meta/examples/requirements/features.csv)."
				notes: ["selenetide.product.features"]
			}, {
				title:       "02 Practical Use Cases"
				description: "User goals, inputs, outputs, and acceptance criteria. Source: [practical_use_cases.csv](../design-meta/examples/requirements/practical_use_cases.csv)."
				notes: ["selenetide.product.usecases"]
			},
		]
	}, {
		title:       "03 Architecture and Period Workflow"
		description: "Storage authority and durable orchestration across subsystem boundaries."
		sections: [
			{
				title:       "01 Datastores and Authority"
				description: "Physical layout, ownership, lifecycle, and recovery responsibilities. Source: [datastores.csv](../design-meta/examples/architecture/datastores.csv)."
				notes: ["selenetide.architecture.datastores"]
			}, {
				title:       "02 Library Processing Flows"
				description: "Initialization, recovery, and subsystem interaction sequences. Source: [library-processing-flows.ts](../design-meta/examples/architecture/library-processing-flows.ts)."
				notes: ["selenetide.architecture.flows"]
			}, {
				title:       "03 Period Workflow Stages"
				description: "The versioned task kinds, dependencies, fan-out, and durable completion gates. Source: [period_workflow_stages.csv](../design-meta/examples/sync/period_workflow_stages.csv)."
				notes: ["selenetide.workflow.stages"]
			}, {
				title:       "04 Period Workflow Rules"
				description: "UTC boundaries, stage gates, backpressure, retries, and completion. Source: [period_workflow_rules.csv](../design-meta/examples/sync/period_workflow_rules.csv)."
				notes: ["selenetide.workflow.rules"]
			}, {
				title:       "05 Account and Workflow Persistence Fields"
				description: "Logical persistence field shapes for accounts, plans, runs, tasks, checkpoints, and temporary content; SQLite storage follows the datastore and pipeline rules. Source: [sqlite_workflow_fields.csv](../design-meta/examples/sync/sqlite_workflow_fields.csv)."
				notes: ["selenetide.workflow.fields"]
			}, {
				title:       "06 Sync API Contract"
				description: "Planning, execution, resumption, cancellation, checkpoints, and progress events. Source: [sync-api.ts](../design-meta/examples/sync/sync-api.ts)."
				notes: ["selenetide.sync.api"]
			},
		]
	}, {
		title:       "04 IMAP Metadata and Schema"
		description: "Stable message identity and the shared live/archive metadata representation."
		sections: [
			{
				title:       "01 IMAP Email Metadata"
				description: "Header, MIME, provider, and derived metadata available without downloading bodies. Source: [imap_email_metadata.csv](../design-meta/examples/metadata/imap_email_metadata.csv)."
				notes: ["selenetide.metadata.imap"]
			}, {
				title:       "02 Email Metadata Columns"
				description: "Core columns, extensions, normalization, and compatible DuckDB/Parquet types. Source: [email_metadata_parquet_columns.csv](../design-meta/examples/metadata/email_metadata_parquet_columns.csv)."
				notes: ["selenetide.metadata.columns"]
			},
		]
	}, {
		title:       "05 Email Processing and Rust Transformers"
		description: "Code-defined processing graphs with durable results and restart recovery."
		sections: [
			{
				title:       "01 Email Processing Pipeline Rules"
				description: "Dependency scheduling, official outcomes, retries, registry lookup, and result reuse. Source: [email_processing_pipeline_rules.csv](../design-meta/examples/processing/email_processing_pipeline_rules.csv)."
				notes: ["selenetide.processing.rules"]
			}, {
				title:       "02 SQLite Processing and Export Fields"
				description: "Jobs, steps, persisted outputs, leases, and versioned export checkpoints. Source: [sqlite_email_pipeline_fields.csv](../design-meta/examples/processing/sqlite_email_pipeline_fields.csv)."
				notes: ["selenetide.processing.fields"]
			}, {
				title:       "03 Email Processing API Contract"
				description: "Language-neutral pipeline definitions, requests, snapshots, and events. Source: [email-processing-pipeline-api.ts](../design-meta/examples/processing/email-processing-pipeline-api.ts)."
				notes: ["selenetide.processing.api"]
			}, {
				title:       "04 Rust Transformer Contract"
				description: "Typed Send + Sync Rust transformers, erased registration, and official versus custom status. Source: [email-transformer.rs](../design-meta/examples/processing/email-transformer.rs)."
				notes: ["selenetide.processing.transformer"]
			},
		]
	}, {
		title:       "06 DuckDB Projection and Parquet Archival"
		description: "Transactional projections, commit-gap recovery, and verified archive publication."
		sections: [
			{
				title:       "01 DuckDB Exporter Rules"
				description: "Eligibility, claims, idempotent upserts, acknowledgements, and archival recovery. Source: [duckdb_exporter_rules.csv](../design-meta/examples/storage/duckdb_exporter_rules.csv)."
				notes: ["selenetide.export.rules"]
			}, {
				title:       "02 DuckDB Processing Export Tables"
				description: "Live results, immutable exporting snapshots, and archive manifests. Source: [duckdb_processing_export_tables.csv](../design-meta/examples/storage/duckdb_processing_export_tables.csv)."
				notes: ["selenetide.export.tables"]
			}, {
				title:       "03 Rust DuckDB Exporter Contract"
				description: "Serialized worker boundary, immutable row snapshots, store traits, and batch acknowledgements. Source: [duckdb-exporter.rs](../design-meta/examples/storage/duckdb-exporter.rs)."
				notes: ["selenetide.export.rust"]
			},
		]
	}, {
		title:       "07 Constrained Analytics Queries"
		description: "Logical datasets and a validated expression language compiled to parameterized SQL."
		sections: [
			{
				title:       "01 Query API Rules"
				description: "Parsing, type checking, identifiers, bindings, aggregation, execution, and errors. Source: [query_api_rules.csv](../design-meta/examples/query/query_api_rules.csv)."
				notes: ["selenetide.query.rules"]
			}, {
				title:       "02 Query Catalogue"
				description: "Allowed datasets, fields, relationships, functions, and aggregates. Source: [query_catalog.csv](../design-meta/examples/query/query_catalog.csv)."
				notes: ["selenetide.query.catalog"]
			}, {
				title:       "03 Query API Contract"
				description: "JSON requests, count/statistics modes, validation results, and execution errors. Source: [query-api.ts](../design-meta/examples/query/query-api.ts)."
				notes: ["selenetide.query.api"]
			}, {
				title:       "04 Email Query Examples"
				description: "Concrete query requests and expected query behavior. Source: [email_query_examples.json](../design-meta/examples/query/email_query_examples.json)."
				notes: ["selenetide.query.examples"]
			},
		]
	}, {
		title:       "08 On-Demand Content"
		description: "Explicit content downloads and disposable artifact retention."
		sections: [
			{
				title:       "01 On-Demand Email Fetch API"
				description: "Message/MIME-part selection, transformation, progress, content leases, and cleanup. Source: [fetch-email-api.ts](../design-meta/examples/content/fetch-email-api.ts)."
				notes: ["selenetide.content.api"]
			}, {
				title:       "02 Multipart Email Fixture"
				description: "A complete sample email with plain text and HTML alternatives. Source: [simple_email_with_html.eml](../design-meta/examples/content/simple_email_with_html.eml)."
				notes: ["selenetide.content.fixture"]
			},
		]
	}, {
		title:       "09 Test Plan"
		description: "Coarse-grained unit and integration suites to implement against the design contracts."
		sections: [{
			title: "01 Unit and Integration Test Catalogue"
			description: """
				Each row is a planned test suite with a stable ID, level, area, title, description, and specification note references. These entries describe coverage to implement; they do not report implemented or passing tests. Source: [test_catalog.csv](../design-meta/examples/testing/test_catalog.csv).

				Unit suites use controlled clocks, deterministic fixtures, and isolated collaborators. Integration suites exercise real temporary SQLite/DuckDB stores and filesystem artifacts, scripted IMAP/provider responses, and injected failures at persistence boundaries. Use caller-supplied test credentials for authentication checks; ordinary tests do not require personal accounts or live providers.

				Resource limits are parameters of the selected configuration. Tests for optional capabilities apply when those capabilities are implemented; migration, retention, provider setup, and platform tests need expectations from the remaining implementation decisions. The catalogue groups assertions into suites rather than prescribing one test method per row.
				"""
			notes: ["selenetide.testing.catalog"]
		}]
	}]
}, {
	title:       "SeleneTide Executive Overview"
	filepath:    "../design/overview.md"
	description: "Start here for the design, its essential rules, and links to implementation detail."
	sections: [
		{
			title:       "01 Purpose and Scope"
			description: """
\(_libraryPurpose)

The design supports multiple accounts, local metadata analytics, and resumable processing. Normal synchronization fetches headers, flags, dates, sizes, and MIME structure. Message bodies and attachments require an explicit on-demand request and remain disposable content. Session handles, JSON requests, operation IDs, and event polling form the C ABI model; the code examples describe contracts for the future implementation.

[Requirements and use cases](selenetide-specs.md#02-product-requirements).
"""
		},
		{
			title:       "02 Architecture and Ownership"
			description: """
\(_storageAuthority)

One application-local SQLite store isolates operational rows by account ID. Each account has separate analytical and artifact folders. An exclusive portable process writer lock coordinates backend processes; Rust workers coordinate concurrent work within the owning process. Temporary content has a separate lease-managed lifecycle.

[Datastores and authority](selenetide-specs.md#01-datastores-and-authority).
"""
		},
		{
			title: "03 Main Workflow"
			description: """
				**Plan → discover UIDs → fetch metadata → transform → project to DuckDB → verify → archive eligible months.**

				Plans, tasks, page cursors, leases, attempts, and results are durable. Independent message work runs with bounded concurrency. Required processing failures block period export. Open months and partial or multi-month date ranges complete after DuckDB verification; only complete closed UTC months instantiate archive stages. Archival claims immutable, queryable snapshots, verifies Parquet files, then commits manifests and finalizes staging.

				[Workflow stages](selenetide-specs.md#03-period-workflow-stages), [recovery rules](selenetide-specs.md#04-period-workflow-rules), and [archival](selenetide-specs.md#06-duckdb-projection-and-parquet-archival).
				"""
		},
		{
			title: "04 Critical Invariants"
			description: """
				- Message identity is account + mailbox + UIDVALIDITY + UID. Provider IDs correlate locations; sequence numbers never identify durable work.
				- Canonical UTC email dates and monthly partitions stay stable across refreshes, including fallback dates.
				- Transformers have durable names and compatible versions. Reuse requires matching inputs and supported outputs; terminal jobs have no unfinished steps.
				- Globally increasing source revisions prevent stale overwrites. Claims fence completion, and replay never loses newer work or double-counts progress.
				- Queries combine live rows, exporting snapshots, archives, and corrections. Choose the newest revision before removing tombstones.
				- Publish verified immutable file generations; retain the previous generation until replacement commits and readers release it. Secrets remain only in session memory.

				[Metadata schema](selenetide-specs.md#04-imap-metadata-and-schema), [processing rules](selenetide-specs.md#01-email-processing-pipeline-rules), and [export rules](selenetide-specs.md#01-duckdb-exporter-rules).
				"""
		},
		{
			title: "05 Public API Boundaries"
			description: """
				[Sync](selenetide-specs.md#06-sync-api-contract) separates planning, execution, resumption, cancellation, status, and events. [Processing](selenetide-specs.md#03-email-processing-api-contract) supplies immutable metadata to registered Rust transformers and persists their versioned outputs. [Queries](selenetide-specs.md#07-constrained-analytics-queries) accept fixed logical datasets and a constrained expression language, compiled to parameterized SQL. [Content fetching](selenetide-specs.md#01-on-demand-email-fetch-api) explicitly selects messages or MIME parts and owns their temporary leases.

				The backend opens one session, supplies configuration and account authentication, then reuses its handle for JSON calls. The session owns runtime workers, database connections, and IMAP authentication state. Long operations return IDs for polling, paginated results, and cooperative cancellation. Close drains workers, releases connections, and clears secrets; reopening retains durable work but requires fresh authentication. Optional UniFFI bindings may provide typed host conveniences over the same Rust model.
				"""
		},
		{
			title: "06 Open Decisions and Next Reading"
			description: """
				Implementation choices still include the minimum Rust version and target matrix, the embedded SQLite/DuckDB adapters and versions, optional UniFFI target bindings, resource ceilings, physical correction schemas, classification rules, retention, and migrations. Required-failure exclusions need a durable policy before being enabled.

				Use the [full specification](selenetide-specs.md) for implementation details and the [consistency review](../design-meta/consistency-review.md#remaining-implementation-choices) for unresolved decisions. This overview guides navigation; detailed rules, tables, and examples define the contract. Both reports are generated from the same flyb configuration.
				"""
		},
	]
}]

notes: [
	{
		name: "selenetide.spec.concepts"
		title: "Canonical Concept Registry"
		filepath: "examples/concepts.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name: "selenetide.api.c"
		title: "C ABI Contract"
		filepath: "render-inputs/selenetide.h.txt"
		labels: ["c", "example"]
	}, {
		name: "selenetide.api.rules"
		title: "Session and Interop Rules"
		filepath: "examples/api/session_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	}, {
		name: "selenetide.api.session"
		title: "Stateful Session and Authentication"
		filepath: "examples/api/session-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.architecture.datastores"
		title:    "Datastores and Authority"
		filepath: "examples/architecture/datastores.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.architecture.flows"
		title:    "Library Processing Flows"
		filepath: "examples/architecture/library-processing-flows.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.content.api"
		title:    "On-Demand Email Fetch API"
		filepath: "examples/content/fetch-email-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.content.fixture"
		title:    "Multipart Email Fixture"
		filepath: "render-inputs/simple_email_with_html.eml.txt"
		labels: ["email", "example"]
	},
	{
		name:     "selenetide.export.rules"
		title:    "DuckDB Exporter Rules"
		filepath: "examples/storage/duckdb_exporter_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.export.rust"
		title:    "Rust DuckDB Exporter Contract"
		filepath: "examples/storage/duckdb-exporter.rs"
		labels: ["example", "rust"]
	},
	{
		name:     "selenetide.export.tables"
		title:    "DuckDB Processing Export Tables"
		filepath: "examples/storage/duckdb_processing_export_tables.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.metadata.columns"
		title:    "Email Metadata Columns"
		filepath: "examples/metadata/email_metadata_parquet_columns.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.metadata.imap"
		title:    "IMAP Email Metadata"
		filepath: "examples/metadata/imap_email_metadata.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.overview.architecture"
		title:    "Storage and Workflow Boundaries"
		markdown: """
			\(_storageAuthority)

			A UTC period flows through planning, UID discovery, metadata fetch, per-email processing, DuckDB export and verification, then archive claim, write, publication, and finalization when eligible. Independent per-email work uses bounded concurrency. Archival normally applies to closed calendar months; open-period metadata remains queryable in DuckDB.

			Message fetch identity is account plus mailbox plus UIDVALIDITY plus UID. Provider message identifiers correlate mailbox locations. Canonical UTC email dates, source versions, and schema versions connect the operational, live, and archived representations.

			Queries resolve fixed logical datasets across live rows, queryable exporting snapshots, archives, and corrections. Select the newest source revision before removing tombstones. Downloaded message bodies and attachments belong to the separate on-demand content API and have explicit temporary retention.

			The sections below preserve the detailed tables and API examples. Their rules and field definitions specify each subsystem's completion and recovery behavior.
			"""
		labels: ["overview"]
	},
	{
		name:     "selenetide.overview.scope"
		title:    "Scope and Rust/C ABI Conventions"
		markdown: """
			\(_libraryPurpose)

			The specification covers account isolation and caller-supplied authentication; metadata-only synchronization; resumable period workflows; versioned per-email transformers; SQLite to DuckDB projection; monthly Parquet archival; constrained analytics; and explicitly requested temporary content.

			TypeScript files are language-neutral API sketches. The Rust core uses owned Send + Sync snapshots and session-owned workers. The public C ABI uses opaque session tokens and versioned UTF-8 JSON; host adapters map operation IDs and event polling to async conveniences. Rust examples define native transformer and exporter boundaries; they are design contracts rather than a complete library implementation.

			This document is generated from `doc/design-meta/app.cue` and every source example. Edit those sources and regenerate with `flyb validate --config doc/design-meta` followed by `flyb generate markdown --config doc/design-meta`.

			The [consistency review](../design-meta/consistency-review.md) records resolved contradictions and remaining implementation choices.
			"""
		labels: ["overview"]
	},
	{
		name:     "selenetide.processing.api"
		title:    "Email Processing API Contract"
		filepath: "examples/processing/email-processing-pipeline-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.processing.fields"
		title:    "SQLite Processing and Export Fields"
		filepath: "examples/processing/sqlite_email_pipeline_fields.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.processing.rules"
		title:    "Email Processing Pipeline Rules"
		filepath: "examples/processing/email_processing_pipeline_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.processing.transformer"
		title:    "Rust Transformer Contract"
		filepath: "examples/processing/email-transformer.rs"
		labels: ["example", "rust"]
	},
	{
		name:     "selenetide.product.features"
		title:    "Feature Requirements"
		filepath: "examples/requirements/features.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.product.usecases"
		title:    "Practical Use Cases"
		filepath: "examples/requirements/practical_use_cases.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.query.api"
		title:    "Query API Contract"
		filepath: "examples/query/query-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.query.catalog"
		title:    "Query Catalogue"
		filepath: "examples/query/query_catalog.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.query.examples"
		title:    "Email Query Examples"
		filepath: "examples/query/email_query_examples.json"
		labels: ["example", "json"]
	},
	{
		name:     "selenetide.query.rules"
		title:    "Query API Rules"
		filepath: "examples/query/query_api_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.sync.api"
		title:    "Sync API Contract"
		filepath: "examples/sync/sync-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.testing.catalog"
		title:    "Planned Unit and Integration Test Suites"
		filepath: "examples/testing/test_catalog.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example", "testing"]
	},
	{
		name:     "selenetide.workflow.fields"
		title:    "Account and Workflow Persistence Fields"
		filepath: "examples/sync/sqlite_workflow_fields.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.workflow.rules"
		title:    "Period Workflow Rules"
		filepath: "examples/sync/period_workflow_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.workflow.stages"
		title:    "Period Workflow Stages"
		filepath: "examples/sync/period_workflow_stages.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
]

relationships: [
	{
		from:  "selenetide.architecture.flows"
		to:    "selenetide.architecture.datastores"
		label: "uses"
		labels: ["uses"]
	},
	{
		from:  "selenetide.architecture.flows"
		to:    "selenetide.workflow.stages"
		label: "describes"
		labels: ["describes"]
	},
	{
		from:  "selenetide.content.fixture"
		to:    "selenetide.content.api"
		label: "illustrates"
		labels: ["illustrates"]
	},
	{
		from:  "selenetide.export.rules"
		to:    "selenetide.export.tables"
		label: "projects_into"
		labels: ["projects_into"]
	},
	{
		from:  "selenetide.export.rules"
		to:    "selenetide.metadata.columns"
		label: "shares_schema"
		labels: ["shares_schema"]
	},
	{
		from:  "selenetide.export.rules"
		to:    "selenetide.processing.fields"
		label: "reads"
		labels: ["reads"]
	},
	{
		from:  "selenetide.export.rust"
		to:    "selenetide.export.rules"
		label: "implements"
		labels: ["implements"]
	},
	{
		from:  "selenetide.metadata.columns"
		to:    "selenetide.metadata.imap"
		label: "normalizes"
		labels: ["normalizes"]
	},
	{
		from:  "selenetide.processing.api"
		to:    "selenetide.processing.rules"
		label: "governed_by"
		labels: ["governed_by"]
	},
	{
		from:  "selenetide.processing.rules"
		to:    "selenetide.processing.fields"
		label: "persisted_in"
		labels: ["persisted_in"]
	},
	{
		from:  "selenetide.processing.transformer"
		to:    "selenetide.processing.rules"
		label: "implements"
		labels: ["implements"]
	},
	{
		from:  "selenetide.product.usecases"
		to:    "selenetide.product.features"
		label: "motivates"
		labels: ["motivates"]
	},
	{
		from:  "selenetide.query.api"
		to:    "selenetide.query.rules"
		label: "governed_by"
		labels: ["governed_by"]
	},
	{
		from:  "selenetide.query.catalog"
		to:    "selenetide.export.tables"
		label: "exposes"
		labels: ["exposes"]
	},
	{
		from:  "selenetide.query.catalog"
		to:    "selenetide.metadata.columns"
		label: "exposes"
		labels: ["exposes"]
	},
	{
		from:  "selenetide.query.examples"
		to:    "selenetide.query.api"
		label: "illustrates"
		labels: ["illustrates"]
	},
	{
		from:  "selenetide.query.rules"
		to:    "selenetide.query.catalog"
		label: "validates_against"
		labels: ["validates_against"]
	},
	{
		from:  "selenetide.sync.api"
		to:    "selenetide.content.api"
		label: "separates_content_fetch"
		labels: ["separates_content_fetch"]
	},
	{
		from:  "selenetide.sync.api"
		to:    "selenetide.metadata.imap"
		label: "fetches"
		labels: ["fetches"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.architecture.datastores"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.content.api"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.export.rules"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.metadata.columns"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.processing.rules"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.product.features"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.query.rules"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.testing.catalog"
		to:    "selenetide.workflow.rules"
		label: "verifies"
		labels: ["verifies"]
	},
	{
		from:  "selenetide.workflow.rules"
		to:    "selenetide.workflow.stages"
		label: "governs"
		labels: ["governs"]
	},
	{
		from:  "selenetide.workflow.stages"
		to:    "selenetide.sync.api"
		label: "exposed_by"
		labels: ["exposed_by"]
	},
	{
		from:  "selenetide.workflow.stages"
		to:    "selenetide.workflow.fields"
		label: "persisted_in"
		labels: ["persisted_in"]
	},
]
