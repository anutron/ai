#!/bin/bash
# test-uninstall.sh — End-to-end tests for anutron-uninstall
#
# Sets up a sandbox directory, runs install.sh to create state,
# adds user-owned content, runs uninstall.sh, then verifies
# cleanup is correct and user content is preserved.
# Also tests that re-running uninstall errors cleanly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL_SH="$SCRIPT_DIR/../uninstall.sh"
INSTALL_SH="$SCRIPT_DIR/../../anutron-install/install.sh"
SOURCE_REPO="/Users/aaron/Personal/claude-skills"

# Sanity: required files must exist
if [ ! -d "$SOURCE_REPO/skills" ]; then
  echo "SKIP: source repo not found at $SOURCE_REPO"
  exit 0
fi

if [ ! -f "$INSTALL_SH" ]; then
  echo "SKIP: install.sh not found at $INSTALL_SH"
  exit 0
fi

if [ ! -f "$UNINSTALL_SH" ]; then
  echo "FAIL: uninstall.sh not found at $UNINSTALL_SH"
  exit 1
fi

# Create sandbox
SANDBOX="/tmp/anutron-uninstall-test-$$-$(date +%s)"
mkdir -p "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

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

assert_file_exists() {
  assert "$1 exists" test -f "$1"
}

assert_file_not_exists() {
  assert "$1 does not exist" test ! -f "$1"
}

assert_dir_not_exists() {
  assert "$1 does not exist" test ! -d "$1"
}

assert_file_contains() {
  local file="$1" pattern="$2"
  assert "$file contains '$pattern'" grep -qF "$pattern" "$file"
}

assert_file_not_contains() {
  local file="$1" pattern="$2"
  assert "$file does not contain '$pattern'" bash -c "! grep -qF '$pattern' '$file'"
}

assert_json_key() {
  local file="$1" key="$2"
  assert "$file has JSON key '$key'" bash -c "jq -e '$key' '$file' > /dev/null"
}

assert_no_json_key() {
  local file="$1" key="$2"
  assert "$file lacks JSON key '$key'" bash -c "! jq -e '$key' '$file' > /dev/null 2>&1"
}

# ============================================================
# Setup: Run install first
# ============================================================
echo "=== Setup: Installing anutron kit ==="

cd "$SANDBOX"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1
install_exit=$?
assert "install.sh exits 0" test "$install_exit" -eq 0

# Verify install worked
assert "breadcrumb exists after install" test -f "$SANDBOX/.anutron-install.json"
assert "skills dir exists after install" test -d "$SANDBOX/.claude/skills"
assert "CLAUDE.md exists after install" test -f "$SANDBOX/CLAUDE.md"

# ============================================================
# Setup: Add user-owned content
# ============================================================
echo "=== Setup: Adding user-owned content ==="

# Add a user-owned hook entry to settings.json
jq '.hooks.PreToolUse = [{"hooks": [{"type": "command", "command": "./my-custom-hook.sh"}]}]' \
  "$SANDBOX/.claude/settings.json" > "$SANDBOX/.claude/settings.json.tmp"
mv "$SANDBOX/.claude/settings.json.tmp" "$SANDBOX/.claude/settings.json"

# Also add a user key to settings.json
jq '.myUserKey = "preserved"' \
  "$SANDBOX/.claude/settings.json" > "$SANDBOX/.claude/settings.json.tmp"
mv "$SANDBOX/.claude/settings.json.tmp" "$SANDBOX/.claude/settings.json"

# Add user content below the CLAUDE.md delimited block
cat >> "$SANDBOX/CLAUDE.md" << 'USERCONTENT'

## My Project Notes

This is user-written content that should survive uninstall.

- Important build instructions
- Custom workflows
USERCONTENT

# Save skill count for later verification
skill_count_before=$(ls "$SANDBOX/.claude/skills/" 2>/dev/null | wc -l | tr -d ' ')

# ============================================================
# Test 1: Uninstall
# ============================================================
echo ""
echo "=== Test 1: Uninstall ==="

cd "$SANDBOX"
UNINSTALL_OUTPUT=$(bash "$UNINSTALL_SH" 2>&1)
uninstall_exit=$?
assert "uninstall.sh exits 0" test "$uninstall_exit" -eq 0

# --- Skill symlinks removed ---
# .claude/skills/ should be empty or gone (all symlinks were anutron-owned)
if [ -d "$SANDBOX/.claude/skills" ]; then
  remaining_skills=$(ls "$SANDBOX/.claude/skills/" 2>/dev/null | wc -l | tr -d ' ')
  assert_equals "skills dir is empty" "0" "$remaining_skills"
fi

# --- Hook symlinks removed ---
if [ -d "$SANDBOX/.claude/hooks" ]; then
  remaining_hooks=$(ls "$SANDBOX/.claude/hooks/" 2>/dev/null | wc -l | tr -d ' ')
  assert_equals "hooks dir is empty" "0" "$remaining_hooks"
fi

# --- settings.json cleaned ---
assert_file_exists "$SANDBOX/.claude/settings.json"
assert_no_json_key "$SANDBOX/.claude/settings.json" '.anutronInstalled'

# Anutron hook entries should be gone
# The SessionStart entry should be gone since it was anutron-owned
session_start_hooks=$(jq '.hooks.SessionStart // [] | length' "$SANDBOX/.claude/settings.json" 2>/dev/null)
assert_equals "SessionStart hooks removed" "0" "$session_start_hooks"

