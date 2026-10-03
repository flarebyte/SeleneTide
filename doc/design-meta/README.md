# SeleneTide specification sources

`app.cue` generates two reports: the one-page
[executive overview](../design/overview.md) and the
[full specification](../design/selenetide-specs.md). The full report assembles
every artifact in `examples/` and covers
requirements, storage authority, period workflows, IMAP metadata, Swift
transformers, DuckDB export and Parquet archival, constrained queries, and
on-demand content.

Start with the overview, follow its section links for implementation detail,
and read the consistency review for unresolved decisions. Keep the overview
between 500 and 700 words. Its six sections live in the second report's
descriptions; purpose and storage ownership paragraphs are shared with the
detailed report through CUE fields. When changing a design rule, update its
summary in the same configuration and regenerate both reports.

The examples are grouped under `requirements/`, `architecture/`, `sync/`,
`metadata/`, `processing/`, `storage/`, `query/`, and `content/`.
[`consistency-review.md`](consistency-review.md) records the file-by-file review,
resolved conflicts, and remaining implementation choices. The workflow field
table is now `sync/coredata_workflow_fields.csv`, reflecting the selected Core
Data persistence architecture.

Edit the original CSV, TypeScript, Swift, JSON, and EML artifacts. CSV notes render
all columns as Markdown tables; TypeScript and JSON notes render as code blocks.
The TypeScript contracts describe the intended Swift API rather than a TypeScript
implementation. Every example section links back to its original source.

The installed flyb renderer does not support `.swift` or `.eml` file extensions.
`render-inputs/` contains three relative `.txt` symlinks to the original Swift and
EML files. These notes render their full contents as text code blocks. The links
read the original files on each generation, so there are no copied excerpts to
refresh. Preserve the symlinks when checking out or copying the repository.

From the repository root, run:

```sh
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
example coverage in the full report, and the overview's word budget.
