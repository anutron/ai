#!/bin/bash
# install.sh — Per-project installer for the anutron (claude-skills) kit.
#
# Installs skills (symlinks or copies), hooks, and compiles CLAUDE.md from
# snippets. Writes a breadcrumb for uninstall/update tracking.
#
# Runs in the current working directory. Idempotent — safe to re-run.
#
# Flags:
#   --mode=<symlink|copy>     Install mode (defaults: symlink for writable
#                             source, copy for ~/.claude/anutron-cache)
#   --scope=<full|spec-discipline|dev-tools|custom>
#                             Which preset of skills/snippets to install
#                             (default: full)
#   --interactive             Force interactive prompts even if a flag is set
#   --for-contributors        Shortcut for --mode=copy --scope=spec-discipline
#   --help                    Print usage and exit
#
# Environment:
#   ANUTRON_SOURCE            Override source-repo location

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

print_usage() {
  cat <<'USAGE'
Usage: install.sh [flags]

Flags:
  --mode=<symlink|copy>     Install mode. symlink (default for writable source)
                            keeps live edits flowing from the source. copy
                            (default for read-only source / contributor installs)
                            produces self-contained files.
  --scope=<name>            One of: full, spec-discipline, dev-tools, custom.
                            full installs everything (current behaviour).
                            spec-discipline installs spec + TDD + quality.
                            dev-tools adds workflow + PR. custom reads from
                            .anutron-install.config.json in the target.
  --interactive             Force prompts even if other flags would suppress them.
  --for-contributors        Shortcut: --mode=copy --scope=spec-discipline.
  --help, -h                Print this message.

Environment:
  ANUTRON_SOURCE            Override the source repo path.
USAGE
}

# ============================================================
# 1. CLI flag parsing
# ============================================================

# Globals set by parse_args:
#   FLAG_MODE          "symlink" | "copy" | ""
#   FLAG_SCOPE         "full" | "spec-discipline" | "dev-tools" | "custom" | ""
#   FLAG_INTERACTIVE   "1" | "0"
#   FLAG_FOR_CONTRIB   "1" | "0"

parse_args() {
  FLAG_MODE=""
  FLAG_SCOPE=""
  FLAG_INTERACTIVE=0
  FLAG_FOR_CONTRIB=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --mode=*)
        FLAG_MODE="${1#--mode=}"
        case "$FLAG_MODE" in
          symlink|copy) ;;
          *) die "Invalid --mode value: $FLAG_MODE (expected symlink or copy)" ;;
        esac
        ;;
      --mode)
        shift
        FLAG_MODE="${1:-}"
        case "$FLAG_MODE" in
          symlink|copy) ;;
          *) die "Invalid --mode value: $FLAG_MODE (expected symlink or copy)" ;;
        esac
        ;;
      --scope=*)
        FLAG_SCOPE="${1#--scope=}"
        case "$FLAG_SCOPE" in
          full|spec-discipline|dev-tools|custom) ;;
          *) die "Invalid --scope value: $FLAG_SCOPE (expected full, spec-discipline, dev-tools, or custom)" ;;
        esac
        ;;
      --scope)
        shift
        FLAG_SCOPE="${1:-}"
        case "$FLAG_SCOPE" in
          full|spec-discipline|dev-tools|custom) ;;
          *) die "Invalid --scope value: $FLAG_SCOPE (expected full, spec-discipline, dev-tools, or custom)" ;;
        esac
        ;;
      --interactive)
        FLAG_INTERACTIVE=1
        ;;
      --for-contributors)
        FLAG_FOR_CONTRIB=1
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1 (try --help)"
        ;;
    esac
    shift
  done

  # --for-contributors expansion (does not override explicit flags)
  if [ "$FLAG_FOR_CONTRIB" -eq 1 ]; then
    [ -z "$FLAG_MODE" ] && FLAG_MODE="copy"
    [ -z "$FLAG_SCOPE" ] && FLAG_SCOPE="spec-discipline"
  fi
}

# ============================================================
# 2. Locate source repo
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

  local candidate
  candidate="$(dirname "$(dirname "$(dirname "$real_path")")")"
  if [ -d "$candidate/skills" ] && [ -d "$candidate/claude-rules/snippets/global" ]; then
    echo "$candidate"
    return
  fi

  die "Cannot locate claude-skills source repo. Tried all three resolution options:
  1. ANUTRON_SOURCE env var (not set)
  2. ~/.claude/anutron-cache plugin cache (not found)
  3. Self-location: install.sh walked back to a repo root containing skills/ and claude-rules/snippets/global/ (not found)"
}

validate_source() {
  local src="$1"
  [ -d "$src/skills" ] || die "Source missing skills/ directory: $src"
  [ -d "$src/claude-rules/snippets/global" ] || die "Source missing claude-rules/snippets/global/: $src"
  [ -d "$src/hooks" ] || die "Source missing hooks/ directory: $src"
}

# Return 0 if source is treated as read-only (cache install).
source_is_read_only() {
  local src="$1"
  local cache_dir="$HOME/.claude/anutron-cache"
  [ "$src" = "$cache_dir" ]
}

# ============================================================
# 3. Manifest reading
# ============================================================

# Globals set by read_manifest:
#   MANIFEST_PRESENT       "1" | "0"
#   MANIFEST_MODE          "" or value
#   MANIFEST_SCOPE         "" or value
#   MANIFEST_INCLUDE_SKILLS  (array)
#   MANIFEST_EXCLUDE_SKILLS  (array)
#   MANIFEST_INCLUDE_SNIPPETS (array)
#   MANIFEST_EXCLUDE_SNIPPETS (array)

