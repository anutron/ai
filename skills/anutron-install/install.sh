#!/bin/bash
# install.sh — Per-project installer for the anutron (claude-skills) kit.
#
# Symlinks skills, installs hooks, compiles CLAUDE.md from snippets,
# and writes a breadcrumb for uninstall/update tracking.
#
# Runs in the current working directory. Idempotent — safe to re-run.

set -euo pipefail

# ============================================================
# Utilities
# ============================================================

die() { echo "Error: $*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed. Install with: brew install jq (macOS) or apt-get install jq (Linux)"
}

iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ============================================================
# 1. Locate source repo
# ============================================================

locate_source() {
  # Priority 1: env var override (for testing)
  if [ -n "${ANUTRON_SOURCE:-}" ]; then
    echo "$ANUTRON_SOURCE"
    return
  fi

  # Priority 2: plugin-cache mode
  local cache_dir="$HOME/.claude/anutron-cache"
  if [ -d "$cache_dir" ]; then
    echo "$cache_dir"
    return
  fi

  # Priority 3: self-locate via readlink (clone+promote mode)
  # The skill lives at ~/.claude/skills/anutron-install/ which may be
  # a symlink back to a clone of claude-skills
  local script_path
  script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Follow symlinks to find the real path
  local real_path
  if command -v greadlink >/dev/null 2>&1; then
    real_path="$(greadlink -f "$script_path")"
  elif readlink -f "$script_path" >/dev/null 2>&1; then
    real_path="$(readlink -f "$script_path")"
  else
    # macOS readlink doesn't support -f; manual resolution
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

  # Walk up from skills/anutron-install/install.sh to repo root
  local candidate
  candidate="$(dirname "$(dirname "$(dirname "$real_path")")")"
  if [ -d "$candidate/skills" ] && [ -d "$candidate/claude-rules/snippets/global" ]; then
    echo "$candidate"
    return
  fi

  die "Cannot locate claude-skills source repo. Set \$ANUTRON_SOURCE or install via plugin."
}

validate_source() {
  local src="$1"
  [ -d "$src/skills" ] || die "Source missing skills/ directory: $src"
  [ -d "$src/claude-rules/snippets/global" ] || die "Source missing claude-rules/snippets/global/: $src"
  [ -d "$src/hooks" ] || die "Source missing hooks/ directory: $src"
}

# ============================================================
# 2. Skill symlinking
# ============================================================

load_exclude_patterns() {
  local src="$1"
  local exclude_file="$src/.publish-exclude"

  if [ -f "$exclude_file" ]; then
    cat "$exclude_file"
  else
    # Default exclude patterns when no .publish-exclude exists
    cat << 'DEFAULTS'
airon-*
thanx-*
baker_st-*
frontend-design
playground
plannotator-*
anutron-install
anutron-uninstall
DEFAULTS
  fi
}

