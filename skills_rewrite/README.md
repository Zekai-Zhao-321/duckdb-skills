# skills_rewrite

A rewrite of this repository's DuckDB skills as **one** skill, `duckdb/`, built around
progressive disclosure and portable across agent harnesses.

## What changed

The original `skills/` directory held nine separate skills — `attach-db`, `query`,
`read-file`, `convert-file`, `s3-explore`, `spatial`, `duckdb-docs`, `read-memories`,
`install-duckdb`. Every one of their descriptions was loaded into context up front, they
overlapped heavily (four of them explained S3 credentials), and each was written for the
Claude Code harness specifically: `allowed-tools`, `argument-hint`, `$0`/`$@` argument
placeholders and `/duckdb-skills:<name>` cross-references.

This version is a single skill:

```
duckdb/
├── SKILL.md              # ~1,300 words: the loop, the rules, a routing table
├── reference/            # nine topic files, read only when the task calls for one
│   ├── friendly-sql.md       file-formats.md      remote-storage.md
│   ├── sessions.md           extensions.md        spatial.md
│   └── overture-maps.md      searching-docs.md    session-logs.md
├── docs/                 # all 442 pages of the official DuckDB documentation
│   ├── TOC.md            # generated map of every page, grouped by section
│   ├── SOURCE.md         # upstream commit this copy came from
│   └── functions.json    # machine-readable catalog of every built-in function
└── scripts/
    ├── sync-docs.sh                # refresh docs/ from duckdb/duckdb-web
    ├── build-docs-index.sh         # regenerate docs/TOC.md
    ├── build-functions-catalog.sh  # regenerate docs/functions.json from duckdb_functions()
    └── check-skill.sh              # validate structure, limits and internal links
```

### Progressive disclosure

| Level | Content | Loaded |
|---|---|---|
| 1 | `name` and `description` in the front matter | Always |
| 2 | `SKILL.md` body | When the skill is judged relevant |
| 3 | `reference/*.md` | When the routing table points at one |
| 4 | `docs/**` via `docs/TOC.md` | When a specific page is needed |

Only levels 1 and 2 cost anything on a task that never touches DuckDB, and level 2 is
deliberately short. The 5.5 MB of documentation at level 4 costs nothing until a page is
actually read.

### Portability

The front matter carries `name` and `description` and nothing else, so the skill loads
anywhere the format is understood rather than only in Claude Code. There are no
harness-specific tool names, argument placeholders or slash-command cross-references;
instructions say "run this command" and every SQL snippet works unchanged from the
`duckdb` CLI or the Python client. `scripts/check-skill.sh` enforces this.

## Bundled documentation

`docs/` is an unmodified copy of
[`duckdb-web/docs/current`](https://github.com/duckdb/duckdb-web/tree/main/docs/current),
so DuckDB questions are answered from the source rather than from recall. Refresh it
with:

```bash
duckdb/scripts/sync-docs.sh          # or: sync-docs.sh lts
```

That re-clones upstream, replaces `docs/`, records the commit in `docs/SOURCE.md`,
rebuilds `docs/TOC.md`, and regenerates `docs/functions.json` from the installed `duckdb`
CLI, so it needs the CLI on `PATH`. Do not hand-edit anything under `docs/` — edits are
lost on the next sync.

The generated index is `TOC.md`, not `INDEX.md`: upstream ships its own `docs/index.md`,
and a case-insensitive filesystem (macOS, Windows) keeps only one of the two.

Because `docs/current` tracks the in-development release, a page can describe behaviour
newer than an installed CLI. The skill says so and tells the agent to check
`duckdb --version` when documented syntax fails.

## Checking it

```bash
duckdb/scripts/check-skill.sh
```

Verifies the required front-matter fields are present and the host-specific ones are
not, that the description stays under 1,024 characters and `SKILL.md` under 5,000 words,
that the bundled docs and generated index are complete and in sync, and that every
`reference/`, `docs/` and `scripts/` path mentioned in the prose actually exists.

## Corrections carried in from the old skills

Porting the content surfaced several errors, checked against the bundled docs:

- **Parquet compression** — the option is `COMPRESSION`, not `CODEC`.
- **Spheroid axis order** — `ST_Distance_Spheroid` and friends take
  `[latitude, longitude]`, the opposite of the `(longitude, latitude)` order the old
  spatial skill used. `reference/spatial.md` explains the swap and gives a known-distance
  sanity check.
- **`geometry_always_xy`** — instructed unconditionally by the old skill, but absent from
  the current documentation. Dropped in favour of handling axis order explicitly.
- **Spheroid input types** — only `ST_Distance_Spheroid` and `ST_DWithin_Spheroid`
  require `POINT_2D`; `ST_Area_Spheroid` and `ST_Length_Spheroid` accept `GEOMETRY`.
  `ST_Point2D()` builds a `POINT_2D` directly, without a cast.
- **SQLite** — `ATTACH 'f.db' (TYPE sqlite)` rather than `sqlite_scan()` against
  `sqlite_master`.
- **Bucket listing** — `glob()` returns names without touching file contents, which is
  safer than `read_blob('…/*')` with the `content` column left unselected.
