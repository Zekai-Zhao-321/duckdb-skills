# Friendly SQL

DuckDB's dialect removes most of the ceremony from analytical SQL. Using these forms
makes queries shorter, easier for the user to read, and less likely to break when the
schema is not exactly what you assumed.

Canonical pages: `docs/sql/dialect/friendly_sql.md`, `docs/sql/query_syntax/`,
`docs/sql/expressions/star.md`, `docs/sql/functions/`.

## Shape of a query

`FROM` can come first and `SELECT` is optional, so exploration is a single clause:

```sql
FROM 'sales.parquet';                     -- SELECT * FROM 'sales.parquet'
FROM 'sales.parquet' WHERE amount > 100;
FROM 'sales.parquet' LIMIT 10;
```

Full queries read top-down when written `FROM … WHERE … GROUP BY … SELECT`:

```sql
FROM orders
WHERE order_date >= '2026-01-01'
GROUP BY ALL
SELECT region, count() AS orders, sum(amount) AS revenue
ORDER BY revenue DESC
LIMIT 10;
```

| Instead of | Write |
|---|---|
| `count(*)` | `count()` |
| Listing every non-aggregate column after `GROUP BY` | `GROUP BY ALL` |
| Listing every column after `ORDER BY` for determinism | `ORDER BY ALL` |
| `42 AS x` | `x: 42` (prefix alias, also works in `FROM`) |
| `DROP TABLE IF EXISTS t; CREATE TABLE t …` | `CREATE OR REPLACE TABLE t …` |
| Defining a schema before loading | `CREATE TABLE t AS FROM 'f.parquet'` (CTAS) |
| `UNION` that depends on column order | `UNION ALL BY NAME` |
| `INSERT` that depends on column order | `INSERT INTO t BY NAME SELECT …` |
| A top-N window function + subquery | `max(val, 3)` — see below |

Trailing commas are legal in select lists and list literals, so you can reorder lines
freely. Numeric literals may use underscores: `1_000_000`.

## Columns without typing them all out

```sql
SELECT * EXCLUDE (internal_id, raw_blob) FROM events;
SELECT * REPLACE (upper(country) AS country) FROM customers;

-- Apply one expression across many columns
SELECT COLUMNS('.*_amount') * 1.1 FROM invoices;          -- regex
SELECT min(COLUMNS(*)) FROM measurements;                 -- every column
SELECT COLUMNS(c -> c LIKE 'total%') FROM report;         -- lambda
```

`COLUMNS(*)` accepts `EXCLUDE` and `REPLACE` too. This is the tool of choice when the
user says "do X to every column" and you do not want to read the schema first.

## Aliases you can reuse

Aliases are visible in `WHERE`, `GROUP BY`, `HAVING`, and in later select items — no
repeating the expression or wrapping in a subquery. (They are *not* visible in a `JOIN
… ON` clause.)

```sql
SELECT
    revenue - cost AS profit,
    profit / revenue AS margin        -- reuses the alias defined one line up
FROM deals
WHERE margin > 0.2;
```

## Aggregation

```sql
-- Conditional aggregation without CASE
SELECT
    count() FILTER (WHERE status = 'failed')  AS failures,
    count() FILTER (WHERE status = 'ok')      AS successes,
    avg(latency_ms) FILTER (WHERE region = 'EMEA') AS emea_latency
FROM requests;

-- Subtotals at several levels in one pass
SELECT region, product, sum(amount)
FROM sales
GROUP BY ROLLUP (region, product);       -- also CUBE (…) and GROUPING SETS (…)
```

**Top-N per group** — these return a list, no window function needed:

| Function | Returns |
|---|---|
| `max(val, n)` / `min(val, n)` | the n largest / smallest values |
| `arg_max(arg, val, n)` / `arg_min(arg, val, n)` | `arg` for the n rows with the largest / smallest `val` |
| `max_by(arg, val, n)` / `min_by(arg, val, n)` | aliases of `arg_max` / `arg_min` |

```sql
SELECT grp, max(val, 3) AS top3 FROM t GROUP BY grp;
SELECT region, arg_max(product, revenue, 3) AS best_sellers FROM sales GROUP BY region;
```

## Reshaping

```sql
PIVOT sales ON month USING sum(amount) GROUP BY region;      -- long → wide
UNPIVOT monthly_wide ON jan, feb, mar INTO NAME month VALUE amount;  -- wide → long
```

`PIVOT` infers the new column names from the data. See `docs/sql/statements/pivot.md`.

## Joins beyond equality

| Join | Use when |
|---|---|
| `ASOF JOIN … ON a.ts >= b.ts` | Matching each row to the most recent prior row — prices to trades, readings to events. Requires an ordered inequality condition. |
| `LATERAL` / `CROSS JOIN LATERAL (…)` | The subquery needs a column from the left side — per-row top-N, nearest neighbour. |
| `POSITIONAL JOIN` | Two sources line up row-by-row with no key. |

```sql
-- Most recent quote at or before each trade
FROM trades t ASOF JOIN quotes q
  ON t.symbol = q.symbol AND t.ts >= q.ts
SELECT t.ts, t.symbol, t.qty, q.price;

-- Three biggest orders per customer
FROM customers c
CROSS JOIN LATERAL (
    FROM orders o WHERE o.customer_id = c.id
    ORDER BY o.amount DESC LIMIT 3
) o
SELECT c.name, o.id, o.amount;
```

## Expressions, lists and structs

```sql
SELECT 'hello'.upper().reverse();              -- dot chaining: func(x) ≡ x.func()
SELECT [x * 2 FOR x IN [1, 2, 3] IF x > 1];    -- list comprehension → [4, 6]
SELECT my_list[1:3], my_list[-1];              -- slicing; -1 is the last element
SELECT format('{} → {}', a, b) FROM t;         -- string formatting
SELECT s.* FROM (SELECT {'a': 1, 'b': 2} AS s);-- expand a struct into columns
SELECT 'x' IN ['x', 'y'];                      -- IN works on lists and maps
```

Nested data: `docs/sql/data_types/struct.md`, `list.md`, `map.md`;
list/lambda functions: `docs/sql/functions/list.md`, `lambda.md`.

## Variables

```sql
SET VARIABLE cutoff = '2026-01-01';
FROM events WHERE ts >= getvariable('cutoff');
```

Useful for threading one value through a multi-statement command without string
interpolation.

## Profiling and inspection

| Statement | Gives you |
|---|---|
| `DESCRIBE FROM 'f.parquet'` | Column names and types |
| `SUMMARIZE FROM 'f.parquet'` | Per-column min, max, approx unique, avg, stddev, quartiles, null % |
| `FROM duckdb_tables()` | Tables in attached databases, with estimated row counts |
| `FROM duckdb_columns()` | Every column in the catalog |
| `FROM duckdb_extensions()` | Which extensions are installed and loaded |
| `FROM duckdb_settings()` | Every setting and its current value |
| `EXPLAIN ANALYZE <query>` | Where the time actually goes |

`SUMMARIZE` is the single best answer to "profile this dataset" — one command, no
guessing which statistics the user wants.
