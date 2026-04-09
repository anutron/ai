#!/bin/bash
# compile.sh — Assemble CLAUDE.md files from snippets
#
# Usage:
#   ./compile.sh              # Compile both global and project files
#   ./compile.sh promote NAME # Move snippet from project/ to global/, recompile
#   ./compile.sh demote NAME  # Move snippet from global/ to project/, recompile
#   ./compile.sh list         # Show all snippets and their scope
#   ./compile.sh status       # Check if dist files have been modified externally

set -euo pipefail

RULES_DIR="$(cd "$(dirname "$0")" && pwd)"
SNIPPETS="$RULES_DIR/snippets"
DIST="$RULES_DIR/dist"
CHECKSUMS="$DIST/.checksums"
TARGETS_FILE="$DIST/.targets"

# Where the compiled files get symlinked/injected to
GLOBAL_TARGET="$HOME/.claude/CLAUDE.md"
PROJECT_TARGET="$RULES_DIR/../CLAUDE.md"

# Inject mode markers
MARKER_BEGIN="<!-- BEGIN claude-rules managed section — do not edit between these markers -->"
MARKER_END="<!-- END claude-rules managed section -->"

# Mode files track symlink vs inject per target
MODE_GLOBAL="$DIST/.mode-global"
MODE_PROJECT="$DIST/.mode-project"

get_mode() {
  local mode_file="$1"
  if [ -f "$mode_file" ]; then
    cat "$mode_file"
  else
    echo "symlink"
  fi
}

# Replace the managed section between markers, or append if no markers exist
inject_section() {
  local target="$1" content_file="$2"

  if grep -qF "$MARKER_BEGIN" "$target" 2>/dev/null; then
    # Replace existing managed section
    local tmp
    tmp=$(mktemp)
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v cfile="$content_file" '
      $0 == begin {
        print
        while ((getline line < cfile) > 0) print line
        skip = 1
        next
      }
      skip && $0 == end {
        print
        skip = 0
        next
      }
      !skip { print }
    ' "$target" > "$tmp"
    mv "$tmp" "$target"
  else
    # First injection — append markers and content
    printf '\n%s\n' "$MARKER_BEGIN" >> "$target"
    cat "$content_file" >> "$target"
    printf '%s\n' "$MARKER_END" >> "$target"
  fi
}