read_manifest() {
  MANIFEST_PRESENT=0
  MANIFEST_MODE=""
  MANIFEST_SCOPE=""
  MANIFEST_INCLUDE_SKILLS=()
  MANIFEST_EXCLUDE_SKILLS=()
  MANIFEST_INCLUDE_SNIPPETS=()
  MANIFEST_EXCLUDE_SNIPPETS=()

  local manifest="./.anutron-install.config.json"
  if [ ! -f "$manifest" ]; then
    return
  fi

  MANIFEST_PRESENT=1

  # Validate JSON
  if ! jq empty "$manifest" >/dev/null 2>&1; then
    die "Manifest .anutron-install.config.json is not valid JSON"
  fi

  MANIFEST_MODE=$(jq -r '.mode // empty' "$manifest")
  MANIFEST_SCOPE=$(jq -r '.scope // empty' "$manifest")

  if [ -n "$MANIFEST_MODE" ]; then
    case "$MANIFEST_MODE" in
      symlink|copy) ;;
      *) die "Manifest mode invalid: $MANIFEST_MODE (expected symlink or copy)" ;;
    esac
  fi

  if [ -n "$MANIFEST_SCOPE" ]; then
    case "$MANIFEST_SCOPE" in
      full|spec-discipline|dev-tools|custom) ;;
      *) die "Manifest scope invalid: $MANIFEST_SCOPE" ;;
    esac
  fi

  # Read array fields
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && MANIFEST_INCLUDE_SKILLS+=("$line")
  done < <(jq -r '.includeSkills[]? // empty' "$manifest" 2>/dev/null)

  while IFS= read -r line; do
    [ -n "$line" ] && MANIFEST_EXCLUDE_SKILLS+=("$line")
  done < <(jq -r '.excludeSkills[]? // empty' "$manifest" 2>/dev/null)

  while IFS= read -r line; do
    [ -n "$line" ] && MANIFEST_INCLUDE_SNIPPETS+=("$line")
  done < <(jq -r '.includeSnippets[]? // empty' "$manifest" 2>/dev/null)

  while IFS= read -r line; do
    [ -n "$line" ] && MANIFEST_EXCLUDE_SNIPPETS+=("$line")
  done < <(jq -r '.excludeSnippets[]? // empty' "$manifest" 2>/dev/null)

  # Warn about unknown top-level keys
  local known='["mode","scope","includeSkills","excludeSkills","includeSnippets","excludeSnippets"]'
  local unknown_keys
  unknown_keys=$(jq -r --argjson known "$known" '
    keys[] | select(. as $k | $known | index($k) | not)
  ' "$manifest" 2>/dev/null || true)
  if [ -n "$unknown_keys" ]; then
    local k
    while IFS= read -r k; do
      [ -n "$k" ] && echo "Warning: unknown manifest key: $k" >&2
    done <<< "$unknown_keys"
  fi
}

# ============================================================
# 4. Interactive prompts
# ============================================================

interactive_prompt() {
  # Sets PROMPTED_MODE and PROMPTED_SCOPE, optionally writes manifest.
  PROMPTED_MODE=""
  PROMPTED_SCOPE=""

  echo ""
  echo "Install mode?"
  echo "  1) symlink (live edits from source)"
  echo "  2) copy    (self-contained, share with contributors)"
  local mode_choice=""
  while [ -z "$mode_choice" ]; do
    printf "Choice [1-2]: "
    read -r mode_choice || mode_choice=""
    case "$mode_choice" in
      1) PROMPTED_MODE="symlink" ;;
      2) PROMPTED_MODE="copy" ;;
      *) echo "Please enter 1 or 2."; mode_choice="" ;;
    esac
  done

  echo ""
  echo "Scope?"
  echo "  1) full              (everything)"
  echo "  2) spec-discipline   (spec + TDD + quality gates — recommended for contributors)"
  echo "  3) dev-tools         (spec-discipline + workflow + PR shipping)"
  echo "  4) custom            (requires .anutron-install.config.json)"
  local scope_choice=""
  while [ -z "$scope_choice" ]; do
    printf "Choice [1-4]: "
    read -r scope_choice || scope_choice=""
    case "$scope_choice" in
      1) PROMPTED_SCOPE="full" ;;
      2) PROMPTED_SCOPE="spec-discipline" ;;
      3) PROMPTED_SCOPE="dev-tools" ;;
      4) PROMPTED_SCOPE="custom" ;;
      *) echo "Please enter 1-4."; scope_choice="" ;;
    esac
  done

  echo ""
  printf "Save these choices to .anutron-install.config.json so re-runs are non-interactive? [Y/n]: "
  local save_choice=""
  read -r save_choice || save_choice=""
  case "$save_choice" in
    n|N|no|No|NO) ;;
    *)
      jq -n --arg mode "$PROMPTED_MODE" --arg scope "$PROMPTED_SCOPE" \
        '{mode: $mode, scope: $scope}' > ./.anutron-install.config.json
      echo "Wrote .anutron-install.config.json"
      ;;
  esac
}

# ============================================================
# 5. Resolve final mode and scope
# ============================================================

# Inputs: FLAG_MODE/FLAG_SCOPE, MANIFEST_*, source path, TTY status
# Outputs: RESOLVED_MODE, RESOLVED_SCOPE
resolve_mode_scope() {
  local src="$1"

  # Precedence: CLI flag > manifest > interactive (if TTY+no flag+no manifest) > default
  RESOLVED_MODE="$FLAG_MODE"
  RESOLVED_SCOPE="$FLAG_SCOPE"

  if [ -z "$RESOLVED_MODE" ] && [ -n "${MANIFEST_MODE:-}" ]; then
    RESOLVED_MODE="$MANIFEST_MODE"
  fi
  if [ -z "$RESOLVED_SCOPE" ] && [ -n "${MANIFEST_SCOPE:-}" ]; then
    RESOLVED_SCOPE="$MANIFEST_SCOPE"
  fi

  # Interactive: TTY stdin, no CLI flag for mode/scope, no manifest
  local need_interactive=0
  if [ -t 0 ]; then
    if [ -z "$FLAG_MODE" ] && [ -z "$FLAG_SCOPE" ] && [ "${MANIFEST_PRESENT:-0}" -eq 0 ]; then
      need_interactive=1
    fi
  fi
  if [ "$FLAG_INTERACTIVE" -eq 1 ]; then
    need_interactive=1
  fi

  if [ "$need_interactive" -eq 1 ]; then
    interactive_prompt
    [ -z "$RESOLVED_MODE" ] && RESOLVED_MODE="$PROMPTED_MODE"
    [ -z "$RESOLVED_SCOPE" ] && RESOLVED_SCOPE="$PROMPTED_SCOPE"
  fi

  # Defaults
  if [ -z "$RESOLVED_MODE" ]; then
    if source_is_read_only "$src"; then
      RESOLVED_MODE="copy"
    else
      RESOLVED_MODE="symlink"
    fi
  fi
  if [ -z "$RESOLVED_SCOPE" ]; then
    RESOLVED_SCOPE="full"
  fi
}

# ============================================================
# 6. Scope resolution
# ============================================================

