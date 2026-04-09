#!/usr/bin/env bash
# Syncs publishable skills from AI-RON to this repo.
# Run from the claude-skills repo root.

set -euo pipefail

SOURCE="$HOME/Personal/AI-RON/.claude/skills"
DEST="$(cd "$(dirname "$0")/.." && pwd)/skills"

# Skills to exclude from publishing
EXCLUDE=(
  publish-skills
)

is_excluded() {
  local name="$1"
  # Exclude namespaced personal/work skills (never published)
  [[ "$name" == airon-* ]] && return 0
  [[ "$name" == thanx-* ]] && return 0
  for ex in "${EXCLUDE[@]}"; do
    [[ "$name" == "$ex" ]] && return 0
  done
  return 1
}

# Clean and re-copy
rm -rf "$DEST"
mkdir -p "$DEST"

copied=0
skipped=0

for skill_dir in "$SOURCE"/*/; do
  name="$(basename "$skill_dir")"
  if is_excluded "$name"; then
    echo "  skip: $name"
    skipped=$((skipped + 1))
  else
    cp -r "$skill_dir" "$DEST/$name"
    echo "  copy: $name"
    copied=$((copied + 1))
  fi
done

# Copy bin/ artifacts
BIN_SOURCE="$HOME/Personal/AI-RON/.claude/bin"
BIN_DEST="$(cd "$(dirname "$0")/.." && pwd)/bin"
BIN_PUBLISH=(
  statusline.sh
)

mkdir -p "$BIN_DEST"
bin_copied=0
for f in "${BIN_PUBLISH[@]}"; do
  if [ -f "$BIN_SOURCE/$f" ]; then
    cp "$BIN_SOURCE/$f" "$BIN_DEST/$f"
    echo "  copy: bin/$f"
    bin_copied=$((bin_copied + 1))
  else
    echo "  MISSING: bin/$f"
  fi
done

# Copy docs (blueprints and reference docs)
DOCS_SOURCE="$HOME/Personal/AI-RON/docs"
DOCS_DEST="$(cd "$(dirname "$0")/.." && pwd)/docs"
DOCS_PUBLISH=(
  stack-spectrum.md
  thanx-dev-system.md
)

mkdir -p "$DOCS_DEST"
docs_copied=0
for f in "${DOCS_PUBLISH[@]}"; do
  if [ -f "$DOCS_SOURCE/$f" ]; then
    cp "$DOCS_SOURCE/$f" "$DOCS_DEST/$f"
    echo "  copy: docs/$f"
    docs_copied=$((docs_copied + 1))
  else
    echo "  MISSING: docs/$f"
  fi
done

# Copy claude-rules (snippets + compile.sh + variables.env; README is maintained in claude-skills)
RULES_ROOT="$HOME/Personal/AI-RON/claude-rules"
RULES_DEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)/claude-rules"
RULES_SOURCE="$RULES_ROOT/snippets/global"
RULES_DEST="$RULES_DEST_ROOT/snippets/global"

rm -rf "$RULES_DEST"
mkdir -p "$RULES_DEST"
rules_copied=0
for f in "$RULES_SOURCE"/*.md; do
  cp "$f" "$RULES_DEST/$(basename "$f")"
  rules_copied=$((rules_copied + 1))
done

# Copy compile.sh and variables.env
cp "$RULES_ROOT/compile.sh" "$RULES_DEST_ROOT/compile.sh"
cp "$RULES_ROOT/variables.env" "$RULES_DEST_ROOT/variables.env"
echo "  copy: $rules_copied rule snippets + compile.sh + variables.env"

# Copy hooks
HOOKS_SOURCE="$HOME/Personal/AI-RON/scripts"
HOOKS_DEST="$(cd "$(dirname "$0")/.." && pwd)/hooks"
HOOKS_PUBLISH=(
  log-skill-use.sh
  log-slash-command.sh
)

mkdir -p "$HOOKS_DEST"
hooks_copied=0
for f in "${HOOKS_PUBLISH[@]}"; do
  if [ -f "$HOOKS_SOURCE/$f" ]; then
    cp "$HOOKS_SOURCE/$f" "$HOOKS_DEST/$f"
    echo "  copy: hooks/$f"
    hooks_copied=$((hooks_copied + 1))
  else
    echo "  MISSING: hooks/$f"
  fi
done

echo ""
echo "Published $copied skills ($skipped excluded), $docs_copied docs, $rules_copied rules, $bin_copied bin files, $hooks_copied hooks"