compile_scope() {
  local scope="$1" header="$2" output="$3"
  local first=true

  echo "$header" > "$output"
  echo "" >> "$output"

  for f in "$SNIPPETS/$scope"/*.md; do
    [ -f "$f" ] || continue
    if [ "$first" = true ]; then
      first=false
    else
      echo -e "\n---\n" >> "$output"
    fi
    cat "$f" >> "$output"
  done

  echo "" >> "$output"
}

save_checksums() {
  shasum -a 256 "$DIST/global.md" "$DIST/project.md" > "$CHECKSUMS"
}

resolve_variables() {
  local file="$1"
  local project_dir
  project_dir="$(dirname "$RULES_DIR")"

  # Built-in variables (name=value, one per line)
  local builtins
  builtins="CLAUDE_RULES_DIR=$RULES_DIR
PROJECT_DIR=$project_dir
GLOBAL_TARGET=$GLOBAL_TARGET"

  # Collect all variables: builtins first, then custom from variables.env
  local all_vars="$builtins"

  local envfile="$RULES_DIR/variables.env"
  if [ -f "$envfile" ]; then
    while IFS='=' read -r key val; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      # Resolve {{VAR}} references in the value using already-known variables
      while IFS='=' read -r vname vval; do
        [ -z "$vname" ] && continue
        val="${val//\{\{$vname\}\}/$vval}"
      done <<< "$all_vars"
      all_vars="$all_vars
$key=$val"
    done < "$envfile"
  fi

  # Replace all {{VAR}} in file
  while IFS='=' read -r vname vval; do
    [ -z "$vname" ] && continue
    sed -i '' "s|{{${vname}}}|${vval}|g" "$file"
  done <<< "$all_vars"
}

# Check if a target file has been modified since last compile.
# Returns 0 if clean, 1 if dirty. Prints diff if dirty.
check_target() {
  local label="$1" target="$2" dist_file="$3"

  # Inject-mode targets are always safe to overwrite (only the managed section changes)
  local mode_file="$DIST/.mode-${label}"
  if [ "$(get_mode "$mode_file")" = "inject" ]; then
    return 0
  fi

  [ -f "$target" ] || return 0
  [ -L "$target" ] || {
    # Target exists but is not a symlink — could be the original file
    # before we set up symlinks. Not our problem to check.
    return 0
  }

  # Target is a symlink (to our dist file). Check if dist was modified.
  [ -f "$CHECKSUMS" ] || return 0

  local expected actual
  expected=$(grep "$(basename "$dist_file")" "$CHECKSUMS" 2>/dev/null | awk '{print $1}')
  [ -z "$expected" ] && return 0

  actual=$(shasum -a 256 "$dist_file" | awk '{print $1}')

  if [ "$expected" != "$actual" ]; then
    echo ""
    echo "WARNING: $label ($target) was modified since last compile."
    echo ""

    # Generate what compile would produce, diff against current
    local tmp
    tmp=$(mktemp)
    if [ "$label" = "global" ]; then
      compile_scope "global" "# Global Claude Code Instructions" "$tmp"
    else
      compile_scope "project" "# AI Ron - Project Instructions" "$tmp"
    fi

    echo "Changes made outside the snippet system:"
    diff --unified=3 "$tmp" "$dist_file" || true
    rm -f "$tmp"

    # Save the pending changes for reference
    local pending="$DIST/.pending-${label}.diff"
    diff --unified=3 "$tmp" "$dist_file" > "$pending" 2>/dev/null || true
    echo ""
    echo "Diff saved to: $pending"
    echo "To incorporate: create a new snippet in snippets/${label}/, then recompile."
    return 1
  fi

  return 0
}

do_status() {
  echo "Modes:"
  echo "  global:  $(get_mode "$MODE_GLOBAL")"
  echo "  project: $(get_mode "$MODE_PROJECT")"
  echo ""

  local dirty=0
  check_target "global" "$GLOBAL_TARGET" "$DIST/global.md" || dirty=1
  check_target "project" "$PROJECT_TARGET" "$DIST/project.md" || dirty=1

  if [ "$dirty" -eq 0 ]; then
    echo "All clean — no external modifications detected."
  fi
  return "$dirty"
}

do_compile() {
  local force="${1:-}"
  mkdir -p "$DIST"

  # Check for external modifications before overwriting
  local dirty=0
  if [ -f "$CHECKSUMS" ]; then
    check_target "global" "$GLOBAL_TARGET" "$DIST/global.md" || dirty=1
    check_target "project" "$PROJECT_TARGET" "$DIST/project.md" || dirty=1

    if [ "$dirty" -ne 0 ]; then
      if [ "$force" = "--force" ]; then
        echo ""
        echo "Forcing compile — overwriting external changes."
      else
        echo ""
        echo "Aborting compile. Incorporate the changes above into snippets first."
        echo "Or run: $0 compile --force to overwrite."
        exit 1
      fi
    fi
  fi

  compile_scope "global" "# Global Claude Code Instructions" "$DIST/global.md"
  resolve_variables "$DIST/global.md"
  compile_scope "project" "# AI Ron - Project Instructions" "$DIST/project.md"
  resolve_variables "$DIST/project.md"
  save_checksums

  # Clean up any pending diff artifacts from previous drift detection
  rm -f "$DIST"/.pending-*.diff

  # Update inject-mode targets
  if [ "$(get_mode "$MODE_GLOBAL")" = "inject" ] && [ -f "$GLOBAL_TARGET" ]; then
    inject_section "$GLOBAL_TARGET" "$DIST/global.md"
    echo "  → Updated managed section in $GLOBAL_TARGET"
  fi
  if [ "$(get_mode "$MODE_PROJECT")" = "inject" ] && [ -f "$PROJECT_TARGET" ]; then
    inject_section "$PROJECT_TARGET" "$DIST/project.md"
    echo "  → Updated managed section in $PROJECT_TARGET"
  fi

  local global_count project_count
  global_count=$(ls "$SNIPPETS/global"/*.md 2>/dev/null | wc -l | tr -d ' ')
  project_count=$(ls "$SNIPPETS/project"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "Compiled: $global_count global + $project_count project snippets"
  echo "  → $DIST/global.md ($(get_mode "$MODE_GLOBAL") mode)"
  echo "  → $DIST/project.md ($(get_mode "$MODE_PROJECT") mode)"
}

link_target() {
  local label="$1" target="$2" dist_file="$3" mode_file="$4"

  # Already managed — check current mode
  if [ -L "$target" ]; then
    echo "$label: already symlinked"
    echo "symlink" > "$mode_file"
    return
  fi

  if grep -qF "$MARKER_BEGIN" "$target" 2>/dev/null; then
    echo "$label: already using inject mode"
    echo "inject" > "$mode_file"
    return
  fi

  # Existing file — ask the user
  if [ -f "$target" ]; then
    echo ""
    echo "$label: $target already exists."
    echo ""
    echo "  1) Replace  — back up existing file, symlink to compiled output"
    echo "               Your current content is replaced entirely."
    echo "  2) Inject   — keep your file, append a managed section with markers"
    echo "               Your content stays. Only the managed section updates on recompile."
    echo ""
    read -rp "  Choose [1/2]: " choice

    case "$choice" in
      1)
        local backup="${target}.bak.$(date +%Y%m%d)"
        cp "$target" "$backup"
        echo "$label: backed up to $backup"
        ln -sf "$dist_file" "$target"
        echo "$label: symlinked → $dist_file"
        echo "symlink" > "$mode_file"
        ;;
      2)
        inject_section "$target" "$dist_file"
        echo "$label: injected managed section"
        echo "inject" > "$mode_file"
        ;;
      *)
        echo "$label: skipped"
        ;;
    esac
    return
  fi

  # No existing file — symlink (nothing to preserve)
  ln -sf "$dist_file" "$target"
  echo "$label: symlinked → $dist_file"
  echo "symlink" > "$mode_file"
}

do_link() {
  mkdir -p "$DIST"
  link_target "global" "$GLOBAL_TARGET" "$DIST/global.md" "$MODE_GLOBAL"
  link_target "project" "$PROJECT_TARGET" "$DIST/project.md" "$MODE_PROJECT"
  echo ""
  echo "Done. Run '$0 compile' to regenerate."
}

do_promote() {
  local name="$1"
  local src="$SNIPPETS/project/$name"
  local dst="$SNIPPETS/global/$name"

  if [ ! -f "$src" ]; then
    echo "Error: $src not found"
    exit 1
  fi
  if [ -f "$dst" ]; then
    echo "Error: $dst already exists"
    exit 1
  fi

  mv "$src" "$dst"
  echo "Promoted: $name (project → global)"
  do_compile
}

do_demote() {
  local name="$1"
  local src="$SNIPPETS/global/$name"
  local dst="$SNIPPETS/project/$name"

  if [ ! -f "$src" ]; then
    echo "Error: $src not found"
    exit 1
  fi
  if [ -f "$dst" ]; then
    echo "Error: $dst already exists"
    exit 1
  fi

  mv "$src" "$dst"
  echo "Demoted: $name (global → project)"
  do_compile
}

do_list() {
  echo "=== Global snippets ==="
  for f in "$SNIPPETS/global"/*.md; do
    [ -f "$f" ] || continue
    echo "  $(basename "$f")"
  done

  echo ""
  echo "=== Project snippets ==="
  for f in "$SNIPPETS/project"/*.md; do
    [ -f "$f" ] || continue
    echo "  $(basename "$f")"
  done
}

case "${1:-compile}" in
  compile)
    do_compile "${2:-}"
    ;;
  link)
    do_link
    ;;
  status)
    do_status
    ;;
  promote)
    [ -z "${2:-}" ] && echo "Usage: $0 promote <snippet-name>.md" && exit 1
    do_promote "$2"
    ;;
  demote)
    [ -z "${2:-}" ] && echo "Usage: $0 demote <snippet-name>.md" && exit 1
    do_demote "$2"
    ;;
  list)
    do_list
    ;;
  *)
    echo "Usage: $0 [compile|link|status|promote|demote|list] [snippet-name]"
    exit 1
    ;;
esac
