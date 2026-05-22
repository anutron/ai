#!/usr/bin/env bash
# parse-frontmatter.sh <file> <key>
#
# Extract a single YAML key's value from a markdown file's frontmatter.
# Frontmatter must be the very first block delimited by --- / --- lines.
#
# Supported value shapes:
#   scalar:      key: value
#   inline list: key: [a, b, c]
#
# Block-list (- item lines) is NOT supported.
# Prints each list element (or the scalar) on its own line to stdout.
# Prints nothing if key is absent, no frontmatter, or file not found.
# Always exits 0.

set -euo pipefail

FILE="${1:-}"
KEY="${2:-}"

if [ -z "$FILE" ] || [ -z "$KEY" ]; then
  exit 0
fi

if [ ! -f "$FILE" ]; then
  exit 0
fi

# Read the frontmatter block: must start at line 1 with ---
# and end at the next --- line. If no closing --- found, treat as no frontmatter.

in_frontmatter=0
found_open=0
value=""

while IFS= read -r line; do
  if [ $found_open -eq 0 ]; then
    # First line must be exactly ---
    if [ "$line" = "---" ]; then
      found_open=1
      in_frontmatter=1
      continue
    else
      # Not a frontmatter file
      break
    fi
  fi

  # Inside frontmatter — look for closing ---
  if [ "$line" = "---" ]; then
    in_frontmatter=0
    break
  fi

  # Try to match key: ...
  # Strip leading whitespace for the comparison
  trimmed="${line#"${line%%[![:space:]]*}"}"
  key_prefix="${KEY}: "
  if [[ "$trimmed" == "${KEY}: "* ]] || [[ "$trimmed" == "${KEY}:"* ]]; then
    # Extract value after the colon
    raw_value="${trimmed#*: }"
    # Handle case where there's no space after colon
    if [[ "$trimmed" == "${KEY}:" ]]; then
      raw_value=""
    fi
    value="$raw_value"
  fi
done < "$FILE"

# If we never found an opening ---, nothing to output
if [ $found_open -eq 0 ]; then
  exit 0
fi

# If key wasn't found, nothing to output
if [ -z "$value" ]; then
  exit 0
fi

# Parse value: inline list or scalar
trimmed_value="${value#"${value%%[![:space:]]*}"}"
trimmed_value="${trimmed_value%"${trimmed_value##*[![:space:]]}"}"

if [[ "$trimmed_value" == "["* ]]; then
  # Inline list: [a, b, c]
  # Strip brackets
  inner="${trimmed_value#[}"
  inner="${inner%]}"
  # Split by comma, trim whitespace from each element
  IFS=',' read -ra items <<< "$inner"
  for item in "${items[@]}"; do
    # Trim whitespace
    trimmed_item="${item#"${item%%[![:space:]]*}"}"
    trimmed_item="${trimmed_item%"${trimmed_item##*[![:space:]]}"}"
    if [ -n "$trimmed_item" ]; then
      echo "$trimmed_item"
    fi
  done
else
  # Scalar
  if [ -n "$trimmed_value" ]; then
    echo "$trimmed_value"
  fi
fi

exit 0
