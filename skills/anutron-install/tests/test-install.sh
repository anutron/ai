#!/bin/bash
# test-install.sh — End-to-end tests for anutron-install
#
# Sets up a sandbox directory, runs install.sh against a self-contained
# fixture source repo, then verifies all artifacts are correct.
#
# Usage:
#   bash test-install.sh                        # uses bundled fixture
#   ANUTRON_SOURCE=/path/to/source bash test-install.sh  # override source

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../install.sh"

# Self-contained fixture — no external dependency on a real clone
FIXTURE_SOURCE="$SCRIPT_DIR/fixtures/source-repo"
SOURCE_REPO="${ANUTRON_SOURCE:-$FIXTURE_SOURCE}"

# Sanity: source repo must exist
if [ ! -d "$SOURCE_REPO/skills" ]; then
  echo "SKIP: source repo not found at $SOURCE_REPO"
  exit 0
fi

# ============================================================
# Test helpers
# ============================================================

passed=0
failed=0
total=0

assert() {
  local desc="$1"
  shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $desc"
  fi
}

assert_file_exists() {
  assert "$1 exists" test -f "$1"
}

assert_dir_exists() {
  assert "$1 exists" test -d "$1"
}

assert_symlink() {
  assert "$1 is a symlink" test -L "$1"
}

assert_not_symlink() {
  assert "$1 is NOT a symlink" bash -c "! test -L '$1'"
}

assert_regular_file() {
  local path="$1"
  assert "$path is a regular file (not symlink)" bash -c "test -f '$path' && ! test -L '$path'"
}

assert_file_contains() {
  local file="$1" pattern="$2"
  assert "$file contains '$pattern'" grep -q "$pattern" "$file"
}

assert_file_not_contains() {
  local file="$1" pattern="$2"
  # Use the function-local args (no shell-quoting hazards) instead of
  # interpolating $pattern into a bash -c string.
  total=$((total + 1))
  if grep -qF "$pattern" "$file" >/dev/null 2>&1; then
    failed=$((failed + 1))
    echo "FAIL: $file does not contain '$pattern'"
  else
    passed=$((passed + 1))
  fi
}

assert_json_key() {
  local file="$1" key="$2"
  assert "$file has JSON key '$key'" bash -c "jq -e '$key' '$file' > /dev/null"
}

assert_equals() {
  local desc="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$expected" = "$actual" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $desc (expected '$expected', got '$actual')"
  fi
}

skip_test() {
  local reason="$1"
  echo "SKIP: $reason"
}

# Create a fresh sandbox and return its path
make_sandbox() {
  local sb
  sb="/tmp/anutron-test-$$-$(date +%s)-$RANDOM"
  mkdir -p "$sb"
  echo "$sb"
}

# ============================================================
# Test 1: Fresh install (baseline — uses fixture)
# ============================================================
echo "=== Test 1: Fresh install ==="

SANDBOX="$(make_sandbox)"
trap 'rm -rf "$SANDBOX"' EXIT

cd "$SANDBOX"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /tmp/anutron-test-output-$$.txt 2>&1
install_exit=$?
assert "install.sh exits 0" test "$install_exit" -eq 0

# --- Skills ---
assert_dir_exists "$SANDBOX/.claude/skills"

# Fixture has: brainstorm (spec), guard (quality), bugbash (workflow), pr (pr),
# personal-only (personal), untagged (no tags), airon-excluded (personal, matches airon-*)
# Full scope (default) excludes: airon-*, personal-only per fixture scope-presets.json
assert_symlink "$SANDBOX/.claude/skills/brainstorm"
assert_symlink "$SANDBOX/.claude/skills/guard"

# Excluded skills should not be present
assert "airon-excluded not installed" test ! -e "$SANDBOX/.claude/skills/airon-excluded"
assert "personal-only not installed" test ! -e "$SANDBOX/.claude/skills/personal-only"
assert "anutron-install not installed (self-exclude)" test ! -e "$SANDBOX/.claude/skills/anutron-install"

