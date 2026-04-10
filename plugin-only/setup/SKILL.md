---
name: setup
description: Interactive onboarding wizard — installs rules, hooks, and statusline for the claude-skills toolkit
---

# Setup

Interactive onboarding for the claude-skills toolkit. Walks the user through what to install and configures everything.

## Context

- Plugin root: !`echo "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"`
- Rules installed: !`grep -qF 'claude-rules managed section' ~/.claude/CLAUDE.md 2>/dev/null && echo "inject mode" || ([ -L ~/.claude/CLAUDE.md ] && readlink ~/.claude/CLAUDE.md | grep -q claude-rules && echo "symlink mode" || echo "no")`
- Statusline installed: !`[ -f ~/.claude/statusline.sh ] && echo "yes" || echo "no"`
- Hooks installed: !`[ -f ~/.claude/hooks/remind-session-topic.sh ] && echo "yes" || echo "no"`
- Current settings hooks: !`cat ~/.claude/settings.json 2>/dev/null | grep -c '"command"' || echo "0"` hook(s) configured
- Permissions configured: !`python3 -c "import json; s=json.load(open('$HOME/.claude/settings.json')); p=s.get('permissions',{}); print(f'{len(p.get(\"allow\",[]))} allow, {len(p.get(\"deny\",[]))} deny, {len(p.get(\"ask\",[]))} ask')" 2>/dev/null || echo "none"`

## Instructions

You are running the setup wizard for the claude-skills toolkit. Be friendly and concise. Ask questions one at a time.

### Step 1: Detect the plugin root

The plugin root is where the claude-skills repo lives. Check the context above for `${CLAUDE_PLUGIN_ROOT}`. If empty, try to find it:

```bash
# Check common locations
for dir in "${CLAUDE_PLUGIN_ROOT:-}" "$(pwd)" "$HOME/claude-skills" "$HOME/anutron-claude-skills"; do
  [ -f "$dir/.claude-plugin/plugin.json" ] && echo "$dir" && break
done
```

Store this path — all subsequent steps reference files relative to it. If not found, ask the user where they cloned the repo.

### Step 2: Rules

Check if rules are already installed (see context). If already installed, say so and skip to step 3.

If not installed, ask:

> The toolkit includes behavioral rules for Claude — git workflow, testing, spec-driven development, markdown formatting, and more. These go in your `~/.claude/CLAUDE.md`.
>
> Would you like to install them?

If yes, explain the two modes and ask which they prefer:

> **Replace** — your current `~/.claude/CLAUDE.md` gets backed up and replaced entirely with the toolkit rules. Best if you're starting fresh.
>
> **Inject** — keeps your existing rules intact and appends a managed section with begin/end markers. On future updates, only the managed section changes. Best if you already have custom rules.

Then execute the chosen mode:

**Replace mode:**
```bash
PLUGIN_ROOT="<detected root>"
DIST="$PLUGIN_ROOT/claude-rules/dist"
mkdir -p "$DIST"
# Compile
cd "$PLUGIN_ROOT/claude-rules" && bash compile.sh compile
# Back up and symlink
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak.$(date +%Y%m%d)
ln -sf "$DIST/global.md" ~/.claude/CLAUDE.md
echo "symlink" > "$DIST/.mode-global"
```

**Inject mode:**
```bash
PLUGIN_ROOT="<detected root>"
cd "$PLUGIN_ROOT/claude-rules" && bash compile.sh compile
# The inject function from compile.sh
MARKER_BEGIN="<!-- BEGIN claude-rules managed section — do not edit between these markers -->"
MARKER_END="<!-- END claude-rules managed section -->"
DIST="$PLUGIN_ROOT/claude-rules/dist"
if grep -qF "$MARKER_BEGIN" ~/.claude/CLAUDE.md 2>/dev/null; then
  # Update existing section
  tmp=$(mktemp)
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v cfile="$DIST/global.md" '
    $0 == begin { print; while ((getline line < cfile) > 0) print line; skip=1; next }
    skip && $0 == end { print; skip=0; next }
    !skip { print }
  ' ~/.claude/CLAUDE.md > "$tmp"
  mv "$tmp" ~/.claude/CLAUDE.md
else
  printf '\n%s\n' "$MARKER_BEGIN" >> ~/.claude/CLAUDE.md
  cat "$DIST/global.md" >> ~/.claude/CLAUDE.md
  printf '%s\n' "$MARKER_END" >> ~/.claude/CLAUDE.md
fi
echo "inject" > "$DIST/.mode-global"
```

