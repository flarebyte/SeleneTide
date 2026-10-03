# SeleneTide
Pulling messages into place with the quiet inevitability of the moon moving the tides

SeleneTide is a Swift library design for local IMAP metadata synchronization,
durable email processing, and DuckDB/Parquet analytics on macOS and iOS.

Choose a reading path:

- **Start here:** the [executive overview](doc/design/overview.md) explains the architecture, main flow, and essential rules in one page.
- **Implement a subsystem:** the [full specification](doc/design/selenetide-specs.md) contains the rules, schemas, and API examples, with section links from the overview.
- **Assess open decisions:** the [consistency review](doc/design-meta/consistency-review.md#remaining-implementation-choices) records unresolved choices and the file-by-file audit.

Both generated reports share [the flyb configuration](doc/design-meta/app.cue).
The full specification includes all 23 artifacts in
[`doc/design-meta/examples`](doc/design-meta/examples).

With `flyb` installed, validate and regenerate both reports from the repository root:

```sh
flyb validate --config doc/design-meta
flyb generate markdown --config doc/design-meta
```

See the [design source workflow](doc/design-meta/README.md) for editing and rendering details.
