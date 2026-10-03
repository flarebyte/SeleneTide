package flyb

// Canonical assembly of every design example into one generated specification.
// Unsupported Swift/EML extensions use text symlinks in render-inputs/.
source: "selenetide-design"
name:   "SeleneTide Swift Library"
modules: ["core"]

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
	title:       "SeleneTide Swift Library Specification"
	filepath:    "../design/selenetide-specs.md"
	description: "Requirements, architecture, persistence, and API contracts assembled from doc/design-meta/examples."
	sections: [{
		title:       "01 Overview"
		description: "Purpose, Swift API conventions, and the relationship between the source artifacts."
		sections: [{
			title: "01 Library Scope"
			notes: ["selenetide.overview.scope"]
		}, {
			title: "02 Architecture Summary"
			notes: ["selenetide.overview.architecture"]
		}]
	}, {
		title:       "02 Product Requirements"
		description: "Library scope, platform requirements, and practical uses."
		sections: [
			{
				title:       "01 Feature Requirements"
				description: "Required, recommended, and optional capabilities for the Swift library and macOS CLI. Source: [features.csv](../design-meta/examples/features.csv)."
				notes: ["selenetide.product.features"]
			}, {
				title:       "02 Practical Use Cases"
				description: "User goals, inputs, outputs, and acceptance criteria. Source: [practical_use_cases.csv](../design-meta/examples/practical_use_cases.csv)."
				notes: ["selenetide.product.usecases"]
			},
		]
	}, {
		title:       "03 Architecture and Period Workflow"
		description: "Storage authority and durable orchestration across subsystem boundaries."
		sections: [
			{
				title:       "01 Datastores and Authority"
				description: "Physical layout, ownership, lifecycle, and recovery responsibilities. Source: [datastores.csv](../design-meta/examples/datastores.csv)."
				notes: ["selenetide.architecture.datastores"]
			}, {
				title:       "02 Library Processing Flows"
				description: "Initialization, recovery, and subsystem interaction sequences. Source: [library-processing-flows.ts](../design-meta/examples/library-processing-flows.ts)."
				notes: ["selenetide.architecture.flows"]
			}, {
				title:       "03 Period Workflow Stages"
				description: "The versioned task kinds, dependencies, fan-out, and durable completion gates. Source: [period_workflow_stages.csv](../design-meta/examples/period_workflow_stages.csv)."
				notes: ["selenetide.workflow.stages"]
			}, {
				title:       "04 Period Workflow Rules"
				description: "UTC boundaries, stage gates, backpressure, retries, and completion. Source: [period_workflow_rules.csv](../design-meta/examples/period_workflow_rules.csv)."
				notes: ["selenetide.workflow.rules"]
			}, {
				title:       "05 Account and Workflow Persistence Fields"
				description: "Swift-facing field shapes for accounts, plans, runs, tasks, checkpoints, and temporary content; Core Data storage follows the datastore and pipeline rules. Source: [swiftdata_coredata_fields.csv](../design-meta/examples/swiftdata_coredata_fields.csv)."
				notes: ["selenetide.workflow.fields"]
			}, {
				title:       "06 Sync API Contract"
				description: "Planning, execution, resumption, cancellation, checkpoints, and progress events. Source: [sync-api.ts](../design-meta/examples/sync-api.ts)."
				notes: ["selenetide.sync.api"]
			},
		]
	}, {
		title:       "04 IMAP Metadata and Schema"
		description: "Stable message identity and the shared live/archive metadata representation."
		sections: [
			{
				title:       "01 IMAP Email Metadata"
				description: "Header, MIME, provider, and derived metadata available without downloading bodies. Source: [imap_email_metadata.csv](../design-meta/examples/imap_email_metadata.csv)."
				notes: ["selenetide.metadata.imap"]
			}, {
				title:       "02 Email Metadata Columns"
				description: "Core columns, extensions, normalization, and compatible DuckDB/Parquet types. Source: [email_metadata_parquet_columns.csv](../design-meta/examples/email_metadata_parquet_columns.csv)."
				notes: ["selenetide.metadata.columns"]
			},
		]
	}, {
		title:       "05 Email Processing and Swift Transformers"
		description: "Code-defined processing graphs with durable results and restart recovery."
		sections: [
			{
				title:       "01 Email Processing Pipeline Rules"
				description: "Dependency scheduling, official outcomes, retries, registry lookup, and result reuse. Source: [email_processing_pipeline_rules.csv](../design-meta/examples/email_processing_pipeline_rules.csv)."
				notes: ["selenetide.processing.rules"]
			}, {
				title:       "02 Core Data Processing and Export Fields"
				description: "Jobs, steps, persisted outputs, leases, and versioned export checkpoints. Source: [coredata_email_pipeline_fields.csv](../design-meta/examples/coredata_email_pipeline_fields.csv)."
				notes: ["selenetide.processing.fields"]
			}, {
				title:       "03 Email Processing API Contract"
				description: "Language-neutral pipeline definitions, requests, snapshots, and events. Source: [email-processing-pipeline-api.ts](../design-meta/examples/email-processing-pipeline-api.ts)."
				notes: ["selenetide.processing.api"]
			}, {
				title:       "04 Swift Transformer Contract"
				description: "Typed Sendable transformers, erased registration, and official versus custom status. Source: [email-transformer.swift](../design-meta/examples/email-transformer.swift)."
				notes: ["selenetide.processing.transformer"]
			},
		]
	}, {
		title:       "06 DuckDB Projection and Parquet Archival"
		description: "Transactional projections, commit-gap recovery, and verified archive publication."
		sections: [
			{
				title:       "01 DuckDB Exporter Rules"
				description: "Eligibility, claims, idempotent upserts, acknowledgements, and archival recovery. Source: [duckdb_exporter_rules.csv](../design-meta/examples/duckdb_exporter_rules.csv)."
				notes: ["selenetide.export.rules"]
			}, {
				title:       "02 DuckDB Processing Export Tables"
				description: "Live results, immutable exporting snapshots, and archive manifests. Source: [duckdb_processing_export_tables.csv](../design-meta/examples/duckdb_processing_export_tables.csv)."
				notes: ["selenetide.export.tables"]
			}, {
				title:       "03 Swift DuckDB Exporter Contract"
				description: "Actor boundary, immutable row snapshots, store protocols, and batch acknowledgements. Source: [duckdb-exporter.swift](../design-meta/examples/duckdb-exporter.swift)."
				notes: ["selenetide.export.swift"]
			},
		]
	}, {
		title:       "07 Constrained Analytics Queries"
		description: "Logical datasets and a validated expression language compiled to parameterized SQL."
		sections: [
			{
				title:       "01 Query API Rules"
				description: "Parsing, type checking, identifiers, bindings, aggregation, execution, and errors. Source: [query_api_rules.csv](../design-meta/examples/query_api_rules.csv)."
				notes: ["selenetide.query.rules"]
			}, {
				title:       "02 Query Catalogue"
				description: "Allowed datasets, fields, relationships, functions, and aggregates. Source: [query_catalog.csv](../design-meta/examples/query_catalog.csv)."
				notes: ["selenetide.query.catalog"]
			}, {
				title:       "03 Query API Contract"
				description: "JSON requests, count/statistics modes, validation results, and execution errors. Source: [query-api.ts](../design-meta/examples/query-api.ts)."
				notes: ["selenetide.query.api"]
			}, {
				title:       "04 Email Query Examples"
				description: "Concrete query requests and expected query behavior. Source: [email_query_examples.json](../design-meta/examples/email_query_examples.json)."
				notes: ["selenetide.query.examples"]
			},
		]
	}, {
		title:       "08 On-Demand Content"
		description: "Explicit content downloads and disposable artifact retention."
		sections: [
			{
				title:       "01 On-Demand Email Fetch API"
				description: "Message/MIME-part selection, transformation, progress, content leases, and cleanup. Source: [fetch-email-api.ts](../design-meta/examples/fetch-email-api.ts)."
				notes: ["selenetide.content.api"]
			}, {
				title:       "02 Multipart Email Fixture"
				description: "A complete sample email with plain text and HTML alternatives. Source: [simple_email_with_html.eml](../design-meta/examples/simple_email_with_html.eml)."
				notes: ["selenetide.content.fixture"]
			},
		]
	}]
}]

