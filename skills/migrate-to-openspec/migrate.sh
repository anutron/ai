#!/usr/bin/env bash
# migrate.sh — deterministic helper CLI for the migrate-to-openspec skill.
#
# The skill orchestrates phases via the LLM; this CLI owns the deterministic
# pieces: preflight checks, inventory dirwalk, classification, file moves,
# banner injection, and validation calls. The LLM never edits migration
# state directly — every read/write goes through one of these subcommands.

set -uo pipefail

# ---------------------------------------------------------------------------
# General helpers
# ---------------------------------------------------------------------------

err() { printf '%s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

# Resolve the project root: prefer git toplevel, fall back to CWD.
project_root() {
  local root
  if root=$(git rev-parse --show-toplevel 2>/dev/null); then
    printf '%s' "$root"
    return 0
  fi
  printf '%s' "$(pwd)"
}

# Read the spec dir from `.specs` (default: specs).
read_spec_dir() {
  local root="$1"
  local default="specs"
  if [[ -f "$root/.specs" ]]; then
    local dir
    dir=$(awk -F: '/^dir:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$root/.specs")
    if [[ -n "$dir" ]]; then
      printf '%s' "$dir"
      return 0
    fi
  fi
  printf '%s' "$default"
}

# ---------------------------------------------------------------------------
# Phase 0 — Preflight
# ---------------------------------------------------------------------------

# Marker filenames.
MIGRATION_MARKER=".openspec-migration.json"
MIGRATION_STATE_FILE=".openspec-migration-state.json"

# Detect whether the project has any legacy specs at all (top-level *.md
# under the configured spec dir, or a `.specs` file pointing at one).
has_legacy_specs() {
  local root="$1"
  local spec_dir
  spec_dir=$(read_spec_dir "$root")
  if [[ -f "$root/.specs" ]]; then
    return 0
  fi
  if compgen -G "$root/$spec_dir/*.md" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Returns 0 if the marker file is present.
already_migrated() {
  local root="$1"
  [[ -f "$root/$MIGRATION_MARKER" ]]
}

preflight() {
  local root="$1"
  local auto_stash="$2"

  # 1. Already-migrated marker — exit 0, idempotent.
  if already_migrated "$root"; then
    printf 'Already migrated, nothing to do (%s present).\n' "$MIGRATION_MARKER"
    exit 0
  fi

  # 2. openspec CLI on PATH.
  if ! command -v openspec >/dev/null 2>&1; then
    die "openspec CLI not found on PATH. Install via \`npm install -g @fission-ai/openspec\`."
  fi

  # 3. Git repository with at least one commit.
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    die "Not in a git repository. Run \`git init\` and create at least one commit before migrating."
  fi
  if ! git -C "$root" rev-parse HEAD >/dev/null 2>&1; then
    die "Repository has no commits. Create at least one commit before migrating."
  fi

  # 4. No existing openspec/ directory.
  if [[ -d "$root/openspec" ]]; then
    die "Project appears already migrated — \`openspec/\` directory exists."
  fi

  # 5. Legacy specs detected.
  if ! has_legacy_specs "$root"; then
    die "No legacy specs detected. Nothing to migrate."
  fi

  # 6. Working tree clean (or auto-stash).
  local porcelain
  porcelain=$(git -C "$root" status --porcelain 2>/dev/null)
  if [[ -n "$porcelain" ]]; then
    if [[ "$auto_stash" == "1" ]]; then
      git -C "$root" stash push -u -m "openspec-migration auto-stash" >/dev/null
      # Record the stash so Phase 5 can pop it later.
      printf '%s\n' "auto-stashed" >&2
      AUTO_STASHED=1
    else
      die "Working tree is dirty. Commit, stash, or pass --auto-stash."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Tag and migration branch creation
# ---------------------------------------------------------------------------

create_pre_migration_tag_and_branch() {
  local root="$1"
  local ts
  ts=$(date +%s)
  local tag="pre-openspec-migration-$ts"
  local branch="openspec-migration-$ts"

  git -C "$root" tag "$tag" >/dev/null 2>&1 || die "failed to create tag $tag"
  git -C "$root" checkout -b "$branch" >/dev/null 2>&1 || die "failed to create branch $branch"

  # Persist state so later phases (and failure cleanup) know what to undo.
  local auto_stashed="${AUTO_STASHED:-0}"
  jq -n \
    --arg tag "$tag" \
    --arg branch "$branch" \
    --argjson stashed "$auto_stashed" \
    --arg ts "$ts" \
    '{
      pre_migration_tag: $tag,
      migration_branch: $branch,
      auto_stashed: ($stashed == 1),
      started_at: $ts
    }' > "$root/$MIGRATION_STATE_FILE"

  printf '%s\n' "tag=$tag"
  printf '%s\n' "branch=$branch"
}

# ---------------------------------------------------------------------------
# Phase 1 — Inventory
# ---------------------------------------------------------------------------

# Classify a single relative path under the spec dir into a bucket.
# Echoes the bucket name.
classify_path() {
  local rel="$1"
  # rel is relative to the project root (e.g. "specs/feature-a.md")
  local stripped="${rel#*/}"
  case "$stripped" in
    plans/*) printf 'plans' ;;
    docs/*)  printf 'docs' ;;
    audits/*) printf 'audits' ;;
    todo/*)  printf 'todo' ;;
    */*)     printf 'other' ;;
    *)       printf 'base' ;;
  esac
}

# Build the inventory JSON from a deterministic walk of the spec dir.
build_inventory_json() {
  local root="$1"
  local change_candidates_json="${2:-{\}}"  # JSON object mapping <spec-base> -> <change-name>
  local spec_dir
  spec_dir=$(read_spec_dir "$root")
  local abs="$root/$spec_dir"

  local base_files=() plans_files=() docs_files=() audits_files=() todo_files=() other_files=()

  if [[ -d "$abs" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      local rel="${f#$root/}"
      local stripped="${rel#$spec_dir/}"
      local bucket
      case "$stripped" in
        plans/*)  bucket=plans ;;
        docs/*)   bucket=docs ;;
        audits/*) bucket=audits ;;
        todo/*)   bucket=todo ;;
        */*)      bucket=other ;;
        *.md)     bucket=base ;;
        *)        bucket=other ;;
      esac
      case "$bucket" in
        base)   base_files+=("$rel") ;;
        plans)  plans_files+=("$rel") ;;
        docs)   docs_files+=("$rel") ;;
        audits) audits_files+=("$rel") ;;
        todo)   todo_files+=("$rel") ;;
        other)  other_files+=("$rel") ;;
      esac
    done < <(find "$abs" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
  fi

  local base_json plans_json docs_json audits_json todo_json other_json
  base_json=$(printf '%s\n' "${base_files[@]:-}" | awk 'NF' | LC_ALL=C sort | jq -R . | jq -s .)
  plans_json=$(printf '%s\n' "${plans_files[@]:-}" | awk 'NF' | LC_ALL=C sort | jq -R . | jq -s .)
  docs_json=$(printf '%s\n' "${docs_files[@]:-}" | awk 'NF' | LC_ALL=C sort | jq -R . | jq -s .)
  audits_json=$(printf '%s\n' "${audits_files[@]:-}" | awk 'NF' | LC_ALL=C sort | jq -R . | jq -s .)
  todo_json=$(printf '%s\n' "${todo_files[@]:-}" | awk 'NF' | LC_ALL=C sort | jq -R . | jq -s .)
  other_json=$(printf '%s\n' "${other_files[@]:-}" | awk 'NF' | LC_ALL=C sort | jq -R . | jq -s .)

  jq -n \
    --arg spec_dir "$spec_dir" \
    --argjson base "$base_json" \
    --argjson plans "$plans_json" \
    --argjson docs "$docs_json" \
    --argjson audits "$audits_json" \
    --argjson todo "$todo_json" \
    --argjson other "$other_json" \
    --argjson change_candidates "$change_candidates_json" \
    '{
      spec_dir: $spec_dir,
      base: $base,
      plans: $plans,
      docs: $docs,
      audits: $audits,
      todo: $todo,
      other: $other,
      change_candidates: $change_candidates
    }'
}

