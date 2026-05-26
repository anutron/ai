#!/usr/bin/env bash
# Emit bug inventory grouped by status folder for the /bugbash skill.
# Lives outside the SKILL.md so command substitution stays out of inline
# context lines (which Claude Code's static analyzer flags).

set -u

any_found=0
for d in todo in-progress blocked merged verified failed conflict; do
  files=$(find ".bug-bash/$d" -name 'bug-*.md' 2>/dev/null)
  if [ -n "$files" ]; then
    printf '[%s]\n%s\n' "$d" "$files"
    any_found=1
  fi
done

if [ "$any_found" = 0 ]; then
  printf '(no bugs found)\n'
fi
