#!/usr/bin/env bash
# Probe whether MAIN_REPO is writable from the current process.
#
# Used by /fixit and /bugbash to decide whether to dispatch through the normal
# in-process worktree path or fall back to sandbox-mode dispatch (host
# task-spawning or staged-command). The probe makes no assumptions about WHY
# MAIN_REPO might be unwritable — sandbox profile, missing dir, perms — and
# treats any failure as sandbox mode.
#
# Usage:  repo-writable-check.sh [MAIN_REPO]
# Output: "ok"      — MAIN_REPO/.claude/ is writable
#         "sandbox" — write failed; caller should use sandbox-mode dispatch
# Exit:   0 always (errors are signaled in output, not exit code)

set -u

MAIN_REPO="${1:-}"
if [ -z "$MAIN_REPO" ]; then
    MAIN_REPO=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
fi

if [ -z "$MAIN_REPO" ] || [ ! -d "$MAIN_REPO" ]; then
    echo "sandbox"
    exit 0
fi

if ! mkdir -p "$MAIN_REPO/.claude" 2>/dev/null; then
    echo "sandbox"
    exit 0
fi

PROBE_FILE="$MAIN_REPO/.claude/.repo-writable-check-$$"
if touch "$PROBE_FILE" 2>/dev/null; then
    rm -f "$PROBE_FILE" 2>/dev/null
    echo "ok"
else
    echo "sandbox"
fi