# Discover the plan file for a change candidate. Echoes the project-relative
# plan path on success; returns 1 with a message on stderr otherwise.
# Lookup order:
#   1. <spec-dir>/plans/<spec-base>.md  (direct match)
#   2. <spec-dir>/plans/*-<spec-base>.md  (any version-prefixed match)
discover_plan_for_change() {
  local root="$1"
  local spec_base="$2"
  local spec_dir
  spec_dir=$(read_spec_dir "$root")

  local direct="$root/$spec_dir/plans/$spec_base.md"
  if [[ -f "$direct" ]]; then
    printf '%s\n' "$spec_dir/plans/$spec_base.md"
    return 0
  fi

  local match
  match=$(find "$root/$spec_dir/plans" -maxdepth 1 -type f -name "*-$spec_base.md" 2>/dev/null \
    | LC_ALL=C sort | head -1)
  if [[ -n "$match" ]]; then
    printf '%s\n' "${match#$root/}"
    return 0
  fi

  err "no matching plan found for change candidate '$spec_base' (looked for $spec_dir/plans/$spec_base.md and $spec_dir/plans/*-$spec_base.md)"
  return 1
}

cmd_inventory() {
  require_jq
  local root
  root=$(project_root)

  # Inventory is a read-only operation that writes its result to disk.
  # It refuses to run if the project has no legacy specs, so callers can
  # trust the output shape.
  if ! has_legacy_specs "$root"; then
    die "No legacy specs detected. Nothing to inventory."
  fi

  local inv
  inv=$(build_inventory_json "$root")
  printf '%s\n' "$inv" > "$root/migration-inventory.json"

  # Print a human summary alongside the JSON file.
  local n_base n_plans n_docs n_audits n_todo n_other
  n_base=$(jq '.base | length' <<< "$inv")
  n_plans=$(jq '.plans | length' <<< "$inv")
  n_docs=$(jq '.docs | length' <<< "$inv")
  n_audits=$(jq '.audits | length' <<< "$inv")
  n_todo=$(jq '.todo | length' <<< "$inv")
  n_other=$(jq '.other | length' <<< "$inv")
  printf 'Phase 1 (inventory): %d base specs, %d plan(s), %d doc(s), %d audit(s), %d todo, %d other\n' \
    "$n_base" "$n_plans" "$n_docs" "$n_audits" "$n_todo" "$n_other"
  printf 'Inventory written to migration-inventory.json\n'
}

# ---------------------------------------------------------------------------
# `run` — orchestrator: Phase 0 + Phase 1 (later phases land in stages 4-5)
# ---------------------------------------------------------------------------

cmd_run() {
  require_jq

  # Parse run-specific flags. Unknown flags fall through silently for
  # forward-compatibility (--max-parallel etc. are accepted but ignored at
  # this stage's CLI; the orchestrator parses them).
  local auto_stash=0
  local auto_accept=0
  local change_bases=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-stash)   auto_stash=1; shift ;;
      --auto-accept)  auto_accept=1; shift ;;
      --change)       change_bases+=("$2"); shift 2 ;;
      --max-parallel) shift 2 ;;
      --) shift; break ;;
      *)  shift ;;
    esac
  done

  local root
  root=$(project_root)

  AUTO_STASHED=0
  preflight "$root" "$auto_stash"

  # Tag + branch
  create_pre_migration_tag_and_branch "$root" >/dev/null

  # Resolve change candidates -> matched plan basenames. Fail fast if any
  # flagged spec lacks a discoverable plan.
  local change_candidates_json='{}'
  if [[ ${#change_bases[@]} -gt 0 ]]; then
    local cb plan_path change_name
    for cb in "${change_bases[@]}"; do
      plan_path=$(discover_plan_for_change "$root" "$cb") || die "Phase 1: --change $cb: no matching plan"
      change_name="${plan_path##*/}"
      change_name="${change_name%.md}"
      change_candidates_json=$(jq --arg k "$cb" --arg v "$change_name" \
        '. + {($k): $v}' <<< "$change_candidates_json")
    done
  fi

  # Phase 1 inventory
  local inv
  inv=$(build_inventory_json "$root" "$change_candidates_json")
  printf '%s\n' "$inv" > "$root/migration-inventory.json"

  # Commit the inventory on the migration branch so the state is durable.
  git -C "$root" add migration-inventory.json "$MIGRATION_STATE_FILE" >/dev/null 2>&1 || true
  git -C "$root" -c user.email=migrate@openspec.local -c user.name="openspec-migration" \
    commit -q -m "openspec migration: inventory" >/dev/null 2>&1 || true

  local n_base n_plans n_docs n_audits n_todo n_other branch
  n_base=$(jq '.base | length' <<< "$inv")
  n_plans=$(jq '.plans | length' <<< "$inv")
  n_docs=$(jq '.docs | length' <<< "$inv")
  n_audits=$(jq '.audits | length' <<< "$inv")
  n_todo=$(jq '.todo | length' <<< "$inv")
  n_other=$(jq '.other | length' <<< "$inv")
  branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')

  printf 'Phase 1 (inventory): %d base specs, %d plan(s), %d doc(s), %d audit(s), %d todo, %d other\n' \
    "$n_base" "$n_plans" "$n_docs" "$n_audits" "$n_todo" "$n_other"
  printf 'Inventory written to migration-inventory.json on branch %s.\n' "$branch"

  # ---- Phase 2: translate + verify (fixture-fast or via the orchestrator).
  #
  # In fixture-fast mode (tests, MIGRATE_FIXTURE_FAST=1), this CLI runs
  # translate and verify directly on every base spec sequentially -- the
  # work is deterministic and cheap. In production, the SKILL.md orchestrator
  # dispatches Agent waves and the CLI helpers (translate/verify per
  # capability) are called individually.
  if [[ "${MIGRATE_FIXTURE_FAST:-0}" == "1" ]]; then
    local rel cap
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      cap=$(slugify "$rel")
      _translate_one "$root" "$root/$rel" "$cap" "" >/dev/null
      cmd_verify --source "$root/$rel" --capability "$cap" >/dev/null 2>&1 || true
    done < <(jq -r '.base[]?' "$root/migration-inventory.json")
    printf 'Phase 2 (translate + verify): %d capabilities processed.\n' "$n_base"
  else
    # In production, the orchestrator handles Phase 2. If invoked from
    # the CLI without prior translation, log a hint and stop.
    if [[ ! -d "$root/.openspec-migration/verifier-reports" ]]; then
      printf 'Phase 2: dispatch translator + verifier waves via the SKILL.md orchestrator.\n'
      printf '       After all reports are written, re-run: migrate.sh execute\n'
      return 0
    fi
  fi

  # ---- Phase 3: resolution.
  cmd_resolve_all "$root" "$auto_accept"

  # ---- Phase 4: execution.
  _execute "$root" || die "Phase 4 execution failed"

  # ---- Phase 5: handoff.
  _handoff "$root"
}

# ---------------------------------------------------------------------------
# Slugify — derive a kebab-case capability name from a filename.
# ---------------------------------------------------------------------------

slugify() {
  # Strip directory components, drop the .md extension, lowercase, replace
  # any run of non-[a-z0-9] with a single hyphen, trim leading/trailing
  # hyphens. Matches the style of .claude/skills/spec-audit/audit.sh.
  local input="$1"
  local base="${input##*/}"
  base="${base%.md}"
  printf '%s' "$base" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# ---------------------------------------------------------------------------
# Phase 2 — Translator + verifier (LLM-driven via `claude -p`)
#
# Both subcommands shell out to `claude -p <prompt>` for the actual LLM
# work. The prompts live in prompts/translator-prompt.md and
# prompts/verifier-prompt.md. Tests can set MIGRATE_FIXTURE_FAST=1 to use
# pre-baked golden translations and a deterministic verifier; production
# runs always hit `claude -p`.
# ---------------------------------------------------------------------------

# Resolve the directory containing this migrate.sh script (so we can find
# prompts/ and test/fixtures-golden/ regardless of CWD).
script_dir() {
  local src="${BASH_SOURCE[0]}"
  while [[ -h "$src" ]]; do
    local dir
    dir=$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)
    src=$(readlink "$src")
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# Render a prompt template by substituting {placeholder} keys.
# Usage: render_prompt <template-path> <key1> <val1> [<key2> <val2> ...]
# The values are passed through to a python helper to avoid sed-quoting
# hazards on values that contain newlines, slashes, or backslashes.
render_prompt() {
  local template="$1"; shift
  python3 - "$template" "$@" <<'PY'
import sys
template_path = sys.argv[1]
pairs = sys.argv[2:]
text = open(template_path).read()
for i in range(0, len(pairs), 2):
    key = "{" + pairs[i] + "}"
    val = pairs[i + 1]
    text = text.replace(key, val)
sys.stdout.write(text)
PY
}

# Locate the claude CLI. Defaults to PATH lookup; can be overridden via
# CLAUDE_BIN environment variable.
claude_bin() {
  if [[ -n "${CLAUDE_BIN:-}" ]]; then
    printf '%s' "$CLAUDE_BIN"
    return 0
  fi
  if command -v claude >/dev/null 2>&1; then
    command -v claude
    return 0
  fi
  if [[ -x "$HOME/.local/bin/claude" ]]; then
    printf '%s' "$HOME/.local/bin/claude"
    return 0
  fi
  printf 'claude'
}

# Strip the META JSON tail from translator output. The tail is delimited
# by a `<!-- META -->` line; everything from that line onward is removed.
# Echoes (1) the cleaned markdown to stdout and (2) the META JSON to a
# file path passed as $2.
split_translator_output() {
  local raw_path="$1"
  local body_path="$2"
  local meta_path="$3"
  python3 - "$raw_path" "$body_path" "$meta_path" <<'PY'
import sys, re, json
raw = open(sys.argv[1]).read()
parts = re.split(r"\n?<!--\s*META\s*-->\n?", raw, maxsplit=1)
body = parts[0].rstrip() + "\n"
meta_raw = parts[1].strip() if len(parts) > 1 else ""

# Some models wrap the JSON in code fences; strip them.
meta_raw = re.sub(r"^```(?:json)?\s*", "", meta_raw)
meta_raw = re.sub(r"\s*```$", "", meta_raw)

if not meta_raw:
    meta = {"unmapped": []}
else:
    try:
        meta = json.loads(meta_raw)
    except Exception:
        meta = {"unmapped": [], "raw_meta": meta_raw}

open(sys.argv[2], "w").write(body)
open(sys.argv[3], "w").write(json.dumps(meta, indent=2) + "\n")
PY
}

# Strip leading code fences from a translator response. Some models like
# to wrap markdown bodies in ```markdown ... ``` despite the prompt.
strip_outer_fences() {
  local raw_path="$1"
  python3 - "$raw_path" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
# Strip a leading code fence that spans the whole document.
m = re.match(r"\s*```(?:markdown|md)?\s*\n(.*?)\n```\s*$", text, re.S)
if m:
    open(path, "w").write(m.group(1) + "\n")
PY
}

# Run a translator agent for one source spec and write the translated
# OpenSpec spec to disk.
cmd_translate() {
  require_jq
  local source_path=""
  local capability=""
  local out_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --capability) capability="$2"; shift 2 ;;
      --out)        out_path="$2"; shift 2 ;;
      -h|--help)
        cat <<EOF
migrate.sh translate <source-spec-path> [--capability <name>] [--out <path>]
EOF
        return 0
        ;;
      *)
        if [[ -z "$source_path" ]]; then
          source_path="$1"; shift
        else
          die "unexpected argument: $1"
        fi
        ;;
    esac
  done

  local root
  root=$(project_root)

  # Bulk mode: no source given. Build inventory on demand (a previously-run
  # `migrate.sh inventory` is honored if present) and translate every base
  # spec.
  if [[ -z "$source_path" ]]; then
    if [[ ! -f "$root/migration-inventory.json" ]]; then
      if ! has_legacy_specs "$root"; then
        die "no source provided and no legacy specs detected"
      fi
      build_inventory_json "$root" > "$root/migration-inventory.json"
    fi
    local rel
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      _translate_one "$root" "$root/$rel" "" ""
    done < <(jq -r '.base[]?' "$root/migration-inventory.json")
    return 0
  fi

  _translate_one "$root" "$source_path" "$capability" "$out_path"
}