# Helper: glob-match. Returns 0 if $name matches glob pattern $pattern.
glob_match() {
  local name="$1" pattern="$2"
  case "$name" in
    $pattern) return 0 ;;
  esac
  return 1
}

# Read a preset's resolved fields, recursively applying `extends`.
# Output to globals:
#   PRESET_SKILLS_STAR         "1" | "0"
#   PRESET_SKILL_TAGS          (array)
#   PRESET_EXCLUDE_SKILLS      (array)
#   PRESET_SNIPPETS_STAR       "1" | "0"
#   PRESET_SNIPPET_TAGS        (array)
#   PRESET_SNIPPET_AUDIENCE    (array)
#   PRESET_FROM_MANIFEST       "1" | "0"
load_preset() {
  local src="$1" name="$2"
  local presets_file="$src/claude-rules/scope-presets.json"
  [ -f "$presets_file" ] || die "Scope presets not found: $presets_file"

  PRESET_SKILLS_STAR=0
  PRESET_SKILL_TAGS=()
  PRESET_EXCLUDE_SKILLS=()
  PRESET_SNIPPETS_STAR=0
  PRESET_SNIPPET_TAGS=()
  PRESET_SNIPPET_AUDIENCE=()
  PRESET_FROM_MANIFEST=0

  _load_preset_recursive "$presets_file" "$name"
}

_load_preset_recursive() {
  local presets_file="$1" name="$2"

  # Check preset exists
  if ! jq -e --arg n "$name" '.presets[$n]' "$presets_file" >/dev/null 2>&1; then
    die "Scope preset not found: $name"
  fi

  # If extends, resolve parent first
  local parent
  parent=$(jq -r --arg n "$name" '.presets[$n].extends // empty' "$presets_file")
  if [ -n "$parent" ]; then
    _load_preset_recursive "$presets_file" "$parent"
  fi

  # from: "manifest" marker
  local from
  from=$(jq -r --arg n "$name" '.presets[$n].from // empty' "$presets_file")
  if [ "$from" = "manifest" ]; then
    PRESET_FROM_MANIFEST=1
  fi

  # skills field
  local skills_kind
  skills_kind=$(jq -r --arg n "$name" '.presets[$n].skills | type' "$presets_file" 2>/dev/null || echo "null")
  if [ "$skills_kind" = "string" ]; then
    local s
    s=$(jq -r --arg n "$name" '.presets[$n].skills' "$presets_file")
    if [ "$s" = "*" ]; then
      PRESET_SKILLS_STAR=1
    fi
  fi

  # snippets field
  local snippets_kind
  snippets_kind=$(jq -r --arg n "$name" '.presets[$n].snippets | type' "$presets_file" 2>/dev/null || echo "null")
  if [ "$snippets_kind" = "string" ]; then
    local s
    s=$(jq -r --arg n "$name" '.presets[$n].snippets' "$presets_file")
    if [ "$s" = "*" ]; then
      PRESET_SNIPPETS_STAR=1
    fi
  fi

  # skillTags (additive — replaces parent if specified per design intent: dev-tools sets its own)
  local kind
  kind=$(jq -r --arg n "$name" '.presets[$n].skillTags | type' "$presets_file" 2>/dev/null || echo "null")
  if [ "$kind" = "array" ]; then
    PRESET_SKILL_TAGS=()
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && PRESET_SKILL_TAGS+=("$line")
    done < <(jq -r --arg n "$name" '.presets[$n].skillTags[]' "$presets_file")
  fi

  # excludeSkills (merge with parent — patterns from both apply)
  kind=$(jq -r --arg n "$name" '.presets[$n].excludeSkills | type' "$presets_file" 2>/dev/null || echo "null")
  if [ "$kind" = "array" ]; then
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && PRESET_EXCLUDE_SKILLS+=("$line")
    done < <(jq -r --arg n "$name" '.presets[$n].excludeSkills[]' "$presets_file")
  fi

  # snippetTags
  kind=$(jq -r --arg n "$name" '.presets[$n].snippetTags | type' "$presets_file" 2>/dev/null || echo "null")
  if [ "$kind" = "array" ]; then
    PRESET_SNIPPET_TAGS=()
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && PRESET_SNIPPET_TAGS+=("$line")
    done < <(jq -r --arg n "$name" '.presets[$n].snippetTags[]' "$presets_file")
  fi

  # snippetAudience
  kind=$(jq -r --arg n "$name" '.presets[$n].snippetAudience | type' "$presets_file" 2>/dev/null || echo "null")
  if [ "$kind" = "array" ]; then
    PRESET_SNIPPET_AUDIENCE=()
    local line
    while IFS= read -r line; do
      [ -n "$line" ] && PRESET_SNIPPET_AUDIENCE+=("$line")
    done < <(jq -r --arg n "$name" '.presets[$n].snippetAudience[]' "$presets_file")
  fi
}

# Path to parse-frontmatter.sh helper in the source repo
parse_frontmatter_script() {
  local src="$1"
  echo "$src/claude-rules/lib/parse-frontmatter.sh"
}

# Read tags for a skill into the provided array variable name
get_skill_tags() {
  local src="$1" skill_dir="$2"
  local parser
  parser="$(parse_frontmatter_script "$src")"
  if [ -f "$parser" ] && [ -f "$skill_dir/SKILL.md" ]; then
    bash "$parser" "$skill_dir/SKILL.md" tags
  fi
}

get_snippet_tags() {
  local src="$1" snippet_file="$2"
  local parser
  parser="$(parse_frontmatter_script "$src")"
  if [ -f "$parser" ] && [ -f "$snippet_file" ]; then
    bash "$parser" "$snippet_file" tags
  fi
}

get_snippet_audience() {
  local src="$1" snippet_file="$2"
  local parser
  parser="$(parse_frontmatter_script "$src")"
  if [ -f "$parser" ] && [ -f "$snippet_file" ]; then
    bash "$parser" "$snippet_file" audience
  fi
}

# Returns 0 if any element of array $1 is in array $2.
# Usage: arrays_intersect arr1_name arr2_name
arrays_intersect() {
  # Bash 3.2 — pass as eval-friendly strings
  local -a a1=("${!1}") a2=("${!2}")
  local x y
  for x in "${a1[@]+"${a1[@]}"}"; do
    for y in "${a2[@]+"${a2[@]}"}"; do
      [ "$x" = "$y" ] && return 0
    done
  done
  return 1
}