is_excluded() {
  local name="$1"
  shift
  local patterns=("$@")

  for pattern in "${patterns[@]}"; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue

    # Use bash pattern matching (glob-style)
    # shellcheck disable=SC2254
    case "$name" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

install_skills() {
  local src="$1"
  local target_dir="./.claude/skills"
  mkdir -p "$target_dir"

  # Load exclude patterns into array
  local -a patterns=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    patterns+=("$line")
  done < <(load_exclude_patterns "$src")

  local -a installed=()
  local -a added=()
  local -a removed=()
  local -a unchanged=()

  # Remove dangling symlinks
  for link in "$target_dir"/*/; do
    [ -e "$link" ] && continue  # valid, skip
    [ -L "${link%/}" ] || continue  # not a symlink, skip
    local name
    name="$(basename "${link%/}")"
    rm -f "${link%/}"
    removed+=("$name")
  done

  # Also check non-directory symlinks (in case trailing / doesn't work)
  for link in "$target_dir"/*; do
    [ -e "$link" ] && continue
    [ -L "$link" ] || continue
    local name
    name="$(basename "$link")"
    rm -f "$link"
    # Avoid duplicate in removed array
    local already=false
    for r in "${removed[@]+"${removed[@]}"}"; do
      [ "$r" = "$name" ] && already=true && break
    done
    $already || removed+=("$name")
  done

  # Install skills
  for skill_dir in "$src/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    local name
    name="$(basename "$skill_dir")"

    if is_excluded "$name" "${patterns[@]}"; then
      continue
    fi

    local link_path="$target_dir/$name"

    if [ -L "$link_path" ]; then
      # Already a symlink — check if target matches
      local current_target
      current_target="$(readlink "$link_path")"
      local expected_target="${skill_dir%/}"

      if [ "$current_target" = "$expected_target" ]; then
        unchanged+=("$name")
      else
        # Target changed — update
        rm -f "$link_path"
        ln -s "$expected_target" "$link_path"
        added+=("$name")
      fi
    else
      # New skill
      rm -rf "$link_path"  # remove if exists as regular dir
      ln -s "${skill_dir%/}" "$link_path"
      added+=("$name")
    fi

    installed+=("$name")
  done

  # Return results via global vars
  SKILLS_INSTALLED=("${installed[@]+"${installed[@]}"}")
  SKILLS_ADDED=("${added[@]+"${added[@]}"}")
  SKILLS_REMOVED=("${removed[@]+"${removed[@]}"}")
  SKILLS_UNCHANGED=("${unchanged[@]+"${unchanged[@]}"}")
}

# ============================================================
# 3. Hook installation
# ============================================================

install_hooks() {
  local src="$1"
  local hooks_json="$src/hooks/hooks.json"

  if [ ! -f "$hooks_json" ]; then
    HOOKS_INSTALLED=()
    HOOK_KEYS=()
    HOOK_COMMANDS=()
    return
  fi

  local hooks_dir="./.claude/hooks"
  mkdir -p "$hooks_dir"

  local settings_file="./.claude/settings.json"
  local existing_settings="{}"
  if [ -f "$settings_file" ]; then
    existing_settings="$(cat "$settings_file")"
  fi

  # Extract hook commands from hooks.json and symlink the scripts
  # hooks.json structure: { "hooks": { "EventName": [ { "hooks": [ { "type": "command", "command": "path" } ] } ] } }
  local -a hook_keys=()
  local -a hook_commands=()
  local -a new_hooks_entries=()

  # Get all event keys from hooks.json
  local event_keys
  event_keys=$(jq -r '.hooks | keys[]' "$hooks_json" 2>/dev/null || true)

  for event in $event_keys; do
    hook_keys+=("$event")

    # Get all command paths for this event
    local commands
    commands=$(jq -r ".hooks[\"$event\"][] | .hooks[]? | select(.type == \"command\") | .command" "$hooks_json" 2>/dev/null || true)

    local -a event_hook_entries=()

    for cmd_template in $commands; do
      # Resolve ${CLAUDE_PLUGIN_ROOT} to the source repo path
      local resolved_cmd="${cmd_template//\$\{CLAUDE_PLUGIN_ROOT\}/$src}"

      if [ -f "$resolved_cmd" ]; then
        local basename
        basename="$(basename "$resolved_cmd")"

        # Symlink the script into .claude/hooks/
        local local_script="$hooks_dir/$basename"
        ln -sf "$resolved_cmd" "$local_script"

        # Build the rewritten command path (relative to project root, using ./)
        local rewritten_cmd="./.claude/hooks/$basename"
        hook_commands+=("$rewritten_cmd")

        # Build the hook entry JSON for this command
        event_hook_entries+=("$rewritten_cmd")
      fi
    done

    # Build settings.json hook entries for this event
    if [ ${#event_hook_entries[@]} -gt 0 ]; then
      local hooks_array="["
      local first=true
      for cmd in "${event_hook_entries[@]}"; do
        if $first; then first=false; else hooks_array+=","; fi
        hooks_array+="{\"type\":\"command\",\"command\":\"$cmd\"}"
      done
      hooks_array+="]"
      new_hooks_entries+=("\"$event\":[{\"hooks\":$hooks_array}]")
    fi
  done

  # Build the anutron hooks object for settings.json
  local anutron_hooks="{"
  local first=true
  for entry in "${new_hooks_entries[@]+"${new_hooks_entries[@]}"}"; do
    if $first; then first=false; else anutron_hooks+=","; fi
    anutron_hooks+="$entry"
  done
  anutron_hooks+="}"

  # Merge into settings.json
  # Strategy: remove old anutron entries from hooks, add new ones
  # We track which hook commands are ours via anutronInstalled.hookCommands

  # Get list of previously owned commands (if any)
  local old_commands_json="[]"
  if echo "$existing_settings" | jq -e '.anutronInstalled.hookCommands' >/dev/null 2>&1; then
    old_commands_json=$(echo "$existing_settings" | jq '.anutronInstalled.hookCommands')
  fi

  # Remove old anutron hook entries from existing hooks
  local cleaned_hooks
  cleaned_hooks=$(echo "$existing_settings" | jq --argjson old_cmds "$old_commands_json" '
    .hooks // {} |
    to_entries | map(
      .value |= map(
        .hooks |= map(
          select(
            .type != "command" or
            (.command as $cmd | ($old_cmds | index($cmd)) == null)
          )
        )
      ) |
      .value |= map(select(.hooks | length > 0))
    ) |
    map(select(.value | length > 0)) |
    from_entries
  ')

  # Merge anutron hooks into the cleaned hooks
  local merged_hooks
  merged_hooks=$(echo "$cleaned_hooks" | jq --argjson new "$anutron_hooks" '
    . as $existing |
    ($new | to_entries) | reduce .[] as $entry ($existing;
      if .[$entry.key] then
        .[$entry.key] += $entry.value
      else
        .[$entry.key] = $entry.value
      end
    )
  ')

  # Build hook_commands JSON array for the breadcrumb
  local hook_cmds_json="["
  first=true
  for cmd in "${hook_commands[@]+"${hook_commands[@]}"}"; do
    if $first; then first=false; else hook_cmds_json+=","; fi
    hook_cmds_json+="\"$cmd\""
  done
  hook_cmds_json+="]"

  # Build hook_keys JSON array
  local hook_keys_json="["
  first=true
  for key in "${hook_keys[@]+"${hook_keys[@]}"}"; do
    if $first; then first=false; else hook_keys_json+=","; fi
    hook_keys_json+="\"$key\""
  done
  hook_keys_json+="]"

  # Write updated settings.json
  local version
  version=$(get_version "$src")
  local timestamp
  timestamp=$(iso_timestamp)

  echo "$existing_settings" | jq \
    --argjson hooks "$merged_hooks" \
    --argjson hookKeys "$hook_keys_json" \
    --argjson hookCommands "$hook_cmds_json" \
    --arg version "$version" \
    --arg installedAt "$timestamp" \
    --arg source "$src" \
    '. + {
      hooks: $hooks,
      anutronInstalled: {
        version: $version,
        installedAt: $installedAt,
        source: $source,
        hookKeys: $hookKeys,
        hookCommands: $hookCommands
      }
    }' > "$settings_file"

  HOOKS_INSTALLED=("${hook_keys[@]+"${hook_keys[@]}"}")
  HOOK_KEYS=("${hook_keys[@]+"${hook_keys[@]}"}")
  HOOK_COMMANDS=("${hook_commands[@]+"${hook_commands[@]}"}")
  SETTINGS_TIMESTAMP="$timestamp"
}

# ============================================================
# 4. CLAUDE.md compilation
# ============================================================

get_version() {
  local src="$1"
  local plugin_json="$src/.claude-plugin/plugin.json"
  if [ -f "$plugin_json" ]; then
    jq -r '.version' "$plugin_json"
  else
    echo "0.0.0"
  fi
}

compile_claudemd() {
  local src="$1"
  local version
  version=$(get_version "$src")

  local marker_begin="<!-- BEGIN ANUTRON-INSTALL v${version} — do not edit, run /anutron-install to update -->"
  local marker_end="<!-- END ANUTRON-INSTALL -->"

  # Compile snippets
  local snippet_dir="$src/claude-rules/snippets/global"
  local compiled=""
  local snippet_count=0
  local first=true

  for f in "$snippet_dir"/*.md; do
    [ -f "$f" ] || continue
    snippet_count=$((snippet_count + 1))

    if $first; then
      first=false
    else
      compiled+=$'\n\n---\n\n'
    fi
    compiled+="$(cat "$f")"
  done

  # Resolve template variables
  # Built-in variables for anutron context:
  #   CLAUDE_RULES_DIR -> source/claude-rules
  #   PROJECT_DIR -> source repo root (the snippets describe global behaviors)
  #   GLOBAL_TARGET -> ~/.claude/CLAUDE.md
  local rules_dir="$src/claude-rules"
  local global_target="$HOME/.claude/CLAUDE.md"

  compiled="${compiled//\{\{CLAUDE_RULES_DIR\}\}/$rules_dir}"
  compiled="${compiled//\{\{PROJECT_DIR\}\}/$src}"
  compiled="${compiled//\{\{GLOBAL_TARGET\}\}/$global_target}"

  # Custom variables from variables.env
  local envfile="$rules_dir/variables.env"
  if [ -f "$envfile" ]; then
    # Parallel arrays for bash 3.2 compatibility (no associative arrays)
    local var_keys=("CLAUDE_RULES_DIR" "PROJECT_DIR" "GLOBAL_TARGET")
    local var_vals=("$rules_dir" "$src" "$global_target")

    while IFS='=' read -r key val; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      # Resolve {{VAR}} references in the value using known variables
      local i
      for ((i = 0; i < ${#var_keys[@]}; i++)); do
        val="${val//\{\{${var_keys[$i]}\}\}/${var_vals[$i]}}"
      done
      var_keys+=("$key")
      var_vals+=("$val")
      compiled="${compiled//\{\{$key\}\}/$val}"
    done < "$envfile"
  fi

  # Build the delimited block
  local block
  block="$marker_begin"$'\n'"$compiled"$'\n'"$marker_end"

  local claudemd="./CLAUDE.md"

  if [ ! -f "$claudemd" ]; then
    # No existing CLAUDE.md — create with block + placeholder
    printf '%s\n\n%s\n' "$block" "<!-- Your project instructions below -->" > "$claudemd"
  elif grep -qF "BEGIN ANUTRON-INSTALL" "$claudemd"; then
    # Existing markers — replace block in place
    # Write block to temp file so awk can read it (avoids newline issues with -v)
    local block_file
    block_file=$(mktemp)
    printf '%s\n' "$block" > "$block_file"

    local tmp
    tmp=$(mktemp)
    awk -v cfile="$block_file" '
      /BEGIN ANUTRON-INSTALL/ {
        while ((getline line < cfile) > 0) print line
        close(cfile)
        skip = 1
        next
      }
      skip && /END ANUTRON-INSTALL/ {
        skip = 0
        next
      }
      !skip { print }
    ' "$claudemd" > "$tmp"
    mv "$tmp" "$claudemd"
    rm -f "$block_file"
  else
    # Existing CLAUDE.md without markers — insert block at top
    local tmp
    tmp=$(mktemp)
    printf '%s\n\n' "$block" > "$tmp"
    cat "$claudemd" >> "$tmp"
    mv "$tmp" "$claudemd"
  fi

  SNIPPET_COUNT=$snippet_count
  CLAUDEMD_MARKER_BEGIN="$marker_begin"
  CLAUDEMD_MARKER_END="$marker_end"
}

# ============================================================
# 5. Breadcrumb
# ============================================================

write_breadcrumb() {
  local src="$1"
  local version
  version=$(get_version "$src")

  # Build skills JSON array
  local skills_json="["
  local first=true
  for s in "${SKILLS_INSTALLED[@]+"${SKILLS_INSTALLED[@]}"}"; do
    if $first; then first=false; else skills_json+=","; fi
    skills_json+="\"$s\""
  done
  skills_json+="]"

  # Build hooks JSON array
  local hooks_json="["
  first=true
  for h in "${HOOK_KEYS[@]+"${HOOK_KEYS[@]}"}"; do
    if $first; then first=false; else hooks_json+=","; fi
    hooks_json+="\"$h\""
  done
  hooks_json+="]"

  # Build hookCommands JSON array (command paths for uninstall)
  local hook_cmds_json="["
  first=true
  for cmd in "${HOOK_COMMANDS[@]+"${HOOK_COMMANDS[@]}"}"; do
    if $first; then first=false; else hook_cmds_json+=","; fi
    hook_cmds_json+="\"$cmd\""
  done
  hook_cmds_json+="]"

  local timestamp
  timestamp="${SETTINGS_TIMESTAMP:-$(iso_timestamp)}"

  jq -n \
    --arg version "$version" \
    --arg source "$src" \
    --arg installedAt "$timestamp" \
    --argjson skills "$skills_json" \
    --argjson hooks "$hooks_json" \
    --argjson hookCommands "$hook_cmds_json" \
    --arg markerBegin "$CLAUDEMD_MARKER_BEGIN" \
    --arg markerEnd "$CLAUDEMD_MARKER_END" \
    '{
      version: $version,
      source: $source,
      installedAt: $installedAt,
      skills: $skills,
      hooks: $hooks,
      hookCommands: $hookCommands,
      claudeMdMarkers: {
        begin: $markerBegin,
        end: $markerEnd
      }
    }' > ./.anutron-install.json
}

# ============================================================
# 6. Summary
# ============================================================

print_summary() {
  local src="$1"
  local version
  version=$(get_version "$src")
  local project_dir
  project_dir="$(pwd)"

  # Check for existing breadcrumb (determines first-install vs update)
  local old_breadcrumb="./.anutron-install.json.prev"
  local is_update=false
  local old_version=""

  if [ -f "$old_breadcrumb" ]; then
    is_update=true
    old_version=$(jq -r '.version' "$old_breadcrumb" 2>/dev/null || echo "unknown")
  fi

  local skill_count=${#SKILLS_INSTALLED[@]}
  local added_count=${#SKILLS_ADDED[@]}
  local removed_count=${#SKILLS_REMOVED[@]}
  local unchanged_count=${#SKILLS_UNCHANGED[@]}
  local hook_count=${#HOOK_KEYS[@]}

  if $is_update; then
    if [ "$old_version" != "$version" ]; then
      echo "Updated anutron kit (v${old_version} -> v${version}):"
    else
      echo "Updated anutron kit (v${version}):"
    fi

    # Skills detail
    local skill_detail=""
    [ "$added_count" -gt 0 ] && skill_detail+=" +${added_count} added"
    [ "$removed_count" -gt 0 ] && skill_detail+=" -${removed_count} removed"
    [ "$unchanged_count" -gt 0 ] && skill_detail+=" ${unchanged_count} unchanged"
    echo "  Skills: ${skill_count} total${skill_detail:+ ($skill_detail )}"
  else
    echo "Installed anutron kit to ${project_dir}:"
    echo "  Skills: ${skill_count} installed"
  fi

  if [ "$hook_count" -gt 0 ]; then
    local keys_str
    keys_str=$(IFS=', '; echo "${HOOK_KEYS[*]}")
    echo "  Hooks: ${hook_count} registered (${keys_str})"
  else
    echo "  Hooks: none"
  fi

  echo "  CLAUDE.md: compiled from ${SNIPPET_COUNT} snippets"

  if ! $is_update; then
    echo ""
    echo "Try: /brainstorm, /guard, /execute-plan"
    echo "Uninstall: /anutron-uninstall"
  fi

  # Clean up the prev file
  rm -f "$old_breadcrumb"
}

# ============================================================
# Main
# ============================================================

main() {
  require_jq

  # Initialize global state
  SKILLS_INSTALLED=()
  SKILLS_ADDED=()
  SKILLS_REMOVED=()
  SKILLS_UNCHANGED=()
  HOOKS_INSTALLED=()
  HOOK_KEYS=()
  HOOK_COMMANDS=()
  SNIPPET_COUNT=0
  CLAUDEMD_MARKER_BEGIN=""
  CLAUDEMD_MARKER_END=""
  SETTINGS_TIMESTAMP=""

  # Step 1: Locate and validate source
  local source
  source=$(locate_source)
  validate_source "$source"

  # Save old breadcrumb for update detection
  if [ -f ./.anutron-install.json ]; then
    cp ./.anutron-install.json ./.anutron-install.json.prev
  fi

  # Step 2: Install skills
  install_skills "$source"

  # Step 3: Install hooks
  install_hooks "$source"

  # Step 4: Compile CLAUDE.md
  compile_claudemd "$source"

  # Step 5: Write breadcrumb
  write_breadcrumb "$source"

  # Step 6: Print summary
  print_summary "$source"
}

main "$@"
