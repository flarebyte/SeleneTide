# SeleneTide design consistency review

The current baseline is a portable Rust library with a stateful C ABI and SQLite
operational persistence. The contracts describe a future implementation; there is
no production library or CLI in this repository.

## Resolved design choices

- **Session ownership.** A frontend backend opens a session and retains its handle
  across requests. The session owns workers, configuration, SQLite connections,
  per-account DuckDB connections, credentials, and authenticated IMAP connections.
  Close rejects new calls, drains admitted work, clears credentials, closes stores,
  releases exclusive root ownership, and invalidates the handle.
- **Portable persistence.** SQLite owns accounts, plans, tasks, checkpoints,
  processing results, revision allocation, leases, and export claims. Explicit SQL
  transactions, migrations, foreign keys, unique identities, and bounded busy
  handling replace managed-object contexts. Relationships use foreign keys or
  join tables; export references use stable step IDs. One root has one owning
  session; account rows remain isolated within a shared operational database.
- **Caller-supplied authentication.** Each request selects exactly one of PLAIN,
  XOAUTH2, OAUTHBEARER, or SCRAM-SHA-256 with username and password or accessToken.
  Authentication remains in memory; the host owns OAuth consent, token refresh,
  and any secret persistence. Replacement fences stale authentication generations.
  Network work requires verified TLS and explicit server mechanism support.
- **Interop.** The C header specifies process-local session tokens, pointer-length
  UTF-8 JSON buffers, status values, output ownership, and explicit freeing. Long
  work returns operation IDs; polling, cancellation, result pages, and bounded
  event queues avoid requiring a host async runtime. The API validates versions,
  handles, methods, and payloads and contains panics at foreign boundaries.
- **UniFFI.** Optional generated records, enums, objects, and async conveniences
  can adapt the same Rust model. Generated scaffolding is distinct from the public
  C ABI and must be pinned with its bindings. See the
  [official UniFFI guide](https://mozilla.github.io/uniffi-rs/).
- **Scope.** CLI commands, exit codes, and command-based automation are deferred.
  CSV/JSON library export remains in scope. Required Apple services and OS
  credential-store integration have been removed.
- **Existing recovery rules.** Durable revisions, fenced claims, idempotent
  projection, queryable archive snapshots, atomic verified Parquet publication,
  correction overlays, and metadata-only synchronization still apply. Credentials
  and session operation IDs expire on restart; durable domain run IDs remain resumable.

## Source coverage

All 28 example artifacts are registered in the full report. New `api/` sources
specify session payloads, authentication alternatives, the C header, and lifecycle
rules. Both persistence tables use SQLite names and explicit storage mappings.
Rust sketches replace the transformer and exporter sketches. Requirements, use
cases, processing flows, recovery rules, and the planned test catalogue follow
the same architecture. The catalogue contains 21 unit and 27 integration suites;
these are planned tests, not implemented test results.
The canonical `concepts.csv` registry links 14 broad CSVs through shared concepts;
optional test tags provide cross-cutting filters. Original cells and relationships
are preserved. The query catalogue and workflow-stage table retain their existing
schemas. See the [selective retrieval convention](README.md#selective-csv-retrieval).

## Remaining implementation choices

- Minimum Rust version, crate layout, exact Linux/Windows/macOS target matrix,
  pinned SQLite/DuckDB and IMAP/TLS adapters, optional UniFFI target languages,
  and static/dynamic packaging remain to be selected.
- Portable exclusive root locking, migration SQL, complete relational DDL,
  connection pool sizes, timeouts, runtime choice, panic containment, and secret
  memory clearing need implementation and integration verification.
- Request/response sizes, event queue bounds, query depth/token limits, retry
  ceilings, and worker limits need defaults. Exporter sketch defaults cover only
  batch size, attempts, and claim duration.
- Physical correction/tombstone tables, processing-result Parquet type mappings,
  classification labels, address normalization, malformed MIME handling, and
  decoding limits need concrete schemas or policies.
- Retention durations, account deletion, incompatible schema migration, and
  support for historical pipeline definitions require policies. Required-failure
  exclusions remain disabled until their durable policy and record format exist.

## Repeatable checks

```sh
python3 scripts/check-design-examples.py --csv-only
python3 scripts/test_design_csv.py
flyb validate --config doc/design-meta
flyb lint names --config doc/design-meta
flyb lint orphans --config doc/design-meta --subject-label example
flyb generate markdown --config doc/design-meta
python3 scripts/check-design-examples.py
clang -x c -std=c11 -Wall -Wextra -Werror -fsyntax-only doc/design-meta/examples/api/selenetide.h
```

The structural checker validates source coverage, CSV widths and IDs, feature
references, planned-test references, entity inverses, stage dependencies, query
columns and examples, the MIME fixture, generated links, and the overview budget.
It also checks CSV integrity, single-line records, registered concept references,
unique concept IDs, hierarchy, and optional tags.
It does not execute SQLite, IMAP, JSON routing, or the C ABI. Rust sketches should
be compiled with edition 2021 or later when a Rust toolchain is available; host
adapter sketches should be checked with a strict ES2022 TypeScript compiler.