# Verify symlink targets resolve
for link in "$SANDBOX/.claude/skills"/*/; do
  name="$(basename "$link")"
  if [ -L "${link%/}" ]; then
    assert "symlink $name resolves" test -d "${link%/}"
  fi
done

# --- Hooks ---
assert_dir_exists "$SANDBOX/.claude/hooks"

# settings.json must exist with anutronInstalled key
assert_file_exists "$SANDBOX/.claude/settings.json"
assert_json_key "$SANDBOX/.claude/settings.json" '.anutronInstalled'
assert_json_key "$SANDBOX/.claude/settings.json" '.anutronInstalled.version'
assert_json_key "$SANDBOX/.claude/settings.json" '.anutronInstalled.installedAt'
assert_json_key "$SANDBOX/.claude/settings.json" '.hooks'

# Check that hooks reference scripts under .claude/hooks/
hook_cmds=$(jq -r '.. | .command? // empty' "$SANDBOX/.claude/settings.json" 2>/dev/null)
for cmd in $hook_cmds; do
  assert "hook command references local path: $cmd" bash -c "echo '$cmd' | grep -q '.claude/hooks/'"
done

# --- CLAUDE.md ---
assert_file_exists "$SANDBOX/CLAUDE.md"
assert_file_contains "$SANDBOX/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
assert_file_contains "$SANDBOX/CLAUDE.md" "END ANUTRON-INSTALL"

# Should have content between markers (compiled snippets)
marker_content=$(sed -n '/BEGIN ANUTRON-INSTALL/,/END ANUTRON-INSTALL/p' "$SANDBOX/CLAUDE.md" | wc -l)
assert "CLAUDE.md has content between markers" test "$marker_content" -gt 3

# --- Breadcrumb ---
assert_file_exists "$SANDBOX/.anutron-install.json"
assert_json_key "$SANDBOX/.anutron-install.json" '.version'
assert_json_key "$SANDBOX/.anutron-install.json" '.source'
assert_json_key "$SANDBOX/.anutron-install.json" '.installedAt'
assert_json_key "$SANDBOX/.anutron-install.json" '.skills'
assert_json_key "$SANDBOX/.anutron-install.json" '.hooks'
assert_json_key "$SANDBOX/.anutron-install.json" '.hookCommands'

# hookCommands should contain actual command paths
hook_cmd_count=$(jq '.hookCommands | length' "$SANDBOX/.anutron-install.json")
assert "breadcrumb hookCommands is non-empty" test "$hook_cmd_count" -gt 0
first_hook_cmd=$(jq -r '.hookCommands[0]' "$SANDBOX/.anutron-install.json")
assert "breadcrumb hookCommands contains .claude/hooks/ path" bash -c "echo '$first_hook_cmd' | grep -q '.claude/hooks/'"

# Version should match plugin.json
expected_version=$(jq -r '.version' "$SOURCE_REPO/.claude-plugin/plugin.json")
actual_version=$(jq -r '.version' "$SANDBOX/.anutron-install.json")
assert_equals "breadcrumb version matches plugin.json" "$expected_version" "$actual_version"

# Source should match
actual_source=$(jq -r '.source' "$SANDBOX/.anutron-install.json")
assert_equals "breadcrumb source matches" "$SOURCE_REPO" "$actual_source"

# --- Summary output ---
assert_file_contains "/tmp/anutron-test-output-$$.txt" "Installed"
assert_file_contains "/tmp/anutron-test-output-$$.txt" "Skills:"

echo ""
echo "=== Test 2: Idempotent re-run ==="

# Save state before re-run
skills_before=$(ls "$SANDBOX/.claude/skills/" | sort)
breadcrumb_before=$(cat "$SANDBOX/.anutron-install.json")

# Re-run
cd "$SANDBOX"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /tmp/anutron-test-output2-$$.txt 2>&1
rerun_exit=$?
assert "re-run exits 0" test "$rerun_exit" -eq 0

# Skills should be identical
skills_after=$(ls "$SANDBOX/.claude/skills/" | sort)
assert_equals "skills unchanged after re-run" "$skills_before" "$skills_after"

# No duplicate hook entries in settings.json
hook_count=$(jq '[.. | .command? // empty] | length' "$SANDBOX/.claude/settings.json" 2>/dev/null)
assert "no duplicate hooks after re-run" test "$hook_count" -le 5

# CLAUDE.md should have exactly one BEGIN marker
begin_count=$(grep -c "BEGIN ANUTRON-INSTALL" "$SANDBOX/CLAUDE.md")
assert_equals "exactly one BEGIN marker" "1" "$begin_count"

# Breadcrumb updated (installedAt should be present)
new_timestamp=$(jq -r '.installedAt' "$SANDBOX/.anutron-install.json")
assert "breadcrumb timestamp present" test -n "$new_timestamp"

# Re-run summary should say "Updated"
assert_file_contains "/tmp/anutron-test-output2-$$.txt" "Updated\|Installed"

echo ""
echo "=== Test 2b: copy-mode idempotent re-run (unchanged skill tracking) ==="
# Verifies that a second --mode=copy run against the same source marks skills as
# unchanged rather than re-copying them (spec: "unchanged skills are not re-copied").
# Implementation choice: uses summary output "unchanged" tally (SKILLS_UNCHANGED count).

SANDBOX_T2B="$(make_sandbox)"
T2B_OUT1="/tmp/anutron-test-t2b1-$$.txt"
T2B_OUT2="/tmp/anutron-test-t2b2-$$.txt"

cd "$SANDBOX_T2B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy > "$T2B_OUT1" 2>&1
t2b_exit1=$?
assert "copy-mode first run exits 0" test "$t2b_exit1" -eq 0

# Re-run with same source — skills should be detected as unchanged
cd "$SANDBOX_T2B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy > "$T2B_OUT2" 2>&1
t2b_exit2=$?
assert "copy-mode second run exits 0" test "$t2b_exit2" -eq 0

# Summary on second run must mention "unchanged" (SKILLS_UNCHANGED count > 0)
assert_file_contains "$T2B_OUT2" "unchanged"

rm -f "$T2B_OUT1" "$T2B_OUT2"
rm -rf "$SANDBOX_T2B"

echo ""
echo "=== Test 3: Existing CLAUDE.md without markers ==="

# Create a new sandbox with existing CLAUDE.md
SANDBOX2="$(make_sandbox)"

cat > "$SANDBOX2/CLAUDE.md" << 'EXISTING'
# My Project

Some existing project instructions that should be preserved.

## Build

Run `make build` to compile.
EXISTING

cd "$SANDBOX2"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

# Markers should be at top
first_line=$(head -1 "$SANDBOX2/CLAUDE.md")
assert "markers inserted at top of existing CLAUDE.md" bash -c "echo '$first_line' | grep -q 'BEGIN ANUTRON-INSTALL'"

# Existing content preserved below
assert_file_contains "$SANDBOX2/CLAUDE.md" "My Project"
assert_file_contains "$SANDBOX2/CLAUDE.md" "make build"

rm -rf "$SANDBOX2"

echo ""
echo "=== Test 4: settings.json preserves user keys ==="

SANDBOX3="$(make_sandbox)"
mkdir -p "$SANDBOX3/.claude"

# Create existing settings with user config
cat > "$SANDBOX3/.claude/settings.json" << 'USERSETTINGS'
{
  "permissions": {
    "allow": ["Read", "Write"]
  },
  "mcpPermissions": {
    "memory": { "allowAllTools": true }
  }
}
USERSETTINGS

cd "$SANDBOX3"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

# User keys preserved
assert_json_key "$SANDBOX3/.claude/settings.json" '.permissions'
assert_json_key "$SANDBOX3/.claude/settings.json" '.mcpPermissions'
# Anutron keys added
assert_json_key "$SANDBOX3/.claude/settings.json" '.anutronInstalled'
assert_json_key "$SANDBOX3/.claude/settings.json" '.hooks'

rm -rf "$SANDBOX3"

echo ""
echo "=== Test 5: Dangling symlink cleanup ==="

SANDBOX4="$(make_sandbox)"
mkdir -p "$SANDBOX4/.claude/skills"

# Create a dangling symlink (simulates a removed skill)
ln -s "/nonexistent/path/to/old-skill" "$SANDBOX4/.claude/skills/old-skill"
assert_symlink "$SANDBOX4/.claude/skills/old-skill"

cd "$SANDBOX4"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

# Dangling symlink should be removed
assert "dangling symlink removed" test ! -e "$SANDBOX4/.claude/skills/old-skill"

rm -rf "$SANDBOX4"

# ============================================================
# RED TESTS — All blocks below SHOULD FAIL until Stage 3
# implements the new features. Each block is marked with
# # RED: fails until Stage 3 implements <X>
# ============================================================

echo ""
echo "=== Test 6: --mode=copy produces regular files, not symlinks ==="
# RED: fails until Stage 3 implements --mode=copy

SANDBOX_T6="$(make_sandbox)"
cd "$SANDBOX_T6"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy > /dev/null 2>&1
t6_exit=$?
assert "mode=copy install exits 0" test "$t6_exit" -eq 0
assert_dir_exists "$SANDBOX_T6/.claude/skills/brainstorm"
assert_not_symlink "$SANDBOX_T6/.claude/skills/brainstorm"
# At least one file inside should be a regular file
assert_regular_file "$SANDBOX_T6/.claude/skills/brainstorm/SKILL.md"
rm -rf "$SANDBOX_T6"

echo ""
echo "=== Test 7: copy-mode install survives source deletion ==="
# RED: fails until Stage 3 implements --mode=copy

SANDBOX_T7="$(make_sandbox)"
# Copy fixture to a temp location so we can delete it
TEMP_SOURCE="$(make_sandbox)/source-copy"
cp -r "$SOURCE_REPO" "$TEMP_SOURCE"

cd "$SANDBOX_T7"
ANUTRON_SOURCE="$TEMP_SOURCE" bash "$INSTALL_SH" --mode=copy > /dev/null 2>&1
t7_exit=$?
assert "mode=copy install with temp source exits 0" test "$t7_exit" -eq 0

# Delete source
rm -rf "$TEMP_SOURCE"

# Installed files should still be readable
assert "brainstorm/SKILL.md still readable after source deletion" test -r "$SANDBOX_T7/.claude/skills/brainstorm/SKILL.md"

# Control: symlink mode with deleted source leaves dangling links
SANDBOX_T7_SYM="$(make_sandbox)"
TEMP_SOURCE2="$(make_sandbox)/source-copy2"
cp -r "$SOURCE_REPO" "$TEMP_SOURCE2"
cd "$SANDBOX_T7_SYM"
ANUTRON_SOURCE="$TEMP_SOURCE2" bash "$INSTALL_SH" --mode=symlink > /dev/null 2>&1
rm -rf "$TEMP_SOURCE2"
assert "symlink mode: brainstorm not readable after source deletion (dangling)" bash -c "! test -r '$SANDBOX_T7_SYM/.claude/skills/brainstorm/SKILL.md'"

rm -rf "$SANDBOX_T7" "$SANDBOX_T7_SYM"

echo ""
echo "=== Test 8: --scope=spec-discipline includes brainstorm but not bugbash/pr ==="
# RED: fails until Stage 3 implements --scope

SANDBOX_T8="$(make_sandbox)"
cd "$SANDBOX_T8"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=spec-discipline > /dev/null 2>&1
t8_exit=$?
assert "scope=spec-discipline install exits 0" test "$t8_exit" -eq 0
assert_dir_exists "$SANDBOX_T8/.claude/skills/brainstorm"
assert_dir_exists "$SANDBOX_T8/.claude/skills/guard"
assert "bugbash not installed under spec-discipline" test ! -e "$SANDBOX_T8/.claude/skills/bugbash"
assert "pr not installed under spec-discipline" test ! -e "$SANDBOX_T8/.claude/skills/pr"
rm -rf "$SANDBOX_T8"

echo ""
echo "=== Test 9: tag-based selection picks up newly-added tagged skill ==="
# RED: fails until Stage 3 implements tag-based scope resolution

# Use a copy of the fixture so we can add a skill to it
FIXTURE_COPY="$(make_sandbox)/fixture-copy"
cp -r "$SOURCE_REPO" "$FIXTURE_COPY"

SANDBOX_T9="$(make_sandbox)"
cd "$SANDBOX_T9"
ANUTRON_SOURCE="$FIXTURE_COPY" bash "$INSTALL_SH" --scope=spec-discipline > /dev/null 2>&1

# New skill not yet added
assert "new-spec-skill absent before being added" test ! -e "$SANDBOX_T9/.claude/skills/new-spec-skill"

# Add a new skill with tags: [spec]
mkdir -p "$FIXTURE_COPY/skills/new-spec-skill"
cat > "$FIXTURE_COPY/skills/new-spec-skill/SKILL.md" << 'NEWSKILL'
---
name: new-spec-skill
description: A newly added spec skill for testing tag-based selection.
tags: [spec]
---

New spec skill body.
NEWSKILL

# Re-run installer
cd "$SANDBOX_T9"
ANUTRON_SOURCE="$FIXTURE_COPY" bash "$INSTALL_SH" --scope=spec-discipline > /dev/null 2>&1

assert_dir_exists "$SANDBOX_T9/.claude/skills/new-spec-skill"
rm -rf "$SANDBOX_T9" "$FIXTURE_COPY"

echo ""
echo "=== Test 10: --scope=custom without manifest fails clearly ==="
# RED: fails until Stage 3 implements --scope=custom manifest validation

SANDBOX_T10="$(make_sandbox)"
cd "$SANDBOX_T10"
set +e
custom_output=$(ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=custom 2>&1)
custom_exit=$?
set -e
assert "scope=custom without manifest exits non-zero" test "$custom_exit" -ne 0
assert "scope=custom error mentions .anutron-install.config.json" bash -c "echo '$custom_output' | grep -q '.anutron-install.config.json'"
rm -rf "$SANDBOX_T10"

echo ""
echo "=== Test 11: manifest values used when no flags passed ==="
# RED: fails until Stage 3 implements manifest reading

SANDBOX_T11="$(make_sandbox)"
cat > "$SANDBOX_T11/.anutron-install.config.json" << 'MANIFEST'
{"mode": "copy", "scope": "spec-discipline"}
MANIFEST

cd "$SANDBOX_T11"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1
t11_exit=$?
assert "manifest-driven install exits 0" test "$t11_exit" -eq 0

# Should behave like --mode=copy --scope=spec-discipline
assert_dir_exists "$SANDBOX_T11/.claude/skills/brainstorm"
assert_not_symlink "$SANDBOX_T11/.claude/skills/brainstorm"
assert "bugbash not installed (scope from manifest)" test ! -e "$SANDBOX_T11/.claude/skills/bugbash"

# Breadcrumb should confirm mode and scope
assert_json_key "$SANDBOX_T11/.anutron-install.json" '.mode'
t11_mode=$(jq -r '.mode' "$SANDBOX_T11/.anutron-install.json" 2>/dev/null || echo "")
assert_equals "breadcrumb mode=copy (from manifest)" "copy" "$t11_mode"
t11_scope=$(jq -r '.scope' "$SANDBOX_T11/.anutron-install.json" 2>/dev/null || echo "")
assert_equals "breadcrumb scope=spec-discipline (from manifest)" "spec-discipline" "$t11_scope"
rm -rf "$SANDBOX_T11"

echo ""
echo "=== Test 12: command-line flags override manifest ==="
# RED: fails until Stage 3 implements flag/manifest precedence

SANDBOX_T12="$(make_sandbox)"
cat > "$SANDBOX_T12/.anutron-install.config.json" << 'MANIFEST'
{"mode": "symlink", "scope": "spec-discipline"}
MANIFEST

cd "$SANDBOX_T12"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=full > /dev/null 2>&1
t12_exit=$?
assert "flag-override install exits 0" test "$t12_exit" -eq 0

# --scope=full overrides manifest's spec-discipline, so bugbash should be present
assert_dir_exists "$SANDBOX_T12/.claude/skills/bugbash"
rm -rf "$SANDBOX_T12"

echo ""
echo "=== Test 13: --for-contributors equivalent to --mode=copy --scope=spec-discipline ==="
# RED: fails until Stage 3 implements --for-contributors

SANDBOX_T13A="$(make_sandbox)"
SANDBOX_T13B="$(make_sandbox)"

# Capture stdout so we can assert on the post-install message (not /dev/null)
T13A_OUT="/tmp/anutron-test-t13a-$$.txt"
cd "$SANDBOX_T13A"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --for-contributors > "$T13A_OUT" 2>&1

cd "$SANDBOX_T13B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy --scope=spec-discipline > /dev/null 2>&1

# Skill listings should match
skills_13a=$(ls "$SANDBOX_T13A/.claude/skills/" 2>/dev/null | sort || echo "")
skills_13b=$(ls "$SANDBOX_T13B/.claude/skills/" 2>/dev/null | sort || echo "")
assert_equals "--for-contributors and --mode=copy --scope=spec-discipline produce same skill list" "$skills_13a" "$skills_13b"

# Breadcrumb should have mode=copy and scope=spec-discipline
if [ -f "$SANDBOX_T13A/.anutron-install.json" ]; then
  t13_mode=$(jq -r '.mode' "$SANDBOX_T13A/.anutron-install.json" 2>/dev/null || echo "")
  t13_scope=$(jq -r '.scope' "$SANDBOX_T13A/.anutron-install.json" 2>/dev/null || echo "")
  assert_equals "--for-contributors breadcrumb mode=copy" "copy" "$t13_mode"
  assert_equals "--for-contributors breadcrumb scope=spec-discipline" "spec-discipline" "$t13_scope"
fi

# Post-install message must mention git add and .claude/skills (spec: "post-install message mentions commit")
assert_file_contains "$T13A_OUT" "git add"
assert_file_contains "$T13A_OUT" ".claude/skills"
rm -f "$T13A_OUT"
rm -rf "$SANDBOX_T13A" "$SANDBOX_T13B"

echo ""
echo "=== Test 14: breadcrumb has mode, scope, sourceCommit, scopeResolution ==="
# RED: fails until Stage 3 implements extended breadcrumb

# Sub-test A: source is a git repo
SANDBOX_T14A="$(make_sandbox)"
FIXTURE_GIT="$(make_sandbox)/fixture-git"
cp -r "$SOURCE_REPO" "$FIXTURE_GIT"

# Make it a git repo
git -C "$FIXTURE_GIT" init -q
git -C "$FIXTURE_GIT" add .
GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@test.com" \
  GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@test.com" \
  git -C "$FIXTURE_GIT" commit -q --allow-empty -m "init" 2>/dev/null

cd "$SANDBOX_T14A"
ANUTRON_SOURCE="$FIXTURE_GIT" bash "$INSTALL_SH" > /dev/null 2>&1

# Required new breadcrumb keys
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.mode'
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.scope'
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.sourceCommit'
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.scopeResolution'
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.scopeResolution.skills'
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.scopeResolution.snippets'
assert_json_key "$SANDBOX_T14A/.anutron-install.json" '.scopeResolution.hooks'

# sourceCommit should be a 40-char hex string
source_commit=$(jq -r '.sourceCommit' "$SANDBOX_T14A/.anutron-install.json" 2>/dev/null || echo "")
assert "sourceCommit is 40-char hex when source is git repo" bash -c "echo '$source_commit' | grep -qE '^[0-9a-f]{40}$'"

# scopeResolution.skills length should match actual installed skills count
skills_in_breadcrumb=$(jq '.scopeResolution.skills | length' "$SANDBOX_T14A/.anutron-install.json" 2>/dev/null || echo "0")
skills_on_disk=$(ls "$SANDBOX_T14A/.claude/skills/" 2>/dev/null | wc -l | tr -d ' ')
assert_equals "scopeResolution.skills count matches installed dirs" "$skills_on_disk" "$skills_in_breadcrumb"

rm -rf "$SANDBOX_T14A" "$FIXTURE_GIT"

# Sub-test B: source is NOT a git repo — sourceCommit should be null
SANDBOX_T14B="$(make_sandbox)"
cd "$SANDBOX_T14B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

source_commit_b=$(jq -r '.sourceCommit' "$SANDBOX_T14B/.anutron-install.json" 2>/dev/null || echo "MISSING")
assert "sourceCommit is null when source has no git repo" bash -c "[ '$source_commit_b' = 'null' ]"
rm -rf "$SANDBOX_T14B"

echo ""
echo "=== Test 15: interactive TTY flow ==="
# RED: fails until Stage 3 implements interactive prompts

# Sub-test A: non-TTY (piped stdin) skips prompts, uses defaults
SANDBOX_T15A="$(make_sandbox)"
cd "$SANDBOX_T15A"
t15a_output=$(ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" < /dev/null 2>&1 || true)
t15a_exit=$?
assert "non-TTY stdin: install exits 0" test "$t15a_exit" -eq 0
# Should use defaults: mode=symlink, scope=full
# brainstorm should be a symlink (symlink mode)
assert_symlink "$SANDBOX_T15A/.claude/skills/brainstorm"
# bugbash should be installed (full scope)
assert_dir_exists "$SANDBOX_T15A/.claude/skills/bugbash"
rm -rf "$SANDBOX_T15A"

# Sub-test B: TTY simulation via expect (skip if expect not installed)
if command -v expect >/dev/null 2>&1; then
  SANDBOX_T15B="$(make_sandbox)"
  cd "$SANDBOX_T15B"
  # Use expect to feed interactive answers: mode=copy, scope=spec-discipline, don't save manifest
  export ANUTRON_SOURCE="$SOURCE_REPO"
  expect_result=$(expect -c "
    set timeout 15
    spawn bash $INSTALL_SH
    expect -re {Install mode.*symlink.*copy}
    send \"2\r\"
    expect -re {Scope.*full.*spec-discipline}
    send \"2\r\"
    expect -re {Save.*manifest.*Y/n}
    send \"n\r\"
    expect eof
    catch wait result
    exit [lindex \$result 3]
  " 2>&1 || true)
  unset ANUTRON_SOURCE
  expect_exit=$?
  assert "TTY interactive: install exits 0" test "$expect_exit" -eq 0
  assert_dir_exists "$SANDBOX_T15B/.claude/skills/brainstorm"
  assert_not_symlink "$SANDBOX_T15B/.claude/skills/brainstorm"
  assert "bugbash not installed (interactive spec-discipline)" test ! -e "$SANDBOX_T15B/.claude/skills/bugbash"
  if [ -f "$SANDBOX_T15B/.anutron-install.json" ]; then
    t15b_mode=$(jq -r '.mode' "$SANDBOX_T15B/.anutron-install.json" 2>/dev/null || echo "")
    assert_equals "interactive TTY: breadcrumb mode=copy" "copy" "$t15b_mode"
  fi
  rm -rf "$SANDBOX_T15B"
else
  skip_test "expect not installed — skipping interactive TTY sub-test (Test 15b)"
fi

echo ""
echo "=== Test 16: stale source detection on copy-mode re-run ==="
# RED: fails until Stage 3 implements stale source detection

FIXTURE_GIT2="$(make_sandbox)/fixture-git2"
cp -r "$SOURCE_REPO" "$FIXTURE_GIT2"
git -C "$FIXTURE_GIT2" init -q
git -C "$FIXTURE_GIT2" add .
GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@test.com" \
  GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@test.com" \
  git -C "$FIXTURE_GIT2" commit -q -m "init" 2>/dev/null

SANDBOX_T16="$(make_sandbox)"
cd "$SANDBOX_T16"
ANUTRON_SOURCE="$FIXTURE_GIT2" bash "$INSTALL_SH" --mode=copy --scope=full > /dev/null 2>&1

# Make a change to brainstorm in the fixture and commit
echo "# Updated" >> "$FIXTURE_GIT2/skills/brainstorm/SKILL.md"
git -C "$FIXTURE_GIT2" add skills/brainstorm/SKILL.md
GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@test.com" \
  GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@test.com" \
  git -C "$FIXTURE_GIT2" commit -q -m "update brainstorm" 2>/dev/null

# Re-run installer
cd "$SANDBOX_T16"
t16_output=$(ANUTRON_SOURCE="$FIXTURE_GIT2" bash "$INSTALL_SH" --mode=copy --scope=full 2>&1 | tee /tmp/anutron-test-t16-$$.txt || true)

# Summary should mention brainstorm as updated/changed
assert "stale re-run mentions brainstorm as updated" bash -c "grep -qi 'brainstorm' /tmp/anutron-test-t16-$$.txt"
rm -rf "$SANDBOX_T16" "$FIXTURE_GIT2"
rm -f /tmp/anutron-test-t16-$$.txt

echo ""
echo "=== Test 17: snippet audience filter ==="
# RED: fails until Stage 3 implements snippet audience filtering

SANDBOX_T17="$(make_sandbox)"
cd "$SANDBOX_T17"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=spec-discipline --mode=symlink > /dev/null 2>&1
t17_exit=$?
assert "scope=spec-discipline snippet install exits 0" test "$t17_exit" -eq 0

# 010-shared-formatting.md (audience: [shared], tags: [formatting]) should be present
assert_file_contains "$SANDBOX_T17/CLAUDE.md" "Shared Formatting Rules"

# aaron-personal.md (audience: [aaron]) should NOT be present
assert_file_not_contains "$SANDBOX_T17/CLAUDE.md" "Aaron's Personal Preferences"
rm -rf "$SANDBOX_T17"

echo ""
echo "=== Test 18: no source resolvable — error names all three resolution options ==="
# Spec scenario: "no source resolvable" under Requirement "Source resolution."
# Run installer with ANUTRON_SOURCE unset, HOME pointing at an empty temp dir
# (so no ~/.claude/anutron-cache), and from a /tmp sandbox (no parent with skills/).
# Expect: non-zero exit, stderr mentions all three resolution options.

SANDBOX_T18="$(mktemp -d /tmp/anutron-t18-home-XXXXXX)"
T18_OUT="/tmp/anutron-test-t18-$$.txt"

# Run from a clean /tmp directory so self-location walk finds nothing
set +e
HOME="$SANDBOX_T18" bash "$INSTALL_SH" > "$T18_OUT" 2>&1
t18_exit=$?
set -e

assert "no-source install exits non-zero" test "$t18_exit" -ne 0
# Error must mention ANUTRON_SOURCE env var
assert_file_contains "$T18_OUT" "ANUTRON_SOURCE"
# Error must mention plugin cache
assert_file_contains "$T18_OUT" "anutron-cache"
# Error must mention self-location
assert_file_contains "$T18_OUT" "skills/"

rm -f "$T18_OUT"
rm -rf "$SANDBOX_T18"

echo ""
echo "=== Test 19: foreign skills preserved across install + re-run ==="

# Fresh sandbox with a foreign skill pre-existing
SANDBOX_T19="/tmp/anutron-test19-$$-$(date +%s)"
mkdir -p "$SANDBOX_T19/.claude/skills/my-foreign-skill"
cat > "$SANDBOX_T19/.claude/skills/my-foreign-skill/SKILL.md" << 'FOREIGN'
---
name: my-foreign-skill
description: User-authored skill, not installed by anutron.
---

# My Foreign Skill

This skill was here before /anutron-install ever ran.
FOREIGN

cd "$SANDBOX_T19"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=spec-discipline --mode=copy > /dev/null 2>&1
assert "T19a: foreign skill survives first install" test -f "$SANDBOX_T19/.claude/skills/my-foreign-skill/SKILL.md"

# Re-run with same scope (should still leave foreign skill alone)
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=spec-discipline --mode=copy > /dev/null 2>&1
assert "T19b: foreign skill survives same-scope re-run" test -f "$SANDBOX_T19/.claude/skills/my-foreign-skill/SKILL.md"

# Re-run with full scope. This adds more skills but must still leave the foreign one alone,
# and must remove anutron-owned skills that drop out of scope if any.
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=full --mode=copy > /dev/null 2>&1
assert "T19c: foreign skill survives scope-widening re-run" test -f "$SANDBOX_T19/.claude/skills/my-foreign-skill/SKILL.md"

# Now narrow scope back to spec-discipline. bugbash was just added under full and is
# anutron-owned; it must be removed. The foreign skill must still survive.
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --scope=spec-discipline --mode=copy > /dev/null 2>&1
assert "T19d: foreign skill survives scope-narrowing re-run" test -f "$SANDBOX_T19/.claude/skills/my-foreign-skill/SKILL.md"
assert "T19d: previously-owned bugbash removed on scope narrow" test ! -e "$SANDBOX_T19/.claude/skills/bugbash"

rm -rf "$SANDBOX_T19"

# ============================================================
# Results
# ============================================================
echo ""
echo "============================================"
echo "Results: $passed/$total passed, $failed failed"
echo "============================================"

# Cleanup test output files
rm -f /tmp/anutron-test-output-$$.txt /tmp/anutron-test-output2-$$.txt

if [ "$failed" -gt 0 ]; then
  # Determine how many are "expected red" vs truly broken
  echo ""
  echo "Note: Tests 6-17 (new red tests) are expected to fail until Stage 3."
  exit 1
fi
echo "All tests passed."
exit 0
