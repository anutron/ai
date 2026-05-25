#!/usr/bin/env bash
# audit.sh — deterministic helper CLI for the spec-audit skill.
#
# Owns config R/W, inventory, symbol index, branch counting, drift detection,
# and verification. The LLM never edits the JSON config directly — every
# config change goes through one of these subcommands.

set -euo pipefail

# ---------------------------------------------------------------------------
# General helpers
# ---------------------------------------------------------------------------

err() { printf '%s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

# Resolve the spec directory to an absolute path. Accepts either an absolute
# path or a path relative to the caller's CWD. The repo root is the parent of
# the spec dir (or, preferably, what `git rev-parse --show-toplevel` reports
# when run from inside it).
resolve_spec_dir() {
  local raw="${1:-}"
  [[ -n "$raw" ]] || die "spec-dir argument required"
  if [[ "$raw" = /* ]]; then
    printf '%s' "$raw"
  else
    printf '%s' "$(cd "$(pwd)" && cd "$raw" 2>/dev/null && pwd)"
  fi
}

repo_root_for() {
  local spec_dir="$1"
  [[ -d "$spec_dir" ]] || die "spec dir does not exist: $spec_dir"
  local root
  if root=$(git -C "$spec_dir" rev-parse --show-toplevel 2>/dev/null); then
    printf '%s' "$root"
  else
    printf '%s' "$(dirname "$spec_dir")"
  fi
}

config_path_for() {
  printf '%s/.audit-config.json' "$1"
}

require_config() {
  local cfg="$1"
  [[ -f "$cfg" ]] || die "config not found: $cfg (run 'audit.sh init' or 'audit.sh init-tree')"
}

# Slugify a path-like string into a module name. e.g. "api/app" -> "api-app".
slugify() {
  printf '%s' "$1" | sed -e 's|^[./]*||' -e 's|/*$||' -e 's|/|-|g' -e 's|[^A-Za-z0-9_-]|-|g' | tr '[:upper:]' '[:lower:]'
}

# Tokenize a name on '-', '_', '.', '/'. Lowercased. One token per line.
tokenize() {
  printf '%s' "$1" | tr 'A-Z/._-' 'a-z\n\n\n\n' | awk 'NF'
}

# Returns 0 if the two names share at least one token.
tokens_overlap() {
  local a="$1" b="$2"
  local toks_a toks_b
  toks_a=$(tokenize "$a" | sort -u)
  toks_b=$(tokenize "$b" | sort -u)
  [[ -n "$toks_a" && -n "$toks_b" ]] || return 1
  if comm -12 <(printf '%s\n' "$toks_a") <(printf '%s\n' "$toks_b") | grep -q .; then
    return 0
  fi
  return 1
}

# Validate that a pre-archive change name resolves to a real change folder
# under <spec_dir>/changes/<name>. Used by `--pre-archive <name>` mode.
validate_pre_archive_change() {
  local spec_dir="$1" change="$2"
  [[ -n "$change" ]] || die "--pre-archive requires a change name"
  local cdir="$spec_dir/changes/$change"
  [[ -d "$cdir" ]] || die "pre-archive change folder not found: $cdir"
}

# Emit one absolute path per line for every spec.md the audit should treat as
# part of the corpus. Always includes base specs at <spec_dir>/specs/. When
# the global PRE_ARCHIVE_CHANGE env is set, also includes the named change's
# delta specs at <spec_dir>/changes/<name>/specs/<capability>/spec.md.
enumerate_spec_files() {
  local spec_dir="$1"
  local base_specs_dir="$spec_dir/specs"
  if [[ -d "$base_specs_dir" ]]; then
    find "$base_specs_dir" -mindepth 2 -maxdepth 2 -type f -name 'spec.md' 2>/dev/null
  fi
  if [[ -n "${PRE_ARCHIVE_CHANGE:-}" ]]; then
    local change_specs_dir="$spec_dir/changes/$PRE_ARCHIVE_CHANGE/specs"
    if [[ -d "$change_specs_dir" ]]; then
      find "$change_specs_dir" -mindepth 2 -maxdepth 2 -type f -name 'spec.md' 2>/dev/null
    fi
  fi
}

# Classify a spec.md path as a base spec or a delta from the pre-archive change.
# Echoes "base" or "pending".
spec_file_source() {
  local spec_dir="$1" abs="$2"
  if [[ -n "${PRE_ARCHIVE_CHANGE:-}" ]]; then
    local change_specs_prefix="$spec_dir/changes/$PRE_ARCHIVE_CHANGE/"
    if [[ "$abs" == "$change_specs_prefix"* ]]; then
      printf 'pending'
      return
    fi
  fi
  printf 'base'
}

# Map a file extension to a language label.
ext_to_lang() {
  case "$1" in
    rb) printf 'ruby' ;;
    ts|tsx) printf 'typescript' ;;
    js|jsx|mjs|cjs) printf 'javascript' ;;
    go) printf 'go' ;;
    py) printf 'python' ;;
    rs) printf 'rust' ;;
    *) printf '%s' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Config R/W subcommands
# ---------------------------------------------------------------------------

cmd_init() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  mkdir -p "$spec_dir"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  jq -n '{
    version: 1,
    modules: [],
    extensions: [],
    excludes: [],
    pitfalls: [],
    test_suites: [],
    mapping_cache: {}
  }' > "$cfg"
  printf 'wrote %s\n' "$cfg"
}

cmd_validate() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  jq -e '
    (.version == 1) and
    (.modules | type == "array") and
    (.modules | all(
      (.name | type == "string") and
      (.paths | type == "array") and
      (.specs | type == "array")
    )) and
    (.extensions | type == "array") and
    (.excludes | type == "array") and
    (.pitfalls | type == "array") and
    (.test_suites | type == "array") and
    (.test_suites | all(
      (.dir | type == "string") and
      (.command | type == "string")
    )) and
    (.mapping_cache | type == "object")
  ' "$cfg" >/dev/null || die "config schema validation failed: $cfg"
  printf 'ok %s\n' "$cfg"
}

cmd_get() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local jq_path="${2:-.}"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  jq "$jq_path" "$cfg"
}

# add-module <spec-dir> <name> --paths a,b --specs c,d
cmd_add_module() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  shift || true
  local name="${1:-}"
  shift || true
  [[ -n "$name" ]] || die "module name required"
  local paths_csv="" specs_csv=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --paths) paths_csv="${2:-}"; shift 2 ;;
      --specs) specs_csv="${2:-}"; shift 2 ;;
      *) die "unknown flag for add-module: $1" ;;
    esac
  done

  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"

  local paths_json specs_json
  paths_json=$(printf '%s' "$paths_csv" | awk -v RS=, 'NF' | jq -R . | jq -s .)
  specs_json=$(printf '%s' "$specs_csv" | awk -v RS=, 'NF' | jq -R . | jq -s .)

  local tmp
  tmp=$(mktemp)
  jq --arg name "$name" --argjson paths "$paths_json" --argjson specs "$specs_json" '
    if (.modules | map(.name) | index($name)) then
      .modules |= map(
        if .name == $name then
          .paths = ((.paths + $paths) | unique) |
          .specs = ((.specs + $specs) | unique)
        else . end
      )
    else
      .modules += [{name: $name, paths: $paths, specs: $specs}]
    end
  ' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cmd_add_path() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local module="${2:-}"
  local path="${3:-}"
  [[ -n "$module" && -n "$path" ]] || die "usage: add-path <spec-dir> <module> <path>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local tmp
  tmp=$(mktemp)
  jq --arg name "$module" --arg path "$path" '
    .modules |= map(
      if .name == $name then
        .paths = ((.paths + [$path]) | unique)
      else . end
    )
  ' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cmd_add_spec() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local module="${2:-}"
  local spec_file="${3:-}"
  [[ -n "$module" && -n "$spec_file" ]] || die "usage: add-spec <spec-dir> <module> <spec-file>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local tmp
  tmp=$(mktemp)
  jq --arg name "$module" --arg spec "$spec_file" '
    .modules |= map(
      if .name == $name then
        .specs = ((.specs + [$spec]) | unique)
      else . end
    )
  ' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cmd_add_pitfall() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local text="${2:-}"
  [[ -n "$text" ]] || die "usage: add-pitfall <spec-dir> <text>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local tmp
  tmp=$(mktemp)
  jq --arg text "$text" '.pitfalls = ((.pitfalls + [$text]) | unique)' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cmd_add_exclude() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local pattern="${2:-}"
  [[ -n "$pattern" ]] || die "usage: add-exclude <spec-dir> <pattern>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local tmp
  tmp=$(mktemp)
  jq --arg p "$pattern" '.excludes = ((.excludes + [$p]) | unique)' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cmd_add_test_suite() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local dir="${2:-}"
  local command="${3:-}"
  [[ -n "$dir" && -n "$command" ]] || die "usage: add-test-suite <spec-dir> <dir> <command>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local tmp
  tmp=$(mktemp)
  jq --arg dir "$dir" --arg cmd "$command" '
    if (.test_suites | map(.dir) | index($dir)) then
      .test_suites |= map(if .dir == $dir then .command = $cmd else . end)
    else
      .test_suites += [{dir: $dir, command: $cmd}]
    end
  ' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

cmd_remove_module() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local name="${2:-}"
  [[ -n "$name" ]] || die "usage: remove-module <spec-dir> <name>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local tmp
  tmp=$(mktemp)
  jq --arg name "$name" '.modules |= map(select(.name != $name))' "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

# ---------------------------------------------------------------------------
# init-tree: deterministic bootstrap proposal
# ---------------------------------------------------------------------------

# Detect project markers and emit extension list (JSON array).
detect_extensions() {
  local root="$1"
  local exts=()
  [[ -f "$root/Gemfile" ]] && exts+=("rb")
  if [[ -f "$root/package.json" ]]; then
    exts+=("js" "ts" "tsx")
  fi
  [[ -f "$root/go.mod" ]] && exts+=("go")
  if [[ -f "$root/pyproject.toml" || -f "$root/requirements.txt" ]]; then
    exts+=("py")
  fi
  [[ -f "$root/Cargo.toml" ]] && exts+=("rs")
  # Even if no top-level marker exists, scan for nested markers in depth-1
  # subdirs so monorepos still produce an extension list.
  local d
  while IFS= read -r -d '' d; do
    [[ -f "$d/Gemfile" ]] && exts+=("rb")
    if [[ -f "$d/package.json" ]]; then
      exts+=("js" "ts" "tsx")
    fi
    [[ -f "$d/go.mod" ]] && exts+=("go")
    if [[ -f "$d/pyproject.toml" || -f "$d/requirements.txt" ]]; then
      exts+=("py")
    fi
    [[ -f "$d/Cargo.toml" ]] && exts+=("rs")
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  if [[ ${#exts[@]} -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s\n' "${exts[@]}" | sort -u | jq -R . | jq -s .
}

# Common dir names we never want to descend into.
EXCLUDE_DIR_NAMES=(node_modules dist build .next vendor tmp .git target coverage .DS_Store .bug-bash .research .claude .superpowers .devbox .circleci logs .venv venv .workflow openspec working)

is_excluded_dir_name() {
  local name="$1"
  local x
  for x in "${EXCLUDE_DIR_NAMES[@]}"; do
    if [[ "$name" == "$x" ]]; then return 0; fi
  done
  return 1
}

# Count files matching configured extensions inside a directory (recursive).
# Honors the static EXCLUDE_DIR_NAMES list via -prune.
count_behavioral_files() {
  local dir="$1"; shift
  local exts=("$@")
  [[ -d "$dir" ]] || { printf '0'; return; }
  local find_args=( "$dir" )
  # Build an OR clause of name-prune patterns
  find_args+=( -type d \( )
  local first=1
  local x
  for x in "${EXCLUDE_DIR_NAMES[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=( -name "$x" )
      first=0
    else
      find_args+=( -o -name "$x" )
    fi
  done
  find_args+=( \) -prune -o -type f \( )
  first=1
  local e
  for e in "${exts[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=( -name "*.$e" )
      first=0
    else
      find_args+=( -o -name "*.$e" )
    fi
  done
  find_args+=( \) -print )
  find "${find_args[@]}" 2>/dev/null | wc -l | awk '{print $1}'
}

# Determine subdirs of <dir> that contain behavioral files. Echoes one path
# per line (relative to repo_root, no trailing slash).
list_behavioral_subdirs() {
  local parent_abs="$1"; shift
  local repo_root="$1"; shift
  local exts=("$@")
  [[ -d "$parent_abs" ]] || return 0
  local sub
  while IFS= read -r -d '' sub; do
    local base
    base=$(basename "$sub")
    if is_excluded_dir_name "$base"; then continue; fi
    local n
    n=$(count_behavioral_files "$sub" "${exts[@]}")
    if [[ "$n" -gt 0 ]]; then
      # Emit relative path
      printf '%s\n' "${sub#$repo_root/}"
    fi
  done < <(find "$parent_abs" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

# Detect test suites and emit a JSON array of {dir, command}.
detect_test_suites_json() {
  local root="$1"
  local devbox_present=0
  [[ -f "$root/devbox.json" ]] && devbox_present=1

  # Build entries via jq
  local entries='[]'

  # Helper to push an entry
  push_entry() {
    local rel="$1" cmd="$2"
    local wrapped="cd $rel && $cmd"
    if [[ "$devbox_present" -eq 1 ]]; then
      wrapped="devbox run -- bash -c '${wrapped//\'/\\\'}'"
    fi
    entries=$(jq --arg dir "$rel" --arg cmd "$wrapped" '. + [{dir: $dir, command: $cmd}]' <<< "$entries")
  }

  # Walk depth 1 and 2 looking for markers
  local d
  while IFS= read -r -d '' d; do
    local base
    base=$(basename "$d")
    if is_excluded_dir_name "$base"; then continue; fi
    local rel="${d#$root/}"
    if [[ -f "$d/Gemfile" ]]; then
      push_entry "$rel" "bundle exec rspec"
    fi
    if [[ -f "$d/package.json" ]]; then
      local test_cmd
      test_cmd=$(jq -r '.scripts.test // empty' "$d/package.json" 2>/dev/null || true)
      if [[ -n "$test_cmd" && "$test_cmd" != "null" ]]; then
        push_entry "$rel" "$test_cmd"
      fi
    fi
    if [[ -f "$d/go.mod" ]]; then
      push_entry "$rel" "go test ./..."
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  # Also handle root-level markers (depth 0) where the project IS the tree
  if [[ -f "$root/Gemfile" ]]; then
    push_entry "." "bundle exec rspec"
  fi
  if [[ -f "$root/package.json" ]]; then
    local test_cmd
    test_cmd=$(jq -r '.scripts.test // empty' "$root/package.json" 2>/dev/null || true)
    if [[ -n "$test_cmd" && "$test_cmd" != "null" ]]; then
      push_entry "." "$test_cmd"
    fi
  fi
  if [[ -f "$root/go.mod" ]]; then
    push_entry "." "go test ./..."
  fi

  # Dedupe by dir+command
  jq 'unique_by(.dir + "|" + .command)' <<< "$entries"
}

cmd_detect_test_suites() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local root
  root=$(repo_root_for "$spec_dir")
  detect_test_suites_json "$root"
}

cmd_init_tree() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  mkdir -p "$spec_dir"
  local root
  root=$(repo_root_for "$spec_dir")
  local cfg
  cfg=$(config_path_for "$spec_dir")

  # 1. Extensions
  local extensions_json
  extensions_json=$(detect_extensions "$root")
  # Convert JSON array to bash array
  local exts=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && exts+=("$line")
  done < <(jq -r '.[]' <<< "$extensions_json")
  if [[ ${#exts[@]} -eq 0 ]]; then
    # Fall back to a generic set so dirwalk still has something to count
    exts=(rb ts tsx js go py)
    extensions_json=$(printf '%s\n' "${exts[@]}" | jq -R . | jq -s .)
  fi

  # 2. Behavioral top-level dirs
  local spec_dir_rel="${spec_dir#$root/}"
  local depth1_dirs=()
  local d
  while IFS= read -r -d '' d; do
    local base
    base=$(basename "$d")
    if is_excluded_dir_name "$base"; then continue; fi
    if [[ "$base" == "$spec_dir_rel" || "$d" == "$spec_dir" ]]; then continue; fi
    local rel="${d#$root/}"
    if [[ "$rel" == "$spec_dir_rel" ]]; then continue; fi
    local n
    n=$(count_behavioral_files "$d" "${exts[@]}")
    if [[ "$n" -gt 0 ]]; then
      depth1_dirs+=("$rel")
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  # 3. For each depth-1 dir, decide depth-1 vs depth-2 modules.
  # Heuristic: if a depth-1 dir has 3+ subdirs each with 5+ behavioral files,
  # prefer depth-2 modules.
  local modules_json='[]'
  local module_path
  for module_path in "${depth1_dirs[@]:-}"; do
    [[ -n "$module_path" ]] || continue
    local abs="$root/$module_path"
    # Examine immediate subdirs
    local sub
    local big_subs=()
    while IFS= read -r -d '' sub; do
      local sb
      sb=$(basename "$sub")
      if is_excluded_dir_name "$sb"; then continue; fi
      local sn
      sn=$(count_behavioral_files "$sub" "${exts[@]}")
      if [[ "$sn" -ge 5 ]]; then
        big_subs+=("$sub")
      fi
    done < <(find "$abs" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    if [[ ${#big_subs[@]} -ge 3 ]]; then
      # Use depth-2 modules
      local s
      for s in "${big_subs[@]}"; do
        local rel="${s#$root/}"
        local name
        name=$(slugify "$rel")
        modules_json=$(jq --arg name "$name" --arg path "$rel/" \
          '. + [{name: $name, paths: [$path], specs: []}]' <<< "$modules_json")
      done
    else
      local name
      name=$(slugify "$module_path")
      modules_json=$(jq --arg name "$name" --arg path "$module_path/" \
        '. + [{name: $name, paths: [$path], specs: []}]' <<< "$modules_json")
    fi
  done

  # 4. Match specs to modules by capability-name token overlap.
  # Enumerate base spec files: only `<spec_dir>/specs/<capability>/spec.md`.
  # OpenSpec layout — change deltas at `<spec_dir>/changes/...` are excluded.
  local spec_files=()
  local base_specs_dir="$spec_dir/specs"
  if [[ -d "$base_specs_dir" ]]; then
    while IFS= read -r f; do
      spec_files+=("$f")
    done < <(find "$base_specs_dir" -mindepth 2 -maxdepth 2 -type f -name 'spec.md' 2>/dev/null)
  fi

  # For each spec file, find modules whose name shares a token with the
  # capability (parent dir of spec.md).
  local sf
  for sf in "${spec_files[@]:-}"; do
    [[ -n "$sf" ]] || continue
    # Capability name is the parent directory of spec.md.
    local cap
    cap=$(basename "$(dirname "$sf")")
    # Path stored in module.specs is relative to spec_dir.
    local rel_spec="${sf#$spec_dir/}"
    # Iterate modules
    local mod_count
    mod_count=$(jq 'length' <<< "$modules_json")
    local i=0
    while [[ $i -lt $mod_count ]]; do
      local mname
      mname=$(jq -r ".[$i].name" <<< "$modules_json")
      if tokens_overlap "$cap" "$mname"; then
        modules_json=$(jq --arg n "$mname" --arg s "$rel_spec" '
          map(if .name == $n then .specs = ((.specs + [$s]) | unique) else . end)
        ' <<< "$modules_json")
      fi
      i=$((i + 1))
    done
  done

  # 5. Test suites
  local test_suites_json
  test_suites_json=$(detect_test_suites_json "$root")

  # 6. Excludes — seeded
  local excludes_json
  excludes_json=$(jq -n '[
    "**/node_modules/**",
    "**/dist/**",
    "**/.next/**",
    "**/build/**",
    "**/vendor/**",
    "**/coverage/**",
    "**/*.bundle.js",
    "**/*.min.js"
  ]')

  # 7. Write config
  jq -n \
    --argjson modules "$modules_json" \
    --argjson extensions "$extensions_json" \
    --argjson excludes "$excludes_json" \
    --argjson test_suites "$test_suites_json" \
    '{
      version: 1,
      modules: $modules,
      extensions: $extensions,
      excludes: $excludes,
      pitfalls: [],
      test_suites: $test_suites,
      mapping_cache: {}
    }' > "$cfg"
  printf 'wrote %s (modules=%s, extensions=%s, test_suites=%s)\n' \
    "$cfg" \
    "$(jq '.modules | length' "$cfg")" \
    "$(jq '.extensions | length' "$cfg")" \
    "$(jq '.test_suites | length' "$cfg")"
}

# ---------------------------------------------------------------------------
# Inventory and indices
# ---------------------------------------------------------------------------

# Match a path against the config's exclude patterns. Returns 0 if excluded.
# We support shell-glob style patterns with ** = any dirs, * = single segment.
matches_exclude() {
  local path="$1"; shift
  local p
  for p in "$@"; do
    # Convert ** → *, then use bash's [[ == pattern ]]
    local pat="${p//\*\*/*}"
    # Make sure ** matches any number of segments by also trying nested forms.
    # Use case which uses fnmatch-like rules.
    case "$path" in
      $pat) return 0 ;;
      $p) return 0 ;;
    esac
    # If pattern starts with **/, also try without
    if [[ "$p" == \*\*/* ]]; then
      local stripped="${p#\*\*/}"
      case "$path" in
        $stripped) return 0 ;;
        */$stripped) return 0 ;;
      esac
    fi
    # Heuristic: if pattern contains a literal directory like 'ux/.next/',
    # match any path that contains it as a substring.
    if [[ "$p" != *"*"* && "$path" == *"$p"* ]]; then
      return 0
    fi
  done
  return 1
}

