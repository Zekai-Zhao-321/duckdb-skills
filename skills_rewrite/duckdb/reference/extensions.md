# Installing DuckDB and its extensions

Canonical pages: `docs/extensions/`, `docs/core_extensions/`,
`docs/operations_manual/installing_duckdb/`, `docs/sql/statements/update_extensions.md`.

## Installing the CLI

| Platform | Command |
|---|---|
| macOS | `brew install duckdb` |
| Linux / macOS | `curl https://install.duckdb.org \| bash` |
| Windows | `winget install DuckDB.cli` |

Tell the user which one you intend to run and let them confirm before installing
software on their machine.

Upgrading:

```bash
duckdb --version
curl -fsSL https://duckdb.org/data/latest_stable_version.txt   # compare
brew upgrade duckdb                     # or re-run the install script / winget upgrade
```

Upgrade when a database file reports a newer storage version, or when documented syntax
is rejected as a parser error.

## Installing extensions

```sql
INSTALL httpfs;              -- from the core repository
LOAD httpfs;                 -- load into this process
INSTALL h3 FROM community;   -- community repository
INSTALL foo FROM core_nightly;
```

`INSTALL` downloads once and persists to `~/.duckdb/extensions`. `LOAD` is per process,
so it belongs in every command that needs it. Both in one line is always safe:

```bash
duckdb -c "INSTALL spatial; LOAD spatial; SELECT ST_Point(1, 2);"
```

Core extensions autoload on first use when the network is available, so a bare
`FROM 's3://…'` often just works. Be explicit anyway — it makes the failure mode obvious
and works offline once installed.

## Which extension provides what

| Need | Extension | Repository |
|---|---|---|
| S3, GCS, R2, HTTPS | `httpfs` | core |
| Azure Blob / ADLS | `azure` | core |
| Geometry functions, `ST_Read`, GDAL output | `spatial` | core |
| Excel `.xlsx` read and write | `excel` | core |
| Avro | `avro` | core |
| SQLite, Postgres, MySQL passthrough | `sqlite`, `postgres`, `mysql` | core |
| Iceberg, Delta Lake | `iceberg`, `delta` | core |
| Full-text search (`match_bm25`) | `fts` | core |
| Vector similarity indexes | `vss` | core |
| H3 hexagonal indexing | `h3` | community |
| DuckLake catalogs | `ducklake` | core |

`GEOMETRY` is a built-in type from DuckDB v1.5, but nearly every geometry *function*
still comes from `spatial`.

## Inspecting and updating

```sql
SELECT extension_name, installed, loaded, extension_version
FROM duckdb_extensions()
WHERE installed ORDER BY extension_name;

UPDATE EXTENSIONS;                       -- all of them
UPDATE EXTENSIONS (httpfs, spatial);     -- named ones
```

Updated extensions are not reloaded in the running process — start a new one.

## Failures

| Symptom | Fix |
|---|---|
| `Catalog Error: Table Function with name read_xlsx does not exist` | The extension is not loaded. `INSTALL excel; LOAD excel;` in the same command |
| `Extension "x" not found` | Wrong repository. Try `INSTALL x FROM community;` — see `docs/extensions/troubleshooting.md` |
| `Initialization function ... not found` | Installed but never loaded in this process. Add `LOAD x;` |
| Install fails with a network error | No egress. Ask the user to install it once on a connected machine, or check whether it is already in `~/.duckdb/extensions` |
| Extension loads but a function is missing | Version skew between CLI and extension. `UPDATE EXTENSIONS;`, then restart |
