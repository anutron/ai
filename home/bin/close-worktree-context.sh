#!/usr/bin/env bash
# Emit the context block for the /close-worktree skill.
# All command substitution lives here so the skill template stays free of
# $(...) — which Claude Code's static analysis flags inline.

set -u

pwd_val=$(pwd)

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf -- '- Current directory: %s\n' "$pwd_val"
  printf -- '- Current branch: (not in a git repo)\n'
  printf -- '- Is worktree: no\n'
  printf -- '- Main repo: (not in a git repo)\n'
  printf -- '- Main branch: (not in a git repo)\n'
  printf -- '- Commits ahead: 0\n'
  printf -- '- Uncommitted changes: (not in a git repo)\n'
  exit 0
fi

branch=$(git branch --show-current 2>/dev/null)
[ -z "$branch" ] && branch='(detached HEAD)'

if git rev-parse --git-common-dir 2>/dev/null | grep -q '/worktrees/'; then
  is_worktree='yes'
else
  is_worktree='no'
fi

main_repo=$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')
main_branch_head=$(git -C "$main_repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -n "$main_branch_head" ]; then
  main_branch="$main_branch_head"
else
  main_branch=$(git -C "$main_repo" branch --show-current 2>/dev/null)
  [ -z "$main_branch" ] && main_branch='main'
fi

main_branch_ref=$(git worktree list 2>/dev/null | head -1 | awk '{print $2}')
if [ -n "$main_branch_ref" ]; then
  commits_ahead=$(git log "${main_branch_ref}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
else
  commits_ahead='0'
fi

uncommitted=$(git status --short 2>/dev/null)
[ -z "$uncommitted" ] && uncommitted='(clean)'

printf -- '- Current directory: %s\n' "$pwd_val"
printf -- '- Current branch: %s\n' "$branch"
printf -- '- Is worktree: %s\n' "$is_worktree"
printf -- '- Main repo: %s\n' "$main_repo"
printf -- '- Main branch: %s\n' "$main_branch"
printf -- '- Commits ahead: %s\n' "$commits_ahead"
printf -- '- Uncommitted changes:\n%s\n' "$uncommitted"