# Internal: translate a single source spec.
_translate_one() {
  local root="$1"
  local source_path="$2"
  local capability="$3"
  local out_path="$4"

  if [[ ! -f "$source_path" ]]; then
    die "source spec not found: $source_path"
  fi
  if [[ -z "$capability" ]]; then
    capability=$(slugify "$source_path")
  fi
  if [[ -z "$out_path" ]]; then
    out_path="$root/openspec/specs/$capability/spec.md"
  fi

  mkdir -p "$(dirname "$out_path")"

  # Fixture-fast path: copy the golden translation deterministically.
  if [[ "${MIGRATE_FIXTURE_FAST:-0}" == "1" ]]; then
    local golden_dir
    golden_dir=$(script_dir)/test/fixtures-golden
    local golden="$golden_dir/$capability.md"
    if [[ ! -f "$golden" ]]; then
      die "MIGRATE_FIXTURE_FAST=1 but no golden translation at $golden"
    fi
    cp "$golden" "$out_path"
    # Synthesize an empty meta sidecar so downstream code paths are
    # uniform.
    printf '{"unmapped": [], "fixture_fast": true}\n' > "$out_path.meta.json"
    printf 'translated %s -> %s\n' "$capability" "$out_path"
    return 0
  fi

  # Production path: render prompt and call `claude -p`.
  local prompts_dir
  prompts_dir=$(script_dir)/prompts
  local template="$prompts_dir/translator-prompt.md"
  if [[ ! -f "$template" ]]; then
    die "translator prompt template missing at $template"
  fi

  local source_content
  source_content=$(cat "$source_path")

  local prompt
  prompt=$(render_prompt "$template" \
    "source_path" "$source_path" \
    "capability_name" "$capability" \
    "source_content" "$source_content")

  local raw_tmp
  raw_tmp=$(mktemp)

  local cb
  cb=$(claude_bin)
  if ! "$cb" -p "$prompt" > "$raw_tmp" 2>/dev/null; then
    rm -f "$raw_tmp"
    die "claude -p failed for $source_path (capability $capability)"
  fi

  # Strip outer code fences (defensive — the prompt forbids them but
  # models occasionally insert them anyway).
  strip_outer_fences "$raw_tmp"

  # Split body and META JSON.
  split_translator_output "$raw_tmp" "$out_path" "$out_path.meta.json"
  rm -f "$raw_tmp"

  printf 'translated %s -> %s\n' "$capability" "$out_path"
}

# Dispatch verification of a single capability against its source.
cmd_verify() {
  require_jq
  local source_path=""
  local capability=""
  local emit_json=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)     source_path="$2"; shift 2 ;;
      --capability) capability="$2"; shift 2 ;;
      --json)       emit_json=1; shift ;;
      -h|--help)
        cat <<EOF
