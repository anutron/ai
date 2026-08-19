#!/usr/bin/env bash
# Compute the next bug ID for the /bugbash skill.
#
# Bug IDs must stay sequential across worktrees, sandboxes, and developers, but
# the .bug-bash/ state folder is gitignored and ephemeral — in a fresh argus
# worktree it starts empty. Counting only local files would reset the counter
# to 001 every session, so the shared branch's git log fills with repeated
# "Fix BUG-001" commits that read like one bug we keep failing to fix.
#
# The fix: derive the next ID from a source of truth that survives the worktree
# and is shared read-only across everyone — git history — combined with any
# local in-flight bug files:
#
#     next_id = max(IDs in .bug-bash/ files, IDs in git log) + 1
#
# This continues the sequence after a worktree reset, picks up other developers'
# fixes once their commits are pulled/merged, and needs no external mutable
# state — it's a pure git read, safe inside sandboxed worktrees (no host write,
# no iris verb). The only gap is two bug bashes allocating simultaneously off
# the same base, which can collide; that's rare and visible at merge time.
#
# Emits the next ID zero-padded to 3 digits (e.g. "008").

set -u

max=0

bump() {
  # $1 may have leading zeros; force base-10 to avoid octal interpretation.
  local n="$1"
  [ -n "$n" ] || return 0
  n=$((10#$n))
  [ "$n" -gt "$max" ] && max=$n
  return 0
}

# 1) Local in-flight bug files: .bug-bash/<status>/bug-NNN.md
while IFS= read -r f; do
  num=$(printf '%s\n' "$f" | grep -oE 'bug-[0-9]+\.md' | grep -oE '[0-9]+')
  bump "$num"
done < <(find .bug-bash -name 'bug-*.md' 2>/dev/null)

# 2) Committed fixes on the current branch and its ancestry: "Fix BUG-NNN: ..."
#    --grep prefilters to keep this fast on large histories.
while IFS= read -r num; do
  bump "$num"
done < <(git log --grep='BUG-' --pretty=%s 2>/dev/null \
           | grep -oE 'BUG-[0-9]+' | grep -oE '[0-9]+')

printf '%03d\n' "$((max + 1))"
