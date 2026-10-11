# SeleneTide specification sources

**AI agents:** start with [AGENTS.md](AGENTS.md) for task-focused searches,
source routing, and dependency retrieval before opening the full specification.

`app.cue` generates two reports: the one-page
[executive overview](../design/overview.md) and the
[full specification](../design/selenetide-specs.md). The full report assembles
every artifact in `examples/` and covers
requirements, stateful Rust/C ABI sessions, authentication, SQLite storage authority,
period workflows, IMAP metadata, Rust
transformers, DuckDB export and Parquet archival, constrained queries,
on-demand content, and planned test coverage.

Start with the overview, follow its section links for implementation detail,
and read the consistency review for unresolved decisions. Keep the overview
between 500 and 700 words. Its six sections live in the second report's
descriptions; purpose and storage ownership paragraphs are shared with the
detailed report through CUE fields. When changing a design rule, update its
summary in the same configuration and regenerate both reports.

The examples are grouped under `api/`, `requirements/`, `architecture/`, `sync/`,
`metadata/`, `processing/`, `storage/`, `query/`, `content/`, and `testing/`.
[`consistency-review.md`](consistency-review.md) records the file-by-file review,
resolved conflicts, and remaining implementation choices. The workflow field
tables are `sync/sqlite_workflow_fields.csv` and
`processing/sqlite_email_pipeline_fields.csv`. They define logical fields and
SQLite mappings, constraints, and relationships rather than managed objects.

[`testing/test_catalog.csv`](examples/testing/test_catalog.csv) records planned
coarse-grained suites: 21 unit and 27 integration. Columns identify each suite's
stable ID, test level, area, title, `desc`, and semicolon-separated specification
note IDs. A row groups related assertions; it is not an implementation or a test
result. The full report's test-plan section describes fixtures, failure injection,
and how unresolved policies or optional capabilities affect the expectations.
The appended `concept` and `tags` columns support selective retrieval.

Edit the original CSV, TypeScript, Rust, C header, JSON, and EML artifacts. CSV notes render
all columns as Markdown tables; TypeScript and JSON notes render as code blocks.
The TypeScript contracts describe JSON payloads and host adapters over the Rust
session, rather than a TypeScript implementation. Promise and AsyncIterable
conveniences map to operation IDs and event polling at the C ABI. Rust transformer
registration stays internal; foreign transformer callbacks are outside v1.
Every example section links back to its original source.

The installed flyb renderer supports `.rs` but not `.h` or `.eml` extensions.
`render-inputs/` contains two relative `.txt` symlinks to the original C header and
EML files. These notes render their full contents as text code blocks. The links
read the original files on each generation, so there are no copied excerpts to
refresh. Preserve the symlinks when checking out or copying the repository.

From the repository root, run:

```sh
python3 scripts/check-design-examples.py --csv-only
flyb validate --config doc/design-meta
flyb generate markdown --config doc/design-meta
```

The configuration declares the `format-csv` argument in its argument registry.
Stable note IDs and relationships connect subsystem rules, schemas, and API
contracts. Numbered section titles preserve reading order under flyb's
deterministic sorting. Generated Markdown has no timestamps.

When adding an example, register a file-backed note and a report subsection in
`app.cue`, using a stable `selenetide.*` note ID. Add relationships where they
clarify a dependency, then validate and regenerate. Commit the inputs,
configuration, and generated specification together.

Run the structural and coverage checks after generation:

```sh
python3 scripts/check-design-examples.py
```

The checker verifies both generated reports and their section links, complete
example coverage in the full report, test catalogue levels and specification
references, the overview's word budget, and the CSV convention below.

## Selective CSV retrieval

[`examples/concepts.csv`](examples/concepts.csv) is the canonical registry. Its
`id`, `description`, and optional `parent` cells define 31 shared retrieval concepts
under 10 parent categories. IDs use lowercase dot-separated segments, with hyphens
allowed inside a segment. A child names its immediate prefix as its parent;
top-level categories have an empty parent. Reuse an existing concept before adding
a new one. Concepts describe implementation concerns; original row IDs and
relationships remain authoritative and unchanged.

Fourteen broad CSVs append one required `concept` cell per row. Shared concepts
connect requirements, use cases, rules, storage fields, metadata, and planned
tests, so a task such as lease recovery can retrieve related records across
subsystems. A row has one primary concept; a matching row can still link to other
concerns through its existing relationships. The query catalogue remains scoped
by `dataset` and `item_kind`, and the workflow-stage table by stage IDs and
dependencies. Those two tables have no extra metadata because their existing
filters already suffice. The registry itself has no `concept` column.

Only the test catalogue adds `tags` for cross-cutting verification filters:
`atomicity`, `cancellation`, `compatibility`, `concurrency`, `limits`, `ordering`,
`recovery`, `security`, `serialization`, and `validation`. Tags are optional,
lowercase keywords separated by commas with no spaces or duplicates. A cell
with multiple tags must be quoted, for example `"concurrency,recovery"`; a single
tag or an empty cell needs no quoting. Tags are lightweight filters, not a second
concept registry. Do not duplicate an existing column just to add a tag.

Keep the original column order, append metadata at the end, and keep every CSV
record on one physical UTF-8 line, with LF line endings. Use standard CSV quoting
for commas and double quotes, and a CSV reader/writer when editing. All current
tables are single-line records; the checker rejects multiline fields, malformed
quoting, uneven row widths, empty or duplicate IDs, invalid headers, unregistered
concepts, invalid parent hierarchies, and malformed or duplicate tags. Existing
ID uniqueness is per table; registry IDs are globally unique. No CSV escapes or
synthetic metadata are needed inside prose cells.

From the repository root, discover a concept, find its source files, and retrieve
matching rows with line numbers:

```sh
# Find workflow concepts and their descriptions in the registry.
rg -n '^workflow(\.|,)' doc/design-meta/examples/concepts.csv

# List CSV files containing lease records, then retrieve only matching records.
rg -l --glob '*.csv' ',workflow\.leases(,|$)' doc/design-meta/examples
rg -n --glob '*.csv' ',workflow\.leases(,|$)' doc/design-meta/examples

# Retrieve projection and archive records across requirements, rules, and schemas.
rg -n --glob '*.csv' ',storage\.(projection|archive)(,|$)' doc/design-meta/examples

# Filter planned tests by a complete tag keyword, including quoted tag lists.
rg -n '(^|[,"])security([,"]|$)' doc/design-meta/examples/testing/test_catalog.csv

# Read the header when interpreting a retrieved field row.
rg -n '^field_id,' doc/design-meta/examples/sync/sqlite_workflow_fields.csv

# Existing filters still work in tables without concept columns.
rg -n '^aggregate\.' doc/design-meta/examples/query/query_catalog.csv
```

The comma/end boundaries match concept cells rather than similar identifier
prefixes. These commands retrieve raw CSV records; use a standard CSV parser to
extract individual cells, since prose can contain quoted commas. Parent searches
use a dot prefix (for example `,storage\.`) to include child concepts; matching a
parent ID alone does not expand the hierarchy automatically.

The `app.cue` manifest registers the registry as a file-backed table note and
includes it in the full report. Flyb renders all CSV columns automatically, so
concepts and quoted tag cells require no custom renderer or duplicated data.
Validate sources without reading generated Markdown or requiring CUE/flyb:

```sh
python3 scripts/check-design-examples.py --csv-only
python3 scripts/test_design_csv.py
```

After generation, run the checker without `--csv-only` to verify that every
source column and record, including the registry, appears in the full report.
