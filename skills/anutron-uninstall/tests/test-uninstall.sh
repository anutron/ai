#!/bin/bash
# test-uninstall.sh — End-to-end tests for anutron-uninstall
#
# Verifies that uninstall.sh correctly reverses both copy-mode and symlink-mode
# installs, including legacy breadcrumbs that predate the mode/scopeResolution fields.
#
# Usage:
#   bash test-uninstall.sh                        # uses bundled fixture
#   ANUTRON_SOURCE=/path/to/source bash test-uninstall.sh  # override source

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL_SH="$SCRIPT_DIR/../uninstall.sh"
INSTALL_SH="$SCRIPT_DIR/../../anutron-install/install.sh"
FIXTURE_SOURCE="$SCRIPT_DIR/../../anutron-install/tests/fixtures/source-repo"
SOURCE_REPO="${ANUTRON_SOURCE:-$FIXTURE_SOURCE}"

# Sanity: source repo must exist
if [ ! -d "$SOURCE_REPO/skills" ]; then
  echo "SKIP: source repo not found at $SOURCE_REPO"
  exit 0
fi

# Also require install.sh
if [ ! -f "$INSTALL_SH" ]; then
  echo "SKIP: install.sh not found at $INSTALL_SH"
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

assert_file_not_exists() {
  assert "$1 does not exist" bash -c "! test -e '$1'"
}

assert_dir_not_exists() {
  assert "$1 directory does not exist" bash -c "! test -d '$1'"
}

assert_symlink() {
  assert "$1 is a symlink" test -L "$1"
}

assert_not_symlink() {
  assert "$1 is NOT a symlink" bash -c "! test -L '$1'"
}

assert_file_contains() {
  local file="$1" pattern="$2"
  assert "$file contains '$pattern'" grep -q "$pattern" "$file"
}

assert_file_not_contains() {
  local file="$1" pattern="$2"
  total=$((total + 1))
  if grep -qF "$pattern" "$file" >/dev/null 2>&1; then
    failed=$((failed + 1))
    echo "FAIL: $file should NOT contain '$pattern'"
  else
    passed=$((passed + 1))
  fi
}

assert_json_key_absent() {
  local file="$1" key="$2"
  total=$((total + 1))
  if jq -e "$key" "$file" >/dev/null 2>&1; then
    failed=$((failed + 1))
    echo "FAIL: $file should NOT have JSON key '$key' but does"
  else
    passed=$((passed + 1))
  fi
}

