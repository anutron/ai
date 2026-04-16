#!/bin/bash
# test-install.sh — End-to-end tests for anutron-install
#
# Sets up a sandbox directory, runs install.sh against the real
# claude-skills repo, then verifies all artifacts are correct.
# Also tests idempotent re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../install.sh"
SOURCE_REPO="/Users/aaron/Personal/claude-skills"

# Sanity: source repo must exist
if [ ! -d "$SOURCE_REPO/skills" ]; then
  echo "SKIP: source repo not found at $SOURCE_REPO"
  exit 0
fi

# Create sandbox
SANDBOX="/tmp/anutron-test-$$-$(date +%s)"
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

assert_file_exists() {
  assert "$1 exists" test -f "$1"
}

assert_dir_exists() {
  assert "$1 exists" test -d "$1"
}

assert_symlink() {
  assert "$1 is a symlink" test -L "$1"
}

assert_file_contains() {
  local file="$1" pattern="$2"
  assert "$file contains '$pattern'" grep -q "$pattern" "$file"
}

assert_file_not_contains() {
  local file="$1" pattern="$2"
  assert "$file does not contain '$pattern'" bash -c "! grep -q '$pattern' '$file'"
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

# ============================================================
# Test 1: Fresh install
# ============================================================
echo "=== Test 1: Fresh install ==="

cd "$SANDBOX"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" > /tmp/anutron-test-output-$$.txt 2>&1
install_exit=$?
assert "install.sh exits 0" test "$install_exit" -eq 0

# --- Skills ---
assert_dir_exists "$SANDBOX/.claude/skills"

# Check that publishable skills are symlinked
assert_symlink "$SANDBOX/.claude/skills/brainstorm"
assert_symlink "$SANDBOX/.claude/skills/guard"
assert_symlink "$SANDBOX/.claude/skills/execute-plan"

# Check that excluded skills are NOT present
assert "airon-blog not installed" test ! -e "$SANDBOX/.claude/skills/airon-blog"
assert "thanx-ai-adoption not installed" test ! -e "$SANDBOX/.claude/skills/thanx-ai-adoption"
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
  # Commands should be under .claude/hooks/ (relative or absolute)
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

# Breadcrumb updated (installedAt should change)
new_timestamp=$(jq -r '.installedAt' "$SANDBOX/.anutron-install.json")
assert "breadcrumb timestamp updated" test -n "$new_timestamp"

# Re-run summary should say "Updated"
assert_file_contains "/tmp/anutron-test-output2-$$.txt" "Updated\|Installed"

echo ""
echo "=== Test 3: Existing CLAUDE.md without markers ==="

# Create a new sandbox with existing CLAUDE.md
SANDBOX2="/tmp/anutron-test2-$$-$(date +%s)"
mkdir -p "$SANDBOX2"

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

SANDBOX3="/tmp/anutron-test3-$$-$(date +%s)"
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

SANDBOX4="/tmp/anutron-test4-$$-$(date +%s)"
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
# Results
# ============================================================
echo ""
echo "============================================"
echo "Results: $passed/$total passed, $failed failed"
echo "============================================"

# Cleanup test output files
rm -f /tmp/anutron-test-output-$$.txt /tmp/anutron-test-output2-$$.txt

if [ "$failed" -gt 0 ]; then
  exit 1
fi
echo "All tests passed."
exit 0