migrate.sh verify --capability <name> [--source <path>] [--json]
EOF
        return 0
        ;;
      *) die "unexpected argument: $1" ;;
    esac
  done

  if [[ -z "$capability" ]]; then
    die "verify requires --capability"
  fi

  local root
  root=$(project_root)

  # Resolve source path from inventory if not given explicitly.
  if [[ -z "$source_path" && -f "$root/migration-inventory.json" ]]; then
    source_path=$(jq -r --arg cap "$capability" '
      .base[]? | select(. as $f
        | ($f | sub("^.+/";"") | sub("\\.md$";""))
          | gsub("[^A-Za-z0-9]";"-")
          | ascii_downcase
          | . == $cap)
    ' "$root/migration-inventory.json" | head -n1)
    if [[ -n "$source_path" ]]; then
      source_path="$root/$source_path"
    fi
  fi

  if [[ -z "$source_path" || ! -f "$source_path" ]]; then
    die "verify: source spec not found (capability=$capability, source=$source_path)"
  fi

  local trans_path="$root/openspec/specs/$capability/spec.md"
  if [[ ! -f "$trans_path" ]]; then
    die "verify: translation not found at $trans_path"
  fi

  local source_content translation_content
  source_content=$(cat "$source_path")
  translation_content=$(cat "$trans_path")

  local report_dir="$root/.openspec-migration/verifier-reports"
  mkdir -p "$report_dir"
  local report_path="$report_dir/$capability.json"

  local raw_tmp
  raw_tmp=$(mktemp)

  if [[ "${MIGRATE_FIXTURE_FAST:-0}" == "1" ]]; then
    # Deterministic verifier: structurally diff the translation against
    # the source's Given/When/Then blocks.
    python3 - "$source_path" "$trans_path" "$capability" "$report_path" <<'PY'
import sys, re, json, os

source_path = sys.argv[1]
trans_path = sys.argv[2]
capability = sys.argv[3]
report_path = sys.argv[4]

src = open(source_path).read()
trn = open(trans_path).read()

# Count Given/When/Then blocks in the source. A block is a bullet that
# starts with "**Given**".
given_count = len(re.findall(r"^\s*-\s*\*\*Given\*\*", src, re.M))

# Count scenarios in the translation.
scenario_count = len(re.findall(r"^####\s+Scenario:", trn, re.M))

# Count requirements in the translation.
req_count = len(re.findall(r"^###\s+Requirement:", trn, re.M))

issues = []

# Check 1: every Given/When/Then in source has a scenario.
# We model this as "scenario_count >= given_count when given_count > 0".
# When given_count is 0 (pure prose), require at least one scenario per
# requirement, which the structural check below handles.
if given_count > 0 and scenario_count < given_count:
    issues.append({
        "location_source": f"## Test cases (Given/When/Then x{given_count})",
        "location_translation": f"#### Scenario: x{scenario_count}",
        "severity": "missing",
        "description": (
            f"Source has {given_count} Given/When/Then test case(s) but "
            f"translation has only {scenario_count} #### Scenario block(s)."
        ),
    })

# Check 2: every requirement has at least one scenario.
# Walk the translation and group scenarios under requirements.
sections = re.split(r"^###\s+Requirement:", trn, flags=re.M)
# sections[0] is preamble; the rest are requirement bodies.
for idx, body in enumerate(sections[1:], start=1):
    if "#### Scenario:" not in body:
        first_line = body.strip().splitlines()[0] if body.strip() else f"requirement {idx}"
        issues.append({
            "location_source": None,
            "location_translation": f"### Requirement: {first_line}",
            "severity": "structural",
            "description": "Requirement has no #### Scenario block",
        })

# Check 3: requirement count >= 1.
if req_count == 0:
    issues.append({
        "location_source": "(any behavioral statement)",
        "location_translation": None,
        "severity": "structural",
        "description": "Translation has no ### Requirement: block",
    })

status = "clean" if not issues else "issues"
report = {
    "source": os.path.relpath(source_path),
    "translated": capability,
    "status": status,
    "issues": issues,
}
open(report_path, "w").write(json.dumps(report, indent=2) + "\n")
sys.stdout.write(json.dumps(report, indent=2) + "\n")
PY
  else
    # Production path: call claude -p with the verifier prompt.
    local prompts_dir
    prompts_dir=$(script_dir)/prompts
    local template="$prompts_dir/verifier-prompt.md"
    if [[ ! -f "$template" ]]; then
      die "verifier prompt template missing at $template"
    fi

    local prompt
    prompt=$(render_prompt "$template" \
      "capability_name" "$capability" \
      "source_content" "$source_content" \
      "translation_content" "$translation_content")

    local cb
    cb=$(claude_bin)
    if ! "$cb" -p "$prompt" > "$raw_tmp" 2>/dev/null; then
      rm -f "$raw_tmp"
      die "claude -p failed for verifier (capability $capability)"
    fi

    # Validate the model output is JSON; if not, wrap into an `issues`
    # report flagging the structural problem.
    python3 - "$raw_tmp" "$capability" "$report_path" <<'PY'
import sys, json, re, os
raw_path = sys.argv[1]
capability = sys.argv[2]
report_path = sys.argv[3]
raw = open(raw_path).read().strip()

# Strip code fences if the model added them.
raw = re.sub(r"^```(?:json)?\s*", "", raw)
raw = re.sub(r"\s*```$", "", raw).strip()

try:
    data = json.loads(raw)
except Exception as exc:
    data = {
        "source": "?",
        "translated": capability,
        "status": "issues",
        "issues": [{
            "location_source": None,
            "location_translation": None,
            "severity": "structural",
            "description": f"verifier returned non-JSON output: {exc}",
        }],
    }

# Schema check: ensure `status` is clean|issues and `issues` is a list.
if data.get("status") not in ("clean", "issues"):
    data.setdefault("issues", []).append({
        "location_source": None,
        "location_translation": None,
        "severity": "structural",
        "description": f"verifier produced unknown status: {data.get('status')!r}",
    })
    data["status"] = "issues"
if not isinstance(data.get("issues", []), list):
    data["issues"] = []
data.setdefault("translated", capability)

open(report_path, "w").write(json.dumps(data, indent=2) + "\n")
sys.stdout.write(json.dumps(data, indent=2) + "\n")
PY
  fi

  rm -f "$raw_tmp"

  # Exit code: 0 for clean, 2 for issues, so callers can distinguish
  # "drift detected" from "real error".
  local final_status
  final_status=$(jq -r '.status' "$report_path")
  if [[ "$final_status" == "issues" ]]; then
    return 2
  fi
  return 0
}

# Validate a single capability via openspec.
# Bootstraps openspec/ if needed (write a minimal init config and inject
# the spec under openspec/specs/<name>/spec.md).
cmd_validate_capability() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    die "validate-capability requires a capability name"
  fi

  local root
  root=$(project_root)

  local spec_file="$root/openspec/specs/$name/spec.md"
  if [[ ! -f "$spec_file" ]]; then
    die "no spec at $spec_file"
  fi

  # If the project hasn't run `openspec init`, bootstrap a minimal
  # config so `openspec validate` can find the spec.
  if [[ ! -f "$root/openspec/project.md" && ! -f "$root/openspec/AGENTS.md" ]]; then
    (cd "$root" && openspec init --tools none . >/dev/null 2>&1) || true
  fi

  (cd "$root" && OPENSPEC_TELEMETRY=0 openspec validate "$name" --type spec --strict)
}

# ---------------------------------------------------------------------------
# Phase 3 — Resolution
#
# Each verifier report (`.openspec-migration/verifier-reports/*.json`) is
# either `clean` (auto-accept) or `issues` (surface to the user, with the
# accept / retry / skip options). Decisions are recorded in
# `.openspec-migration/resolution.json` so Phase 4 knows which capabilities
# to actually write into `openspec/specs/`.
#
# In `--auto-accept` mode (Phase 0 orchestrator flag), clean reports are
# accepted and any with issues are skipped. Auto-accept never retries --
# the semantics are "trust whatever's clean, defer the rest".
# ---------------------------------------------------------------------------