After either mode, stamp the installed version so version-check.sh can detect updates:
```bash
PLUGIN_ROOT="<detected root>"
VERSION=$(grep -o '"version": *"[^"]*"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" | head -1 | grep -o '[0-9][0-9.]*')
echo "$VERSION" > ~/.claude/.anutron-claude-skills-version
```

### Step 3: Terminal features

Ask:

> Are you using Claude Code in the **terminal** (not VS Code, JetBrains, or the desktop app)?
> Terminal-only features: status line and session topic hooks.

If no (or they're unsure), skip to the summary — these features only work in the terminal CLI.

If yes, ask about each feature:

#### Statusline

> The **status line** shows context usage, git status, and session topic at the top of every response. Install it?

If yes:
```bash
PLUGIN_ROOT="<detected root>"
cp "$PLUGIN_ROOT/bin/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

#### Hooks

> **Hooks** add two behaviors:
> - Session topic reminders — nudges Claude to set a topic for each session
> - Skill usage logging — logs which skills you use to `~/.claude/skill-usage.tsv`
>
> Install hooks?

If yes:
```bash
PLUGIN_ROOT="<detected root>"
mkdir -p ~/.claude/hooks
cp "$PLUGIN_ROOT/hooks/remind-session-topic.sh" ~/.claude/hooks/
cp "$PLUGIN_ROOT/hooks/log-skill-use.sh" ~/.claude/hooks/
cp "$PLUGIN_ROOT/hooks/log-slash-command.sh" ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

Then update `~/.claude/settings.json` to register the hooks. Read the current file, merge the hooks config, and write it back. The hooks config to add:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/remind-session-topic.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/log-skill-use.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/log-slash-command.sh"
          }
        ]
      }
    ]
  }
}
```

Be careful to merge, not overwrite — the user may have existing hooks. Read `~/.claude/settings.json`, add any missing hook entries, write it back.

### Step 4: Permissions

> The toolkit includes recommended permission rules that reduce how often Claude asks for confirmation while protecting sensitive files and blocking destructive commands. Want to set up permissions?

If no, skip to the summary.

If yes, read the permissions guide for the full reference:

```bash
PLUGIN_ROOT="<detected root>"
cat "$PLUGIN_ROOT/docs/permissions-guide.md"
```

Walk through the categories one at a time. For each, explain what it does and ask if they want it:

1. **Auto-allow core tools** — `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, etc. run without asking. This is the big quality-of-life improvement. Ask: "This lets Claude run all core tools without confirmation. The biggest change is auto-allowing Bash — Claude can run any shell command. OK with that, or would you prefer to leave Bash out and confirm shell commands individually?"

2. **Deny destructive operations** — Blocks `rm -rf /`, `diskutil eraseDisk`, `gh repo delete`, etc. Recommend this to everyone: "These are catastrophic commands no one runs intentionally. Recommended for all users."

3. **Privacy boundaries** — Blocks access to `~/Documents`, `~/Downloads`, `~/Desktop`, `~/Pictures`. Ask: "This walls off personal directories that aren't code. Skip if your code lives inside these folders."

4. **Sensitive file protection** — Blocks reading SSH keys, AWS credentials, GPG private keys. Recommend to everyone. Then ask: "Do you use other credential files? (e.g., `~/.kube/config`, `~/.npmrc`, `~/.docker/config.json`)" — add any they mention.

5. **Guardrails** — Force push, repo visibility changes, and settings.json edits require confirmation. "These are sometimes needed but should always be a conscious decision."

6. **Environment protection** — Shell profiles and `env`/`printenv` require confirmation. "Your shell config can contain secrets. This lets Claude read them when needed but you see what's accessed."

For each category the user accepts, collect the rules. After all categories, merge them into `~/.claude/settings.json`:

```bash
# Read current settings, merge permissions, write back
# Be careful to merge arrays, not replace them — the user may have existing allow/deny/ask rules
```

Read `~/.claude/settings.json`, parse the existing `permissions` object (if any), append new rules to each array (deduplicating), and write it back. Use `jq` if available, otherwise do it carefully with a script.

### Step 5: Summary

Print a clear summary of what was installed:

```
Setup complete!

  Rules:       installed (inject mode)
  Statusline:  installed
  Hooks:       installed (3 hooks)
  Permissions: installed (6 categories)

To update later: git pull in the plugin directory, then run /claude-skills:setup again.
Available skills: /claude-skills:list-skills
Full permissions reference: docs/permissions-guide.md
```

Adjust the summary based on what was actually installed vs skipped.