# User-owned hook should be preserved
assert_json_key "$SANDBOX/.claude/settings.json" '.hooks.PreToolUse'
user_hook_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SANDBOX/.claude/settings.json" 2>/dev/null)
assert_equals "user hook command preserved" "./my-custom-hook.sh" "$user_hook_cmd"

# User key should be preserved
assert_json_key "$SANDBOX/.claude/settings.json" '.myUserKey'
user_key_val=$(jq -r '.myUserKey' "$SANDBOX/.claude/settings.json" 2>/dev/null)
assert_equals "user key value preserved" "preserved" "$user_key_val"

# --- CLAUDE.md cleaned ---
assert_file_exists "$SANDBOX/CLAUDE.md"
assert_file_not_contains "$SANDBOX/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
assert_file_not_contains "$SANDBOX/CLAUDE.md" "END ANUTRON-INSTALL"

# User content should be preserved
assert_file_contains "$SANDBOX/CLAUDE.md" "My Project Notes"
assert_file_contains "$SANDBOX/CLAUDE.md" "user-written content"
assert_file_contains "$SANDBOX/CLAUDE.md" "Important build instructions"

# --- Breadcrumb removed ---
assert_file_not_exists "$SANDBOX/.anutron-install.json"

# --- Summary output ---
assert "summary mentions uninstalled" bash -c "echo '$UNINSTALL_OUTPUT' | grep -qi 'uninstall'"
assert "summary mentions skills" bash -c "echo '$UNINSTALL_OUTPUT' | grep -qi 'skill'"

# ============================================================
# Test 2: Re-run uninstall errors cleanly
# ============================================================
echo ""
echo "=== Test 2: Re-run uninstall (should error) ==="

cd "$SANDBOX"
rerun_output=$(bash "$UNINSTALL_SH" 2>&1 || true)
rerun_exit=$?
# Capture exit code properly
set +e
bash "$UNINSTALL_SH" > /dev/null 2>&1
rerun_exit=$?
set -e

assert "re-run exits non-zero" test "$rerun_exit" -ne 0

# ============================================================
# Test 3: CLAUDE.md deletion when only markers present
# ============================================================
echo ""
echo "=== Test 3: CLAUDE.md deleted when empty after strip ==="

SANDBOX2="/tmp/anutron-uninstall-test2-$$-$(date +%s)"
mkdir -p "$SANDBOX2"

cd "$SANDBOX2"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

# CLAUDE.md should just have the block + placeholder comment
# The placeholder heading is "<!-- Your project instructions below -->"
# Uninstall should delete the file since it's effectively empty
bash "$UNINSTALL_SH" > /dev/null 2>&1
assert "CLAUDE.md deleted when empty" test ! -f "$SANDBOX2/CLAUDE.md"

rm -rf "$SANDBOX2"

# ============================================================
# Test 4: Handles replaced symlinks (regular files instead)
# ============================================================
echo ""
echo "=== Test 4: Handles replaced symlinks gracefully ==="

SANDBOX3="/tmp/anutron-uninstall-test3-$$-$(date +%s)"
mkdir -p "$SANDBOX3"

cd "$SANDBOX3"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

# Replace one skill symlink with a regular directory
first_skill=$(jq -r '.skills[0]' "$SANDBOX3/.anutron-install.json")
if [ -n "$first_skill" ] && [ "$first_skill" != "null" ]; then
  rm -f "$SANDBOX3/.claude/skills/$first_skill"
  mkdir -p "$SANDBOX3/.claude/skills/$first_skill"
  echo "user-owned" > "$SANDBOX3/.claude/skills/$first_skill/SKILL.md"
fi

# Uninstall should still succeed
uninstall3_output=$(bash "$UNINSTALL_SH" 2>&1)
uninstall3_exit=$?
assert "uninstall succeeds with replaced symlinks" test "$uninstall3_exit" -eq 0

# The replaced skill dir should still exist (user-owned)
if [ -n "$first_skill" ] && [ "$first_skill" != "null" ]; then
  assert "user-replaced skill preserved" test -d "$SANDBOX3/.claude/skills/$first_skill"
fi

rm -rf "$SANDBOX3"

# ============================================================
# Test 5: settings.json removed when it becomes empty
# ============================================================
echo ""
echo "=== Test 5: settings.json removed when empty ==="

SANDBOX4="/tmp/anutron-uninstall-test4-$$-$(date +%s)"
mkdir -p "$SANDBOX4"

cd "$SANDBOX4"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /dev/null 2>&1

# Remove all non-anutron keys from settings.json so uninstall leaves it empty
jq 'del(.permissions) | del(.mcpPermissions) | del(.myUserKey)' \
  "$SANDBOX4/.claude/settings.json" > "$SANDBOX4/.claude/settings.json.tmp" 2>/dev/null || true
mv "$SANDBOX4/.claude/settings.json.tmp" "$SANDBOX4/.claude/settings.json" 2>/dev/null || true

# Make sure settings.json only has anutron keys
jq '{hooks: .hooks, anutronInstalled: .anutronInstalled}' \
  "$SANDBOX4/.claude/settings.json" > "$SANDBOX4/.claude/settings.json.tmp"
mv "$SANDBOX4/.claude/settings.json.tmp" "$SANDBOX4/.claude/settings.json"

bash "$UNINSTALL_SH" > /dev/null 2>&1
assert "settings.json removed when empty" test ! -f "$SANDBOX4/.claude/settings.json"

rm -rf "$SANDBOX4"

# ============================================================
# Results
# ============================================================
echo ""
echo "============================================"
echo "Results: $passed/$total passed, $failed failed"
echo "============================================"

if [ "$failed" -gt 0 ]; then
  exit 1
fi
echo "All tests passed."
exit 0
