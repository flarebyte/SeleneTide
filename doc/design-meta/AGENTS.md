# Task-focused documentation entry point

Use this guide when implementing, reviewing, or changing SeleneTide. Start with
the task's source records and contracts. Read the generated full specification
only when a targeted source search leaves a specific question unresolved.

## Retrieval workflow

1. Identify the task's concepts in [examples/concepts.csv](examples/concepts.csv)
   and choose starting files from the table below. The registry is authoritative;
   concept IDs group records, while original row IDs identify individual rules.
2. Find matching CSV files with `rg -l`, then retrieve matching records with
   `rg -n`. Read each file's header to interpret columns. A row occupies one
   physical line; use a CSV parser to extract cells containing quoted commas.
3. Follow only relevant links: `related_feature_ids`, `related_note_ids`, stage
   `depends_on`, entity relationships, and referenced field or transformer IDs.
   Resolve specification note IDs in [app.cue](app.cue) to their source files.
   Inspect the relevant TypeScript, Rust, or C contract alongside the rules.
4. Retrieve matching tests in [test_catalog.csv](examples/testing/test_catalog.csv).
   Check [remaining implementation choices](consistency-review.md#remaining-implementation-choices)
   when a required behavior is unspecified. The test catalogue describes planned
   coverage, not passing implementation tests.
5. Stop expanding once you have the applicable requirements, rules, fields,
   contract, dependencies, and verification criteria. In your implementation or
   review, cite source paths and stable row IDs so another agent can retrieve them.

## Starting points by task

Paths in this table are relative to `examples/`. Concepts are search starting
points; follow dependencies when the task crosses subsystem boundaries.

| Task | Concepts | First sources |
| --- | --- | --- |
| Sessions and bindings | `session.lifecycle`, `session.abi` | `api/session_rules.csv`, `api/session-api.ts`, `api/selenetide.h` |
| Authentication and accounts | `session.authentication`, `account.configuration` | `api/session_rules.csv`, `requirements/features.csv`, `sync/sqlite_workflow_fields.csv` |
| SQLite and migrations | `storage.sqlite`, `storage.schema` | `architecture/datastores.csv`, `sync/sqlite_workflow_fields.csv`, `processing/sqlite_email_pipeline_fields.csv` |
| IMAP discovery and checkpoints | `sync.discovery`, `sync.checkpoints`, `metadata.identity` | `sync/period_workflow_rules.csv`, `sync/sync-api.ts`, `metadata/imap_email_metadata.csv` |
| Scheduling and recovery | `workflow.scheduling`, `workflow.recovery`, `workflow.retry`, `workflow.leases` | `sync/period_workflow_rules.csv`, `sync/period_workflow_stages.csv`, `processing/email_processing_pipeline_rules.csv` |
| Transformers and reuse | `processing.pipeline`, `processing.transformers`, `processing.results`, `processing.reuse` | `processing/email_processing_pipeline_rules.csv`, `processing/email-transformer.rs`, `processing/email-processing-pipeline-api.ts` |
| Projection and archival | `storage.projection`, `storage.archive`, `storage.corrections` | `storage/duckdb_exporter_rules.csv`, `storage/duckdb_processing_export_tables.csv`, `storage/duckdb-exporter.rs` |
| Queries and export | `query.syntax`, `query.validation`, `query.execution` | `query/query_api_rules.csv`, `query/query_catalog.csv`, `query/query-api.ts`, `query/email_query_examples.json` |
| Content and cleanup | `content.fetch`, `metadata.mime`, `storage.artifacts` | `content/fetch-email-api.ts`, `sync/sqlite_workflow_fields.csv`, `architecture/datastores.csv` |
| Metadata normalization | `metadata.headers`, `metadata.provider`, `metadata.derived` | `metadata/imap_email_metadata.csv`, `metadata/email_metadata_parquet_columns.csv` |
| Build and portability | `library.portability` | `requirements/features.csv`, `architecture/datastores.csv`, `testing/test_catalog.csv` |

## Example searches

Run from the repository root; replace the example concept with the task's concept.

```sh
# Discover concepts, then locate lease-related sources without reading them all.
rg -n '^workflow(\.|,)' doc/design-meta/examples/concepts.csv
rg -l --glob '*.csv' ',workflow\.leases(,|$)' doc/design-meta/examples

# Retrieve rules and fields needed for the task, including their headers.
rg -n '^rule_id,|,workflow\.leases(,|$)' doc/design-meta/examples/processing/email_processing_pipeline_rules.csv
rg -n '^field_id,|,workflow\.leases(,|$)' doc/design-meta/examples/processing/sqlite_email_pipeline_fields.csv

# Retrieve applicable planned tests and resolve a referenced note to its source.
rg -n '^test_id,|,workflow\.leases(,|$)' doc/design-meta/examples/testing/test_catalog.csv
rg -n -A 6 -B 2 'name:.*"selenetide\.processing\.rules"' doc/design-meta/app.cue
```

Concept filters alone are not exhaustive: each record has one primary concept.
Follow related IDs and search a specific identifier or term in the relevant
subsystem to find secondary concerns. The query catalogue and workflow stages
have no concept column; filter their existing IDs, datasets, and dependencies.
See the [CSV convention](README.md#selective-csv-retrieval) for tags and hierarchy
searches. For broad architecture questions, use the short
[overview](../design/overview.md) before expanding the search.

## Editing design sources

Edit original artifacts in `examples/` and their registrations in `app.cue`.
Preserve row IDs, relationships, and existing cells; reuse registered concepts.
Generated Markdown belongs in `doc/design/`. For design changes, follow the
[generation and validation workflow](README.md). For implementation-only tasks,
use retrieved rules as acceptance criteria and run checks appropriate to the code.
