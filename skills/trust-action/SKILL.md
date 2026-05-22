---
name: trust-action
description: Eliminate a specific Claude Code permission prompt by adding a targeted allowlist rule to global (~/.claude/settings.json) or project (.claude/settings.json) scope. Use when the user pastes a single permission prompt (text containing "Do you want to proceed?" or "don't ask again") and wants future occurrences of that exact action silenced. Always asks the user to choose global vs project scope before writing. Refuses unfixable patterns (`$(...)`, heredocs, `cd && ...`) and bypass-prone path-based rules (scripts in /tmp/, untracked files) and proposes CLAUDE.md hardening instead. Companion skill `/trust-skills` handles bulk-trust of project-local skills.
tags: [personal]
---

## Context

- Global settings (allow list relevant portion):

  !{python3 -c "import json; d=json.load(open('/Users/aaron/.claude/settings.json')); a=d.get('permissions',{}).get('allow',[]); print('\n'.join(a[-30:]))" 2>/dev/null}

- Bash-style snippet exists: !{test -f ~/Development/Personal/ai-ron/claude-rules/snippets/global/045-bash-command-style.md && echo yes || echo no}

## Purpose

The user pasted (or will paste) a Claude Code permission prompt and wants to stop seeing it. Parse the prompt, classify it, and either:
- **Allowlist** it via the helper script (when the pattern can be silenced), or
- **Refuse** with an explanation and a CLAUDE.md hardening proposal (when static-analysis flags make allowlisting impossible).

## Instructions

### Step 1: Classify the prompt

Scan the pasted text for these signals.

**Static-analysis flags (unfixable via allowlist — go to Step 4):**

- `Contains simple_expansion`
- `Contains shell syntax that cannot be statically analyzed`
- `Contains command substitution`
- `Contains heredoc`
- `changes directory before running`

**Tool types (allowlistable — go to Step 2):**

- **MCP**: pasted text mentions `(MCP)` and a server name like `claude.ai Granola` or `Notion - notion-fetch`
- **Bash**: pasted text starts with `Bash command` or shows a shell command without static-analysis flags
- **File**: pasted text shows `Read`, `Write`, or `Edit` plus a path

### Step 2: Build a smart-default allowlist pattern

**MCP tools:**

- Convert the server display name to the prefix used in tool names:
  - `claude.ai Granola` → `claude_ai_Granola`
  - `claude.ai Notion` → `claude_ai_Notion`
  - `plugin playwright playwright` → `plugin_playwright_playwright`
- Rule: `mcp__<server>__*`
- Do **not** rely on the existing `mcp__*` catch-all — it has been observed not to match in practice.

**Bash commands:**

- Take the first 1-2 tokens of the command (verb + subcommand). Examples:
  - `gh api repos/x/y` → `Bash(gh api:*)`
  - `npm install foo` → `Bash(npm install:*)`
  - `git push origin main` → `Bash(git push:*)`
  - `kubectl get pods` → `Bash(kubectl get:*)`
- **Refuse to broaden** these verbs — propose an exact-args pattern only, or refuse outright:
  - `rm`, `sudo`, `chmod`, `chown`, `dd`, `mkfs`, `kill`, `pkill`, `curl`, `wget`, `npm publish`, `gh repo delete`
- If the command points to a script under `~/.claude/bin/`, `~/Development/`, or a project's `.claude/bin/`, prefer the exact path pattern: `Bash(/full/path/script.sh:*)`.

**File operations:**

- Read/Write/Edit on a specific path → use the directory + `**` for projects, or exact path for one-offs:
  - `Read(/Users/aaron/Development/Personal/foo/bar.md)` → `Read(/Users/aaron/Development/Personal/foo/**)`
  - `Read(/tmp/x.txt)` → `Read(/tmp/**)` (already allowed)

### Step 3: Choose scope (global vs project)

Before writing the rule, always ask the user where it should land. Use `AskUserQuestion` with two options (no auto-pick — the user gets the final say every time):

- **Global** (`~/.claude/settings.json`) — applies everywhere. Default for rules that aren't project-specific (helper scripts under `~/.claude/bin/`, generic verbs like `gh api`, MCP tools, etc.).
- **Project** (`<project-root>/.claude/settings.json`) — applies only inside that repo. Right choice when the rule references a path under that project, or when the project is a Thanx repo (`~/Development/thanx/*`) where global rules shouldn't bleed.

Recommend the better default in the question (mark it "Recommended"), but always present both options:

- Path under `~/Development/thanx/*` → **Recommend Project**
- Path inside a non-global project (e.g. `~/Development/Personal/<repo>/.claude/bin/foo.sh`) → **Recommend Project**
- Global helper (`~/.claude/bin/*`) or verb-only Bash rule or MCP tool → **Recommend Global**

Resolve `<project-root>` from the prompt path or the current working directory (`git -C <cwd> rev-parse --show-toplevel`). If the user picks Project, the target settings file is `<project-root>/.claude/settings.json`.

### Step 4: Apply the rule

Run the helper script (already allowlisted, no prompts). The second argument is the target settings file — omit it for global, pass the project path for project scope:

```bash
# Global
~/Development/Personal/ai-ron/.claude/skills/trust-action/scripts/add-rule.sh "<rule>"

# Project
~/Development/Personal/ai-ron/.claude/skills/trust-action/scripts/add-rule.sh "<rule>" "<project-root>/.claude/settings.json"
```

The helper:

- Reads the target settings file (creates a minimal one if it's a project settings path that doesn't exist yet)
- Appends the rule to `permissions.allow` if missing
- Validates the JSON
- Writes a `.bak.<timestamp>` backup
- Prints a diff

Show the diff back to the user. Done.

### Step 5: Refuse + propose hardening (unfixable patterns)

When a static-analysis flag is present, do **not** write any allowlist rule. Instead:

1. **Explain the flag.** Cite which static-analysis message Claude Code emitted (e.g. "Contains simple_expansion") and why no allowlist can silence it.

2. **Propose the calling-side fix.** Match the flag to its remedy:

   - `Contains simple_expansion` / `Contains command substitution` / `Contains heredoc` → use a helper script under `~/.claude/bin/` (global) or `.claude/bin/` (project), invoked with simple arguments. Or use the Write tool to create a tempfile, then pass it to the command via `-F` / similar.
   - `changes directory before running` → use the tool's `-C` flag (e.g. `git -C <path>`, `make -C <path>`) instead of `cd <path> && cmd`.

3. **Check the bash-style snippet.** Look at `~/Development/Personal/ai-ron/claude-rules/snippets/global/045-bash-command-style.md`:

   - If the specific pattern is already documented there: note that Claude is ignoring its own guidance. Suggest *strengthening* the snippet (concrete example, stronger language, or a new explicit "never do X" line).
   - If the pattern is new: propose appending a new section to the snippet with bad/good examples.

4. **Stop and ask.** Do not edit CLAUDE.md or the snippet without explicit user confirmation. Just propose the text and offer to apply it.

### Step 6: Edge cases

- **Already allowlisted:** the helper script will detect this and no-op. Tell the user.
- **Conflicts with deny list:** if the rule pattern is in `permissions.deny`, refuse and explain.
- **Multiple prompts pasted at once:** process each one (re-asking scope each time unless they share a project), then summarize.
- **Ambiguous bash command** (looks dangerous, looks like a one-off): default to refusing and asking the user which broadening they want.

## Output format

End with a one-paragraph summary:

- What rule (if any) was added
- What was refused and why
- Any CLAUDE.md hardening proposed
- What backup file was written (path to `.bak.<timestamp>`)
