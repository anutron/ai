#!/usr/bin/env bash
# Pre-commit hook for claude-skills: checks for broken links and orphan docs.
#
# Checks:
# 1. Broken relative links in all markdown files
# 2. Published docs/hooks/bin not linked from any markdown file
#
# Exit 0 = clean, exit 1 = problems found.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

errors=0
warnings=0

# Extract link target from markdown [text](target) syntax.
# Returns "line_num:target" pairs, one per line.
# Filters out http(s), mailto, anchors-only, and template placeholders.
extract_links() {
  local file="$1"
  grep -noE '\]\([^)]+\)' "$file" 2>/dev/null \
    | sed 's/](/:/' | sed 's/)$//' | sed 's/^[^:]*:/&/' \
    | while IFS= read -r raw; do
        line_num="${raw%%:*}"
        rest="${raw#*:}"
        # Remove everything up to and including ](
        link="${rest#*:}"
        # Skip non-relative links
        case "$link" in
          http://*|https://*|mailto:*|\#*|\<*) continue ;;
        esac
        [ -z "$link" ] && continue
        echo "$line_num:$link"
      done
}

# --- Check 1: Broken relative links in markdown files ---

while IFS= read -r md_file; do
  dir="$(dirname "$md_file")"

  while IFS=: read -r line_num link_raw; do
    [ -z "$link_raw" ] && continue

    # Strip anchor fragments
    link="${link_raw%%#*}"
    [ -z "$link" ] && continue

    # Resolve relative to the markdown file's directory
    target="$dir/$link"

    if [ ! -e "$target" ]; then
      echo "BROKEN LINK: $md_file:$line_num → $link_raw"
      errors=$((errors + 1))
    fi
  done < <(extract_links "$md_file")
done < <(find . -name '*.md' -not -path './.git/*' -not -path './site/vendor/*' -not -path './vendor/*' -not -path './node_modules/*' | sed 's|^\./||')


# --- Check 2: Orphan published artifacts ---
# Files in docs/, hooks/, bin/ that aren't linked from any markdown file.

all_links_file=$(mktemp)
trap 'rm -f "$all_links_file"' EXIT

# Collect all relative link targets across all markdown files, normalized.
# Links from README.md: docs/foo.md, skills/bar/SKILL.md
# Links from docs/workflow-guide.md: images/foo.png, ../claude-rules/README.md
# We resolve each link relative to its source file to get repo-root-relative paths.
while IFS= read -r md_file; do
  dir="$(dirname "$md_file")"
  while IFS=: read -r _ link_raw; do
    link="${link_raw%%#*}"
    [ -z "$link" ] && continue
    # Normalize: resolve relative path from the file's directory
    # Use Python for reliable path normalization (available on macOS)
    resolved=$(python3 -c "import os.path; print(os.path.normpath('$dir/$link'))" 2>/dev/null || echo "$dir/$link")
    echo "$resolved"
  done < <(extract_links "$md_file")
done < <(find . -name '*.md' -not -path './.git/*' -not -path './site/vendor/*' -not -path './vendor/*' -not -path './node_modules/*' | sed 's|^\./||') \
  | sort -u > "$all_links_file"

check_orphan() {
  local file="$1"
  local basename
  basename="$(basename "$file")"

  # Skip non-content files
  case "$basename" in
    .DS_Store|hooks.json) return ;;
  esac

  # Check if any resolved link points to this file
  if ! grep -qxF "$file" "$all_links_file"; then
    echo "ORPHAN: $file — not linked from any markdown file"
    warnings=$((warnings + 1))
  fi
}

# Check docs
for f in docs/*.md; do
  [ -f "$f" ] || continue
  check_orphan "$f"
done

# Check images
if [ -d docs/images ]; then
  for f in docs/images/*; do
    [ -f "$f" ] || continue
    check_orphan "$f"
  done
fi

# Check hooks
for f in hooks/*.sh; do
  [ -f "$f" ] || continue
  check_orphan "$f"
done

# Check bin
for f in bin/*.sh; do
  [ -f "$f" ] || continue
  check_orphan "$f"
done


# --- Summary ---

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "Found $errors broken link(s). Fix before committing."
  [ "$warnings" -gt 0 ] && echo "Also found $warnings orphan file(s) (warning only)."
  exit 1
fi

if [ "$warnings" -gt 0 ]; then
  echo ""
  echo "Found $warnings orphan file(s) — published but not linked from any markdown."
  echo "(Proceeding anyway — orphans are warnings, not blockers.)"
fi

exit 0
