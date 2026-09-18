#!/usr/bin/env bash
# Refresh docs/ from the upstream DuckDB documentation, then rebuild docs/INDEX.md.
#
#   scripts/sync-docs.sh            # track docs/current (the default)
#   scripts/sync-docs.sh lts        # track the LTS docs instead
#
# Upstream: https://github.com/duckdb/duckdb-web/tree/main/docs
set -euo pipefail

CHANNEL="${1:-current}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$SKILL_DIR/docs"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Cloning duckdb-web (sparse: docs/$CHANNEL)..."
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/duckdb/duckdb-web.git "$WORK/duckdb-web" >/dev/null
git -C "$WORK/duckdb-web" sparse-checkout set "docs/$CHANNEL" >/dev/null

SRC="$WORK/duckdb-web/docs/$CHANNEL"
[ -d "$SRC" ] && [ -n "$(ls -A "$SRC")" ] || {
  echo "docs/$CHANNEL is empty or missing upstream" >&2
  exit 1
}

COMMIT="$(git -C "$WORK/duckdb-web" rev-parse HEAD)"
COMMIT_DATE="$(git -C "$WORK/duckdb-web" log -1 --format=%ad --date=short)"

echo "Replacing $DOCS_DIR..."
rm -rf "$DOCS_DIR"
mkdir -p "$DOCS_DIR"
cp -R "$SRC"/. "$DOCS_DIR"/
rm -f "$DOCS_DIR/.gitignore"

cat > "$DOCS_DIR/SOURCE.md" <<META
# Source

These pages are an unmodified copy of the DuckDB documentation.

| | |
|---|---|
| Upstream | https://github.com/duckdb/duckdb-web/tree/main/docs/$CHANNEL |
| Channel | \`$CHANNEL\` |
| Commit | \`$COMMIT\` |
| Commit date | $COMMIT_DATE |
| Synced | $(date -u +%Y-%m-%d) |

Refresh with \`scripts/sync-docs.sh $CHANNEL\`. Do not hand-edit anything in this
directory — edits are lost on the next sync. Corrections belong upstream.
META

"$SKILL_DIR/scripts/build-docs-index.sh"
echo "synced docs/$CHANNEL @ $COMMIT ($COMMIT_DATE)"