# Resolve to RESOLVED_SKILLS and RESOLVED_SNIPPETS arrays
resolve_scope() {
  local src="$1" scope="$2"

  RESOLVED_SKILLS=()
  RESOLVED_SNIPPETS=()

  load_preset "$src" "$scope"

  # Manifest-driven (custom scope)
  if [ "$PRESET_FROM_MANIFEST" -eq 1 ]; then
    if [ "${MANIFEST_PRESENT:-0}" -ne 1 ]; then
      die "--scope=custom requires .anutron-install.config.json in the target directory."
    fi
  fi

  # --- Skills ---
  local skill_dir name
  for skill_dir in "$src/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    name="$(basename "$skill_dir")"

    local included=0

    # Per-preset exclude patterns
    local pat
    local excluded=0
    for pat in "${PRESET_EXCLUDE_SKILLS[@]+"${PRESET_EXCLUDE_SKILLS[@]}"}"; do
      if glob_match "$name" "$pat"; then
        excluded=1
        break
      fi
    done

    if [ "$excluded" -eq 1 ]; then
      continue
    fi

    if [ "$PRESET_SKILLS_STAR" -eq 1 ]; then
      included=1
    elif [ "${#PRESET_SKILL_TAGS[@]}" -gt 0 ]; then
      # Read skill tags and intersect with preset tags
      local -a stags=()
      local t
      while IFS= read -r t; do
        [ -n "$t" ] && stags+=("$t")
      done < <(get_skill_tags "$src" "$skill_dir")
      if [ "${#stags[@]}" -gt 0 ]; then
        # Inline intersection for bash 3.2 compat
        local x y matched=0
        for x in "${stags[@]}"; do
          for y in "${PRESET_SKILL_TAGS[@]}"; do
            if [ "$x" = "$y" ]; then matched=1; break; fi
          done
          [ "$matched" -eq 1 ] && break
        done
        [ "$matched" -eq 1 ] && included=1
      fi
    fi

    # Custom-scope: manifest includeSkills picks up named skills
    if [ "$PRESET_FROM_MANIFEST" -eq 1 ]; then
      local m
      for m in "${MANIFEST_INCLUDE_SKILLS[@]+"${MANIFEST_INCLUDE_SKILLS[@]}"}"; do
        if [ "$m" = "$name" ]; then included=1; break; fi
      done
    fi

    if [ "$included" -eq 1 ]; then
      RESOLVED_SKILLS+=("$name")
    fi
  done

  # Apply legacy .publish-exclude to scope=full only (preserves existing test 1)
  if [ "$scope" = "full" ]; then
    local exclude_file="$src/.publish-exclude"
    if [ -f "$exclude_file" ]; then
      local -a publish_patterns=()
      local line
      while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        publish_patterns+=("$line")
      done < "$exclude_file"

      local -a filtered=()
      local n keep p
      for n in "${RESOLVED_SKILLS[@]+"${RESOLVED_SKILLS[@]}"}"; do
        keep=1
        for p in "${publish_patterns[@]+"${publish_patterns[@]}"}"; do
          if glob_match "$n" "$p"; then keep=0; break; fi
        done
        [ "$keep" -eq 1 ] && filtered+=("$n")
      done
      RESOLVED_SKILLS=("${filtered[@]+"${filtered[@]}"}")
    fi
  fi

  # Always exclude anutron-install / anutron-uninstall from any scope
  local -a filtered2=()
  local n
  for n in "${RESOLVED_SKILLS[@]+"${RESOLVED_SKILLS[@]}"}"; do
    if [ "$n" = "anutron-install" ] || [ "$n" = "anutron-uninstall" ]; then
      continue
    fi
    filtered2+=("$n")
  done
  RESOLVED_SKILLS=("${filtered2[@]+"${filtered2[@]}"}")

  # Apply manifest overrides: excludeSkills removes; includeSkills adds (custom scope already handles add via above logic, but for non-custom scopes a manifest can also include extras).
  if [ "${MANIFEST_PRESENT:-0}" -eq 1 ]; then
    # excludeSkills
    local m
    if [ "${#MANIFEST_EXCLUDE_SKILLS[@]}" -gt 0 ]; then
      local -a kept=()
      local n keep
      for n in "${RESOLVED_SKILLS[@]+"${RESOLVED_SKILLS[@]}"}"; do
        keep=1
        for m in "${MANIFEST_EXCLUDE_SKILLS[@]}"; do
          if [ "$n" = "$m" ]; then keep=0; break; fi
        done
        [ "$keep" -eq 1 ] && kept+=("$n")
      done
      RESOLVED_SKILLS=("${kept[@]+"${kept[@]}"}")
    fi
    # includeSkills (non-custom adds; custom handled above)
    if [ "$PRESET_FROM_MANIFEST" -ne 1 ] && [ "${#MANIFEST_INCLUDE_SKILLS[@]}" -gt 0 ]; then
      for m in "${MANIFEST_INCLUDE_SKILLS[@]}"; do
        # Only add if skill dir exists
        if [ -d "$src/skills/$m" ]; then
          local already=0
          local n
          for n in "${RESOLVED_SKILLS[@]+"${RESOLVED_SKILLS[@]}"}"; do
            [ "$n" = "$m" ] && already=1 && break
          done
          [ "$already" -eq 0 ] && RESOLVED_SKILLS+=("$m")
        fi
      done
    fi
  fi

  # --- Snippets ---
  local snip_file base
  for snip_file in "$src/claude-rules/snippets/global"/*.md; do
    [ -f "$snip_file" ] || continue
    base="$(basename "$snip_file")"

    local included=0

    if [ "$PRESET_SNIPPETS_STAR" -eq 1 ]; then
      included=1
    else
      # Read tags + audience
      local -a stags=() saud=()
      local t a
      while IFS= read -r t; do
        [ -n "$t" ] && stags+=("$t")
      done < <(get_snippet_tags "$src" "$snip_file")
      while IFS= read -r a; do
        [ -n "$a" ] && saud+=("$a")
      done < <(get_snippet_audience "$src" "$snip_file")

      # Must intersect snippetTags AND snippetAudience (when both specified)
      local tag_ok=0 aud_ok=0

      if [ "${#PRESET_SNIPPET_TAGS[@]}" -eq 0 ]; then
        tag_ok=1
      else
        local x y
        for x in "${stags[@]+"${stags[@]}"}"; do
          for y in "${PRESET_SNIPPET_TAGS[@]}"; do
            [ "$x" = "$y" ] && tag_ok=1 && break
          done
          [ "$tag_ok" -eq 1 ] && break
        done
      fi

      if [ "${#PRESET_SNIPPET_AUDIENCE[@]}" -eq 0 ]; then
        aud_ok=1
      else
        local x y
        for x in "${saud[@]+"${saud[@]}"}"; do
          for y in "${PRESET_SNIPPET_AUDIENCE[@]}"; do
            [ "$x" = "$y" ] && aud_ok=1 && break
          done
          [ "$aud_ok" -eq 1 ] && break
        done
      fi

      if [ "$tag_ok" -eq 1 ] && [ "$aud_ok" -eq 1 ]; then
        included=1
      fi
    fi

    # Custom scope: manifest includeSnippets adds named snippets
    if [ "$PRESET_FROM_MANIFEST" -eq 1 ]; then
      local m
      for m in "${MANIFEST_INCLUDE_SNIPPETS[@]+"${MANIFEST_INCLUDE_SNIPPETS[@]}"}"; do
        if [ "$m" = "$base" ]; then included=1; break; fi
      done
    fi

    if [ "$included" -eq 1 ]; then
      RESOLVED_SNIPPETS+=("$base")
    fi
  done

  # Apply manifest snippet overrides
  if [ "${MANIFEST_PRESENT:-0}" -eq 1 ]; then
    if [ "${#MANIFEST_EXCLUDE_SNIPPETS[@]}" -gt 0 ]; then
      local -a kept=()
      local n keep m
      for n in "${RESOLVED_SNIPPETS[@]+"${RESOLVED_SNIPPETS[@]}"}"; do
        keep=1
        for m in "${MANIFEST_EXCLUDE_SNIPPETS[@]}"; do
          [ "$n" = "$m" ] && keep=0 && break
        done
        [ "$keep" -eq 1 ] && kept+=("$n")
      done
      RESOLVED_SNIPPETS=("${kept[@]+"${kept[@]}"}")
    fi
    if [ "$PRESET_FROM_MANIFEST" -ne 1 ] && [ "${#MANIFEST_INCLUDE_SNIPPETS[@]}" -gt 0 ]; then
      local m
      for m in "${MANIFEST_INCLUDE_SNIPPETS[@]}"; do
        if [ -f "$src/claude-rules/snippets/global/$m" ]; then
          local already=0
          local n
          for n in "${RESOLVED_SNIPPETS[@]+"${RESOLVED_SNIPPETS[@]}"}"; do
            [ "$n" = "$m" ] && already=1 && break
          done
          [ "$already" -eq 0 ] && RESOLVED_SNIPPETS+=("$m")
        fi
      done
    fi
  fi
}

# ============================================================
# 7. Skill installation
# ============================================================

# Strip frontmatter --- ... --- block (if first block) from content read from stdin.
strip_frontmatter_from_file() {
  local file="$1"
  awk '
    BEGIN { state = 0 }
    NR == 1 && /^---$/ { state = 1; next }
    state == 1 && /^---$/ { state = 2; next }
    state == 1 { next }
    { print }
  ' "$file"
}

# Get the source commit (HEAD SHA) or print "null" if not git.
# Only treats $src as a git repo if its top-level matches $src — otherwise we'd
# pick up the commit of an enclosing repo (e.g. fixture inside the kit's worktree).
get_source_commit() {
  local src="$1"
  local toplevel
  toplevel=$(git -C "$src" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -z "$toplevel" ]; then
    echo "null"
    return
  fi
  # Resolve both to absolute paths for comparison
  local src_abs
  src_abs=$(cd "$src" 2>/dev/null && pwd -P)
  local top_abs
  top_abs=$(cd "$toplevel" 2>/dev/null && pwd -P)
  if [ "$src_abs" = "$top_abs" ]; then
    git -C "$src" rev-parse HEAD 2>/dev/null || echo "null"
  else
    echo "null"
  fi
}

# Returns 0 if $name is in RESOLVED_SKILLS
in_resolved_skills() {
  local needle="$1"
  local n
  for n in "${RESOLVED_SKILLS[@]+"${RESOLVED_SKILLS[@]}"}"; do
    [ "$n" = "$needle" ] && return 0
  done
  return 1
}

install_skills() {
  local src="$1" mode="$2"
  local target_dir="./.claude/skills"
  mkdir -p "$target_dir"

  local source_commit
  source_commit=$(get_source_commit "$src")

  # Read prev source commit from breadcrumb (used for copy-mode idempotency)
  local prev_source_commit=""
  local prev_breadcrumb="./.anutron-install.json.prev"
  if [ -f "$prev_breadcrumb" ]; then
    prev_source_commit=$(jq -r '.sourceCommit // empty' "$prev_breadcrumb" 2>/dev/null || echo "")
  fi

  local -a installed=()
  local -a added=()
  local -a removed=()
  local -a unchanged=()

  # Read previously-owned skill names from the prior breadcrumb. We only ever
  # remove things we previously installed; foreign skills (added by the user or
  # other tooling) are left untouched even if they aren't in the current scope.
  local -a prev_owned_skills=()
  if [ -f "$prev_breadcrumb" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && prev_owned_skills+=("$line")
    done < <(jq -r '(.scopeResolution.skills // .skills // [])[]' "$prev_breadcrumb" 2>/dev/null)
  fi

  was_previously_owned() {
    local needle="$1"
    local n
    for n in "${prev_owned_skills[@]+"${prev_owned_skills[@]}"}"; do
      [ "$n" = "$needle" ] && return 0
    done
    return 1
  }

  # 1. Clean up only PREVIOUSLY-OWNED entries that aren't in the current
  #    resolved scope. Foreign skills are skipped.
  local existing
  for existing in "$target_dir"/* "$target_dir"/.[!.]*; do
    [ -e "$existing" ] || [ -L "$existing" ] || continue
    local name
    name="$(basename "$existing")"

    # Skip dotfiles we don't manage
    case "$name" in
      ""|".") continue ;;
    esac

    if in_resolved_skills "$name"; then
      continue
    fi

    if ! was_previously_owned "$name"; then
      # Foreign skill — never installed by anutron. Leave it alone.
      continue
    fi

    # Remove — we previously owned this and the new scope no longer includes it.
    if [ -L "$existing" ]; then
      rm -f "$existing"
      removed+=("$name")
    elif [ -d "$existing" ]; then
      rm -rf "$existing"
      removed+=("$name")
    else
      rm -f "$existing"
      removed+=("$name")
    fi
  done

  # 2. Install/update each resolved skill
  local name
  for name in "${RESOLVED_SKILLS[@]+"${RESOLVED_SKILLS[@]}"}"; do
    local skill_dir="$src/skills/$name"
    [ -d "$skill_dir" ] || continue

    local target_path="$target_dir/$name"

    if [ "$mode" = "symlink" ]; then
      if [ -L "$target_path" ]; then
        local current_target
        current_target="$(readlink "$target_path")"
        if [ "$current_target" = "$skill_dir" ]; then
          unchanged+=("$name")
        else
          rm -f "$target_path"
          ln -s "$skill_dir" "$target_path"
          added+=("$name")
        fi
      else
        # Could be a stale copy directory; remove
        if [ -d "$target_path" ]; then
          rm -rf "$target_path"
        elif [ -e "$target_path" ]; then
          rm -f "$target_path"
        fi
        ln -s "$skill_dir" "$target_path"
        added+=("$name")
      fi
    else
      # copy mode
      # Check if the skill is unchanged before re-copying (idempotency).
      # Strategy: inspect the breadcrumb comment written into the dest SKILL.md during
      # a prior copy. If the breadcrumb records the same source+commit as the current
      # run, the content is identical and we can skip the rm+copy.
      #
      # For git sources: breadcrumb <src>@<source_commit> must match exactly.
      # Fallback for non-git sources (sourceCommit null): breadcrumb <src>@null must
      # be present (proving same source path), then content-diff ignoring that line.
      local skip_copy=0
      if [ ! -L "$target_path" ] && [ -d "$target_path" ]; then
        local skill_md_check="$target_path/SKILL.md"
        if [ -n "$source_commit" ] && [ "$source_commit" != "null" ] && \
           [ -n "$prev_source_commit" ] && [ "$prev_source_commit" != "null" ] && \
           [ "$prev_source_commit" = "$source_commit" ]; then
          # Same git source commit: breadcrumb must match exactly
          local expected_breadcrumb="<!-- anutron-installed-from: ${src}@${source_commit} -->"
          if grep -qF "$expected_breadcrumb" "$skill_md_check" 2>/dev/null; then
            skip_copy=1
          fi
        else
          # Non-git source or different commit: require breadcrumb showing same src,
          # then verify content equality. The breadcrumb is always appended at the end
          # of SKILL.md, so we compare only the first N lines (= source line count).
          local src_breadcrumb_anchor="anutron-installed-from: ${src}@"
          if grep -qF "$src_breadcrumb_anchor" "$skill_md_check" 2>/dev/null; then
            local content_matches=1
            local src_skill_md="$skill_dir/SKILL.md"
            # Compare SKILL.md: take only the first (wc -l of source) lines of dest
            if [ -f "$src_skill_md" ]; then
              local src_line_count
              src_line_count=$(wc -l < "$src_skill_md" | tr -d ' ')
              local tmp_trimmed
              tmp_trimmed="$(mktemp /tmp/anutron-diff-XXXXXX)"
              head -n "$src_line_count" "$skill_md_check" > "$tmp_trimmed" 2>/dev/null || true
              diff "$src_skill_md" "$tmp_trimmed" >/dev/null 2>&1 || content_matches=0
              rm -f "$tmp_trimmed"
            fi
            # Compare all other files individually
            if [ "$content_matches" -eq 1 ]; then
              local f rel
              for f in "$skill_dir"/* "$skill_dir"/.[!.]*; do
                [ -f "$f" ] || continue
                rel="$(basename "$f")"
                [ "$rel" = "SKILL.md" ] && continue
                diff "$f" "$target_path/$rel" >/dev/null 2>&1 || { content_matches=0; break; }
              done
            fi
            if [ "$content_matches" -eq 1 ]; then
              skip_copy=1
            fi
          fi
        fi
      fi

      if [ "$skip_copy" -eq 1 ]; then
        unchanged+=("$name")
      else
        # If existing target is a symlink, replace with copy
        if [ -L "$target_path" ]; then
          rm -f "$target_path"
        fi
        if [ -d "$target_path" ]; then
          rm -rf "$target_path"
        elif [ -e "$target_path" ]; then
          rm -f "$target_path"
        fi
        mkdir -p "$target_path"
        # Copy contents
        # Use a portable form that copies hidden files too
        if command -v cp >/dev/null 2>&1; then
          # Copy everything inside the source dir to the target dir
          ( cd "$skill_dir" && tar cf - . ) | ( cd "$target_path" && tar xf - )
        fi

        # Append source-commit breadcrumb to SKILL.md if present
        local skill_md="$target_path/SKILL.md"
        if [ -f "$skill_md" ]; then
          printf '\n<!-- anutron-installed-from: %s@%s -->\n' "$src" "$source_commit" >> "$skill_md"
        fi
        added+=("$name")
      fi
    fi

    installed+=("$name")
  done

  SKILLS_INSTALLED=("${installed[@]+"${installed[@]}"}")
  SKILLS_ADDED=("${added[@]+"${added[@]}"}")
  SKILLS_REMOVED=("${removed[@]+"${removed[@]}"}")
  SKILLS_UNCHANGED=("${unchanged[@]+"${unchanged[@]}"}")
}

# ============================================================
# 8. Hook installation
# ============================================================

install_hooks() {
  local src="$1" mode="$2"
  local hooks_json="$src/hooks/hooks.json"

  HOOKS_INSTALLED=()
  HOOK_KEYS=()
  HOOK_COMMANDS=()
  SETTINGS_TIMESTAMP=""

  if [ ! -f "$hooks_json" ]; then
    return
  fi

  local hooks_dir="./.claude/hooks"
  mkdir -p "$hooks_dir"

  local settings_file="./.claude/settings.json"
  local existing_settings="{}"
  if [ -f "$settings_file" ]; then
    existing_settings="$(cat "$settings_file")"
  fi

  local -a hook_keys=()
  local -a hook_commands=()
  local -a new_hooks_entries=()

  local event_keys
  event_keys=$(jq -r '.hooks | keys[]' "$hooks_json" 2>/dev/null || true)

  for event in $event_keys; do
    hook_keys+=("$event")
    local commands
    commands=$(jq -r ".hooks[\"$event\"][] | .hooks[]? | select(.type == \"command\") | .command" "$hooks_json" 2>/dev/null || true)

    local -a event_hook_entries=()
    for cmd_template in $commands; do
      local resolved_cmd="${cmd_template//\$\{CLAUDE_PLUGIN_ROOT\}/$src}"
      if [ -f "$resolved_cmd" ]; then
        local basename_v
        basename_v="$(basename "$resolved_cmd")"
        local local_script="$hooks_dir/$basename_v"

        if [ "$mode" = "symlink" ]; then
          # Remove if existing as file
          [ -L "$local_script" ] && rm -f "$local_script"
          [ -f "$local_script" ] && [ ! -L "$local_script" ] && rm -f "$local_script"
          ln -sf "$resolved_cmd" "$local_script"
        else
          # copy mode
          [ -L "$local_script" ] && rm -f "$local_script"
          cp -f "$resolved_cmd" "$local_script"
          chmod +x "$local_script" 2>/dev/null || true
        fi

        local rewritten_cmd="./.claude/hooks/$basename_v"
        hook_commands+=("$rewritten_cmd")
        event_hook_entries+=("$rewritten_cmd")
      fi
    done

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

  local anutron_hooks="{"
  local first=true
  for entry in "${new_hooks_entries[@]+"${new_hooks_entries[@]}"}"; do
    if $first; then first=false; else anutron_hooks+=","; fi
    anutron_hooks+="$entry"
  done
  anutron_hooks+="}"

  local old_commands_json="[]"
  if echo "$existing_settings" | jq -e '.anutronInstalled.hookCommands' >/dev/null 2>&1; then
    old_commands_json=$(echo "$existing_settings" | jq '.anutronInstalled.hookCommands')
  fi

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

  local hook_cmds_json="["
  first=true
  for cmd in "${hook_commands[@]+"${hook_commands[@]}"}"; do
    if $first; then first=false; else hook_cmds_json+=","; fi
    hook_cmds_json+="\"$cmd\""
  done
  hook_cmds_json+="]"

  local hook_keys_json="["
  first=true
  for key in "${hook_keys[@]+"${hook_keys[@]}"}"; do
    if $first; then first=false; else hook_keys_json+=","; fi
    hook_keys_json+="\"$key\""
  done
  hook_keys_json+="]"

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
# 9. CLAUDE.md compilation
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

  local snippet_dir="$src/claude-rules/snippets/global"
  local compiled=""
  local snippet_count=0
  local first=true

  local base
  for base in "${RESOLVED_SNIPPETS[@]+"${RESOLVED_SNIPPETS[@]}"}"; do
    local f="$snippet_dir/$base"
    [ -f "$f" ] || continue
    snippet_count=$((snippet_count + 1))

    if $first; then
      first=false
    else
      compiled+=$'\n\n---\n\n'
    fi
    # Strip frontmatter from the snippet content
    compiled+="$(strip_frontmatter_from_file "$f")"
  done

  local rules_dir="$src/claude-rules"
  local global_target="$HOME/.claude/CLAUDE.md"

  compiled="${compiled//\{\{CLAUDE_RULES_DIR\}\}/$rules_dir}"
  compiled="${compiled//\{\{PROJECT_DIR\}\}/$src}"
  compiled="${compiled//\{\{GLOBAL_TARGET\}\}/$global_target}"

  local envfile="$rules_dir/variables.env"
  if [ -f "$envfile" ]; then
    local var_keys=("CLAUDE_RULES_DIR" "PROJECT_DIR" "GLOBAL_TARGET")
    local var_vals=("$rules_dir" "$src" "$global_target")

    while IFS='=' read -r key val; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      local i
      for ((i = 0; i < ${#var_keys[@]}; i++)); do
        val="${val//\{\{${var_keys[$i]}\}\}/${var_vals[$i]}}"
      done
      var_keys+=("$key")
      var_vals+=("$val")
      compiled="${compiled//\{\{$key\}\}/$val}"
    done < "$envfile"
  fi

  local block
  block="$marker_begin"$'\n'"$compiled"$'\n'"$marker_end"

  local claudemd="./CLAUDE.md"

  if [ ! -f "$claudemd" ]; then
    printf '%s\n\n%s\n' "$block" "<!-- Your project instructions below -->" > "$claudemd"
  elif grep -qF "BEGIN ANUTRON-INSTALL" "$claudemd"; then
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
# 10. Breadcrumb
# ============================================================

write_breadcrumb() {
  local src="$1" mode="$2" scope="$3"
  local version
  version=$(get_version "$src")

  local skills_json="["
  local first=true
  for s in "${SKILLS_INSTALLED[@]+"${SKILLS_INSTALLED[@]}"}"; do
    if $first; then first=false; else skills_json+=","; fi
    skills_json+="\"$s\""
  done
  skills_json+="]"

  local hooks_json="["
  first=true
  for h in "${HOOK_KEYS[@]+"${HOOK_KEYS[@]}"}"; do
    if $first; then first=false; else hooks_json+=","; fi
    hooks_json+="\"$h\""
  done
  hooks_json+="]"

  local hook_cmds_json="["
  first=true
  for cmd in "${HOOK_COMMANDS[@]+"${HOOK_COMMANDS[@]}"}"; do
    if $first; then first=false; else hook_cmds_json+=","; fi
    hook_cmds_json+="\"$cmd\""
  done
  hook_cmds_json+="]"

  local snippets_json="["
  first=true
  for s in "${RESOLVED_SNIPPETS[@]+"${RESOLVED_SNIPPETS[@]}"}"; do
    if $first; then first=false; else snippets_json+=","; fi
    snippets_json+="\"$s\""
  done
  snippets_json+="]"

  local timestamp
  timestamp="${SETTINGS_TIMESTAMP:-$(iso_timestamp)}"

  local source_commit
  source_commit=$(get_source_commit "$src")

  # Format sourceCommit: if "null", emit JSON null; otherwise as string
  local source_commit_arg
  if [ "$source_commit" = "null" ]; then
    source_commit_arg="null"
    jq -n \
      --arg version "$version" \
      --arg source "$src" \
      --arg installedAt "$timestamp" \
      --arg mode "$mode" \
      --arg scope "$scope" \
      --argjson skills "$skills_json" \
      --argjson hooks "$hooks_json" \
      --argjson hookCommands "$hook_cmds_json" \
      --argjson snippets "$snippets_json" \
      --arg markerBegin "$CLAUDEMD_MARKER_BEGIN" \
      --arg markerEnd "$CLAUDEMD_MARKER_END" \
      '{
        version: $version,
        source: $source,
        installedAt: $installedAt,
        mode: $mode,
        scope: $scope,
        sourceCommit: null,
        skills: $skills,
        hooks: $hooks,
        hookCommands: $hookCommands,
        scopeResolution: {
          skills: $skills,
          snippets: $snippets,
          hooks: $hooks
        },
        claudeMdMarkers: {
          begin: $markerBegin,
          end: $markerEnd
        }
      }' > ./.anutron-install.json
  else
    jq -n \
      --arg version "$version" \
      --arg source "$src" \
      --arg installedAt "$timestamp" \
      --arg mode "$mode" \
      --arg scope "$scope" \
      --arg sourceCommit "$source_commit" \
      --argjson skills "$skills_json" \
      --argjson hooks "$hooks_json" \
      --argjson hookCommands "$hook_cmds_json" \
      --argjson snippets "$snippets_json" \
      --arg markerBegin "$CLAUDEMD_MARKER_BEGIN" \
      --arg markerEnd "$CLAUDEMD_MARKER_END" \
      '{
        version: $version,
        source: $source,
        installedAt: $installedAt,
        mode: $mode,
        scope: $scope,
        sourceCommit: $sourceCommit,
        skills: $skills,
        hooks: $hooks,
        hookCommands: $hookCommands,
        scopeResolution: {
          skills: $skills,
          snippets: $snippets,
          hooks: $hooks
        },
        claudeMdMarkers: {
          begin: $markerBegin,
          end: $markerEnd
        }
      }' > ./.anutron-install.json
  fi
}

# ============================================================
# 11. Stale source detection
# ============================================================

# Returns list of skill names whose files changed between prev_commit and current HEAD
detect_stale_skills() {
  local src="$1" prev_commit="$2"
  if [ -z "$prev_commit" ] || [ "$prev_commit" = "null" ]; then
    return
  fi
  # Must be a git repo
  if ! git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
    return
  fi
  local changed
  changed=$(git -C "$src" diff --name-only "$prev_commit"..HEAD -- skills/ 2>/dev/null || true)
  if [ -z "$changed" ]; then
    return
  fi
  echo "$changed" | awk -F/ '/^skills\// { print $2 }' | sort -u
}

# ============================================================
# 12. Summary
# ============================================================

print_summary() {
  local src="$1" mode="$2" scope="$3"
  local version
  version=$(get_version "$src")
  local project_dir
  project_dir="$(pwd)"

  local old_breadcrumb="./.anutron-install.json.prev"
  local is_update=false
  local old_version=""
  local old_source_commit=""

  if [ -f "$old_breadcrumb" ]; then
    is_update=true
    old_version=$(jq -r '.version // "unknown"' "$old_breadcrumb" 2>/dev/null || echo "unknown")
    old_source_commit=$(jq -r '.sourceCommit // empty' "$old_breadcrumb" 2>/dev/null || echo "")
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

    local skill_detail=""
    [ "$added_count" -gt 0 ] && skill_detail+=" +${added_count} added"
    [ "$removed_count" -gt 0 ] && skill_detail+=" -${removed_count} removed"
    [ "$unchanged_count" -gt 0 ] && skill_detail+=" ${unchanged_count} unchanged"
    echo "  Skills: ${skill_count} total${skill_detail:+ ($skill_detail )}"
  else
    echo "Installed anutron kit to ${project_dir}:"
    echo "  Skills: ${skill_count} installed"
  fi

  echo "  Mode: ${mode}"
  echo "  Scope: ${scope}"

  if [ "$hook_count" -gt 0 ]; then
    local keys_str
    keys_str=$(IFS=', '; echo "${HOOK_KEYS[*]}")
    echo "  Hooks: ${hook_count} registered (${keys_str})"
  else
    echo "  Hooks: none"
  fi

  echo "  CLAUDE.md: compiled from ${SNIPPET_COUNT} snippets"

  # Stale source detection (copy mode re-run)
  if $is_update && [ "$mode" = "copy" ] && [ -n "$old_source_commit" ] && [ "$old_source_commit" != "null" ]; then
    local stale_skills
    stale_skills=$(detect_stale_skills "$src" "$old_source_commit" || true)
    if [ -n "$stale_skills" ]; then
      echo ""
      echo "Updated since previous install (source advanced):"
      echo "$stale_skills" | while IFS= read -r s; do
        [ -n "$s" ] && echo "  - $s"
      done
    fi
  fi

  if [ "$FLAG_FOR_CONTRIB" -eq 1 ]; then
    echo ""
    echo "This is a contributor-facing install. Commit the .claude/ tree so contributors"
    echo "get the skills on clone:"
    echo ""
    echo "  git add .claude/skills .claude/hooks .claude/settings.json CLAUDE.md"
    echo "  git commit -m \"Add anutron skills for spec-driven contribution workflow\""
  fi

  if ! $is_update; then
    echo ""
    echo "Try: /brainstorm, /guard, /execute-plan"
    echo "Uninstall: /anutron-uninstall"
  fi

  rm -f "$old_breadcrumb"
}

# ============================================================
# Main
# ============================================================

main() {
  require_jq

  # Initialize globals
  SKILLS_INSTALLED=()
  SKILLS_ADDED=()
  SKILLS_REMOVED=()
  SKILLS_UNCHANGED=()
  HOOKS_INSTALLED=()
  HOOK_KEYS=()
  HOOK_COMMANDS=()
  RESOLVED_SKILLS=()
  RESOLVED_SNIPPETS=()
  SNIPPET_COUNT=0
  CLAUDEMD_MARKER_BEGIN=""
  CLAUDEMD_MARKER_END=""
  SETTINGS_TIMESTAMP=""

  parse_args "$@"

  local source
  source=$(locate_source)
  validate_source "$source"

  read_manifest

  resolve_mode_scope "$source"

  resolve_scope "$source" "$RESOLVED_SCOPE"

  # Save old breadcrumb for update detection
  if [ -f ./.anutron-install.json ]; then
    cp ./.anutron-install.json ./.anutron-install.json.prev
  fi

  install_skills "$source" "$RESOLVED_MODE"
  install_hooks "$source" "$RESOLVED_MODE"
  compile_claudemd "$source"
  write_breadcrumb "$source" "$RESOLVED_MODE" "$RESOLVED_SCOPE"
  print_summary "$source" "$RESOLVED_MODE" "$RESOLVED_SCOPE"
}

main "$@"
