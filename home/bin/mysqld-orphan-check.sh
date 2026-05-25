#!/usr/bin/env bash
# mysqld-orphan-check.sh — detect mysqld processes whose --datadir directory no longer exists.
#
# When a devbox/nix worktree (sketch and similar) is torn down without first running
# `devbox services stop`, the mysqld keeps running against deleted file handles. The
# inodes stay allocated until the process dies — so disk usage looks "used" to df but
# is invisible to du. This script catches that state before it fills the disk.
#
# Usage:
#   mysqld-orphan-check.sh           Report orphans (exit 0 = clean, 1 = found)
#   mysqld-orphan-check.sh --kill    SIGTERM-then-SIGKILL each orphan, remove stale socket
#   mysqld-orphan-check.sh --quiet   Suppress "all clean" line (cron-friendly)

set -euo pipefail

action=report
quiet=0
for arg in "$@"; do
  case "$arg" in
    --kill)  action=kill ;;
    --quiet) quiet=1 ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg (see --help)" >&2
      exit 2
      ;;
  esac
done

extract_flag() {
  local cmd="$1" flag="$2" val
  val=$(echo "$cmd" | grep -oE -- "--${flag}=[^ ]+" | head -1 | sed "s/^--${flag}=//")
  if [ -z "$val" ]; then
    val=$(echo "$cmd" | grep -oE -- "--${flag} +[^ ]+" | head -1 | awk '{print $2}')
  fi
  echo "$val"
}

found=0
while IFS= read -r line; do
  pid=$(echo "$line" | awk '{print $1}')
  cmd=$(echo "$line" | cut -d' ' -f2-)

  case "$cmd" in
    *"/mysqld "*|*"/mysqld") ;;
    *) continue ;;
  esac

  datadir=$(extract_flag "$cmd" datadir)
  if [ -z "$datadir" ]; then
    [ "$quiet" -eq 0 ] && echo "skip pid=$pid (no --datadir flag)"
    continue
  fi

  if [ -d "$datadir" ]; then
    continue
  fi

  found=$((found + 1))
  echo "ORPHAN pid=$pid datadir=$datadir (gone)"

  if [ "$action" = "kill" ]; then
    if ! ps -p "$pid" -o args= 2>/dev/null | grep -q mysqld; then
      echo "  -> pid $pid is no longer mysqld; skipping"
      continue
    fi

    kill "$pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
      echo "  -> SIGKILL"
    else
      echo "  -> SIGTERM"
    fi

    socket=$(extract_flag "$cmd" socket)
    if [ -n "$socket" ] && [ -S "$socket" ]; then
      rm -f "$socket" && echo "  -> removed stale socket $socket"
    fi
  fi
done < <(ps -axo pid,args= | grep -E '/mysqld( |$)' | grep -v grep || true)

if [ "$found" -eq 0 ]; then
  [ "$quiet" -eq 1 ] || echo "no orphan mysqld processes"
  exit 0
fi

if [ "$action" = "report" ]; then
  echo ""
  echo "Re-run with --kill to terminate them and clean their sockets."
fi
exit 1
