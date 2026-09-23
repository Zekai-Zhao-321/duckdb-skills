#!/usr/bin/env bash
# Regenerate docs/functions.json from duckdb_functions() in the installed duckdb CLI.
# Usage: scripts/build-functions-catalog.sh
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$SKILL_DIR/docs/functions.json"
TMP="$OUT.tmp"

command -v duckdb >/dev/null || {
  echo "duckdb CLI not found — install it first (reference/extensions.md)" >&2
  exit 1
}

# One row per overload of every built-in function. `internal` excludes user-defined
# functions; pg_catalog holds only PostgreSQL-compatibility shims, so it is left out.
duckdb -c "
COPY (
  SELECT function_name AS name, function_type AS type, parameters, parameter_types,
         return_type, varargs, description, examples, categories, alias_of
  FROM duckdb_functions()
  WHERE internal AND schema_name = 'main'
  ORDER BY name, type, parameter_types::VARCHAR
) TO '${TMP//\'/\'\'}' (FORMAT json, ARRAY true);
"

rows=$(grep -c '{"name":' "$TMP" || true)
[ "${rows:-0}" -gt 0 ] || { rm -f "$TMP"; echo "duckdb_functions() returned no rows" >&2; exit 1; }
mv "$TMP" "$OUT"

echo "wrote $OUT ($rows function overloads from DuckDB $(duckdb --version))"
