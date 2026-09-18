# Searching logs and transcripts

Agent transcripts, application logs and event streams are usually newline-delimited JSON
in numbers too large to read directly. DuckDB queries them in place, which beats grep
because you can filter on structure — role, timestamp, level — not just substrings.

Canonical pages: `docs/data/json/`, `docs/sql/functions/text.md`,
`docs/sql/functions/timestamp.md`.

## The shape of it

```bash
duckdb -c "
FROM read_json('<GLOB>', format = 'newline_delimited',
                ignore_errors = true, filename = true)
WHERE <FILTER>
LIMIT 40;
"
```

`ignore_errors = true` matters: log files are often truncated mid-write or contain a
stray non-JSON line, and without it one bad line fails the whole scan. `filename = true`
adds a column telling you which file each row came from.

Inspect the schema before filtering — log formats vary and guessing at field names
wastes a round trip:

```bash
duckdb -c "DESCRIBE FROM read_json('<GLOB>', format = 'newline_delimited', ignore_errors = true) LIMIT 1;"
```

## Agent session transcripts

Coding agents typically keep per-session JSONL under a per-project directory. For Claude
Code that is `~/.claude/projects/<mangled-project-path>/*.jsonl`, where the project path
has its separators replaced by dashes. Check what exists before assuming a layout:

```bash
ls ~/.claude/projects/ 2>/dev/null | head
```

Then search across sessions:

```bash
duckdb -c "
SELECT regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
       strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M')  AS ts,
       message.role                                        AS role,
       left(message.content::VARCHAR, 400)                 AS excerpt
FROM read_json('$HOME/.claude/projects/*/*.jsonl',
                format = 'newline_delimited', ignore_errors = true, filename = true)
WHERE message::VARCHAR ILIKE '%<KEYWORD>%'
  AND message.role IS NOT NULL
ORDER BY timestamp DESC
LIMIT 40;
"
```

Scope to the current project by replacing the glob with that project's directory.

**Use the results, do not recite them.** Extract the decisions, conventions, unresolved
TODOs and corrections that bear on the current task, and carry them into your work. A
wall of pasted transcript is not what the user asked for; a sentence naming what was
decided and when is.

**These transcripts are the user's private history.** Search them when the task calls
for it, quote sparingly, and do not copy them into files or anywhere off the machine.

## Useful shapes

```sql
-- What happened, by day
SELECT timestamp::DATE AS day, count() AS events
FROM read_json('logs/*.jsonl', format = 'newline_delimited', ignore_errors = true)
GROUP BY ALL ORDER BY day;

-- Most common errors
SELECT error.type AS type, count() AS n, min(timestamp) AS first, max(timestamp) AS last
FROM read_json('logs/*.jsonl', format = 'newline_delimited', ignore_errors = true)
WHERE level = 'error'
GROUP BY ALL ORDER BY n DESC LIMIT 20;

-- Fields vary between lines: keep JSON and pull values out by path
SELECT json_extract_string(line, '$.user.id')    AS user_id,
       json_extract_string(line, '$.event.name') AS event
FROM read_json('mixed.jsonl', format = 'newline_delimited',
                columns = {line: 'JSON'}, ignore_errors = true)
LIMIT 20;
```

## When there is a lot of it

Scanning gigabytes of JSON repeatedly is slow. Convert once, then explore at speed:

```bash
duckdb /tmp/logs.duckdb -c "
CREATE TABLE events AS
FROM read_json('logs/**/*.jsonl', format = 'newline_delimited',
                ignore_errors = true, filename = true);
"
duckdb /tmp/logs.duckdb -csv -c "SUMMARIZE events;"
```

Keep the scratch database in a temp location, tell the user it exists, and clean it up
when the task is done.
