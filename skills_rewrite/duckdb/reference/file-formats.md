# Reading, writing and converting files

Canonical pages: `docs/data/` (csv, json, parquet, multiple_files, partitioning),
`docs/sql/statements/copy.md`, `docs/core_extensions/` (excel, avro, sqlite, spatial).

## Reading

For most formats the path alone is enough — DuckDB picks the reader from the extension:

```sql
FROM 'data.csv';
FROM 'data.parquet';
FROM 'events/*.json';
```

Use the explicit reader when you need options, or when the extension is missing or lying:

| Format | Reader | Extension needed |
|---|---|---|
| CSV / TSV / delimited text | `read_csv('f.csv')` | built in |
| JSON, JSONL, NDJSON, GeoJSON | `read_json('f.json')` | built in |
| Parquet | `read_parquet('f.parquet')` | built in |
| Excel `.xlsx` | `read_xlsx('f.xlsx')` | `excel` |
| Avro | `read_avro('f.avro')` | `avro` |
| SQLite `.db` / `.sqlite` | `ATTACH 'f.db' AS s (TYPE sqlite); FROM s.tbl;` | `sqlite` |
| Shapefile, GeoPackage, KML, GPX, FlatGeobuf | `ST_Read('f.shp')` | `spatial` |
| GeoParquet | `FROM 'f.geoparquet'` | `spatial` for the functions |
| Iceberg / Delta | `iceberg_scan(…)` / `delta_scan(…)` | `iceberg` / `delta` |
| Raw bytes, or unknown format | `read_blob('f.bin')` | built in |
| Jupyter notebook `.ipynb` | JSON reader plus `UNNEST` — see below | built in |

Install and load in the same command as the query — see `extensions.md`.

### Options worth knowing

```sql
-- Type detection went wrong: pin the types you care about
FROM read_csv('f.csv', types = {'zip': 'VARCHAR', 'amount': 'DOUBLE'});

-- Detection sampled too few rows (default 20480)
FROM read_csv('f.csv', sample_size = -1);      -- -1 scans the whole file

-- Salvage a dirty file
FROM read_csv('f.csv', ignore_errors = true);

-- Nothing parses: read everything as text and clean it in SQL
FROM read_csv('f.csv', all_varchar = true);

-- Non-standard shape
FROM read_csv('f.txt', delim = '|', header = false, skip = 2);
```

If a load fails on a cast, `all_varchar = true` gets you a readable table you can fix
column by column — a better first move than guessing at the delimiter.

### Many files at once

```sql
FROM 'logs/2026-*/*.parquet';                              -- glob
FROM read_csv(['a.csv', 'b.csv']);                         -- explicit list
FROM read_csv('logs/*.csv', union_by_name = true);         -- schemas differ
FROM read_parquet('logs/*.parquet', filename = true);      -- add a filename column
FROM read_parquet('orders/*/*/*.parquet', hive_partitioning = true);
```

`union_by_name` aligns columns by name instead of position — the fix when files gained
or lost a column over time. With Hive-style directories (`year=2026/month=03/`),
`hive_partitioning = true` turns the path components into real, filterable columns.

### Jupyter notebooks

```sql
WITH nb AS (FROM read_json('analysis.ipynb'))
SELECT i AS cell, c.cell_type, array_to_string(c.source, '') AS source
FROM nb, unnest(cells) WITH ORDINALITY AS t(c, i)
ORDER BY cell;
```

### When you do not know the format

Probe cheaply before committing to a reader:

```bash
duckdb -c "FROM read_blob('mystery.bin') SELECT size, content[1:16] AS magic;"
```

Or define a dispatching macro that picks a reader by extension. Every branch must bind,
so load the extensions the branches mention first:

```sql
INSTALL excel; INSTALL avro; LOAD excel; LOAD avro;
CREATE OR REPLACE MACRO read_any(path) AS TABLE
  WITH csv_case     AS (FROM read_csv(path)),
       json_case    AS (FROM read_json(path)),
       parquet_case AS (FROM read_parquet(path)),
       avro_case    AS (FROM read_avro(path)),
       excel_case   AS (FROM read_xlsx(path)),
       blob_case    AS (FROM read_blob(path))
  FROM query_table(
    CASE
      WHEN path ILIKE '%.csv' OR path ILIKE '%.tsv' OR path ILIKE '%.txt' THEN 'csv_case'
      WHEN path ILIKE '%.json' OR path ILIKE '%.jsonl' OR path ILIKE '%.ndjson' THEN 'json_case'
      WHEN path ILIKE '%.parquet' OR path ILIKE '%.pq' THEN 'parquet_case'
      WHEN path ILIKE '%.avro' THEN 'avro_case'
      WHEN path ILIKE '%.xlsx' THEN 'excel_case'
      ELSE 'blob_case'
    END
  );
DESCRIBE FROM read_any('mystery.parquet');
```

Worth it when profiling a directory of mixed formats; overkill for a single known file.

## Writing and converting

One statement converts anything readable into anything writable:

```sql
COPY (FROM 'input.csv') TO 'output.parquet';
```

| Target | Clause | Extension |
|---|---|---|
| Parquet | *(default — no clause needed)* | built in |
| CSV | `(FORMAT csv, HEADER)` | built in |
| TSV | `(FORMAT csv, HEADER, DELIMITER '\t')` | built in |
| JSON array | `(FORMAT json, ARRAY true)` | built in |
| JSON Lines / NDJSON | `(FORMAT json, ARRAY false)` | built in |
| Excel `.xlsx` | `(FORMAT xlsx, HEADER true)` | `excel` |
| GeoJSON | `(FORMAT gdal, DRIVER 'GeoJSON')` | `spatial` |
| GeoPackage | `(FORMAT gdal, DRIVER 'GPKG')` | `spatial` |
| Shapefile | `(FORMAT gdal, DRIVER 'ESRI Shapefile')` | `spatial` |
| A whole database, as SQL + Parquet | `EXPORT DATABASE 'dir' (FORMAT parquet)` | built in |

Compression and partitioning:

```sql
-- Smaller Parquet (default is snappy)
COPY (FROM big) TO 'out.parquet' (COMPRESSION zstd, COMPRESSION_LEVEL 9);

-- Hive-partitioned directory tree
COPY (FROM events) TO 'events' (FORMAT parquet, PARTITION_BY (year, month));

-- Gzipped CSV — inferred from the extension
COPY (FROM t) TO 'out.csv.gz' (FORMAT csv, HEADER);
```

The option is `COMPRESSION`, not `CODEC`. `PARTITION_BY` takes bare column names, not
expressions — compute the column in the subquery first. Writing into a directory that
already has files fails unless you pass `OVERWRITE_OR_IGNORE`, `OVERWRITE` or `APPEND`;
prefer naming a fresh directory over overwriting the user's data.

### Converting: the checklist

1. Resolve the input path; confirm the output path and say so if it already exists.
2. `DESCRIBE FROM '<input>'` — check the inferred types are what the user wants before
   freezing them into Parquet or Excel.
3. Run the `COPY`.
4. Verify and report: `ls -lh <output>` plus
   `duckdb -c "SELECT count() FROM '<output>'"` so the row counts can be compared.

Converting CSV to Parquet usually shrinks the file several-fold and makes later queries
much faster — worth suggesting when the user will query the same CSV repeatedly.
