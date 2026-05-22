#!/usr/bin/env bash
# Append a rule to a settings.json permissions.allow array (dedup, validate, backup).
# Usage: add-rule.sh '<rule>' [target-file]
#   <rule>: the allowlist string (single-quote to preserve glob chars)
#   target-file: optional, defaults to ~/.claude/settings.json. May be a project
#                .claude/settings.json or .claude/settings.local.json.

set -euo pipefail

RULE="${1:?usage: add-rule.sh <rule> [target-file]}"
SETTINGS="${2:-$HOME/.claude/settings.json}"

if [ ! -f "$SETTINGS" ]; then
  # If target is a project settings file and doesn't exist, create a minimal one
  if [[ "$SETTINGS" == *".claude/settings"*".json" ]]; then
    mkdir -p "$(dirname "$SETTINGS")"
    echo '{"permissions":{"allow":[],"ask":[],"deny":[]}}' > "$SETTINGS"
    echo "Created: $SETTINGS"
  else
    echo "ERROR: $SETTINGS not found" >&2
    exit 1
  fi
fi

# Safety guardrail: refuse bypass-prone path-based Bash rules.
# Pattern: Bash(/absolute/path/...:*) — path-allowlisting a script.
# Refuse if the script is in a location Claude can freely write to (so the rule
# would grant trust to content that can be silently rewritten). Refuse if it's
# not tracked by git (no audit trail on modifications). Otherwise, surface the
# script content for review before adding the rule.
if [[ "$RULE" =~ ^Bash\(([^:]+) ]]; then
  CMD_PATH="${BASH_REMATCH[1]}"
  if [[ "$CMD_PATH" == /* ]]; then
    # Refuse temp locations Claude has broad Write access to
    case "$CMD_PATH" in
      /tmp/*|/private/tmp/*|/var/folders/*|/var/tmp/*)
        echo "REFUSED: $CMD_PATH is in a temporary location Claude can freely write to." >&2
        echo "         Path-based trust doesn't bind to content — Claude could rewrite the script and the rule would still pass." >&2
        echo "         Move the script to a versioned location (under a git-tracked directory) first." >&2
        exit 4
        ;;
    esac

    # Require the file to exist and be inside a git repo, tracked
    if [ -e "$CMD_PATH" ]; then
      script_dir="$(dirname "$CMD_PATH")"
      if ! git -C "$script_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "REFUSED: $CMD_PATH is not inside a git repository." >&2
        echo "         Path-based allowlists require git tracking so modifications are auditable." >&2
        exit 5
      fi
      if ! git -C "$script_dir" ls-files --error-unmatch "$CMD_PATH" >/dev/null 2>&1; then
        echo "REFUSED: $CMD_PATH exists in a git repo but is not tracked." >&2
        echo "         Commit it first so future modifications appear in git diff." >&2
        echo "         (Untracked file content preview:)" >&2
        head -50 "$CMD_PATH" >&2 2>/dev/null || true
        exit 5
      fi

      # Path is tracked — show content so the user can review what they're authorizing
      echo "--- script content review (first 50 lines) ---" >&2
      head -50 "$CMD_PATH" >&2
      echo "--- end content review ---" >&2
    fi
  fi
fi

if jq -e --arg r "$RULE" '.permissions.allow | index($r)' "$SETTINGS" >/dev/null; then
  echo "Already allowlisted: $RULE"
  exit 0
fi

if jq -e --arg r "$RULE" '.permissions.deny // [] | index($r)' "$SETTINGS" >/dev/null; then
  echo "CONFLICT: rule is in deny list: $RULE" >&2
  exit 2
fi

TS=$(date +%s)
BACKUP="${SETTINGS}.bak.${TS}"
cp "$SETTINGS" "$BACKUP"

TMP=$(mktemp)
jq --arg r "$RULE" '.permissions.allow += [$r]' "$SETTINGS" > "$TMP"

if ! jq empty "$TMP" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON after edit. Backup at $BACKUP" >&2
  rm -f "$TMP"
  exit 1
fi

# Write through the symlink (cat redirection follows symlinks, unlike mv which
# replaces them). This matters now that ~/.claude/settings.json is symlinked to
# the versioned source in the repo.
cat "$TMP" > "$SETTINGS"
rm -f "$TMP"
echo "Added: $RULE"
echo "Backup: $BACKUP"
echo "--- diff ---"
diff "$BACKUP" "$SETTINGS" || true
