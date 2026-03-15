#!/usr/bin/env bash
# Generate bug bash regression testing report from merged/ bug files
set -euo pipefail

PROJECT_ROOT="${1:-.}"
BUGBASH_DIR="$PROJECT_ROOT/.bug-bash"
MERGED_DIR="$BUGBASH_DIR/merged"
REPORT="$BUGBASH_DIR/report.md"

if [ ! -d "$MERGED_DIR" ]; then
  echo "No merged/ directory found at $MERGED_DIR" >&2
  exit 1
fi

shopt -s nullglob
bugs=("$MERGED_DIR"/bug-*.md)
if [ ${#bugs[@]} -eq 0 ]; then
  echo "No merged bugs to report." >&2
  exit 0
fi

cat > "$REPORT" <<'HEADER'
# Bug Bash — Regression Testing

Instructions: Test each bug below. Add an inline comment on any that fail.
Bugs without comments are assumed to PASS and will be moved to verified.
HEADER

for bugfile in "${bugs[@]}"; do
  title=$(sed -n 's/^title: *//p' "$bugfile" | sed 's/^"//;s/"$//')
  id=$(sed -n 's/^id: *//p' "$bugfile")

  resolution=$(awk '/^## Resolution/{found=1; next} found && /^## /{exit} found && NF{print}' "$bugfile" | head -3 | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')

  expected=$(awk '/^## Expected Behavior/{found=1; next} found && /^## /{exit} found && NF{print}' "$bugfile" | head -3 | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')

  files_changed=$(awk '/^## Files Changed/{found=1; next} found && /^## /{exit} found && /^- /{print}' "$bugfile" | sed 's/^- //' | sed 's/ — .*//' | tr '\n' ', ' | sed 's/, $//')

  if [ -z "$files_changed" ]; then
    files_changed=$(cd "$PROJECT_ROOT" && git log --all --grep="$id" --name-only --pretty=format: 2>/dev/null | sort -u | grep -v '^$' | tr '\n' ', ' | sed 's/, $//') || true
    [ -z "$files_changed" ] && files_changed="See bug file"
  fi

  if [ ${#resolution} -gt 200 ]; then
    resolution="${resolution:0:197}..."
  fi

  cat >> "$REPORT" <<EOF

---

## ${id}: ${title} [needs testing]

- **What was fixed:** ${resolution:-See bug file for details}
- **How to test:** ${expected:-See bug file for expected behavior}
- **Files changed:** ${files_changed}
EOF

done

echo "Report written to $REPORT (${#bugs[@]} bugs)"
