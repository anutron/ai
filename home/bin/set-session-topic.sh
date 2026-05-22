#!/usr/bin/env bash
# set-session-topic.sh — write the topic file for the current Claude Code session.
#
# Usage:
#   set-session-topic.sh "<topic text>"             # unconditional set
#   set-session-topic.sh --initial "<topic text>"   # set only if no topic exists yet
#
# Exits silently and successfully if no SESSION_ID can be resolved (so it's safe to
# invoke from any environment without crashing the caller).

set -euo pipefail

TOPIC_DIR="$HOME/.claude/session-topics"
INITIAL=false

if [ "${1:-}" = "--initial" ]; then
  INITIAL=true
  shift
fi

TOPIC="${1:?usage: set-session-topic.sh [--initial] <topic>}"

# Resolve session ID. Prefer CLAUDE_CODE_SESSION_ID (set by Claude Code in every
# tool-invocation shell). Fall back to the PID map written at session start,
# walking up the process tree — this script runs in a subshell whose $PPID is
# the immediate caller, not the Claude Code process.
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  pid="$PPID"
  for _ in 1 2 3 4; do
    [ -n "$pid" ] && [ "$pid" != "1" ] || break
    map="$TOPIC_DIR/pid-$pid.map"
    if [ -r "$map" ]; then
      SESSION_ID="$(cat "$map" 2>/dev/null || true)"
      [ -n "$SESSION_ID" ] && break
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  done
fi
[ -n "$SESSION_ID" ] || exit 0

TOPIC_FILE="$TOPIC_DIR/${SESSION_ID}.txt"

if $INITIAL && [ -s "$TOPIC_FILE" ]; then
  exit 0
fi

mkdir -p "$TOPIC_DIR"
printf '%s' "$TOPIC" > "$TOPIC_FILE"
