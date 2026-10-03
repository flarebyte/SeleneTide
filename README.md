# SeleneTide
Pulling messages into place with the quiet inevitability of the moon moving the tides

SeleneTide is a Swift library design for local IMAP metadata synchronization,
durable email processing, and DuckDB/Parquet analytics on macOS and iOS.

The [Swift library specification](doc/design/selenetide-specs.md) is generated
from [the flyb configuration](doc/design-meta/app.cue) and all 23 artifacts in
[`doc/design-meta/examples`](doc/design-meta/examples).

With `flyb` installed, validate and regenerate the specification from the repository root:

```sh
flyb validate --config doc/design-meta
flyb generate markdown --config doc/design-meta
```

See the [design source workflow](doc/design-meta/README.md) for editing and rendering details.
