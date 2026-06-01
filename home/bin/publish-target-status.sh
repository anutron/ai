#!/usr/bin/env bash
# Show git status + recent log for the publish target repo (anutron/ai).
#
# Used by the /publish-skills skill's ## Context block. Lives in a script so the
# skill can surface the status without an inline subshell + && chain, which the
# Claude Code static analyzer flags as "shell operators that require approval"
# (and which allowlist rules cannot silence).
#
# Usage:  publish-target-status.sh [TARGET_REPO]
# Output: status (short) + "---" + last 3 commits, or a "not cloned yet" notice.
# Exit:   0 always.

set -u

TARGET="${1:-$HOME/Development/Personal/ai}"

if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    echo "(publish target not cloned yet: $TARGET)"
    exit 0
fi

git -C "$TARGET" status --short
echo "---"
git -C "$TARGET" log --oneline -3
