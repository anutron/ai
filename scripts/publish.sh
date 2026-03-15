#!/usr/bin/env bash
# Syncs publishable skills from AI-RON to this repo.
# Run from the claude-skills repo root.

set -euo pipefail

SOURCE="$HOME/Personal/AI-RON/.claude/skills"
DEST="$(cd "$(dirname "$0")/.." && pwd)/skills"

# Skills to exclude from publishing
EXCLUDE=(
  steal
  refresh-command-center
  daily-rhythm
  weekly-rhythm
  monthly-rhythm
  logo
  software-best-practices
  bookmark
  paused-sessions
  wind-down
  wind-up
  publish-skills
  set-topic
  todo-agent
)

is_excluded() {
  local name="$1"
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
    ((skipped++))
  else
    cp -r "$skill_dir" "$DEST/$name"
    echo "  copy: $name"
    ((copied++))
  fi
done

echo ""
echo "Published $copied skills ($skipped excluded)"
