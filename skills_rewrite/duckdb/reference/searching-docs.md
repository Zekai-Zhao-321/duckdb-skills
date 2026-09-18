# Looking things up

`docs/` holds the complete DuckDB documentation — 442 pages, offline, authoritative.
Consult it rather than trusting recall, especially for exact option names, function
signatures and anything added in a recent release.

## 1. The index

`docs/INDEX.md` lists every page with its path, grouped by section. Read it, pick the
page, read the page. This is the fastest route when you roughly know the area:

| Question about | Section |
|---|---|
| A statement — `COPY`, `ATTACH`, `PIVOT`, `CREATE SECRET` | `docs/sql/statements/` |
| A function's exact signature | `docs/sql/functions/` |
| A type and its casts | `docs/sql/data_types/` |
| Clause behaviour — joins, `GROUP BY`, window frames | `docs/sql/query_syntax/` |
| Reading or writing a format | `docs/data/` |
| A setting or pragma | `docs/configuration/overview.md` |
| An extension's functions | `docs/core_extensions/<name>/` |
| A whole task, end to end | `docs/guides/` |

## 2. Grep

When you do not know which page covers something:

```bash
grep -rli 'asof join' docs/ | head -10                  # which pages mention it
grep -rn 'union_by_name' docs/data/ | head -20          # with line numbers
grep -rn -A 4 '^### list_transform' docs/sql/functions/ # a function's entry
```

Search `docs/sql/` and `docs/data/` before the whole tree — `docs/clients/` is large and
will bury a SQL answer under language-binding noise.

## 3. The function catalog

`docs/functions.json` is every built-in function as structured data — queryable, which
beats grep when you want to search by behaviour rather than by name:

```bash
duckdb -c "
SELECT name, parameters, return_type, description
FROM read_json_auto('docs/functions.json')
WHERE description ILIKE '%levenshtein%' OR name ILIKE '%similar%'
LIMIT 20;
"
```

Run `DESCRIBE FROM read_json_auto('docs/functions.json')` once to see the fields it
actually has before filtering on them.

## 4. Ranked full-text search

For a vague or natural-language question, BM25 ranking beats grep. Build an index over
the bundled pages once; it is self-contained and works offline:

```bash
duckdb ~/.cache/duckdb-docs.duckdb <<'SQL'
INSTALL fts; LOAD fts;
CREATE OR REPLACE TABLE pages AS
    SELECT filename AS path, content AS text
    FROM read_text('docs/**/*.md');
PRAGMA create_fts_index('pages', 'path', 'text', overwrite = 1);
SQL
```

Then query it:

```bash
duckdb ~/.cache/duckdb-docs.duckdb <<'SQL'
LOAD fts;
SELECT path, score
FROM (SELECT path, fts_main_pages.match_bm25(path, 'read csv custom delimiter') AS score
      FROM pages)
WHERE score IS NOT NULL
ORDER BY score DESC LIMIT 8;
SQL
```

Read the top pages that come back. Rebuild the index after running
`scripts/sync-docs.sh`.

DuckDB also publishes a hosted index covering the docs *and* the blog at
`https://duckdb.org/data/docs-search.duckdb` (and DuckLake's at
`https://ducklake.select/data/docs-search.duckdb`), attachable read-only over HTTPS with
`httpfs`. It is worth trying when the user wants blog posts, design rationale or
release-note context that the reference docs do not carry — but it needs network access,
so treat the local index above as the default.

## Version caveat

`docs/` tracks the in-development release (see `docs/SOURCE.md`). A page may describe
behaviour the user's CLI does not have yet. When something documented does not work:

```bash
duckdb --version
```

Compare against the feature's stated version, and say so plainly rather than working
around it silently.

## Diagnosing an error

Search for the distinctive part of the message — a function name, an option, an error
class — not the whole string, which usually contains a path or value unique to this run:

```bash
grep -rn 'Conversion Error' docs/ | head
grep -rli 'could not convert string' docs/data/csv/ | head
```

`docs/guides/troubleshooting/` and `docs/extensions/troubleshooting.md` cover the common
cases directly.