# Extract top-level definitions for a single file. Outputs a JSON array of
# strings (export names). Empty result is fine — we tolerate grep -E returning
# 1 (no match) by suffixing `|| true` on the leading command.
extract_exports_json() {
  local file="$1" lang="$2"
  case "$lang" in
    ruby)
      { grep -nE '^[[:space:]]*(class|module|def)[[:space:]]+([A-Za-z_:][A-Za-z0-9_:.]*)' "$file" 2>/dev/null || true; } \
        | sed -E 's/^[0-9]+:[[:space:]]*(class|module|def)[[:space:]]+([A-Za-z_:][A-Za-z0-9_:.]*).*/\2/' \
        | awk 'NF' | sort -u | jq -R . | jq -s .
      ;;
    typescript|javascript)
      { grep -nE '^[[:space:]]*(export[[:space:]]+(async[[:space:]]+)?(function|class|const|let|var)|class|function)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)' "$file" 2>/dev/null || true; } \
        | sed -E 's/.*(class|function|const|let|var)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*).*/\2/' \
        | awk 'NF' | sort -u | jq -R . | jq -s .
      ;;
    go)
      {
        { grep -nE '^func[[:space:]]+(\([^)]*\)[[:space:]]+)?[A-Z][A-Za-z0-9_]*' "$file" 2>/dev/null || true; } \
          | sed -E 's/^[0-9]+:func[[:space:]]+(\([^)]*\)[[:space:]]+)?([A-Z][A-Za-z0-9_]*).*/\2/'
        { grep -nE '^type[[:space:]]+[A-Z][A-Za-z0-9_]*' "$file" 2>/dev/null || true; } \
          | sed -E 's/^[0-9]+:type[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\1/'
      } | awk 'NF' | sort -u | jq -R . | jq -s .
      ;;
    python)
      { grep -nE '^[[:space:]]*(def|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null || true; } \
        | sed -E 's/^[0-9]+:[[:space:]]*(def|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
        | awk 'NF' | sort -u | jq -R . | jq -s .
      ;;
    *)
      printf '[]'
      ;;
  esac
}

