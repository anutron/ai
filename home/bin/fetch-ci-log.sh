#!/usr/bin/env bash
# Fetch a CircleCI presigned step-output URL. Never inline curl for CI logs -
# presigned URLs are per-job dynamic tokens that can't be safely allowlisted,
# so the fetch lives here (script path is allowlistable) instead of in a
# raw Bash(curl ...) call.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: fetch-ci-log.sh <presigned-output-url>" >&2
  exit 1
fi

curl -fsSL "$1"