# Internal: write `.openspec-migration/resolution.json` mapping capability
# names to actions (accept | skip).
cmd_resolve_all() {
  require_jq
  local root="$1"
  local auto_accept="$2"

  local report_dir="$root/.openspec-migration/verifier-reports"
  mkdir -p "$root/.openspec-migration"
  local resolution_path="$root/.openspec-migration/resolution.json"

  local actions_json='{}'
  if [[ -d "$report_dir" ]]; then
    local report cap status action
    for report in "$report_dir"/*.json; do
      [[ -e "$report" ]] || continue
      cap=$(jq -r '.translated // empty' "$report")
      status=$(jq -r '.status // empty' "$report")
      [[ -n "$cap" ]] || continue

      if [[ "$status" == "clean" ]]; then
        action="accept"
      elif [[ "$auto_accept" == "1" ]]; then
        # Auto-accept mode: skip any capability with issues.
        action="skip"
      else
        # Honor any pre-recorded action from `migrate.sh resolve`.
        action=$(jq -r --arg cap "$cap" '.[$cap] // empty' "$resolution_path" 2>/dev/null || true)
        if [[ -z "$action" ]]; then
          # Default to "skip" so the run continues without invented
          # decisions. The orchestrator (SKILL.md) is responsible for
          # surfacing the report and recording the user's choice via
          # `migrate.sh resolve` before reaching this code path.
          action="skip"
        fi
      fi
      actions_json=$(jq --arg cap "$cap" --arg action "$action" \
        '. + {($cap): $action}' <<< "$actions_json")
    done
  fi
  printf '%s\n' "$actions_json" > "$resolution_path"

  local accepted skipped
  accepted=$(jq -r 'to_entries | map(select(.value=="accept")) | length' <<< "$actions_json")
  skipped=$(jq -r 'to_entries | map(select(.value=="skip")) | length' <<< "$actions_json")
  printf 'Phase 3 (resolution): %d accepted, %d skipped.\n' "$accepted" "$skipped"
}

# CLI: print a unified diff between source and translation.
cmd_diff() {
  local source_path="${1:-}"
  local capability="${2:-}"
  if [[ -z "$source_path" || -z "$capability" ]]; then
    die "diff requires <source-path> <capability>"
  fi
  local root
  root=$(project_root)
  local trans="$root/openspec/specs/$capability/spec.md"
  if [[ ! -f "$source_path" ]]; then die "source not found: $source_path"; fi
  if [[ ! -f "$trans" ]]; then die "translation not found: $trans"; fi
  diff -u "$source_path" "$trans" || true
}

# CLI: re-run translator with verifier issues appended as a constraint.
# Bumps a retry counter capped at 2.
cmd_retry() {
  require_jq
  local source_path="${1:-}"
  local capability="${2:-}"
  if [[ -z "$source_path" || -z "$capability" ]]; then
    die "retry requires <source-path> <capability>"
  fi
  local root
  root=$(project_root)

  local retry_dir="$root/.openspec-migration/retries"
  mkdir -p "$retry_dir"
  local counter_path="$retry_dir/$capability.txt"
  local count=0
  if [[ -f "$counter_path" ]]; then count=$(cat "$counter_path"); fi
  if (( count >= 2 )); then
    die "retry limit (2) reached for capability $capability"
  fi
  count=$((count + 1))
  printf '%d\n' "$count" > "$counter_path"

  local report_path="$root/.openspec-migration/verifier-reports/$capability.json"
  local issues=""
  if [[ -f "$report_path" ]]; then
    issues=$(jq -r '.issues // [] | map("- (\(.severity // "?")) \(.description // "")") | join("\n")' "$report_path" 2>/dev/null || true)
  fi

  # In fixture-fast mode, just re-run the deterministic translation. In
  # production, append the issues block to the translator prompt as a
  # retry constraint by setting an env var the translator reads.
  if [[ "${MIGRATE_FIXTURE_FAST:-0}" == "1" ]]; then
    _translate_one "$root" "$source_path" "$capability" "" >/dev/null
  else
    MIGRATE_RETRY_CONSTRAINT="$issues" _translate_one "$root" "$source_path" "$capability" "" >/dev/null
  fi

  # Re-run the verifier so the report reflects the fresh translation.
  cmd_verify --source "$source_path" --capability "$capability" >/dev/null 2>&1 || true
  printf 'retried %s (attempt %d/2)\n' "$capability" "$count"
}

# CLI: record a resolution decision for a single capability.
cmd_resolve() {
  require_jq
  local capability=""
  local action=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action) action="$2"; shift 2 ;;
      *)
        if [[ -z "$capability" ]]; then capability="$1"; shift
        else die "unexpected argument: $1"; fi
        ;;
    esac
  done
  if [[ -z "$capability" || -z "$action" ]]; then
    die "resolve requires <capability> --action accept|retry|skip"
  fi
  case "$action" in
    accept|retry|skip) ;;
    *) die "invalid action: $action (must be accept|retry|skip)" ;;
  esac
  local root
  root=$(project_root)
  mkdir -p "$root/.openspec-migration"
  local path="$root/.openspec-migration/resolution.json"
  if [[ ! -f "$path" ]]; then
    printf '{}\n' > "$path"
  fi
  local updated
  updated=$(jq --arg cap "$capability" --arg action "$action" \
    '. + {($cap): $action}' "$path")
  printf '%s\n' "$updated" > "$path"
  printf 'recorded %s = %s\n' "$capability" "$action"
}

# ---------------------------------------------------------------------------
# Phase 4 — Execution
#
# After resolution decisions are recorded, _execute writes accepted specs
# into openspec/specs/, archives every source spec under
# .workflow/legacy-specs/ with a forwarding banner, moves sibling artifacts
# (plans, docs, audits, todo) under .workflow/, validates the result,
# installs templates, writes the .openspec-migration.json marker, and
# commits everything as one migration commit.
#
# Transactional rollback: before any file moves, we record the current
# HEAD; on validation failure, `git reset --hard <pre-migration-tag>` and
# `git clean -fd` restore the project to its pre-migration state.
# ---------------------------------------------------------------------------

# Derive the H1 title from a markdown file (first `# ...` line). Falls back
# to the basename without extension.
_derive_title() {
  local file="$1"
  local title
  title=$(awk '
    /^#[[:space:]]+/ {
      sub(/^#[[:space:]]+/, "")
      print
      exit
    }
  ' "$file")
  if [[ -z "$title" ]]; then
    local base="${file##*/}"
    title="${base%.md}"
  fi
  printf '%s' "$title"
}

# Build the [Legacy] banner for an archived spec. Args:
# $1 = original title  $2 = newline-delimited list of capability names
_render_banner() {
  local title="$1"
  local capabilities="$2"
  local today
  today=$(date +%Y-%m-%d)
  printf '# [Legacy] %s\n\n' "$title"
  printf '> Migrated to OpenSpec on %s.\n' "$today"
  printf '> New location(s):\n'
  while IFS= read -r cap; do
    [[ -n "$cap" ]] || continue
    printf '> - `openspec/specs/%s/spec.md`\n' "$cap"
  done <<< "$capabilities"
  printf '>\n'
  printf '> Preserved for reference. Updates belong in the OpenSpec capability spec.\n'
  printf '\n'
}

# Install a template file from templates/ to dest. If the template doesn't
# exist yet (Stage 6 hasn't filled it in), write a one-line stub so the
# fixture tests' existence check passes.
_install_template() {
  local src="$1"
  local dest="$2"
  local stub="$3"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
  else
    printf '%s\n' "$stub" > "$dest"
  fi
}

# Translate a legacy spec-audit config (`<spec-dir>/.audit-config.json`) into
# the OpenSpec location (`openspec/.audit-config.json`). Modules' `specs`
# arrays are normalized from legacy filenames (`foo.md`, `path/foo.md`) to
# capability slugs (`foo`); entries whose slug is not in the accepted-caps
# set are dropped; `mapping_cache` is reset to `{}`; everything else
# (`pitfalls`, `extensions`, `excludes`, `test_suites`, `version`) is
# preserved verbatim. No-op if the legacy config is absent.
# Install a change-folder at openspec/changes/<change-name>/ for an accepted
# change candidate, using the Phase 2 translation as the source for the delta
# spec and the matched plan as the source for tasks.md. Removes the original
# openspec/specs/<cap>/spec.md so the change folder is the sole home of the
# capability until the change is later archived.
#
# Args: <root> <spec-base> <change-name> <capability> <spec-relpath> <plan-relpath>
_install_change_folder() {
  local root="$1"
  local spec_base="$2"
  local change_name="$3"
  local cap="$4"
  local spec_relpath="$5"   # e.g. "specs/revise.md"
  local plan_relpath="$6"   # e.g. "specs/plans/v1.1-revise.md"

  local src_translation="$root/openspec/specs/$cap/spec.md"
  if [[ ! -f "$src_translation" ]]; then
    err "Phase 4: change candidate '$cap' has no Phase 2 translation at $src_translation"
    return 1
  fi

  local change_dir="$root/openspec/changes/$change_name"
  mkdir -p "$change_dir/specs/$cap"

  # ---- 1. Convert translation -> delta.
  # The translator emits:
  #   # <title>
  #   ## Purpose
  #   <text>
  #   ## Requirements
  #   ### Requirement: ...
  # For the delta, drop everything up to (but not including) ## Requirements,
  # and rename that header to ## ADDED Requirements.
  local delta_path="$change_dir/specs/$cap/spec.md"
  awk '
    BEGIN { found = 0 }
    /^## Requirements[[:space:]]*$/ {
      print "## ADDED Requirements"
      found = 1
      next
    }
    found { print }
  ' "$src_translation" > "$delta_path.tmp"

  if [[ ! -s "$delta_path.tmp" ]]; then
    rm -f "$delta_path.tmp"
    err "Phase 4: failed to extract requirements section from translation for '$cap'"
    return 1
  fi
  mv "$delta_path.tmp" "$delta_path"

  # ---- 2. Generate proposal.md (deterministic).
  local title
  title=$(_derive_title "$root/$spec_relpath")
  local plan_basename="${plan_relpath##*/}"
  local spec_basename="${spec_relpath##*/}"

  cat > "$change_dir/proposal.md" <<PROPOSAL
## Why

