#!/usr/bin/env bash
# Validate the skill's structure: front matter, bundled docs, and internal links.
# Usage: scripts/check-skill.sh
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SKILL_DIR"
fail=0
note() { printf '  %-4s %s\n' "$1" "$2"; [ "$1" = "FAIL" ] && fail=1; return 0; }

echo "SKILL.md"
[ -f SKILL.md ] && note OK "present" || note FAIL "missing"

fm="$(awk '/^---$/{n++; next} n==1{print} n>1{exit}' SKILL.md)"
for field in name description; do
  printf '%s\n' "$fm" | grep -q "^$field:" \
    && note OK "front matter has '$field'" \
    || note FAIL "front matter missing '$field'"
done

# Keep the skill portable across harnesses: no host-specific front matter.
for field in allowed-tools argument-hint; do
  printf '%s\n' "$fm" | grep -q "^$field:" \
    && note FAIL "front matter has host-specific '$field'" \
    || note OK "no '$field' (portable)"
done

desc_len=$(printf '%s' "$fm" | sed -n '/^description:/,$p' | tr -d '\n' | wc -c)
[ "$desc_len" -lt 1024 ] \
  && note OK "description is $desc_len chars (limit 1024)" \
  || note FAIL "description is $desc_len chars, over the 1024 limit"

words=$(wc -w < SKILL.md)
[ "$words" -lt 5000 ] \
  && note OK "SKILL.md is $words words (guideline < 5000)" \
  || note FAIL "SKILL.md is $words words, over the 5000-word guideline"

[ -f README.md ] && note FAIL "README.md inside the skill folder" || note OK "no README.md inside the skill"

echo "docs/"
pages=$(find docs -name '*.md' ! -name 'INDEX.md' ! -name 'SOURCE.md' 2>/dev/null | wc -l)
[ "$pages" -gt 100 ] && note OK "$pages documentation pages" || note FAIL "only $pages pages — run scripts/sync-docs.sh"
for f in docs/INDEX.md docs/SOURCE.md docs/functions.json; do
  [ -f "$f" ] && note OK "$f" || note FAIL "$f missing"
done

indexed=$(grep -c '^- `' docs/INDEX.md 2>/dev/null || echo 0)
[ "$indexed" -ge "$pages" ] \
  && note OK "INDEX.md covers $indexed entries" \
  || note FAIL "INDEX.md has $indexed entries for $pages pages — run scripts/build-docs-index.sh"

echo "links"
missing=0
while read -r p; do
  [ -e "$p" ] || { note FAIL "broken link: $p"; missing=$((missing + 1)); }
done < <(grep -ohE '`(reference|docs|scripts)/[A-Za-z0-9_./-]+`' SKILL.md reference/*.md | tr -d '`' | sort -u)
[ "$missing" -eq 0 ] && note OK "all internal links resolve"

echo
[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