assert_json_key_present() {
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

# Count non-dotfile items in a directory
count_entries() {
  local dir="$1"
  ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' '
}

# Create a fresh sandbox and return its path
make_sandbox() {
  local sb
  sb="/tmp/uninstall-test-$$-$(date +%s)-$RANDOM"
  mkdir -p "$sb"
  echo "$sb"
}

# ============================================================
# Test 1: Copy-mode uninstall
# ============================================================
echo "=== Test 1: Copy-mode uninstall ==="

SANDBOX1="$(make_sandbox)"

# Install in copy mode
cd "$SANDBOX1"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy --scope=full > /dev/null 2>&1
install_exit=$?
assert "copy-mode install succeeded" test "$install_exit" -eq 0
assert "breadcrumb exists after install" test -f "$SANDBOX1/.anutron-install.json"

# Snapshot: skills are real dirs (not symlinks) in copy mode
assert_not_symlink "$SANDBOX1/.claude/skills/brainstorm"
assert "brainstorm is a real directory" test -d "$SANDBOX1/.claude/skills/brainstorm"
skills_before="$(count_entries "$SANDBOX1/.claude/skills")"
assert "copy-mode install has at least one skill dir" test "$skills_before" -gt 0

# Run uninstall
cd "$SANDBOX1"
uninstall_exit=0
bash "$UNINSTALL_SH" > /dev/null 2>&1 || uninstall_exit=$?
assert "copy-mode uninstall exits 0" test "$uninstall_exit" -eq 0

# Assert: every skill dir from snapshot is gone (fully removed, not just emptied)
assert "brainstorm dir gone after copy-mode uninstall" bash -c "! test -e '$SANDBOX1/.claude/skills/brainstorm'"
assert "guard dir gone after copy-mode uninstall" bash -c "! test -e '$SANDBOX1/.claude/skills/guard'"

# No dangling symlinks left in .claude/skills
if [ -d "$SANDBOX1/.claude/skills" ]; then
  leftover_links="$(find "$SANDBOX1/.claude/skills" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
  assert "no dangling symlinks left in .claude/skills" test "$leftover_links" -eq 0
fi

# Breadcrumb gone
assert_file_not_exists "$SANDBOX1/.anutron-install.json"

# CLAUDE.md ANUTRON-INSTALL block gone
if [ -f "$SANDBOX1/CLAUDE.md" ]; then
  assert_file_not_contains "$SANDBOX1/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
fi

# Settings cleaned
if [ -f "$SANDBOX1/.claude/settings.json" ]; then
  assert_json_key_absent "$SANDBOX1/.claude/settings.json" '.anutronInstalled'
fi

rm -rf "$SANDBOX1"

echo ""
echo "=== Test 1b: Copy-mode uninstall preserves other user settings keys ==="

SANDBOX1B="$(make_sandbox)"
mkdir -p "$SANDBOX1B/.claude"

# Settings with user keys that must survive
cat > "$SANDBOX1B/.claude/settings.json" << 'USERSETTINGS'
{
  "permissions": {
    "allow": ["Read", "Write", "Bash"]
  },
  "mcpPermissions": {
    "memory": { "allowAllTools": true }
  }
}
USERSETTINGS

cd "$SANDBOX1B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy --scope=full > /dev/null 2>&1
assert "copy-mode install with user settings succeeded" test "$?" -eq 0

cd "$SANDBOX1B"
bash "$UNINSTALL_SH" > /dev/null 2>&1

# User keys must survive; anutron key must be gone
if [ -f "$SANDBOX1B/.claude/settings.json" ]; then
  assert_json_key_present "$SANDBOX1B/.claude/settings.json" '.permissions'
  assert_json_key_present "$SANDBOX1B/.claude/settings.json" '.mcpPermissions'
  assert_json_key_absent "$SANDBOX1B/.claude/settings.json" '.anutronInstalled'
fi

rm -rf "$SANDBOX1B"

echo ""
echo "=== Test 1c: Copy-mode uninstall idempotent (second run fails cleanly) ==="

SANDBOX1C="$(make_sandbox)"
cd "$SANDBOX1C"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy > /dev/null 2>&1
cd "$SANDBOX1C"
bash "$UNINSTALL_SH" > /dev/null 2>&1

# Second run: breadcrumb is gone — must error with a clear message (not crash)
set +e
second_run_output="$(bash "$UNINSTALL_SH" 2>&1)"
second_run_exit=$?
set -e
assert "second copy-mode uninstall exits non-zero (no breadcrumb)" test "$second_run_exit" -ne 0
assert "second run error mentions breadcrumb" bash -c "echo '$second_run_output' | grep -qi 'anutron-install.json'"

rm -rf "$SANDBOX1C"

echo ""
echo "=== Test 2: Symlink-mode uninstall ==="

SANDBOX2="$(make_sandbox)"
cd "$SANDBOX2"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=symlink --scope=full > /dev/null 2>&1
assert "symlink-mode install succeeded" test "$?" -eq 0

# Verify skills are symlinks
assert_symlink "$SANDBOX2/.claude/skills/brainstorm"
skills_sym_before="$(count_entries "$SANDBOX2/.claude/skills")"
assert "symlink install has at least one skill" test "$skills_sym_before" -gt 0

cd "$SANDBOX2"
sym_uninstall_exit=0
bash "$UNINSTALL_SH" > /dev/null 2>&1 || sym_uninstall_exit=$?
assert "symlink-mode uninstall exits 0" test "$sym_uninstall_exit" -eq 0

# All symlinks gone
assert "brainstorm symlink gone after symlink-mode uninstall" bash -c "! test -e '$SANDBOX2/.claude/skills/brainstorm'"
assert "guard symlink gone after symlink-mode uninstall" bash -c "! test -e '$SANDBOX2/.claude/skills/guard'"

# Breadcrumb gone
assert_file_not_exists "$SANDBOX2/.anutron-install.json"

# CLAUDE.md block gone
if [ -f "$SANDBOX2/CLAUDE.md" ]; then
  assert_file_not_contains "$SANDBOX2/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
fi

# Settings cleaned
if [ -f "$SANDBOX2/.claude/settings.json" ]; then
  assert_json_key_absent "$SANDBOX2/.claude/settings.json" '.anutronInstalled'
fi

# Source files untouched
assert "source repo brainstorm skill still intact after symlink uninstall" test -d "$SOURCE_REPO/skills/brainstorm"

rm -rf "$SANDBOX2"

echo ""
echo "=== Test 2b: Symlink-mode uninstall preserves user settings keys ==="

SANDBOX2B="$(make_sandbox)"
mkdir -p "$SANDBOX2B/.claude"

cat > "$SANDBOX2B/.claude/settings.json" << 'USERSETTINGS2'
{
  "permissions": {
    "allow": ["Read"]
  },
  "theme": "dark"
}
USERSETTINGS2

cd "$SANDBOX2B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=symlink > /dev/null 2>&1
cd "$SANDBOX2B"
bash "$UNINSTALL_SH" > /dev/null 2>&1

if [ -f "$SANDBOX2B/.claude/settings.json" ]; then
  assert_json_key_present "$SANDBOX2B/.claude/settings.json" '.permissions'
  assert_json_key_absent "$SANDBOX2B/.claude/settings.json" '.anutronInstalled'
fi

rm -rf "$SANDBOX2B"

echo ""
echo "=== Test 3: Legacy breadcrumb (no mode/scopeResolution fields) ==="

SANDBOX3="$(make_sandbox)"

# Step 1: Install with symlink mode to generate a real breadcrumb
cd "$SANDBOX3"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=symlink --scope=full > /dev/null 2>&1
assert "install for legacy test succeeded" test "$?" -eq 0
assert "breadcrumb exists for legacy stripping" test -f "$SANDBOX3/.anutron-install.json"

# Step 2: Strip mode and scopeResolution — simulate a legacy breadcrumb
jq 'del(.mode) | del(.scopeResolution)' "$SANDBOX3/.anutron-install.json" > "$SANDBOX3/.anutron-install.json.tmp"
mv "$SANDBOX3/.anutron-install.json.tmp" "$SANDBOX3/.anutron-install.json"

# Verify stripping worked
legacy_mode_val="$(jq -r '.mode // "ABSENT"' "$SANDBOX3/.anutron-install.json")"
assert_equals "mode field stripped from legacy breadcrumb" "ABSENT" "$legacy_mode_val"

# Step 3: Run uninstall with the legacy breadcrumb
cd "$SANDBOX3"
legacy_exit=0
bash "$UNINSTALL_SH" > /dev/null 2>&1 || legacy_exit=$?
assert "legacy breadcrumb uninstall exits 0" test "$legacy_exit" -eq 0

# Step 4: Assert clean removal — symlinks are gone
assert "brainstorm symlink gone (legacy uninstall)" bash -c "! test -e '$SANDBOX3/.claude/skills/brainstorm'"
assert "guard symlink gone (legacy uninstall)" bash -c "! test -e '$SANDBOX3/.claude/skills/guard'"

# Breadcrumb gone
assert_file_not_exists "$SANDBOX3/.anutron-install.json"

# CLAUDE.md block gone
if [ -f "$SANDBOX3/CLAUDE.md" ]; then
  assert_file_not_contains "$SANDBOX3/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
fi

# Settings cleaned
if [ -f "$SANDBOX3/.claude/settings.json" ]; then
  assert_json_key_absent "$SANDBOX3/.claude/settings.json" '.anutronInstalled'
fi

rm -rf "$SANDBOX3"

echo ""
echo "=== Test 3b: Legacy breadcrumb + copy-mode install exits 0 (graceful skip) ==="
# When a copy-mode install has had mode/scopeResolution stripped, the uninstaller
# sees real directories in legacy mode where it only expects symlinks or plain files.
# The uninstaller must exit 0 (not crash) and still clean up breadcrumb and settings.

SANDBOX3B="$(make_sandbox)"
cd "$SANDBOX3B"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy --scope=full > /dev/null 2>&1

# Strip mode and scopeResolution
jq 'del(.mode) | del(.scopeResolution)' "$SANDBOX3B/.anutron-install.json" > "$SANDBOX3B/.anutron-install.json.tmp"
mv "$SANDBOX3B/.anutron-install.json.tmp" "$SANDBOX3B/.anutron-install.json"

cd "$SANDBOX3B"
legacy_copy_exit=0
bash "$UNINSTALL_SH" > /dev/null 2>&1 || legacy_copy_exit=$?
assert "legacy-breadcrumb + copy-mode: uninstall exits 0" test "$legacy_copy_exit" -eq 0

# Breadcrumb gone
assert_file_not_exists "$SANDBOX3B/.anutron-install.json"

# Settings cleaned
if [ -f "$SANDBOX3B/.claude/settings.json" ]; then
  assert_json_key_absent "$SANDBOX3B/.claude/settings.json" '.anutronInstalled'
fi

rm -rf "$SANDBOX3B"

echo ""
echo "=== Test 4: Pre-existing CLAUDE.md content preserved after uninstall ==="

SANDBOX4="$(make_sandbox)"

# Lay down project instructions before installing
cat > "$SANDBOX4/CLAUDE.md" << 'EXISTING'
# My Project

These are my project instructions.

## Build

Run `make build`.
EXISTING

cd "$SANDBOX4"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy > /dev/null 2>&1

# Verify markers are present alongside existing content
assert_file_contains "$SANDBOX4/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
assert_file_contains "$SANDBOX4/CLAUDE.md" "My Project"

cd "$SANDBOX4"
bash "$UNINSTALL_SH" > /dev/null 2>&1

# After uninstall: original content preserved, markers gone
assert "CLAUDE.md still exists (had project content)" test -f "$SANDBOX4/CLAUDE.md"
assert_file_not_contains "$SANDBOX4/CLAUDE.md" "BEGIN ANUTRON-INSTALL"
assert_file_contains "$SANDBOX4/CLAUDE.md" "My Project"
assert_file_contains "$SANDBOX4/CLAUDE.md" "make build"

rm -rf "$SANDBOX4"

echo ""
echo "=== Test 5: Uninstall summary mentions mode ==="

SANDBOX5="$(make_sandbox)"
cd "$SANDBOX5"
ANUTRON_SOURCE="$SOURCE_REPO" bash "$INSTALL_SH" --mode=copy > /dev/null 2>&1

cd "$SANDBOX5"
summary_out="$(bash "$UNINSTALL_SH" 2>&1)"
assert "uninstall summary mentions mode" bash -c "echo '$summary_out' | grep -qi 'mode'"
assert "uninstall summary mentions skills" bash -c "echo '$summary_out' | grep -qi 'skill'"

rm -rf "$SANDBOX5"

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