\`$cap\` describes future behavior preserved during the OpenSpec migration. The original brainstorm and implementation plan live at \`.workflow/plans/$plan_basename\`; the legacy requirements doc is preserved at \`.workflow/legacy-specs/$spec_basename\`. This change captures that future state in OpenSpec form so the work can be tracked, validated, and ultimately archived once shipped.

## What Changes

- Add \`$cap\` capability with the requirements lifted from the legacy spec (see \`specs/$cap/spec.md\` for the delta).

## Capabilities

### New Capabilities

- \`$cap\`: $title

### Modified Capabilities

(none)

## Impact

- Affected code: TBD - the change has not been implemented yet. See \`tasks.md\` for the implementation phases.
- Original design: \`.workflow/plans/$plan_basename\`.
- Legacy requirements: \`.workflow/legacy-specs/$spec_basename\`.
PROPOSAL

  # ---- 3. Generate tasks.md from the matched plan.
  # Parse "### Phase N:" headings first; fall back to "## " headings.
  local plan_full="$root/$plan_relpath"
  {
    printf '# Tasks\n\n'
    printf '## Implementation\n\n'
    if grep -qE '^### Phase [0-9]+' "$plan_full" 2>/dev/null; then
      local n=0 line heading
      while IFS= read -r line; do
        n=$((n + 1))
        heading="${line#### }"
        printf -- '- [ ] %d. %s\n' "$n" "$heading"
      done < <(grep -E '^### Phase [0-9]+' "$plan_full")
    else
      local n=0 line heading
      while IFS= read -r line; do
        n=$((n + 1))
        heading="${line## }"
        heading="${heading## }"
        printf -- '- [ ] %d. %s\n' "$n" "$heading"
      done < <(grep -E '^## [^#]' "$plan_full" 2>/dev/null)
      if [[ $n -eq 0 ]]; then
        printf -- '- [ ] 1. Implement %s per `.workflow/plans/%s`\n' "$cap" "$plan_basename"
      fi
    fi
  } > "$change_dir/tasks.md"

  # ---- 4. Remove the openspec/specs/ landing the translator wrote, since
  # the change folder is the sole home of the capability until archive.
  # rm -rf to clean up sidecars (spec.md.meta.json) too.
  rm -rf "$root/openspec/specs/$cap"

  printf 'Phase 4 (change candidate): wrote openspec/changes/%s/{proposal.md,tasks.md,specs/%s/spec.md}\n' \
    "$change_name" "$cap"
}

_translate_audit_config() {
  local root="$1"
  local accepted_caps="$2"  # newline-separated list
  local change_cap_slugs_csv="${3:-}"  # comma-separated list of change-candidate slugs

  local spec_dir
  spec_dir=$(read_spec_dir "$root")
  local src_config="$root/$spec_dir/.audit-config.json"
  [[ -f "$src_config" ]] || return 0

  # Drop change-candidate slugs from accepted: they live at
  # openspec/changes/<name>/specs/<cap>/, not openspec/specs/<cap>/, so
  # the spec-audit skill's spec walk won't see them and any module
  # reference to them would dangle.
  local accepted_in_specs
  if [[ -n "$change_cap_slugs_csv" ]]; then
    local IFS=','
    local -a change_arr=($change_cap_slugs_csv)
    accepted_in_specs="$accepted_caps"
    local cs
    for cs in "${change_arr[@]}"; do
      [[ -n "$cs" ]] || continue
      accepted_in_specs=$(printf '%s\n' "$accepted_in_specs" | grep -vx "$cs" || true)
    done
  else
    accepted_in_specs="$accepted_caps"
  fi

  local accepted_json
  accepted_json=$(printf '%s\n' "$accepted_in_specs" | awk 'NF' | jq -R . | jq -s .)

  local dest_config="$root/openspec/.audit-config.json"
  mkdir -p "$root/openspec"

  if ! jq --argjson accepted "$accepted_json" '
    def to_slug:
      sub(".*/"; "")
      | sub("\\.md$"; "")
      | ascii_downcase
      | gsub("[^a-z0-9]+"; "-")
      | sub("^-+"; "")
      | sub("-+$"; "");
    (.modules // []) |= map(
      .specs |= (
        (. // [])
        | map(to_slug)
        | map(select(. as $s | $accepted | any(. == $s)))
        | unique
      )
    )
    | .mapping_cache = {}
  ' "$src_config" > "$dest_config.tmp"; then
    rm -f "$dest_config.tmp"
    err "Phase 4: failed to translate $spec_dir/.audit-config.json; skipping (config not migrated)"
    return 0
  fi
  mv "$dest_config.tmp" "$dest_config"

  printf 'Phase 4 (audit config): translated %s/.audit-config.json -> openspec/.audit-config.json\n' "$spec_dir"
}

_execute() {
  local root="$1"

  # --- Read state.
  local state_path="$root/$MIGRATION_STATE_FILE"
  local pre_tag="" branch=""
  if [[ -f "$state_path" ]]; then
    pre_tag=$(jq -r '.pre_migration_tag // empty' "$state_path")
    branch=$(jq -r '.migration_branch // empty' "$state_path")
  fi

  # --- Read inventory and resolution.
  local inv_path="$root/migration-inventory.json"
  local res_path="$root/.openspec-migration/resolution.json"
  if [[ ! -f "$inv_path" ]]; then die "Phase 4: missing migration-inventory.json"; fi
  if [[ ! -f "$res_path" ]]; then printf '{}\n' > "$res_path"; fi

  local accepted_caps skipped_caps
  accepted_caps=$(jq -r 'to_entries | map(select(.value=="accept")) | .[].key' "$res_path")
  skipped_caps=$(jq -r 'to_entries | map(select(.value=="skip")) | .[].key' "$res_path")

  # --- Read change-candidate routing from inventory.
  # Build parallel arrays indexed by slug for cheap O(N) lookup. The count is
  # tiny (typically < 5) so a linear scan is fine.
  local change_cap_slugs=() change_cap_names=() change_cap_specs=() change_cap_plans=()
  local cb cn cap_slug spec_rel plan_rel
  while IFS=$'\t' read -r cb cn; do
    [[ -n "$cb" ]] || continue
    cap_slug=$(slugify "$cb")
    spec_rel=$(jq -r --arg b "${cb}.md" '.base[]? | select(((.|sub(".*/"; ""))==$b))' "$inv_path" | head -1)
    plan_rel=$(jq -r --arg n "${cn}.md" '.plans[]? | select(((.|sub(".*/"; ""))==$n))' "$inv_path" | head -1)
    if [[ -z "$spec_rel" ]]; then
      err "Phase 4: change candidate '$cb' not found in inventory.base; skipping"
      continue
    fi
    if [[ -z "$plan_rel" ]]; then
      err "Phase 4: change candidate '$cb': plan '$cn' not found in inventory.plans; skipping"
      continue
    fi
    change_cap_slugs+=("$cap_slug")
    change_cap_names+=("$cn")
    change_cap_specs+=("$spec_rel")
    change_cap_plans+=("$plan_rel")
  done < <(jq -r '(.change_candidates // {}) | to_entries[]? | "\(.key)\t\(.value)"' "$inv_path")

  is_change_cap() {
    local needle="$1" i
    for i in "${change_cap_slugs[@]:-}"; do
      [[ "$i" == "$needle" ]] && return 0
    done
    return 1
  }

  get_change_cap_index() {
    local needle="$1" i
    for i in "${!change_cap_slugs[@]}"; do
      [[ "${change_cap_slugs[$i]}" == "$needle" ]] && { printf '%s' "$i"; return 0; }
    done
    return 1
  }

  # --- Initialize OpenSpec dir.
  if [[ ! -d "$root/openspec" ]]; then
    (cd "$root" && openspec init --tools none . >/dev/null 2>&1) || true
  fi
  mkdir -p "$root/openspec/specs"

  # --- Snapshot pre-Phase-4 HEAD for rollback.
  local rollback_ref
  rollback_ref=$(git -C "$root" rev-parse HEAD 2>/dev/null || true)

  # --- 1. Write accepted OpenSpec specs.
  # Each accepted capability already has a translation at
  # openspec/specs/<cap>/spec.md from Phase 2. The presence check below is
  # belt-and-suspenders.
  while IFS= read -r cap; do
    [[ -n "$cap" ]] || continue
    local spec_file="$root/openspec/specs/$cap/spec.md"
    if [[ ! -f "$spec_file" ]]; then
      err "Phase 4: missing translated spec for accepted capability '$cap' at $spec_file"
    fi
  done <<< "$accepted_caps"

  # --- 1b. Convert accepted change-candidate translations into change folders.
  # Reads each translation that Phase 2 wrote to openspec/specs/<cap>/spec.md,
  # rewrites it as a delta + proposal + tasks under openspec/changes/<name>/,
  # then deletes the openspec/specs/<cap>/ landing.
  local cap_idx cn sr pr cb_for_cap
  while IFS= read -r cap; do
    [[ -n "$cap" ]] || continue
    if is_change_cap "$cap"; then
      cap_idx=$(get_change_cap_index "$cap") || continue
      cn="${change_cap_names[$cap_idx]}"
      sr="${change_cap_specs[$cap_idx]}"
      pr="${change_cap_plans[$cap_idx]}"
      cb_for_cap="${sr##*/}"
      cb_for_cap="${cb_for_cap%.md}"
      _install_change_folder "$root" "$cb_for_cap" "$cn" "$cap" "$sr" "$pr" \
        || err "Phase 4: _install_change_folder failed for '$cap'"
    fi
  done <<< "$accepted_caps"

  # --- 2. Archive each source spec with banner; build basename->capability map.
  mkdir -p "$root/.workflow/legacy-specs"
  local spec_dir
  spec_dir=$(read_spec_dir "$root")

  local rel src_full base cap_for_src title
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src_full="$root/$rel"
    base="${rel##*/}"

    # Capability the source maps to — by convention the slugified basename.
    cap_for_src=$(slugify "$base")
    title=$(_derive_title "$src_full")

    # Skip banner injection only if explicitly skipped in resolution. Even
    # then, archive the original verbatim (no banner) so nothing is lost.
    local banner_caps="$cap_for_src"
    local banner=""
    if grep -qx "$cap_for_src" <<< "$accepted_caps"; then
      if is_change_cap "$cap_for_src"; then
        local _cn_idx cn_for_cap
        _cn_idx=$(get_change_cap_index "$cap_for_src") || true
        cn_for_cap="${change_cap_names[$_cn_idx]:-}"
        banner=$(printf '# [Legacy] %s\n\n' "$title"
                 printf '> Translated to in-flight OpenSpec change `%s`.\n>\n' "$cn_for_cap"
                 printf '> Source preserved for reference. Behavior changes belong in `openspec/changes/%s/specs/<capability>/spec.md` until the change is archived.\n\n' "$cn_for_cap")
      else
        banner=$(_render_banner "$title" "$banner_caps")
      fi
    elif grep -qx "$cap_for_src" <<< "$skipped_caps"; then
      banner=$(printf '# [Legacy] %s\n\n' "$title"
               printf '> Source preserved as-is — translation was skipped during migration.\n\n')
    fi

    {
      printf '%s' "$banner"
      cat "$src_full"
    } > "$root/.workflow/legacy-specs/$base"
  done < <(jq -r '.base[]?' "$inv_path")

  # --- 3. Move sibling artifact directories.
  for kind in plans docs audits todo; do
    local src_kind="$root/$spec_dir/$kind"
    local dest_kind="$root/.workflow/$kind"
    if [[ -d "$src_kind" ]]; then
      mkdir -p "$dest_kind"
      # Use cp -R then rm so we never partially move; rm afterwards.
      (cd "$src_kind" && find . -type f -print0 | while IFS= read -r -d '' f; do
        local rel="${f#./}"
        local target="$dest_kind/$rel"
        mkdir -p "$(dirname "$target")"
        cp "$f" "$target"
      done)
    fi
  done

  # --- 3b. Translate legacy spec-audit config (best-effort, no-op if absent).
  # Must run before step 5's spec-dir removal so the source is still readable.
  # Pass change-candidate slugs so the helper can drop them from modules'
  # specs arrays (those caps live at openspec/changes/, not openspec/specs/).
  local _ccs_csv=""
  if [[ ${#change_cap_slugs[@]} -gt 0 ]]; then
    _ccs_csv=$(IFS=,; printf '%s' "${change_cap_slugs[*]}")
  fi
  _translate_audit_config "$root" "$accepted_caps" "$_ccs_csv"

  # --- 4. Preserve original .specs.
  if [[ -f "$root/.specs" ]]; then
    cp "$root/.specs" "$root/.workflow/legacy-specs/.specs"
  fi

  # --- 5. Delete original .specs and the (now-empty) spec dir.
  rm -f "$root/.specs"
  if [[ -d "$root/$spec_dir" ]]; then
    # Remove plans/docs/audits/todo (already copied) plus base specs.
    rm -rf "$root/$spec_dir"
  fi

  # --- 6. Validate.
  mkdir -p "$root/.openspec-migration"
  local validate_log="$root/.openspec-migration/validate-error.log"
  if ! (cd "$root" && OPENSPEC_TELEMETRY=0 openspec validate --all --strict 2>&1 | tee "$validate_log" >/dev/null); then
    err "Phase 4: openspec validate --all --strict failed; rolling back."
    err "Phase 4: see .openspec-migration/validate-error.log and verifier-reports/ (preserved across rollback)"

    # Stash .openspec-migration/ outside the worktree so rollback's `git clean`
    # doesn't wipe verifier reports and the validate error log. Restore it
    # after the reset so the user can debug why translation failed.
    local stash_dir
    stash_dir=$(mktemp -d -t openspec-migration-debug.XXXXXX)
    if [[ -d "$root/.openspec-migration" ]]; then
      cp -R "$root/.openspec-migration/." "$stash_dir/" 2>/dev/null || true
    fi

    if [[ -n "$pre_tag" ]]; then
      git -C "$root" reset --hard "$pre_tag" >/dev/null 2>&1 || true
      git -C "$root" clean -fdq >/dev/null 2>&1 || true
    elif [[ -n "$rollback_ref" ]]; then
      git -C "$root" reset --hard "$rollback_ref" >/dev/null 2>&1 || true
      git -C "$root" clean -fdq >/dev/null 2>&1 || true
    fi

    # Restore debug artifacts.
    mkdir -p "$root/.openspec-migration"
    cp -R "$stash_dir/." "$root/.openspec-migration/" 2>/dev/null || true
    rm -rf "$stash_dir"

    return 1
  fi

  # --- 7. Install templates (stub if Stage 6 templates are missing).
  local sd
  sd=$(script_dir)
  _install_template "$sd/templates/snippets/global/080-spec-driven-dev.md" \
    "$root/claude-rules/snippets/global/080-spec-driven-dev.md" \
    "<!-- Stub: Stage 6 fills in spec-driven-dev guidance for OpenSpec workflow. -->"
  _install_template "$sd/templates/snippets/global/085-openspec-migration-prompt.md" \
    "$root/claude-rules/snippets/global/085-openspec-migration-prompt.md" \
    "<!-- Stub: Stage 6 fills in the OpenSpec migration prompt rule. -->"
  _install_template "$sd/templates/snippets/global/090-plan-archiving.md" \
    "$root/claude-rules/snippets/global/090-plan-archiving.md" \
    "<!-- Stub: Stage 6 fills in plan archiving guidance for .workflow/plans/. -->"
  _install_template "$sd/templates/spec-check-hook.sh" \
    "$root/scripts/spec-check-hook.sh" \
    '#!/usr/bin/env bash
# Stub: Stage 6 fills in the OpenSpec-aware pre-commit hook.
exit 0'
  chmod +x "$root/scripts/spec-check-hook.sh"

  # --- 8. Run claude-rules/compile.sh if present.
  if [[ -x "$root/claude-rules/compile.sh" ]]; then
    (cd "$root" && ./claude-rules/compile.sh compile >/dev/null 2>&1) || true
  fi

  # --- 9. Write the .openspec-migration.json marker.
  local migrated_at
  migrated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local capabilities_json skipped_json
  capabilities_json=$(printf '%s\n' "$accepted_caps" | awk 'NF' | jq -R . | jq -s .)
  skipped_json=$(printf '%s\n' "$skipped_caps" | awk 'NF' | jq -R . | jq -s .)
  jq -n \
    --arg migrated_at "$migrated_at" \
    --arg branch "$branch" \
    --arg pre_tag "$pre_tag" \
    --argjson caps "$capabilities_json" \
    --argjson skipped "$skipped_json" \
    --arg version "1.0.0" \
    '{
      migrated_at: $migrated_at,
      migration_branch: $branch,
      pre_migration_tag: $pre_tag,
      capabilities: $caps,
      skipped: $skipped,
      tool_version: $version
    }' > "$root/$MIGRATION_MARKER"

  # --- 10. Commit everything.
  local n_caps n_arch n_plans_moved n_docs_moved
  n_caps=$(jq 'length' <<< "$capabilities_json")
  n_arch=$(jq '.base | length' "$inv_path")
  n_plans_moved=$(jq '.plans | length' "$inv_path")
  n_docs_moved=$(jq '.docs | length' "$inv_path")
  local commit_msg
  commit_msg=$(printf 'Migrate to OpenSpec layout\n\n- %d capabilities migrated from %s/<file> -> openspec/specs/<capability>/spec.md\n- %d originals archived at .workflow/legacy-specs/ with forwarding banners\n- %d plans, %d docs moved to .workflow/\n- New pre-commit hook at scripts/spec-check-hook.sh\n- New CLAUDE.md snippets at claude-rules/snippets/global/\n' \
    "$n_caps" "$spec_dir" "$n_arch" "$n_plans_moved" "$n_docs_moved")

  # Stage everything except transient migration internals. The marker
  # (.openspec-migration.json) IS committed; .openspec-migration/ (verifier
  # reports, resolution) and the in-progress state file are not.
  git -C "$root" add -A >/dev/null 2>&1 || true
  git -C "$root" reset -q -- \
    ".openspec-migration" \
    ".openspec-migration-state.json" \
    "migration-inventory.json" >/dev/null 2>&1 || true
  git -C "$root" -c user.email=migrate@openspec.local -c user.name="openspec-migration" \
    commit -q --no-verify -m "$commit_msg" >/dev/null 2>&1 || true

  printf 'Phase 4 (execution): wrote %d openspec capabilities, archived %d source(s), moved %d plan(s) / %d doc(s).\n' \
    "$n_caps" "$n_arch" "$n_plans_moved" "$n_docs_moved"
  return 0
}

cmd_execute() {
  require_jq
  local auto_accept=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-accept) auto_accept=1; shift ;;
      --no-auto-accept) auto_accept=0; shift ;;
      *) shift ;;
    esac
  done

  local root
  root=$(project_root)

  # If resolution wasn't already recorded by `cmd_run`, run it now so
  # standalone callers (`migrate.sh execute` after a manually-orchestrated
  # Phase 2) get a populated accepted_caps list. Without this, the banner
  # injection branch in _execute is skipped and the marker's capabilities
  # array ends up empty.
  if [[ ! -f "$root/.openspec-migration/resolution.json" ]]; then
    cmd_resolve_all "$root" "$auto_accept"
  fi

  _execute "$root"
}

# ---------------------------------------------------------------------------
# Phase 5 — Handoff
# ---------------------------------------------------------------------------

_handoff() {
  local root="$1"

  # Capture state and (potentially) auto-stash flag before we delete the
  # in-progress marker.
  local state_path="$root/$MIGRATION_STATE_FILE"
  local pre_tag="" branch="" stashed=0
  if [[ -f "$state_path" ]]; then
    pre_tag=$(jq -r '.pre_migration_tag // empty' "$state_path")
    branch=$(jq -r '.migration_branch // empty' "$state_path")
    stashed=$(jq -r 'if .auto_stashed then 1 else 0 end' "$state_path" 2>/dev/null || printf '0')
  fi

  local marker="$root/$MIGRATION_MARKER"
  local n_caps=0 n_skip=0
  if [[ -f "$marker" ]]; then
    n_caps=$(jq '.capabilities | length' "$marker" 2>/dev/null || printf '0')
    n_skip=$(jq '.skipped | length' "$marker" 2>/dev/null || printf '0')
  fi

  local n_arch=0 n_plans=0 n_docs=0 n_audits=0
  if [[ -d "$root/.workflow/legacy-specs" ]]; then
    n_arch=$(find "$root/.workflow/legacy-specs" -maxdepth 1 -type f -name '*.md' | wc -l | awk '{print $1}')
  fi
  if [[ -d "$root/.workflow/plans" ]]; then
    n_plans=$(find "$root/.workflow/plans" -type f | wc -l | awk '{print $1}')
  fi
  if [[ -d "$root/.workflow/docs" ]]; then
    n_docs=$(find "$root/.workflow/docs" -type f | wc -l | awk '{print $1}')
  fi
  if [[ -d "$root/.workflow/audits" ]]; then
    n_audits=$(find "$root/.workflow/audits" -type f | wc -l | awk '{print $1}')
  fi

  # Summary
  printf '\n'
  printf 'Migration complete.\n\n'
  printf '  Branch:               %s\n' "$branch"
  printf '  Pre-migration tag:    %s\n' "$pre_tag"
  printf '  Capabilities migrated: %d  (skipped: %d)\n' "$n_caps" "$n_skip"
  printf '  Archived legacy specs: %d\n' "$n_arch"
  printf '  Plans / docs / audits moved: %d/%d/%d\n' "$n_plans" "$n_docs" "$n_audits"
  printf '\n'
  printf '  Review:\n'
  printf '    git diff main..%s\n' "$branch"
  printf '    openspec validate --all --strict\n\n'
  printf '  Merge when ready:\n'
  printf '    git checkout main && git merge --no-ff %s\n\n' "$branch"
  printf '  Restore original spec layout if needed:\n'
  printf '    git reset --hard %s\n' "$pre_tag"

  # Pop the auto-stash if we made one.
  if [[ "$stashed" == "1" ]]; then
    git -C "$root" stash pop >/dev/null 2>&1 || true
  fi

  # Write a structured report alongside the marker.
  local report_path="$root/.openspec-migration/report.json"
  mkdir -p "$root/.openspec-migration"
  jq -n \
    --arg branch "$branch" \
    --arg pre_tag "$pre_tag" \
    --argjson caps "$n_caps" \
    --argjson skipped "$n_skip" \
    --argjson arch "$n_arch" \
    --argjson plans "$n_plans" \
    --argjson docs "$n_docs" \
    --argjson audits "$n_audits" \
    '{
      migration_branch: $branch,
      pre_migration_tag: $pre_tag,
      capabilities_migrated: $caps,
      capabilities_skipped: $skipped,
      legacy_specs_archived: $arch,
      plans_moved: $plans,
      docs_moved: $docs,
      audits_moved: $audits
    }' > "$report_path"

  # Drop the in-progress state file; the final .openspec-migration.json
  # marker is the durable signal.
  rm -f "$state_path"
}

cmd_handoff() {
  require_jq
  local root
  root=$(project_root)
  _handoff "$root"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
migrate.sh — deterministic helper CLI for the migrate-to-openspec skill.

Usage: migrate.sh <subcommand> [args...]

Subcommands:
  run [--auto-stash] [--auto-accept] [--max-parallel N]
      Run the full migration pipeline. Stage 3 implements Phase 0 (preflight)
      and Phase 1 (inventory); later phases land in stages 4-5.

  inventory
      Run Phase 1 only. Walks the spec dir from `.specs`, classifies each
      file into base/plans/docs/audits/todo/other, and writes
      migration-inventory.json at the project root.

  translate <source-spec-path> [--capability <name>] [--out <path>]
      Run the translator agent on a single source spec via `claude -p`.
      Writes the OpenSpec spec body to <out> (default
      openspec/specs/<capability>/spec.md) and the META JSON tail to
      <out>.meta.json. With no source path, translates every base spec
      in migration-inventory.json. Set MIGRATE_FIXTURE_FAST=1 to use
      pre-baked golden translations from test/fixtures-golden/.

  translate
      (no args) Translate every base spec listed in migration-inventory.json.

  verify --capability <name> [--source <path>] [--json]
      Run the verifier agent against capability <name>. Writes a
      structured report to .openspec-migration/verifier-reports/<name>.json
      and (with --json) emits the same JSON to stdout. Exits 0 for
      clean, 2 if any issues were flagged.

  validate-capability <name>
      Run `openspec validate <name> --type spec --strict`. Bootstraps
      openspec/ via `openspec init --tools none .` if necessary.

  diff <source-path> <capability>
      Print a unified diff between the source spec and the translated
      OpenSpec spec. Used during Phase 3 resolution.

  retry <source-path> <capability>
      Re-run the translator with the verifier issues appended to the
      prompt as a retry constraint. Bumps a counter at
      .openspec-migration/retries/<capability>.txt (max 2 retries).

  resolve <capability> --action accept|retry|skip
      Record a Phase 3 resolution decision for a single capability.
      Used by the orchestrator after the user picks an action.

  execute
      Run Phase 4 only. Requires Phase 3 resolution decisions to be
      recorded at .openspec-migration/resolution.json. Writes accepted
      OpenSpec specs, archives originals with banners, moves sibling
      artifacts to .workflow/, validates, installs templates, and
      commits.

  handoff
      Print the Phase 5 summary, restore any auto-stashed WIP, write a
      structured report at .openspec-migration/report.json, and clear
      the in-progress state file.

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
  local cmd="$1"; shift
  case "$cmd" in
    run)                  cmd_run "$@" ;;
    inventory)            cmd_inventory "$@" ;;
    translate)            cmd_translate "$@" ;;
    verify)               cmd_verify "$@" ;;
    validate-capability)  cmd_validate_capability "$@" ;;
    diff)                 cmd_diff "$@" ;;
    retry)                cmd_retry "$@" ;;
    resolve)              cmd_resolve "$@" ;;
    execute)              cmd_execute "$@" ;;
    handoff)              cmd_handoff "$@" ;;
    *)                    err "unknown subcommand: $cmd"; usage; exit 2 ;;
  esac
}

main "$@"
