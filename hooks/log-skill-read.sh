#!/bin/bash
# Logs Read tool accesses to skill files for dependency tracking.
# Tracks which skills are loaded as dependencies by other skills,
# even when they're never directly invoked via /command.
# Triggered by PostToolUse hook with matcher "Read".

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only track reads of skill files (markdown within .claude/skills/)
[[ "$FILE_PATH" != */.claude/skills/*.md ]] && exit 0

# Extract skill name from the directory path.
# Skills are directories: .claude/skills/<skill-name>/SKILL.md
# Also handles sub-files: .claude/skills/<skill-name>/some-prompt.md
# Strip everything up to and including ".claude/skills/", then take the first path segment.
SKILL_NAME=$(echo "$FILE_PATH" | sed 's|.*/.claude/skills/||' | cut -d'/' -f1)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="$HOME/.claude/skill-reads.tsv"

# Create header if file does not exist
if [ ! -f "$LOG_FILE" ]; then
  printf "timestamp\tskill\tskill_path\tproject\n" > "$LOG_FILE"
fi

# Deduplicate: skip if same skill was logged in last 5 seconds
# (skills get re-read during multi-step execution)
LAST_LINE=$(tail -1 "$LOG_FILE" 2>/dev/null)
LAST_SKILL=$(echo "$LAST_LINE" | cut -f2)
if [ "$LAST_SKILL" = "$SKILL_NAME" ]; then
  LAST_TS=$(echo "$LAST_LINE" | cut -f1)
  if [ -n "$LAST_TS" ]; then
    LAST_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_TS" +%s 2>/dev/null)
    NOW_EPOCH=$(date -u +%s)
    if [ -n "$LAST_EPOCH" ] && [ $((NOW_EPOCH - LAST_EPOCH)) -lt 5 ]; then
      exit 0
    fi
  fi
fi

printf "%s\t%s\t%s\t%s\n" "$TIMESTAMP" "$SKILL_NAME" "$FILE_PATH" "$PROJECT_DIR" >> "$LOG_FILE"

exit 0
