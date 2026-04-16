#!/bin/bash
# uninstall.sh — Per-project uninstaller for the anutron (claude-skills) kit.
#
# Reads the breadcrumb (.anutron-install.json) and reverses every
# operation that install.sh performed: removes skill symlinks,
# hook symlinks, anutron entries from settings.json, the delimited
# block from CLAUDE.md, and the breadcrumb itself.
#
# Runs in the current working directory. If run twice: first run
# cleans, second run errors cleanly.

set -euo pipefail

# ============================================================
# Utilities
# ============================================================

die() { echo "Error: $*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed. Install with: brew install jq (macOS) or apt-get install jq (Linux)"
}

# ============================================================
# 1. Read breadcrumb
# ============================================================

read_breadcrumb() {
  local bc="./.anutron-install.json"
  if [ ! -f "$bc" ]; then
    die "No .anutron-install.json found. Either anutron is not installed here, or the breadcrumb was deleted. Manual cleanup: remove .claude/skills, .claude/hooks, anutronInstalled key in .claude/settings.json, and the delimited block in CLAUDE.md."
  fi
  cat "$bc"
}

# ============================================================
# 2. Remove skill symlinks
# ============================================================

remove_skills() {
  local breadcrumb="$1"
  local target_dir="./.claude/skills"
  local removed=0
  local skipped=0
  local -a skipped_names=()

  if [ ! -d "$target_dir" ]; then
    SKILLS_REMOVED=0
    SKILLS_SKIPPED=0
    SKILLS_SKIPPED_NAMES=()
    return
  fi

  local skill_count
  skill_count=$(echo "$breadcrumb" | jq -r '.skills | length')
  local i=0
  while [ "$i" -lt "$skill_count" ]; do
    local name
    name=$(echo "$breadcrumb" | jq -r ".skills[$i]")
    local link_path="$target_dir/$name"

    if [ -L "$link_path" ]; then
      rm -f "$link_path"
      removed=$((removed + 1))
    elif [ -e "$link_path" ]; then
      # Regular file/dir — user may have replaced it
      skipped=$((skipped + 1))
      skipped_names+=("$name")
    fi
    # If doesn't exist: nothing to do
    i=$((i + 1))
  done

  # Remove directory if empty
  if [ -d "$target_dir" ] && [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
    rmdir "$target_dir"
  fi

  SKILLS_REMOVED=$removed
  SKILLS_SKIPPED=$skipped
  SKILLS_SKIPPED_NAMES=("${skipped_names[@]+"${skipped_names[@]}"}")
}

# ============================================================
# 3. Remove hook symlinks
# ============================================================

remove_hooks() {
  local breadcrumb="$1"
  local hooks_dir="./.claude/hooks"
  local removed=0
  local skipped=0
  local -a skipped_names=()
  local -a removed_events=()

  if [ ! -d "$hooks_dir" ]; then
    HOOKS_REMOVED=0
    HOOKS_SKIPPED=0
    HOOKS_SKIPPED_NAMES=()
    HOOKS_REMOVED_EVENTS=()
    return
  fi

  local cmd_count
  cmd_count=$(echo "$breadcrumb" | jq -r '.hookCommands | length')
  local i=0
  while [ "$i" -lt "$cmd_count" ]; do
    local cmd_path
    cmd_path=$(echo "$breadcrumb" | jq -r ".hookCommands[$i]")

    if [ -L "$cmd_path" ]; then
      rm -f "$cmd_path"
      removed=$((removed + 1))
    elif [ -f "$cmd_path" ]; then
      # Regular file — user may have replaced it
      local basename
      basename="$(basename "$cmd_path")"
      skipped=$((skipped + 1))
      skipped_names+=("$basename")
    fi
    i=$((i + 1))
  done

  # Collect event names from breadcrumb
  local hook_count
  hook_count=$(echo "$breadcrumb" | jq -r '.hooks | length')
  i=0
  while [ "$i" -lt "$hook_count" ]; do
    local event
    event=$(echo "$breadcrumb" | jq -r ".hooks[$i]")
    removed_events+=("$event")
    i=$((i + 1))
  done

  # Remove directory if empty
  if [ -d "$hooks_dir" ] && [ -z "$(ls -A "$hooks_dir" 2>/dev/null)" ]; then
    rmdir "$hooks_dir"
  fi

  HOOKS_REMOVED=$removed
  HOOKS_SKIPPED=$skipped
  HOOKS_SKIPPED_NAMES=("${skipped_names[@]+"${skipped_names[@]}"}")
  HOOKS_REMOVED_EVENTS=("${removed_events[@]+"${removed_events[@]}"}")
}

# ============================================================
# 4. Clean settings.json
# ============================================================

clean_settings() {
  local settings_file="./.claude/settings.json"

  if [ ! -f "$settings_file" ]; then
    SETTINGS_CLEANED=false
    return
  fi

  local settings
  settings="$(cat "$settings_file")"

  # Read the list of anutron-owned hook commands from settings.json
  # (not from breadcrumb, since user might have edited settings.json)
  local owned_commands="[]"
  if echo "$settings" | jq -e '.anutronInstalled.hookCommands' >/dev/null 2>&1; then
    owned_commands=$(echo "$settings" | jq '.anutronInstalled.hookCommands')
  fi

  # Remove anutron-owned hook entries from each event's hooks array
  # Then remove empty events and the hooks key if empty
  # Also remove the anutronInstalled key
  local cleaned
  cleaned=$(echo "$settings" | jq --argjson owned "$owned_commands" '
    # Remove anutronInstalled key
    del(.anutronInstalled) |

    # Clean hooks
    if .hooks then
      .hooks |= (
        to_entries | map(
          .value |= map(
            .hooks |= map(
              select(
                .type != "command" or
                (.command as $cmd | ($owned | index($cmd)) == null)
              )
            )
          ) |
          .value |= map(select(.hooks | length > 0))
        ) |
        map(select(.value | length > 0)) |
        from_entries
      ) |
      if .hooks == {} then del(.hooks) else . end
    else
      .
    end
  ')

  # Check if the result is empty
  local is_empty
  is_empty=$(echo "$cleaned" | jq '. == {}')

  if [ "$is_empty" = "true" ]; then
    rm -f "$settings_file"
  else
    echo "$cleaned" > "$settings_file"
  fi

  # Remove .claude/ directory if empty
  if [ -d "./.claude" ] && [ -z "$(ls -A "./.claude" 2>/dev/null)" ]; then
    rmdir "./.claude"
  fi

  SETTINGS_CLEANED=true
}

# ============================================================
# 5. Strip CLAUDE.md block
# ============================================================

strip_claudemd() {
  local breadcrumb="$1"
  local claudemd="./CLAUDE.md"

  if [ ! -f "$claudemd" ]; then
    CLAUDEMD_STRIPPED=false
    CLAUDEMD_NOTE="CLAUDE.md not found, skipped"
    return
  fi

  local marker_begin
  local marker_end
  marker_begin=$(echo "$breadcrumb" | jq -r '.claudeMdMarkers.begin')
  marker_end=$(echo "$breadcrumb" | jq -r '.claudeMdMarkers.end')

  # Check if markers exist in the file
  if ! grep -qF "$marker_begin" "$claudemd" || ! grep -qF "$marker_end" "$claudemd"; then
    CLAUDEMD_STRIPPED=false
    CLAUDEMD_NOTE="markers not found in CLAUDE.md, skipped (may have been manually edited)"
    return
  fi

  # Remove lines from begin marker through end marker (inclusive)
  # Then trim trailing blank lines that immediately followed the block
  local tmp
  tmp=$(mktemp)

  awk -v begin="$marker_begin" -v end="$marker_end" '
    BEGIN { skip = 0 }
    index($0, begin) { skip = 1; next }
    skip && index($0, end) { skip = 0; next }
    !skip { print }
  ' "$claudemd" > "$tmp"

  # Trim leading blank lines (the block was at the top, so removing it may leave blanks)
  local tmp2
  tmp2=$(mktemp)
  awk '
    BEGIN { found_content = 0 }
    /^[[:space:]]*$/ { if (!found_content) next }
    { found_content = 1; print }
  ' "$tmp" > "$tmp2"
  mv "$tmp2" "$tmp"

  # Check if resulting content is empty or just the placeholder
  local content
  content=$(cat "$tmp")
  local trimmed
  trimmed=$(echo "$content" | sed '/^[[:space:]]*$/d')

  if [ -z "$trimmed" ] || [ "$trimmed" = "<!-- Your project instructions below -->" ]; then
    rm -f "$claudemd"
    CLAUDEMD_STRIPPED=true
    CLAUDEMD_NOTE="file deleted (empty after strip)"
  else
    mv "$tmp" "$claudemd"
    CLAUDEMD_STRIPPED=true
    CLAUDEMD_NOTE="stripped delimited block"
  fi

  rm -f "$tmp" 2>/dev/null || true
}

# ============================================================
# 6. Delete breadcrumb
# ============================================================

delete_breadcrumb() {
  rm -f "./.anutron-install.json"
}

# ============================================================
# 7. Print summary
# ============================================================

print_summary() {
  local project_dir
  project_dir="$(pwd)"

  echo "Uninstalled anutron kit from ${project_dir}:"
  echo "  Skills: ${SKILLS_REMOVED} symlinks removed"

  if [ "${SKILLS_SKIPPED:-0}" -gt 0 ]; then
    local names_str=""
    local first=true
    for name in "${SKILLS_SKIPPED_NAMES[@]+"${SKILLS_SKIPPED_NAMES[@]}"}"; do
      if $first; then first=false; else names_str+=", "; fi
      names_str+="$name"
    done
    echo "    (skipped ${SKILLS_SKIPPED}: ${names_str} — not symlinks, may be user-owned)"
  fi

  if [ "${HOOKS_REMOVED:-0}" -gt 0 ]; then
    local events_str=""
    local first=true
    for event in "${HOOKS_REMOVED_EVENTS[@]+"${HOOKS_REMOVED_EVENTS[@]}"}"; do
      if $first; then first=false; else events_str+=", "; fi
      events_str+="$event"
    done
    echo "  Hooks: ${HOOKS_REMOVED} entries removed (${events_str})"
  else
    echo "  Hooks: none to remove"
  fi

  if [ "${HOOKS_SKIPPED:-0}" -gt 0 ]; then
    local hnames_str=""
    local first=true
    for name in "${HOOKS_SKIPPED_NAMES[@]+"${HOOKS_SKIPPED_NAMES[@]}"}"; do
      if $first; then first=false; else hnames_str+=", "; fi
      hnames_str+="$name"
    done
    echo "    (skipped ${HOOKS_SKIPPED}: ${hnames_str} — not symlinks, may be user-owned)"
  fi

  echo "  CLAUDE.md: ${CLAUDEMD_NOTE:-stripped}"
  if [ "$SETTINGS_CLEANED" = "true" ]; then
    echo "  Settings: cleaned"
  else
    echo "  Settings: skipped (no settings.json found)"
  fi
  echo "  Breadcrumb: removed"

  echo ""
  echo "Folder is now in pre-install state (modulo any user edits)."
}

# ============================================================
# Main
# ============================================================

main() {
  require_jq

  # Initialize global state
  SKILLS_REMOVED=0
  SKILLS_SKIPPED=0
  SKILLS_SKIPPED_NAMES=()
  HOOKS_REMOVED=0
  HOOKS_SKIPPED=0
  HOOKS_SKIPPED_NAMES=()
  HOOKS_REMOVED_EVENTS=()
  SETTINGS_CLEANED=false
  CLAUDEMD_STRIPPED=false
  CLAUDEMD_NOTE=""

  # Step 1: Read breadcrumb
  local breadcrumb
  breadcrumb=$(read_breadcrumb)

  # Step 2: Remove skill symlinks
  remove_skills "$breadcrumb"

  # Step 3: Remove hook symlinks
  remove_hooks "$breadcrumb"

  # Step 4: Clean settings.json
  clean_settings

  # Step 5: Strip CLAUDE.md block
  strip_claudemd "$breadcrumb"

  # Step 6: Delete breadcrumb
  delete_breadcrumb

  # Step 7: Print summary
  print_summary
}

main "$@"