notes: [
	{
		name:     "selenetide.architecture.datastores"
		title:    "Datastores and Authority"
		filepath: "examples/datastores.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.architecture.flows"
		title:    "Library Processing Flows"
		filepath: "examples/library-processing-flows.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.content.api"
		title:    "On-Demand Email Fetch API"
		filepath: "examples/fetch-email-api.ts"
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
		filepath: "examples/duckdb_exporter_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.export.swift"
		title:    "Swift DuckDB Exporter Contract"
		filepath: "render-inputs/duckdb-exporter.swift.txt"
		labels: ["example", "swift"]
	},
	{
		name:     "selenetide.export.tables"
		title:    "DuckDB Processing Export Tables"
		filepath: "examples/duckdb_processing_export_tables.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.metadata.columns"
		title:    "Email Metadata Columns"
		filepath: "examples/email_metadata_parquet_columns.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.metadata.imap"
		title:    "IMAP Email Metadata"
		filepath: "examples/imap_email_metadata.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:  "selenetide.overview.architecture"
		title: "Storage and Workflow Boundaries"
		markdown: """
			Core Data owns durable operational state, including plans, tasks, checkpoints, processing jobs, step results, and export claims. Keychain owns credentials. Each account has its own analytical files and DuckDB database; DuckDB is a replayable projection of operational results, while Parquet holds verified historical datasets.
			
			A UTC period flows through planning, UID discovery, metadata fetch, per-email processing, DuckDB export and verification, then archive claim, write, publication, and finalization when eligible. Independent per-email work uses bounded concurrency. Archival normally applies to closed calendar months; open-period metadata remains queryable in DuckDB.
			
			Message fetch identity is account plus mailbox plus UIDVALIDITY plus UID. Provider message identifiers correlate mailbox locations. Canonical UTC email dates, source versions, and schema versions connect the operational, live, and archived representations.
			
			Queries resolve fixed logical datasets across live data, archives, corrections, and tombstones. Downloaded message bodies and attachments belong to the separate on-demand content API and have explicit temporary retention.
			
			The sections below preserve the detailed tables and API examples. Their rules and field definitions specify each subsystem's completion and recovery behavior.
			"""
		labels: ["overview"]
	},
	{
		name:  "selenetide.overview.scope"
		title: "Scope and Swift API Conventions"
		markdown: """
			SeleneTide is a Swift library for macOS and iOS that brings IMAP message metadata into durable local storage. A macOS CLI exposes account, sync, fetch, and export operations for interactive and headless use.
			
			The specification covers account isolation and Keychain credentials; metadata-only synchronization; resumable period workflows; versioned per-email transformers; Core Data to DuckDB projection; monthly Parquet archival; constrained analytics; and explicitly requested temporary content.
			
			TypeScript files are language-neutral API sketches. The production Swift surface uses immutable Sendable values, async operations, AsyncSequence progress events, and cooperative cancellation. Swift examples define native transformer and exporter boundaries; they are design contracts rather than a complete library implementation.
			
			This document is generated from `doc/design-meta/app.cue` and every source example. Edit those sources and regenerate with `flyb validate --config doc/design-meta` followed by `flyb generate markdown --config doc/design-meta`.
			"""
		labels: ["overview"]
	},
	{
		name:     "selenetide.processing.api"
		title:    "Email Processing API Contract"
		filepath: "examples/email-processing-pipeline-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.processing.fields"
		title:    "Core Data Processing and Export Fields"
		filepath: "examples/coredata_email_pipeline_fields.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.processing.rules"
		title:    "Email Processing Pipeline Rules"
		filepath: "examples/email_processing_pipeline_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.processing.transformer"
		title:    "Swift Transformer Contract"
		filepath: "render-inputs/email-transformer.swift.txt"
		labels: ["example", "swift"]
	},
	{
		name:     "selenetide.product.features"
		title:    "Feature Requirements"
		filepath: "examples/features.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.product.usecases"
		title:    "Practical Use Cases"
		filepath: "examples/practical_use_cases.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.query.api"
		title:    "Query API Contract"
		filepath: "examples/query-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.query.catalog"
		title:    "Query Catalogue"
		filepath: "examples/query_catalog.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.query.examples"
		title:    "Email Query Examples"
		filepath: "examples/email_query_examples.json"
		labels: ["example", "json"]
	},
	{
		name:     "selenetide.query.rules"
		title:    "Query API Rules"
		filepath: "examples/query_api_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.sync.api"
		title:    "Sync API Contract"
		filepath: "examples/sync-api.ts"
		labels: ["example", "typescript"]
	},
	{
		name:     "selenetide.workflow.fields"
		title:    "Account and Workflow Persistence Fields"
		filepath: "examples/swiftdata_coredata_fields.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.workflow.rules"
		title:    "Period Workflow Rules"
		filepath: "examples/period_workflow_rules.csv"
		arguments: ["format-csv=table"]
		labels: ["csv", "example"]
	},
	{
		name:     "selenetide.workflow.stages"
		title:    "Period Workflow Stages"
		filepath: "examples/period_workflow_stages.csv"
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
		from:  "selenetide.export.swift"
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
