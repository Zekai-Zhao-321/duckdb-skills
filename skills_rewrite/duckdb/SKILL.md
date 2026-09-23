---
name: duckdb
description: >
  Query, explore, profile and convert data with DuckDB, and look up any DuckDB SQL
  syntax, function, setting or extension in a bundled copy of the official docs. Use
  when the request involves a data file or dataset (.csv, .tsv, .json, .jsonl, .parquet,
  .avro, .xlsx, .duckdb, .db, .sqlite, .geojson, .shp, .gpkg, .ipynb) or a storage URL
  (s3://, gs://, r2://, az://, https://); when asked what is in a file, for a schema,
  row count, summary or profile; to filter, aggregate, join, pivot or reshape data; to
  "convert to parquet", "save as xlsx", "export as csv"; for any DuckDB or SQL question
  (window functions, PIVOT, ASOF join, COPY, ATTACH, secrets, extensions, Friendly SQL);
  for geospatial or Overture Maps work; or when a DuckDB command fails and you need the
  cause. Not for reading source code or config files — use ordinary file tools for those.
---

# DuckDB

DuckDB is an in-process analytical database. It reads CSV, JSON, Parquet, Avro, Excel,
SQLite, spatial formats and more — local or remote — with no import step, so it is
usually the fastest and cheapest way to answer a question about a data file. Reach for
it instead of reading a data file into context or writing throwaway pandas code.

## How to run it

Drive the `duckdb` CLI through whatever command execution you have:

```bash
duckdb -c "SELECT 42"
```

Check it exists before the first real command:

```bash
command -v duckdb || duckdb --version
```

If it is missing, read `reference/extensions.md` for install commands per platform, and
tell the user what you are about to install before installing it. If you cannot run
shell commands but can run Python, `import duckdb; duckdb.sql("...")` is equivalent —
every SQL snippet in this skill transfers unchanged.

## The loop

Follow these four steps for every data task. Do not skip step 2.

**1. Resolve the target.** Turn a bare filename into a real path before querying:

```bash
find "$PWD" -name 'sales.csv' -not -path '*/.git/*' 2>/dev/null | head -5
```

For a URL (`s3://`, `gs://`, `https://`, …) skip the lookup and read
`reference/remote-storage.md` for the credential setup that protocol needs.

**2. Inspect before you query.** Never write a substantive query against a schema you
have not seen. One command gets you everything:

```bash
duckdb -c "
DESCRIBE FROM 'sales.parquet';
SELECT count() AS rows FROM 'sales.parquet';
FROM 'sales.parquet' LIMIT 10;
"
```

`SUMMARIZE FROM 'sales.parquet'` adds per-column min/max/median/null counts — use it
when the user asks to profile, describe or "understand" a dataset.

**3. Run the real query.** Use a quoted heredoc for anything multi-line, so the shell
leaves your SQL alone:

```bash
duckdb -csv <<'SQL'
FROM 'sales.parquet'
WHERE region = 'EMEA'
GROUP BY ALL
SELECT region, product, sum(amount) AS revenue
ORDER BY revenue DESC
LIMIT 20;
SQL
```

**4. Report.** Give the answer first, then the evidence. Show the SQL you ran so the
user can check and reuse it.

## Which reference to read

Read at most the one or two files that match the task — they are written to be opened
on demand, not up front.

| The task is about | Read |
|---|---|
| Writing better SQL: `GROUP BY ALL`, `EXCLUDE`, `COLUMNS(*)`, PIVOT, ASOF/LATERAL joins, list and struct handling | `reference/friendly-sql.md` |
| Reading an unfamiliar or awkward format; converting between formats; writing Parquet/Excel/JSON; partitioning and compression | `reference/file-formats.md` |
| `s3://`, `r2://`, `gs://`, `az://`, `https://`; credentials and secrets; listing a bucket; querying remote Parquet cheaply | `reference/remote-storage.md` |
| A `.duckdb` database, `ATTACH`, or carrying setup across several commands in one task | `reference/sessions.md` |
| Installing, loading or updating extensions; upgrading the CLI itself | `reference/extensions.md` |
| Geometry, coordinates, distance, containment, maps, GeoJSON/Shapefile/GeoPackage, H3 | `reference/spatial.md` |
| Finding real-world places, buildings, roads or boundaries with no user-supplied file | `reference/overture-maps.md` |
| Looking up DuckDB syntax, a function signature, a setting, or diagnosing an error message | `reference/searching-docs.md` |
| Searching past agent/session transcripts or any large pile of JSONL logs | `reference/session-logs.md` |

## The bundled documentation

`docs/` holds the complete official DuckDB documentation — 442 pages, mirroring
<https://github.com/duckdb/duckdb-web/tree/main/docs/current>. It is the authority for
this skill: when your memory of DuckDB syntax disagrees with `docs/`, `docs/` wins.

- `docs/TOC.md` — every page grouped by section with its path. Read this first to
  pick the right page, rather than guessing a filename.
- `docs/functions.json` — machine-readable catalog of every built-in function, one row
  per overload.
- `docs/SOURCE.md` — which upstream commit this copy came from.

Grep the tree when you do not know which page covers something:

```bash
grep -rli 'asof join' docs/ | head -10
```

`reference/searching-docs.md` covers ranked full-text search over these pages and over
the DuckDB blog, which beats grep for vague or natural-language questions.

Two version notes, because `docs/` tracks the in-development release: `GEOMETRY` is a
built-in type from v1.5 (most spatial *functions* still need the `spatial` extension),
and a page may document behaviour newer than the user's installed CLI. Check with
`duckdb --version` when something documented does not work.

## Rules that always apply

- **Bound the output.** Query results come back into context and cost tokens. Add
  `LIMIT`, aggregate, or `count()` unless the user asked for the full set. Before
  running an unbounded query against a source you have not sized, check
  `SELECT count() FROM '<source>'`; above ~1M rows, say so and propose a `LIMIT` or an
  aggregation rather than dumping the rows.
- **Prefer one command over many.** DuckDB starts fresh each invocation — `LOAD`,
  `CREATE SECRET`, macros and temp tables do not survive between `duckdb -c` calls.
  Put the setup and the query in the same command, or read `reference/sessions.md`.
- **Pick the output format deliberately.** `-csv` for data you will parse or show,
  `-json` when you need nested values intact, `-line` for a single wide row, the default
  box format for small results a human will read.
- **Sandbox untrusted input.** When querying a file you were pointed at rather than one
  the user owns, restrict what the query can touch:

  ```sql
  SET allowed_paths = ['/abs/path/to/data.parquet'];
  SET enable_external_access = false;
  SET lock_configuration = true;
  ```

  Set these before the query, in the same command. Skip them when the user is querying
  their own database and expects network or filesystem access.
- **Never write to the user's data without asking.** `COPY`, `CREATE TABLE`, `INSERT`,
  `UPDATE`, `DELETE`, `ATTACH` without `READ_ONLY`, and any `DROP` change state.
  Confirm the destination path first, and say if it already exists.
- **Read-only when you only mean to read.** `duckdb -readonly file.duckdb` and
  `ATTACH '…' AS db (READ_ONLY)` make an accidental write impossible.

## When a command fails

Work through these in order; most failures are one of the first three.

| Symptom | Fix |
|---|---|
| `duckdb: command not found` | Install it — `reference/extensions.md` |
| `Catalog Error: Table Function with name read_xlsx does not exist`, or any "not loaded"/"no function matches" error | The feature lives in an extension. `INSTALL <ext>; LOAD <ext>;` in the same command, then retry — `reference/extensions.md` |
| `IO Error` / `No files found that match the pattern` | The path is wrong. Re-resolve with `find`; for a URL, the credentials or endpoint are wrong — `reference/remote-storage.md` |
| `Binder Error: Referenced column ... not found` | You guessed the schema. Go back to step 2 and `DESCRIBE` it |
| `Parser Error` / `Syntax Error` | Look the statement up in `docs/` before rewriting it by trial and error |
| Conversion or cast error on load | The reader inferred a type wrong. Widen it — `reference/file-formats.md` |
| Anything you cannot place | Search the bundled docs for the distinctive words in the error — `reference/searching-docs.md` |

Report failures honestly: show the command and the actual error rather than describing
it. If two attempts at the same approach fail, change approach instead of retrying.
