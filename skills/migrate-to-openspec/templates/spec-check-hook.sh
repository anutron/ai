#!/usr/bin/env bash
#
# Pre-commit hook: blocks commits when behavioral code changes don't include
# corresponding OpenSpec delta updates inside an active change folder.
#
# Active change deltas live at:
#   openspec/changes/<name>/specs/<capability>/spec.md
#
# Install by symlinking into .git/hooks/pre-commit:
#   ln -sf /path/to/spec-check-hook.sh .git/hooks/pre-commit
#
# Bypass with: git commit --no-verify

set -uo pipefail

staged=$(git diff --cached --name-only --diff-filter=ACMR)

if [ -z "$staged" ]; then
  exit 0
fi

# If the project doesn't use OpenSpec, don't gate.
if [ ! -d "openspec" ]; then
  exit 0
fi

code_files=""
has_delta=false

while IFS= read -r file; do
  [ -z "$file" ] && continue

  # Detect staged delta updates inside an active change folder.
  case "$file" in
    openspec/changes/*/specs/*/spec.md)
      has_delta=true
      continue
      ;;
  esac

  # Skip test files
  case "$file" in
    *_test.go|*.test.ts|*.test.js|*.spec.ts|*.spec.js|*_test.py|*/test_*.py|*/tests/*.py) continue ;;
  esac

  # Skip non-behavioral files
  case "$file" in
    *.md|*.json|*.yaml|*.yml|*.toml|*.css|*.lock) continue ;;
    go.mod|go.sum|package.json|package-lock.json|pnpm-lock.yaml) continue ;;
    .gitignore|.cursorrules|.claude/*) continue ;;
    .workflow/*) continue ;;
  esac

  # Match behavioral code files
  case "$file" in
    *.go|*.ts|*.js|*.py|*.sh|*.bash|*.rb|*.rake)
      code_files="$code_files  $file"$'\n'
      ;;
  esac
done <<< "$staged"

# No behavioral code changed – pass
if [ -z "$code_files" ]; then
  exit 0
fi

# At least one delta is staged – pass
if $has_delta; then
  exit 0
fi

# Block the commit
echo ""
echo "SPEC check failed"
echo ""
echo "Behavioral code changed:"
printf '%s' "$code_files"
echo "But no OpenSpec deltas are staged."
echo ""

# Show active change folders if any.
if compgen -G "openspec/changes/*/" > /dev/null; then
  echo "Active changes:"
  for change_dir in openspec/changes/*/; do
    [ -d "$change_dir" ] || continue
    name="${change_dir#openspec/changes/}"
    name="${name%/}"
    echo "  - $name"
  done
  echo ""
fi

echo "Update the relevant change's specs (e.g. openspec/changes/<name>/specs/<capability>/spec.md)"
echo "or use --no-verify to bypass."
echo ""
exit 1