# Walk repo root and emit a JSON list of code files that match extensions and
# don't match excludes.
list_code_files() {
  local root="$1"; shift
  local cfg="$1"; shift

  local exts=()
  while IFS= read -r e; do exts+=("$e"); done < <(jq -r '.extensions[]' "$cfg")
  local excludes=()
  while IFS= read -r e; do excludes+=("$e"); done < <(jq -r '.excludes[]' "$cfg")

  if [[ ${#exts[@]} -eq 0 ]]; then
    return 0
  fi

  local find_args=( "$root" )
  find_args+=( -type d \( )
  local first=1 x
  for x in "${EXCLUDE_DIR_NAMES[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=( -name "$x" )
      first=0
    else
      find_args+=( -o -name "$x" )
    fi
  done
  find_args+=( \) -prune -o -type f \( )
  first=1
  local e
  for e in "${exts[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=( -name "*.$e" )
      first=0
    else
      find_args+=( -o -name "*.$e" )
    fi
  done
  find_args+=( \) -print )

  while IFS= read -r f; do
    local rel="${f#$root/}"
    if matches_exclude "$rel" "${excludes[@]:-}"; then
      continue
    fi
    printf '%s\n' "$rel"
  done < <(find "${find_args[@]}" 2>/dev/null)
}

cmd_inventory() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local root
  root=$(repo_root_for "$spec_dir")

  # Build code_files entries
  local code_json='[]'
  local total_exports=0
  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    local abs="$root/$rel"
    local ext="${rel##*.}"
    local lang
    lang=$(ext_to_lang "$ext")
    local exports_json
    exports_json=$(extract_exports_json "$abs" "$lang")
    local n
    n=$(jq 'length' <<< "$exports_json")
    total_exports=$((total_exports + n))
    code_json=$(jq --arg path "$rel" --arg lang "$lang" --argjson exports "$exports_json" \
      '. + [{path: $path, language: $lang, exports: $exports}]' <<< "$code_json")
  done < <(list_code_files "$root" "$cfg")

  # Build spec_files entries.
  # OpenSpec layout: base specs at `<spec_dir>/specs/<capability>/spec.md`.
  # When PRE_ARCHIVE_CHANGE is set, also include the named change's deltas
  # at `<spec_dir>/changes/<change>/specs/<capability>/spec.md`; each such
  # entry is tagged `source: "pending"` and `pending_change: "<name>"`.
  local spec_json='[]'
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    local rel="${f#$root/}"
    local cap
    cap=$(basename "$(dirname "$f")")
    local sections_json
    sections_json=$({ grep -nE '^#+[[:space:]]+' "$f" 2>/dev/null || true; } \
      | sed -E 's/^[0-9]+:#+[[:space:]]+//' \
      | awk 'NF' | jq -R . | jq -s .)
    local source
    source=$(spec_file_source "$spec_dir" "$f")
    if [[ "$source" == "pending" ]]; then
      spec_json=$(jq --arg path "$rel" --arg cap "$cap" --argjson sections "$sections_json" --arg change "$PRE_ARCHIVE_CHANGE" \
        '. + [{path: $path, capability: $cap, sections: $sections, source: "pending", pending_change: $change}]' <<< "$spec_json")
    else
      spec_json=$(jq --arg path "$rel" --arg cap "$cap" --argjson sections "$sections_json" \
        '. + [{path: $path, capability: $cap, sections: $sections, source: "base"}]' <<< "$spec_json")
    fi
  done < <(enumerate_spec_files "$spec_dir")

  jq -n \
    --argjson code "$code_json" \
    --argjson specs "$spec_json" \
    --argjson exports_count "$total_exports" \
    --arg pending_change "${PRE_ARCHIVE_CHANGE:-}" \
    '{
      code_files: $code,
      spec_files: $specs,
      counts: {
        code_files: ($code | length),
        spec_files: ($specs | length),
        exports: $exports_count,
        pending_spec_files: ($specs | map(select(.source == "pending")) | length)
      },
      pre_archive: (if $pending_change == "" then null else $pending_change end)
    }'
}

cmd_symbols() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local root
  root=$(repo_root_for "$spec_dir")

  # Compute inventory once
  local inv
  inv=$(cmd_inventory "$spec_dir")

  # Build module → symbols map
  local out='{}'
  local mod_count
  mod_count=$(jq '.modules | length' "$cfg")
  local i=0
  while [[ $i -lt $mod_count ]]; do
    local mname
    mname=$(jq -r ".modules[$i].name" "$cfg")
    local mpaths_json
    mpaths_json=$(jq -c ".modules[$i].paths" "$cfg")
    out=$(jq --arg name "$mname" '. + {($name): {symbols: []}}' <<< "$out")

    # Files in this module: any code_file whose path starts with one of the module's paths
    local files_in_module
    files_in_module=$(jq --argjson paths "$mpaths_json" '
      .code_files
      | map(select(. as $f | $paths | any(. as $p | $f.path | startswith($p))))
    ' <<< "$inv")

    # For each file, extract symbols (already in `exports`) plus qualified
    # names (Class.method) where reasonable.
    local sym_lines=""
    local fcount
    fcount=$(jq 'length' <<< "$files_in_module")
    local j=0
    while [[ $j -lt $fcount ]]; do
      local fpath flang
      fpath=$(jq -r ".[$j].path" <<< "$files_in_module")
      flang=$(jq -r ".[$j].language" <<< "$files_in_module")
      # Plain exports
      while IFS= read -r e; do
        [[ -n "$e" ]] && sym_lines+="$e"$'\n'
      done < <(jq -r ".[$j].exports[]?" <<< "$files_in_module")

      # Qualified names — best-effort. Use grep to find class/module + def
      # combinations within the file.
      local abs="$root/$fpath"
      case "$flang" in
        ruby)
          # Walk file: track current class/module, emit Class.method for each def.
          while IFS= read -r line; do
            [[ -n "$line" ]] && sym_lines+="$line"$'\n'
          done < <(awk '
            /^[[:space:]]*(class|module)[[:space:]]+[A-Za-z_:][A-Za-z0-9_:.]*/ {
              match($0, /(class|module)[[:space:]]+[A-Za-z_:][A-Za-z0-9_:.]*/)
              s=substr($0, RSTART, RLENGTH); sub(/^(class|module)[[:space:]]+/, "", s)
              ctx=s; next
            }
            /^[[:space:]]*end[[:space:]]*$/ { ctx=""; next }
            /^[[:space:]]*def[[:space:]]+[A-Za-z_][A-Za-z0-9_?!=]*/ {
              match($0, /def[[:space:]]+[A-Za-z_][A-Za-z0-9_?!=]*/)
              m=substr($0, RSTART, RLENGTH); sub(/^def[[:space:]]+/, "", m)
              if (ctx != "") print ctx "." m
            }
          ' "$abs" 2>/dev/null)
          ;;
        typescript|javascript)
          while IFS= read -r line; do
            [[ -n "$line" ]] && sym_lines+="$line"$'\n'
          done < <(awk '
            /^[[:space:]]*(export[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*/ {
              match($0, /class[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*/)
              s=substr($0, RSTART, RLENGTH); sub(/^class[[:space:]]+/, "", s)
              ctx=s; next
            }
            /^[[:space:]]*}[[:space:]]*$/ { ctx=""; next }
            /^[[:space:]]+(public|private|protected|static|async)?[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\(/ {
              # crude method detection
              line=$0
              sub(/^[[:space:]]+/, "", line)
              sub(/^(public|private|protected|static|async)[[:space:]]+/, "", line)
              match(line, /^[A-Za-z_$][A-Za-z0-9_$]*/)
              if (RSTART > 0) {
                m=substr(line, RSTART, RLENGTH)
                if (ctx != "" && m != "constructor" && m != "if" && m != "for" && m != "while" && m != "switch" && m != "return")
                  print ctx "." m
              }
            }
          ' "$abs" 2>/dev/null)
          ;;
        *)
          ;;
      esac
      j=$((j + 1))
    done

    # De-dupe and serialize to JSON
    local syms_json
    if [[ -n "$sym_lines" ]]; then
      syms_json=$(printf '%s' "$sym_lines" | awk 'NF' | sort -u | jq -R . | jq -s .)
    else
      syms_json='[]'
    fi
    out=$(jq --arg name "$mname" --argjson syms "$syms_json" \
      '.[$name].symbols = $syms' <<< "$out")
    i=$((i + 1))
  done

  printf '%s\n' "$out"
}

# count-branches <file>
cmd_count_branches() {
  local file="${1:-}"
  [[ -n "$file" && -f "$file" ]] || die "usage: count-branches <file>"
  local ext="${file##*.}"
  local lang
  lang=$(ext_to_lang "$ext")

  # Find function/method declarations along with their line numbers, so we
  # can attribute branches.
  local fn_lines_file
  fn_lines_file=$(mktemp)
  case "$lang" in
    ruby)
      grep -nE '^[[:space:]]*def[[:space:]]+[A-Za-z_][A-Za-z0-9_?!=]*' "$file" 2>/dev/null > "$fn_lines_file" || true
      ;;
    typescript|javascript)
      grep -nE '^([[:space:]]*)(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*|^([[:space:]]+)(public|private|protected|static|async)*[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\(.*\)[[:space:]]*\{' "$file" 2>/dev/null > "$fn_lines_file" || true
      ;;
    go)
      grep -nE '^func[[:space:]]+' "$file" 2>/dev/null > "$fn_lines_file" || true
      ;;
    python)
      grep -nE '^[[:space:]]*def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null > "$fn_lines_file" || true
      ;;
    *)
      ;;
  esac

  # Helper: given a line number, return the name of the most recent
  # preceding function declaration (or "<top>" if none).
  enclosing_fn() {
    local line="$1"
    awk -F: -v target="$line" '
      $1 <= target {
        # extract function name from $2..end
        rest=$0
        sub(/^[0-9]+:/, "", rest)
        # ruby: def NAME
        if (match(rest, /def[[:space:]]+[A-Za-z_][A-Za-z0-9_?!=]*/)) {
          fn=substr(rest, RSTART, RLENGTH); sub(/^def[[:space:]]+/, "", fn); name=fn
        }
        else if (match(rest, /function[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
          fn=substr(rest, RSTART, RLENGTH); sub(/^function[[:space:]]+/, "", fn); name=fn
        }
        else if (match(rest, /func[[:space:]]+(\([^)]*\)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*/)) {
          fn=substr(rest, RSTART, RLENGTH); sub(/^func[[:space:]]+(\([^)]*\)[[:space:]]+)?/, "", fn); name=fn
        }
        else {
          # JS method-ish: leading whitespace + name(...)
          line2=rest
          sub(/^[[:space:]]+/, "", line2)
          sub(/^(public|private|protected|static|async)[[:space:]]+/, "", line2)
          if (match(line2, /^[A-Za-z_$][A-Za-z0-9_$]*/)) {
            name=substr(line2, RSTART, RLENGTH)
          }
        }
      }
      END { if (name == "") name="<top>"; print name }
    ' "$fn_lines_file"
  }

  # Patterns for branch kinds.
  declare -a kinds patterns
  case "$lang" in
    ruby)
      patterns+=( '^[[:space:]]*if[[:space:]]' )           ; kinds+=( 'if' )
      patterns+=( '^[[:space:]]*elsif[[:space:]]' )        ; kinds+=( 'elsif' )
      patterns+=( '^[[:space:]]*else[[:space:]]*$' )       ; kinds+=( 'else' )
      patterns+=( '^[[:space:]]*case[[:space:]]' )         ; kinds+=( 'case' )
      patterns+=( '^[[:space:]]*when[[:space:]]' )         ; kinds+=( 'when' )
      patterns+=( '^[[:space:]]*rescue([[:space:]]|$)' )   ; kinds+=( 'rescue' )
      patterns+=( '\?.+:' )                                 ; kinds+=( 'ternary' )
      patterns+=( '^[[:space:]]+return[[:space:]]' )       ; kinds+=( 'early_return' )
      ;;
    typescript|javascript)
      patterns+=( '^[[:space:]]*if[[:space:]]*\(' )        ; kinds+=( 'if' )
      patterns+=( '^[[:space:]]*\}[[:space:]]*else[[:space:]]+if[[:space:]]*\(' ) ; kinds+=( 'elsif' )
      patterns+=( '^[[:space:]]*\}[[:space:]]*else[[:space:]]*\{?[[:space:]]*$' ) ; kinds+=( 'else' )
      patterns+=( '^[[:space:]]*switch[[:space:]]*\(' )    ; kinds+=( 'case' )
      patterns+=( '^[[:space:]]*case[[:space:]]' )         ; kinds+=( 'when' )
      patterns+=( '^[[:space:]]*catch[[:space:]]*\(' )     ; kinds+=( 'catch' )
      patterns+=( '\?.+:.+' )                              ; kinds+=( 'ternary' )
      patterns+=( '^[[:space:]]+return[[:space:]]' )       ; kinds+=( 'early_return' )
      ;;
    go)
      patterns+=( '^[[:space:]]*if[[:space:]]' )           ; kinds+=( 'if' )
      patterns+=( '^[[:space:]]*\}[[:space:]]*else[[:space:]]+if[[:space:]]' ) ; kinds+=( 'elsif' )
      patterns+=( '^[[:space:]]*\}[[:space:]]*else[[:space:]]*\{?' )           ; kinds+=( 'else' )
      patterns+=( '^[[:space:]]*switch[[:space:]]' )       ; kinds+=( 'case' )
      patterns+=( '^[[:space:]]*case[[:space:]]' )         ; kinds+=( 'when' )
      patterns+=( '^[[:space:]]+return([[:space:]]|$)' )   ; kinds+=( 'early_return' )
      ;;
    python)
      patterns+=( '^[[:space:]]*if[[:space:]]' )           ; kinds+=( 'if' )
      patterns+=( '^[[:space:]]*elif[[:space:]]' )         ; kinds+=( 'elsif' )
      patterns+=( '^[[:space:]]*else[[:space:]]*:' )       ; kinds+=( 'else' )
      patterns+=( '^[[:space:]]*try[[:space:]]*:' )        ; kinds+=( 'case' )
      patterns+=( '^[[:space:]]*except([[:space:]]|:)' )   ; kinds+=( 'rescue' )
      patterns+=( '^[[:space:]]+return[[:space:]]' )       ; kinds+=( 'early_return' )
      ;;
  esac

  local out='[]'
  local idx=0
  while [[ $idx -lt ${#patterns[@]} ]]; do
    local pat="${patterns[$idx]}" kind="${kinds[$idx]}"
    while IFS=: read -r ln rest; do
      [[ -n "$ln" ]] || continue
      local fn
      fn=$(enclosing_fn "$ln")
      out=$(jq --arg fn "$fn" --argjson line "$ln" --arg kind "$kind" \
        '. + [{function: $fn, line: $line, kind: $kind}]' <<< "$out")
    done < <(grep -nE "$pat" "$file" 2>/dev/null || true)
    idx=$((idx + 1))
  done

  rm -f "$fn_lines_file"
  jq 'sort_by(.line)' <<< "$out"
}

# spec-modules <spec-dir> <spec-file>
cmd_spec_modules() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local spec_file="${2:-}"
  [[ -n "$spec_file" ]] || die "usage: spec-modules <spec-dir> <spec-file>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"

  # Resolve spec_file: if not absolute, treat as relative to spec_dir
  local abs
  if [[ "$spec_file" = /* ]]; then
    abs="$spec_file"
  elif [[ -f "$spec_dir/$spec_file" ]]; then
    abs="$spec_dir/$spec_file"
  else
    abs="$spec_file"
  fi

  # 1. YAML frontmatter `covers:`
  if [[ -f "$abs" ]]; then
    local first_line
    first_line=$(head -1 "$abs" 2>/dev/null || true)
    if [[ "$first_line" == "---" ]]; then
      # Extract block between first two --- lines
      local block
      block=$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f {print}' "$abs")
      # Look for `covers:` array
      if [[ -n "$block" ]]; then
        local covers_line
        covers_line=$(grep -E '^covers:' <<< "$block" || true)
        if [[ -n "$covers_line" ]]; then
          # Two formats: `covers: [a, b]` or list lines. Try the inline form first.
          local inline
          inline=$(sed -nE 's/^covers:[[:space:]]*\[(.*)\][[:space:]]*$/\1/p' <<< "$covers_line")
          if [[ -n "$inline" ]]; then
            printf '%s' "$inline" \
              | tr ',' '\n' \
              | sed -E 's/^[[:space:]]*"?//;s/"?[[:space:]]*$//' \
              | awk 'NF' | jq -R . | jq -s .
            return
          fi
          # List form: lines starting with "- "
          local list
          list=$(awk '/^covers:/{f=1; next} f && /^[[:space:]]*-[[:space:]]+/ {sub(/^[[:space:]]*-[[:space:]]+/,""); print; next} f && /^[^[:space:]]/{exit}' <<< "$block")
          if [[ -n "$list" ]]; then
            printf '%s' "$list" \
              | sed -E 's/^[[:space:]]*"?//;s/"?[[:space:]]*$//' \
              | awk 'NF' | jq -R . | jq -s .
            return
          fi
        fi
      fi
    fi
  fi

  # 2. Capability/filename token overlap.
  # OpenSpec layout: when spec_file ends with `/spec.md`, the capability name
  # is the parent directory (e.g. `specs/auth/spec.md` -> `auth`). For legacy
  # callers passing arbitrary .md filenames, fall back to the filename stem.
  local base
  if [[ "$(basename "$spec_file")" == "spec.md" ]]; then
    base=$(basename "$(dirname "$spec_file")")
  else
    base=$(basename "$spec_file" .md)
  fi
  local result='[]'
  local mod_count
  mod_count=$(jq '.modules | length' "$cfg")
  local i=0
  while [[ $i -lt $mod_count ]]; do
    local mname
    mname=$(jq -r ".modules[$i].name" "$cfg")
    if tokens_overlap "$base" "$mname"; then
      result=$(jq --arg n "$mname" '. + [$n]' <<< "$result")
    fi
    i=$((i + 1))
  done
  jq 'unique' <<< "$result"
}

# detect-drift <spec-dir>
cmd_detect_drift() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local root
  root=$(repo_root_for "$spec_dir")

  # All configured module paths
  local paths_json
  paths_json=$(jq '[.modules[].paths[]]' "$cfg")

  local drift='[]'
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    local in_module
    in_module=$(jq --arg f "$rel" --argjson paths "$paths_json" \
      '$paths | any(. as $p | $f | startswith($p))' <<< 'null')
    if [[ "$in_module" == "false" ]]; then
      drift=$(jq --arg f "$rel" '. + [$f]' <<< "$drift")
    fi
  done < <(list_code_files "$root" "$cfg")

  jq '.' <<< "$drift"
}

# assign-drift <spec-dir>
cmd_assign_drift() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"

  local drifted
  drifted=$(cmd_detect_drift "$spec_dir")

  local unresolved='[]'
  local count
  count=$(jq 'length' <<< "$drifted")
  local i=0
  while [[ $i -lt $count ]]; do
    local f
    f=$(jq -r ".[$i]" <<< "$drifted")
    local fdir
    fdir=$(dirname "$f")
    [[ "$fdir" == "." ]] && fdir=""
    [[ -n "$fdir" ]] && fdir="$fdir/"

    # Find configured paths that are prefixes of fdir, longest match wins.
    local best_module="" best_len=0 ties=0
    local mod_count
    mod_count=$(jq '.modules | length' "$cfg")
    local j=0
    while [[ $j -lt $mod_count ]]; do
      local mname
      mname=$(jq -r ".modules[$j].name" "$cfg")
      local pcount
      pcount=$(jq ".modules[$j].paths | length" "$cfg")
      local k=0
      while [[ $k -lt $pcount ]]; do
        local p
        p=$(jq -r ".modules[$j].paths[$k]" "$cfg")
        if [[ -n "$p" && "$fdir" == "$p"* ]]; then
          local plen=${#p}
          if [[ $plen -gt $best_len ]]; then
            best_module="$mname"
            best_len=$plen
            ties=0
          elif [[ $plen -eq $best_len && "$mname" != "$best_module" ]]; then
            ties=1
          fi
        fi
        k=$((k + 1))
      done
      j=$((j + 1))
    done

    if [[ -n "$best_module" && "$ties" -eq 0 ]]; then
      cmd_add_path "$spec_dir" "$best_module" "$fdir" >/dev/null
    else
      unresolved=$(jq --arg f "$f" '. + [$f]' <<< "$unresolved")
    fi
    i=$((i + 1))
  done

  jq -n --argjson u "$unresolved" '{unresolved: $u}'
}

# verify-finding <spec-dir> <symbol>
cmd_verify_finding() {
  local spec_dir
  spec_dir=$(resolve_spec_dir "${1:-}")
  local symbol="${2:-}"
  [[ -n "$symbol" ]] || die "usage: verify-finding <spec-dir> <symbol>"
  local cfg
  cfg=$(config_path_for "$spec_dir")
  require_config "$cfg"
  local root
  root=$(repo_root_for "$spec_dir")

  # Strip qualified names: "Class.method" → search for both pieces.
  # We search for the trailing component (most distinctive).
  local search_term
  if [[ "$symbol" == *.* ]]; then
    search_term="${symbol##*.}"
  else
    search_term="$symbol"
  fi

  # Build grep --include flags from extensions
  local include_args=()
  while IFS= read -r e; do
    include_args+=( --include="*.$e" )
  done < <(jq -r '.extensions[]' "$cfg")

  # Build --exclude-dir flags from EXCLUDE_DIR_NAMES
  local exclude_dir_args=()
  local x
  for x in "${EXCLUDE_DIR_NAMES[@]}"; do
    exclude_dir_args+=( --exclude-dir="$x" )
  done

  # Also exclude patterns from config that are dir-shaped
  while IFS= read -r p; do
    # Strip leading **/ and trailing /**
    local d="${p#\*\*/}"
    d="${d%/\*\*}"
    if [[ "$d" != *"*"* && "$d" == */ ]]; then
      exclude_dir_args+=( --exclude-dir="${d%/}" )
    fi
  done < <(jq -r '.excludes[]' "$cfg")

  local matches='[]'
  if [[ ${#include_args[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local file_part rest line_no
      # grep -rn output: file:line:content
      file_part="${line%%:*}"
      rest="${line#*:}"
      line_no="${rest%%:*}"
      local content="${rest#*:}"
      local rel="${file_part#$root/}"
      matches=$(jq --arg f "$rel" --argjson l "${line_no:-0}" --arg c "$content" \
        '. + [{file: $f, line: $l, context: $c}]' <<< "$matches")
    done < <(grep -rn "${include_args[@]}" "${exclude_dir_args[@]}" -- "$search_term" "$root" 2>/dev/null || true)
  fi

  jq '.' <<< "$matches"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
audit.sh — deterministic helper CLI for the spec-audit skill.

Usage: audit.sh [--pre-archive <change>] <subcommand> [args...]

Global flags (must precede the subcommand):
  --pre-archive <change>   Treat the named active change's delta specs as part
                           of the spec corpus, as if it had just been archived.
                           Affects: inventory (delta specs tagged
                           source: "pending"). Other subcommands ignore it.
                           The change folder at <spec-dir>/changes/<change>/
                           must exist.

Config R/W:
  init <spec-dir>                              Write empty config skeleton.
  init-tree <spec-dir>                         Deterministic bootstrap proposal.
  validate <spec-dir>                          Schema-check; non-zero on failure.
  get <spec-dir> <jq-path>                     Read a value via jq.
  add-module <spec-dir> <name> --paths a,b --specs c,d
  add-path <spec-dir> <module> <path>
  add-spec <spec-dir> <module> <spec-file>
  add-pitfall <spec-dir> "<text>"
  add-exclude <spec-dir> <pattern>
  add-test-suite <spec-dir> <dir> "<command>"
  remove-module <spec-dir> <name>

Detection:
  detect-test-suites <spec-dir>                Inferred test suites (JSON).
  detect-drift <spec-dir>                      Files outside any module.
  assign-drift <spec-dir>                      Auto-assign drift via prefix.

Inventory and indices:
  inventory <spec-dir>                         Behavioral file inventory (JSON).
  symbols <spec-dir>                           Per-module symbol index (JSON).
  count-branches <file>                        Per-function branch list (JSON).
  spec-modules <spec-dir> <spec-file>          Modules a spec covers (JSON).

Verification:
  verify-finding <spec-dir> <symbol>           Grep symbol across repo (JSON).
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  if [[ $# -eq 0 ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  # Parse leading global flags before the subcommand.
  PRE_ARCHIVE_CHANGE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pre-archive)
        PRE_ARCHIVE_CHANGE="${2:-}"
        [[ -n "$PRE_ARCHIVE_CHANGE" ]] || die "--pre-archive requires a change name"
        shift 2
        ;;
      --pre-archive=*)
        PRE_ARCHIVE_CHANGE="${1#--pre-archive=}"
        [[ -n "$PRE_ARCHIVE_CHANGE" ]] || die "--pre-archive requires a change name"
        shift
        ;;
      *)
        break
        ;;
    esac
  done
  export PRE_ARCHIVE_CHANGE

  if [[ $# -eq 0 ]]; then
    err "missing subcommand"
    usage
    exit 2
  fi

  require_jq
  local cmd="$1"; shift

  # Validate pre-archive change exists when applicable. Only inventory
  # currently honors the flag; other subcommands silently ignore it.
  if [[ -n "$PRE_ARCHIVE_CHANGE" && "$cmd" == "inventory" ]]; then
    local _spec_dir_for_pre_archive
    _spec_dir_for_pre_archive=$(resolve_spec_dir "${1:-}")
    validate_pre_archive_change "$_spec_dir_for_pre_archive" "$PRE_ARCHIVE_CHANGE"
  fi

  case "$cmd" in
    init)               cmd_init "$@" ;;
    init-tree)          cmd_init_tree "$@" ;;
    validate)           cmd_validate "$@" ;;
    get)                cmd_get "$@" ;;
    add-module)         cmd_add_module "$@" ;;
    add-path)           cmd_add_path "$@" ;;
    add-spec)           cmd_add_spec "$@" ;;
    add-pitfall)        cmd_add_pitfall "$@" ;;
    add-exclude)        cmd_add_exclude "$@" ;;
    add-test-suite)     cmd_add_test_suite "$@" ;;
    remove-module)      cmd_remove_module "$@" ;;
    detect-test-suites) cmd_detect_test_suites "$@" ;;
    detect-drift)       cmd_detect_drift "$@" ;;
    assign-drift)       cmd_assign_drift "$@" ;;
    inventory)          cmd_inventory "$@" ;;
    symbols)            cmd_symbols "$@" ;;
    count-branches)     cmd_count_branches "$@" ;;
    spec-modules)       cmd_spec_modules "$@" ;;
    verify-finding)     cmd_verify_finding "$@" ;;
    *)                  err "unknown subcommand: $cmd"; usage; exit 2 ;;
  esac
}

main "$@"
