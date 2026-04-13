#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper: ensure the claude-skills repo is cached locally, then delegate
# to the real install.sh. Designed for the plugin distribution path — users who
# installed via `/plugin install anutron-install@anutron/claude-skills`.

CACHE="$HOME/.claude/anutron-cache"

if [ ! -d "$CACHE/.git" ]; then
  echo "Cloning anutron toolkit to $CACHE..."
  git clone https://github.com/anutron/claude-skills "$CACHE"
else
  echo "Updating anutron cache..."
  git -C "$CACHE" pull --ff-only
fi

INSTALL_SCRIPT="$CACHE/skills/anutron-install/install.sh"

if [ ! -f "$INSTALL_SCRIPT" ]; then
  echo "Error: install.sh not found at $INSTALL_SCRIPT" >&2
  echo "The cached clone may be corrupt or outdated. Try removing $CACHE and running again." >&2
  exit 1
fi

exec "$INSTALL_SCRIPT"
