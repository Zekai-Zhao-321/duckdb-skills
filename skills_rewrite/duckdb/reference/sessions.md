# Databases and multi-step sessions

Each `duckdb -c "…"` starts a fresh process. `LOAD`, `CREATE SECRET`, macros, `SET`,
temp tables and `USE` do not survive to the next call. Three ways to deal with that,
cheapest first.

Canonical pages: `docs/sql/statements/attach.md`, `docs/connect/`,
`docs/clients/cli/arguments.md`, `docs/clients/cli/dot_commands.md`.

## 1. One command (default)

Put setup and query together. This covers most tasks — prefer it:

```bash
duckdb -csv <<'SQL'
INSTALL httpfs; LOAD httpfs;
CREATE SECRET (TYPE s3, PROVIDER credential_chain);
FROM 's3://bucket/events/*.parquet'
WHERE day = '2026-09-01'
GROUP BY ALL
SELECT hour, count() AS n
ORDER BY hour;
SQL
```

## 2. An init file (repeated commands, same setup)

`-init FILE` runs a SQL script before each invocation. Write the setup once, then reuse
it across as many commands as the task needs:

```bash
cat > /tmp/duckdb-init.sql <<'SQL'
INSTALL httpfs; LOAD httpfs;
CREATE SECRET (TYPE s3, PROVIDER credential_chain);
ATTACH IF NOT EXISTS 'warehouse.duckdb' AS warehouse;
USE warehouse;
SQL

duckdb -init /tmp/duckdb-init.sql -csv -c "SHOW TABLES;"
duckdb -init /tmp/duckdb-init.sql -csv -c "FROM orders LIMIT 5;"
```

Keep it in a temp location unless the user wants it kept. If they do want it in the
project, ask where it should live and whether to gitignore it — do not create files in
their repository unprompted. A file containing `CREATE SECRET` with literal keys must
not be committed; use `PROVIDER credential_chain` instead.

## 3. A persistent database file

When the task produces tables the user will come back to, write a real database:

```bash
duckdb analysis.duckdb -c "CREATE TABLE clean AS FROM 'raw/*.csv' WHERE amount > 0;"
duckdb analysis.duckdb -csv -c "SUMMARIZE clean;"
```

This is also the right move when a remote or CSV source is queried repeatedly: load it
once, then query locally at full speed.

## Working with a `.duckdb` file

```sql
ATTACH 'warehouse.duckdb' AS warehouse;              -- read-write
ATTACH 'warehouse.duckdb' AS warehouse (READ_ONLY);  -- safe for exploration
ATTACH 'https://blobs.duckdb.org/databases/stations.duckdb' AS s (READ_ONLY);
ATTACH 'postgres://user@host/db' AS pg (TYPE postgres);
ATTACH 'legacy.sqlite' AS lite (TYPE sqlite);
USE warehouse;
DETACH warehouse;
```

`duckdb -readonly file.duckdb` opens the whole session read-only — use it whenever you
only intend to look. Attaching Postgres, MySQL or SQLite alongside DuckDB lets you join
across them in one query; the `postgres`, `mysql` and `sqlite` extensions provide this.

### Surveying an unfamiliar database

```bash
duckdb -readonly warehouse.duckdb -csv <<'SQL'
SELECT database_name, schema_name, table_name, estimated_size AS approx_rows, column_count
FROM duckdb_tables()
ORDER BY approx_rows DESC;
SQL
```

Then `DESCRIBE <table>` the handful that matter, rather than every table. Report the
tables, their approximate row counts, and the columns that look like keys or dates —
that is what the user needs in order to ask the next question.

### Version mismatch

A database file written by a newer DuckDB will not open in an older one:

> `The file was written by DuckDB version X, but we are version Y`

Check `duckdb --version`, then upgrade the CLI (`extensions.md`) — the file is fine.

## Cleaning up

Say what you created and where. If you wrote a database or an init file only to answer a
one-off question, offer to delete it rather than leaving it behind.
