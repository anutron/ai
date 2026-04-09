#!/bin/bash
# Compares installed version against plugin version.
# Run as a SessionStart hook — prints a one-line nudge if stale.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -z "$PLUGIN_ROOT" ] && exit 0

STAMP="$HOME/.claude/.anutron-claude-skills-version"
[ -f "$STAMP" ] || exit 0

installed=$(cat "$STAMP")
current=$(grep -o '"version": *"[^"]*"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*')
[ -z "$current" ] && exit 0

if [ "$installed" != "$current" ]; then
    echo "claude-skills $current is available (you have $installed). Run /claude-skills:setup to update."
fi
