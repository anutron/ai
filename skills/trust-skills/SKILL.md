---
name: trust-skills
description: Bulk-trust all skills defined in the current project's `.claude/skills/` directory. Discovers local skills, shows them to the user, asks where to write the rules (project settings.json vs settings.local.json), then adds `Skill(<name>)` allowlist entries. Use when working in a project that has its own skills and you keep getting per-skill permission prompts.
tags: [personal]
---

## Context

- Working directory: !{pwd}
- Local skills dir present: !{test -d .claude/skills && echo yes || echo no}
- Local skills count: !{ls -1 .claude/skills/ 2>/dev/null | wc -l | tr -d ' '}
- Project settings.json present: !{test -f .claude/settings.json && echo yes || echo no}
- Project settings.local.json present: !{test -f .claude/settings.local.json && echo yes || echo no}

## Purpose

Project-local equivalent of `/trust-action`, but proactive and bulk. When a project has its own `.claude/skills/` directory full of skills the user trusts (they live in the repo, they're committed), repeatedly approving each one is friction without benefit. This skill discovers them all and adds them to the project's allow list in one shot.

## Instructions

### Step 1: Abort if no local skills

If `.claude/skills/` does not exist or is empty, tell the user there's nothing to trust and stop. Suggest they may be looking for `/trust-action` (global, reactive) instead.

### Step 2: Discover local skills

List every directory under `.claude/skills/`. For each, read `<name>/SKILL.md`'s frontmatter to extract:

- `name:` — the skill identifier used in `Skill(<name>)` rules
- `description:` — the one-line summary

If a directory has no SKILL.md, skip it with a note.

### Step 3: Present and confirm

Show the user a markdown list of discovered skills:

```
Found N skills in .claude/skills/:

- **skill-one** — brief description
- **skill-two** — brief description
- ...
```

Then use AskUserQuestion to confirm the action:

- **Question:** "Trust all N skills?"
- **Options:**
  - "Yes — trust all" (recommended)
  - "Choose individually" — fall through to a multi-select (one AskUserQuestion per group of ≤4 skills)
  - "Cancel"

### Step 4: Ask where to write the rules

Use AskUserQuestion to pick the destination file. **Always ask — never default.**

- **Question:** "Where should the allowlist entries go?"
- **Options:**
  - "Project `.claude/settings.json`" — versioned, shared with collaborators. Use when the trust decision should apply to everyone working on the repo.
  - "Project `.claude/settings.local.json`" — per-user, gitignored. Use when the decision is yours and might differ across contributors.

### Step 5: Apply rules

For each confirmed skill, invoke the shared helper at the absolute path:

```bash
/Users/aaron/Development/Personal/ai-ron/.claude/skills/trust-action/scripts/add-rule.sh "Skill(<name>)" "<destination-file>"
```

The helper handles dedup, deny-conflict, JSON validation, and backup. If the destination file doesn't exist, it creates a minimal one with `{"permissions":{"allow":[],"ask":[],"deny":[]}}`.

### Step 6: Report

Print a short summary:

- N skills processed
- M added (newly allowlisted)
- K already present (no-op)
- Backup path (from the helper)
- Reminder: tell the user to restart Claude Code if rule changes don't take effect immediately

### Safety notes

- This skill only adds `Skill(<name>)` rules — never `Bash(...)`, `Read(...)`, etc. Skills are instruction text; dangerous operations inside still hit their own permission checks.
- Refuses to add rules that conflict with the `deny` list (handled by the helper).
- Project-local: scope of impact is bounded to this repo's settings, not global.
