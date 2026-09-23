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
pages=$(find docs -name '*.md' ! -name 'TOC.md' ! -name 'SOURCE.md' 2>/dev/null | wc -l)
[ "$pages" -gt 100 ] && note OK "$pages documentation pages" || note FAIL "only $pages pages — run scripts/sync-docs.sh"
for f in docs/TOC.md docs/SOURCE.md docs/functions.json; do
  [ -f "$f" ] && note OK "$f" || note FAIL "$f missing"
done

# grep -c prints 0 and exits 1 on no match, so no `|| echo 0` fallback here.
indexed=$(grep -c '^- `' docs/TOC.md 2>/dev/null); indexed=${indexed:-0}
[ "$indexed" -ge "$pages" ] \
  && note OK "TOC.md covers $indexed entries" \
  || note FAIL "TOC.md has $indexed entries for $pages pages — run scripts/build-docs-index.sh"

functions=$(grep -c '{"name":' docs/functions.json 2>/dev/null); functions=${functions:-0}
[ "$functions" -gt 500 ] \
  && note OK "functions.json lists $functions function overloads" \
  || note FAIL "functions.json lists $functions functions — run scripts/build-functions-catalog.sh"

echo "filenames"
# A case-insensitive filesystem (macOS, Windows) silently keeps one of two paths that
# differ only by case, so check what git tracks as well as what is on disk.
collisions="$({ git ls-files . 2>/dev/null; find . -type f | sed 's|^\./||'; } | sort -u \
  | tr '[:upper:]' '[:lower:]' | sort | uniq -d)"
if [ -z "$collisions" ]; then
  note OK "no paths that differ only by case"
else
  while read -r p; do note FAIL "case collision: $p"; done <<< "$collisions"
fi

echo "links"
missing=0
while read -r p; do
  [ -e "$p" ] || { note FAIL "broken link: $p"; missing=$((missing + 1)); }
done < <(grep -ohE '`(reference|docs|scripts)/[A-Za-z0-9_./-]+`' SKILL.md reference/*.md | tr -d '`' | sort -u)
[ "$missing" -eq 0 ] && note OK "all internal links resolve"

echo
[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
