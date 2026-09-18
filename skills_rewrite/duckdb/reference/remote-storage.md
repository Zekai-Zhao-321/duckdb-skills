# S3, GCS, R2, Azure and HTTPS

DuckDB queries object storage in place. It reads only the byte ranges a query needs, so
filtering a 100 GB remote Parquet dataset can move a few megabytes. Never download a
file first just to query it.

Canonical pages: `docs/core_extensions/httpfs/`, `docs/core_extensions/azure.md`,
`docs/configuration/secrets_manager.md`, `docs/guides/network_cloud_storage/`.

## Credentials

`httpfs` handles S3-compatible storage; Azure needs its own extension. Create the secret
in the same command as the query — secrets made with `CREATE SECRET` are session-scoped
and gone when the process exits.

| Storage | URL prefix | Setup |
|---|---|---|
| AWS S3 | `s3://` | `INSTALL httpfs; LOAD httpfs;`<br>`CREATE SECRET (TYPE s3, PROVIDER credential_chain);` |
| Cloudflare R2 | `r2://` | `CREATE SECRET (TYPE r2, ACCOUNT_ID '…', KEY_ID '…', SECRET '…');` |
| Google Cloud Storage | `gs://`, `gcs://` | `CREATE SECRET (TYPE gcs, KEY_ID '…', SECRET '…');` — HMAC keys, not a service-account JSON |
| Azure Blob / ADLS | `az://`, `abfss://` | `INSTALL azure; LOAD azure;`<br>`CREATE SECRET (TYPE azure, PROVIDER credential_chain);` |
| Plain HTTPS | `https://` | `INSTALL httpfs; LOAD httpfs;` — nothing else |
| MinIO or another S3 clone | `s3://` | `CREATE SECRET (TYPE s3, KEY_ID '…', SECRET '…', ENDPOINT 'host:9000', URL_STYLE 'path', USE_SSL false);` |

`PROVIDER credential_chain` reuses whatever the environment already has — environment
variables, `~/.aws/credentials`, an instance or container role. Prefer it: it keeps
secrets out of the command line and out of the transcript. Ask the user for explicit
keys only when the chain fails, and never echo a key back to them.

Public buckets — Overture Maps, AWS Open Data, most `https://` files — need no secret
at all. Try without one first.

```sql
-- Region matters for public S3 buckets that are not in us-east-1
CREATE SECRET (TYPE s3, PROVIDER config, REGION 'us-west-2');
```

To make credentials persist across invocations instead, use
`CREATE PERSISTENT SECRET` (stored unencrypted under `~/.duckdb/stored_secrets`) — tell
the user that is what you are doing before you do it.

## Exploring a bucket

List first, query second. `glob()` returns names only and downloads nothing:

```bash
duckdb -c "
LOAD httpfs;
CREATE SECRET (TYPE s3, PROVIDER credential_chain);
FROM glob('s3://my-bucket/prefix/**') LIMIT 100;
"
```

To see sizes without reading contents, select only the metadata columns from
`read_blob` — never select `content`, which downloads every file:

```sql
SELECT filename, (size / 1024 / 1024)::DECIMAL(10,1) AS mb, last_modified
FROM read_blob('s3://my-bucket/prefix/*')
ORDER BY mb DESC LIMIT 20;
```

For Parquet, the footer alone answers most questions — row counts and compressed size
for a whole dataset, with no column data transferred:

```sql
SELECT file_name,
       sum(row_group_num_rows) AS rows,
       (sum(row_group_compressed_bytes) / 1024 / 1024)::DECIMAL(10,1) AS mb
FROM parquet_metadata('s3://my-bucket/data/*.parquet')
GROUP BY file_name ORDER BY rows DESC;
```

`DESCRIBE FROM 's3://…/file.parquet'` reads only the schema. Use it before any `SELECT`.

## Querying efficiently

- **Filter on partition columns first.** With Hive-style paths, either restrict the glob
  (`'s3://b/year=2026/month=0*/*.parquet'`) or pass `hive_partitioning = true` and put
  the partition column in `WHERE`. Both skip whole files.
- **Project narrowly.** `SELECT a, b` on Parquet reads two column chunks; `SELECT *`
  reads them all. Avoid `FROM 't' LIMIT 10` on wide remote tables — name the columns.
- **Let predicates push down.** A `WHERE` on a Parquet column uses row-group statistics
  to skip data. Wrapping the column in a function (`WHERE upper(region) = 'EMEA'`)
  defeats this; compare the raw column instead.
- **Materialize before iterating.** If you will run several queries against the same
  remote data, pull it down once and work locally:

  ```sql
  CREATE TABLE local AS FROM 's3://bucket/data/*.parquet' WHERE year = 2026;
  ```
- **Set the region** when a bucket is outside `us-east-1`; a wrong region shows up as a
  confusing 400 or a redirect loop rather than a clear error.

## Failures

| Symptom | Cause |
|---|---|
| `HTTP 403` / `Access Denied` | No or wrong credentials. Check the chain resolves: `aws sts get-caller-identity`. For a public bucket, drop the secret entirely |
| `HTTP 404` / `No files found that match the pattern` | Wrong path, wrong bucket, or a glob that matches nothing. List the parent prefix with `glob()` |
| `HTTP 400` on a bucket you can see | Wrong `REGION`, or `URL_STYLE` should be `path` for a non-AWS endpoint |
| `Invalid Input Error: Initialization function ... not found` | `httpfs` not loaded. `INSTALL httpfs; LOAD httpfs;` in the same command |
| Hangs or times out | Glob too broad, or the query is scanning everything. Narrow the prefix, then add `LIMIT` |
| Works locally, fails in CI | The credential chain resolves differently there. Check the role, not the SQL |
