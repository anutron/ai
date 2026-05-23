#!/bin/bash
# install.sh — User-env installer for the anutron (claude-skills) kit.
#
# Symlinks helper scripts from <source>/.claude/home/bin/ into ~/.claude/bin/
# and registers allowlist entries in ~/.claude/settings.json so the helpers
# run without prompts.
#
# Idempotent — safe to re-run. Never overwrites a non-anutron symlink.

set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed. Install with: brew install jq"
}

# ============================================================
# Locate source repo (mirrors anutron-install/install.sh)
# ============================================================

locate_source() {
  if [ -n "${ANUTRON_SOURCE:-}" ]; then
    echo "$ANUTRON_SOURCE"
    return
  fi

  local cache_dir="$HOME/.claude/anutron-cache"
  if [ -d "$cache_dir" ]; then
    echo "$cache_dir"
    return
  fi

  local script_path
  script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  local real_path
  if command -v greadlink >/dev/null 2>&1; then
    real_path="$(greadlink -f "$script_path")"
  elif readlink -f "$script_path" >/dev/null 2>&1; then
    real_path="$(readlink -f "$script_path")"
  else
    real_path="$script_path"
    while [ -L "$real_path" ]; do
      local target
      target="$(readlink "$real_path")"
      if [[ "$target" == /* ]]; then
        real_path="$target"
      else
        real_path="$(dirname "$real_path")/$target"
      fi
    done
    real_path="$(cd "$(dirname "$real_path")" && pwd)/$(basename "$real_path")"
  fi

  # Walk up from .claude/skills/setup/install.sh to repo root
  local candidate
  candidate="$(dirname "$(dirname "$(dirname "$(dirname "$real_path")")")")"
  if [ -d "$candidate/.claude/home/bin" ] || [ -d "$candidate/home/bin" ]; then
    echo "$candidate"
    return
  fi

  die "Cannot locate claude-skills source repo. Set \$ANUTRON_SOURCE or install via plugin."
}

# ============================================================
# Main
# ============================================================

require_jq

SOURCE="$(locate_source)"

# Source dirs: prefer .claude/home/{bin,hooks} (AI-RON layout), fall back to home/{bin,hooks} (published layout)
if [ -d "$SOURCE/.claude/home/bin" ]; then
  BIN_SOURCE="$SOURCE/.claude/home/bin"
elif [ -d "$SOURCE/home/bin" ]; then
  BIN_SOURCE="$SOURCE/home/bin"
else
  BIN_SOURCE=""
fi

if [ -d "$SOURCE/.claude/home/hooks" ]; then
  HOOKS_SOURCE="$SOURCE/.claude/home/hooks"
elif [ -d "$SOURCE/home/hooks" ]; then
  HOOKS_SOURCE="$SOURCE/home/hooks"
else
  HOOKS_SOURCE=""
fi

if [ -z "$BIN_SOURCE" ] && [ -z "$HOOKS_SOURCE" ]; then
  die "Neither home/bin nor home/hooks found in source: $SOURCE"
fi

BIN_DEST="$HOME/.claude/bin"
HOOKS_DEST="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$BIN_DEST" "$HOOKS_DEST"

installed=0
already=0
conflicts=0
allowlist_added=0

add_allowlist() {
  local rule="$1"
  if [ ! -f "$SETTINGS" ]; then
    echo "  WARN: $SETTINGS not found; skipping allowlist entry for $rule"
    return
  fi
  if jq -e --arg r "$rule" '.permissions.allow | index($r)' "$SETTINGS" >/dev/null 2>&1; then
    return
  fi
  local tmp
  tmp="$(mktemp)"
  jq --arg r "$rule" '.permissions.allow += [$r]' "$SETTINGS" > "$tmp"
  if ! jq empty "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "  ERROR: would have produced invalid JSON; skipping $rule"
    return
  fi
  mv "$tmp" "$SETTINGS"
  allowlist_added=$((allowlist_added + 1))
  echo "  allowlist: $rule"
}

# Generic per-section sync. Returns conflicts on stderr-style line, mutates counters.
sync_dir() {
  local label="$1" src_dir="$2" dest_dir="$3" with_allowlist="$4"

  if [ -z "$src_dir" ]; then
    echo "[$label] no source dir — skipped"
    return
  fi

  echo "[$label] $src_dir -> $dest_dir"

  for src in "$src_dir"/*; do
    [ -f "$src" ] || continue
    local name dest current_target
    name="$(basename "$src")"
    dest="$dest_dir/$name"

    if [ -L "$dest" ]; then
      current_target="$(readlink "$dest")"
      if [ "$current_target" = "$src" ]; then
        echo "  ok:    $name (already linked)"
        already=$((already + 1))
      else
        echo "  CONFLICT: $name -> $current_target (expected $src) — skipped"
        conflicts=$((conflicts + 1))
        continue
      fi
    elif [ -e "$dest" ]; then
      echo "  CONFLICT: $name exists as a regular file at $dest — skipped"
      conflicts=$((conflicts + 1))
      continue
    else
      ln -s "$src" "$dest"
      echo "  link:  $name"
      installed=$((installed + 1))
    fi

    if [ "$with_allowlist" = "yes" ]; then
      add_allowlist "Bash($dest:*)"
    fi
  done

  echo ""
}

sync_dir "bin"   "$BIN_SOURCE"   "$BIN_DEST"   yes
sync_dir "hooks" "$HOOKS_SOURCE" "$HOOKS_DEST" no

# settings.json: single-file sync with stricter semantics (no auto-split — that's
# scripts/split-settings.sh, run once by the originator).
SETTINGS_SOURCE="$SOURCE/.claude/home/settings.json"
[ -f "$SETTINGS_SOURCE" ] || SETTINGS_SOURCE="$SOURCE/home/settings.json"

if [ -f "$SETTINGS_SOURCE" ]; then
  echo "[settings] $SETTINGS_SOURCE -> $SETTINGS"
  if [ -L "$SETTINGS" ]; then
    current_target="$(readlink "$SETTINGS")"
    if [ "$current_target" = "$SETTINGS_SOURCE" ]; then
      echo "  ok:    settings.json (already linked)"
      already=$((already + 1))
    else
      echo "  CONFLICT: settings.json -> $current_target (expected $SETTINGS_SOURCE) — skipped"
      conflicts=$((conflicts + 1))
    fi
  elif [ -f "$SETTINGS" ]; then
    echo "  CONFLICT: $SETTINGS exists as a regular file. To split secrets and adopt"
    echo "            the versioned source, run scripts/split-settings.sh in the source repo."
    echo "            /setup will NOT auto-split — that's a one-time originator operation."
    conflicts=$((conflicts + 1))
  else
    ln -s "$SETTINGS_SOURCE" "$SETTINGS"
    echo "  link:  settings.json"
    echo "  reminder: ~/.claude/settings.local.json holds machine-specific env vars and is NOT versioned."
    echo "            Set OTEL_EXPORTER_OTLP_HEADERS etc. there if you want telemetry."
    installed=$((installed + 1))
  fi
  echo ""
fi

echo "Summary:"
echo "  installed:        $installed"
echo "  already in place: $already"
echo "  conflicts:        $conflicts"
echo "  allowlist added:  $allowlist_added"

if [ "$conflicts" -gt 0 ]; then
  echo ""
  echo "Resolve conflicts manually: inspect the listed paths and either remove the existing symlink/file or move the source to match."
  echo "Note: hooks listed as conflicts likely point to legacy locations (e.g. scripts/). Update them to point at .claude/home/hooks/ once you're ready to converge."
  exit 3
fi
