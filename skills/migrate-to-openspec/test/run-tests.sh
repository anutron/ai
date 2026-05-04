#!/usr/bin/env bash
# run-tests.sh — failing-test harness for the migrate-to-openspec skill.
#
# Implements the Prove-It Pattern: every assertion described in the Stage 2
# done criteria runs against the not-yet-implemented migration tool.
# All tests are expected to FAIL at start. Subsequent stages implement
# `migrate.sh` subcommands and SKILL.md phase logic until each test passes.
#
# Usage:
#   ./run-tests.sh             # run all suites
#   ./run-tests.sh --suite preflight   # run a single suite (preflight|inventory|translator|verifier|execution|idempotence|templates|hook)
#
# Exit code: 0 if all tests pass, 1 otherwise.

set -uo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_SRC="$SCRIPT_DIR/fixture-legacy-project"
MIGRATE_SH="$SKILL_DIR/migrate.sh"

# Working sandbox where each test runs an isolated copy of the fixture.
SANDBOX_ROOT="$(mktemp -d -t migrate-to-openspec-tests.XXXXXX)"
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# Phase 2 fixture-fast mode keeps tests deterministic — translator and
# verifier use pre-baked golden translations + a structural verifier.
# Set MIGRATE_TEST_REAL_CLAUDE=1 to bypass the fast path and exercise
# the real `claude -p` integration. See SKILL.md "Test determinism" note.
if [[ "${MIGRATE_TEST_REAL_CLAUDE:-0}" != "1" ]]; then
  export MIGRATE_FIXTURE_FAST=1
fi

# Optional suite filter
SUITE_FILTER=""
if [[ "${1:-}" == "--suite" ]]; then
  SUITE_FILTER="${2:-}"
fi

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
FAIL_NAMES=()

test_case() {
  local name="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out" | sed 's/^/         /'
    fi
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name")
  fi
}

suite() {
  local label="$1"
  if [[ -n "$SUITE_FILTER" && "$SUITE_FILTER" != "$label" ]]; then
    SKIP_SUITE=1
    return 0
  fi
  SKIP_SUITE=0
  echo ""
  echo "Suite: $label"
}

skip_if_filtered() {
  [[ "${SKIP_SUITE:-0}" == "1" ]]
}

# ---------------------------------------------------------------------------
# Fixture management
# ---------------------------------------------------------------------------

# setup_fixture <name>
#
# Copies fixture-legacy-project to "$SANDBOX_ROOT/<name>", runs `git init`,
# stages everything, makes an initial commit, and echoes the absolute path.
setup_fixture() {
  local name="$1"
  local dest="$SANDBOX_ROOT/$name"
  rm -rf "$dest"
  cp -R "$FIXTURE_SRC" "$dest"
  (
    cd "$dest"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git add -A
    git commit -q -m "initial fixture commit"
  ) >/dev/null
  echo "$dest"
}

# Run the migration entry point inside the given fixture dir.
# Captures stdout and stderr; returns the tool's exit code.
run_migrate() {
  local dir="$1"; shift
  (
    cd "$dir"
    "$MIGRATE_SH" "$@"
  )
}

# ---------------------------------------------------------------------------
# Phase 0 — Preflight failures
# ---------------------------------------------------------------------------

assert_preflight_missing_openspec() {
  local dir
  dir="$(setup_fixture preflight-missing-openspec)"

  # Strip openspec from PATH for this test only. Use a clean PATH that won't
  # find the openspec binary at any standard location.
  local out rc
  out=$(
    cd "$dir"
    PATH="/usr/bin:/bin" "$MIGRATE_SH" run 2>&1
  )
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "expected non-zero exit when openspec CLI is missing, got 0"
    echo "output: $out"
    return 1
  fi
  if ! grep -qiE 'openspec.*(not found|not installed|missing|required)' <<<"$out"; then
    echo "expected error mentioning missing openspec CLI; got:"
    echo "$out"
    return 1
  fi
}

assert_preflight_dirty_tree() {
  local dir
  dir="$(setup_fixture preflight-dirty-tree)"
  # Make the working tree dirty
  echo "dirty content" > "$dir/dirty.txt"

  local out rc
  out=$(run_migrate "$dir" run 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "expected non-zero exit when working tree is dirty; got 0"
    echo "output: $out"
    return 1
  fi
  if ! grep -qiE '(dirty|uncommitted|working tree|--auto-stash)' <<<"$out"; then
    echo "expected error mentioning dirty working tree or --auto-stash; got:"
    echo "$out"
    return 1
  fi
}

assert_preflight_existing_openspec_dir() {
  local dir
  dir="$(setup_fixture preflight-existing-openspec)"
  mkdir -p "$dir/openspec/specs/dummy"
  (cd "$dir" && git add -A && git commit -q -m "add stale openspec dir") >/dev/null

  local out rc
  out=$(run_migrate "$dir" run 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "expected non-zero exit when openspec/ already exists; got 0"
    echo "output: $out"
    return 1
  fi
  if ! grep -qiE '(already migrated|openspec.*exists|openspec/ directory)' <<<"$out"; then
    echo "expected error mentioning existing openspec directory; got:"
    echo "$out"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Phase 1 — Inventory classification
# ---------------------------------------------------------------------------

assert_inventory_classifies_correctly() {
  local dir
  dir="$(setup_fixture inventory-classify)"

  local out rc
  out=$(run_migrate "$dir" inventory 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "inventory subcommand exited non-zero (rc=$rc): $out"
    return 1
  fi

  # The inventory must be written somewhere discoverable. Stage 3
  # writes it to migration-inventory.json at the project root.
  local inv="$dir/migration-inventory.json"
  if [[ ! -f "$inv" ]]; then
    echo "expected migration-inventory.json at $inv; not found"
    return 1
  fi

  # Verify each fixture file ends up in the right bucket. The inventory is
  # JSON; parse it with python3 (available on macOS) for resilience to
  # whitespace/key-order differences.
  python3 - "$inv" <<'PY' || return 1
import json, sys
inv = json.load(open(sys.argv[1]))

def in_bucket(bucket, basename):
    files = inv.get(bucket, [])
    return any(basename in str(f) for f in files)

errors = []
if not in_bucket("base", "feature-a.md"):
    errors.append("feature-a.md should be in 'base'")
if not in_bucket("base", "feature-b-cli.md"):
    errors.append("feature-b-cli.md should be in 'base'")
if not in_bucket("base", "feature-c-mixed.md"):
    errors.append("feature-c-mixed.md should be in 'base'")
if not in_bucket("plans", "some-plan.md"):
    errors.append("some-plan.md should be in 'plans'")
if not in_bucket("docs", "brainstorm.md"):
    errors.append("brainstorm.md should be in 'docs'")
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
PY
}

# ---------------------------------------------------------------------------
# Phase 2 — Translator structural validity
# ---------------------------------------------------------------------------

assert_translator_output_is_valid() {
  local dir
  dir="$(setup_fixture translator-valid)"

  # Drive a full translate phase via the helper. Stage 4 implements
  # `migrate.sh translate` to dispatch agents; for the purposes of this
  # test we expect it to produce openspec/specs/<capability>/spec.md files
  # that pass `openspec validate --strict` per capability.
  local out rc
  out=$(run_migrate "$dir" translate 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "translate subcommand exited non-zero (rc=$rc): $out"
    return 1
  fi

  local fail=0
  for cap in feature-a feature-b-cli feature-c-mixed; do
    local spec_file="$dir/openspec/specs/$cap/spec.md"
    if [[ ! -f "$spec_file" ]]; then
      echo "missing translated spec: $spec_file"
      fail=1
      continue
    fi
    if ! (cd "$dir" && OPENSPEC_TELEMETRY=0 openspec validate "$cap" --type spec --strict >/dev/null 2>&1); then
      echo "openspec validate --strict failed for capability '$cap'"
      fail=1
    fi
  done
  return $fail
}

# ---------------------------------------------------------------------------
# Phase 2 — Verifier flags drift
# ---------------------------------------------------------------------------

assert_verifier_flags_missing_scenario() {
  local dir
  dir="$(setup_fixture verifier-drift)"

  # First run translate so we have a real translation to corrupt.
  local out rc
  out=$(run_migrate "$dir" translate 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "translate subcommand exited non-zero (rc=$rc): $out"
    return 1
  fi

  # Inject drift: delete a Scenario block from the translated feature-b-cli
  # spec so the verifier should complain about a missing test case.
  local target="$dir/openspec/specs/feature-b-cli/spec.md"
  if [[ ! -f "$target" ]]; then
    echo "expected translated file at $target"
    return 1
  fi
  python3 - "$target" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
# Remove the first scenario block (#### Scenario: ... up to next ## or #### header)
new = re.sub(r"#### Scenario:[^\n]*\n(?:(?!\n#### |\n## ).)*", "", text, count=1, flags=re.S)
open(path, "w").write(new)
PY

  # Run the verifier on this single capability and expect status=issues
  # with at least one `missing` issue.
  local report
  report=$(run_migrate "$dir" verify --capability feature-b-cli --json 2>&1)
  rc=$?
  if [[ $rc -ne 0 && $rc -ne 2 ]]; then
    # The verifier may return a non-zero "drift detected" code; only
    # fail the test on real errors.
    echo "verify subcommand exited unexpectedly (rc=$rc): $report"
    return 1
  fi

  # Write the report to a temp file and pass the path to Python (heredoc
  # consumes stdin on `python3 -`, so we can't pipe the JSON in).
  local report_tmp
  report_tmp=$(mktemp)
  printf '%s' "$report" > "$report_tmp"
  python3 - "$report_tmp" <<'PY' || { rm -f "$report_tmp"; return 1; }
import json, sys
raw = open(sys.argv[1]).read()
try:
    data = json.loads(raw)
except Exception as exc:
    print(f"verifier output is not valid JSON: {exc}", file=sys.stderr)
    print(raw, file=sys.stderr)
    sys.exit(1)

status = data.get("status")
issues = data.get("issues", [])
if status != "issues":
    print(f"expected status=issues, got status={status}", file=sys.stderr)
    sys.exit(1)
if not any(i.get("severity") == "missing" for i in issues):
    print("expected at least one issue with severity=missing", file=sys.stderr)
    print(json.dumps(data, indent=2), file=sys.stderr)
    sys.exit(1)
PY
  rm -f "$report_tmp"
}

# ---------------------------------------------------------------------------
# Phase 4 — File moves end up at correct destinations
# ---------------------------------------------------------------------------

assert_full_run_produces_expected_layout() {
  local dir
  dir="$(setup_fixture full-run-layout)"

  local out rc
  out=$(run_migrate "$dir" run --auto-accept 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "full run exited non-zero (rc=$rc): $out"
    return 1
  fi

  local fail=0
  for cap in feature-a feature-b-cli feature-c-mixed; do
    if [[ ! -f "$dir/openspec/specs/$cap/spec.md" ]]; then
      echo "missing $dir/openspec/specs/$cap/spec.md"
      fail=1
    fi
  done

  for archived in feature-a.md feature-b-cli.md feature-c-mixed.md; do
    if [[ ! -f "$dir/.workflow/legacy-specs/$archived" ]]; then
      echo "missing archive at $dir/.workflow/legacy-specs/$archived"
      fail=1
    fi
  done

  if [[ ! -f "$dir/.workflow/legacy-specs/.specs" ]]; then
    echo "expected preserved .specs at $dir/.workflow/legacy-specs/.specs"
    fail=1
  fi
  if [[ ! -f "$dir/.workflow/plans/some-plan.md" ]]; then
    echo "expected $dir/.workflow/plans/some-plan.md"
    fail=1
  fi
  if [[ ! -f "$dir/.workflow/docs/2026-01-01-some-design/brainstorm.md" ]]; then
    echo "expected $dir/.workflow/docs/2026-01-01-some-design/brainstorm.md"
    fail=1
  fi
  if [[ -d "$dir/specs" ]]; then
    echo "expected legacy specs/ directory to be removed after migration"
    fail=1
  fi
  if [[ -f "$dir/.specs" ]]; then
    echo "expected legacy .specs file to be removed (preserved under .workflow/legacy-specs/.specs)"
    fail=1
  fi
  if [[ ! -f "$dir/.openspec-migration.json" ]]; then
    echo "expected $dir/.openspec-migration.json marker"
    fail=1
  fi

  return $fail
}

# ---------------------------------------------------------------------------
# Banner correctness
# ---------------------------------------------------------------------------

assert_banner_present_on_archived_files() {
  local dir
  dir="$(setup_fixture banner-correctness)"

  run_migrate "$dir" run --auto-accept >/dev/null 2>&1 || {
    echo "full run failed; cannot assert banner"
    return 1
  }

  local fail=0
  for archived in feature-a.md feature-b-cli.md feature-c-mixed.md; do
    local file="$dir/.workflow/legacy-specs/$archived"
    if [[ ! -f "$file" ]]; then
      echo "missing $file"
      fail=1
      continue
    fi
    local first5
    first5=$(head -n 5 "$file")
    if ! grep -q "\[Legacy\]" <<<"$first5"; then
      echo "$archived: first 5 lines missing '[Legacy]' marker"
      fail=1
    fi
    if ! grep -q "Migrated to OpenSpec on" <<<"$first5"; then
      echo "$archived: first 5 lines missing 'Migrated to OpenSpec on' line"
      fail=1
    fi
  done
  return $fail
}

# ---------------------------------------------------------------------------
# Idempotence — second invocation exits cleanly with no changes
# ---------------------------------------------------------------------------

assert_idempotent_second_run() {
  local dir
  dir="$(setup_fixture idempotent)"

  # First run — must succeed.
  if ! run_migrate "$dir" run --auto-accept >/dev/null 2>&1; then
    echo "first migration run failed; cannot assert idempotence"
    return 1
  fi

  # Snapshot the working tree.
  local snapshot
  snapshot=$(cd "$dir" && find . -type f -not -path './.git/*' | sort | xargs shasum 2>/dev/null | shasum)

  # Second run — must exit zero with idempotent message and no file changes.
  local out rc
  out=$(run_migrate "$dir" run --auto-accept 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "second run exited non-zero (rc=$rc): $out"
    return 1
  fi
  if ! grep -qiE '(already migrated|nothing to do|idempotent)' <<<"$out"; then
    echo "second run output did not signal idempotency:"
    echo "$out"
    return 1
  fi

  local snapshot_after
  snapshot_after=$(cd "$dir" && find . -type f -not -path './.git/*' | sort | xargs shasum 2>/dev/null | shasum)
  if [[ "$snapshot" != "$snapshot_after" ]]; then
    echo "second run modified files; expected no changes"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Templates installed
# ---------------------------------------------------------------------------

assert_templates_installed() {
  local dir
  dir="$(setup_fixture templates-installed)"

  if ! run_migrate "$dir" run --auto-accept >/dev/null 2>&1; then
    echo "full run failed; cannot assert template installation"
    return 1
  fi

  local fail=0
  for snippet in 080-spec-driven-dev.md 085-openspec-migration-prompt.md 090-plan-archiving.md; do
    local path="$dir/claude-rules/snippets/global/$snippet"
    if [[ ! -f "$path" ]]; then
      echo "missing installed snippet: $path"
      fail=1
    fi
  done
  return $fail
}

# ---------------------------------------------------------------------------
# Pre-commit hook installed
# ---------------------------------------------------------------------------

assert_hook_installed() {
  local dir
  dir="$(setup_fixture hook-installed)"

  if ! run_migrate "$dir" run --auto-accept >/dev/null 2>&1; then
    echo "full run failed; cannot assert hook installation"
    return 1
  fi

  local hook="$dir/scripts/spec-check-hook.sh"
  if [[ ! -f "$hook" ]]; then
    echo "missing pre-commit hook at $hook"
    return 1
  fi
  if [[ ! -x "$hook" ]]; then
    echo "pre-commit hook is not executable: $hook"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Sanity: migrate.sh exists and is executable (runs even if all suites filtered)
# ---------------------------------------------------------------------------

assert_migrate_sh_exists() {
  if [[ ! -f "$MIGRATE_SH" ]]; then
    echo "migrate.sh not found at $MIGRATE_SH"
    return 1
  fi
  if [[ ! -x "$MIGRATE_SH" ]]; then
    echo "migrate.sh is not executable: $MIGRATE_SH"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Run suites
# ---------------------------------------------------------------------------

echo "migrate-to-openspec test harness"
echo "  fixture: $FIXTURE_SRC"
echo "  migrate: $MIGRATE_SH"
echo "  sandbox: $SANDBOX_ROOT"

suite sanity
if ! skip_if_filtered; then
  test_case "migrate.sh exists and is executable" assert_migrate_sh_exists
fi

suite preflight
if ! skip_if_filtered; then
  test_case "Phase 0 fails when openspec CLI is missing" assert_preflight_missing_openspec
  test_case "Phase 0 fails when working tree is dirty" assert_preflight_dirty_tree
  test_case "Phase 0 fails when openspec/ already exists" assert_preflight_existing_openspec_dir
fi

suite inventory
if ! skip_if_filtered; then
  test_case "Phase 1 inventory classifies fixture files into base/plans/docs" assert_inventory_classifies_correctly
fi

suite translator
if ! skip_if_filtered; then
  test_case "Phase 2 translator output passes openspec validate --strict per capability" assert_translator_output_is_valid
fi

suite verifier
if ! skip_if_filtered; then
  test_case "Phase 2 verifier flags missing scenario as severity=missing" assert_verifier_flags_missing_scenario
fi

suite execution
if ! skip_if_filtered; then
  test_case "Phase 4 produces expected file layout (openspec/, .workflow/, marker)" assert_full_run_produces_expected_layout
  test_case "Phase 4 archives every source spec with [Legacy] banner" assert_banner_present_on_archived_files
fi

suite idempotence
if ! skip_if_filtered; then
  test_case "Second invocation exits cleanly without modifying files" assert_idempotent_second_run
fi

suite templates
if ! skip_if_filtered; then
  test_case "Phase 4 installs CLAUDE.md snippets at claude-rules/snippets/global/" assert_templates_installed
fi

suite hook
if ! skip_if_filtered; then
  test_case "Phase 4 installs scripts/spec-check-hook.sh as executable" assert_hook_installed
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  echo "Failed cases:"
  for n in "${FAIL_NAMES[@]}"; do
    echo "  - $n"
  done
  exit 1
fi
exit 0
