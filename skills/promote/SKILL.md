---
name: promote
description: Use when checking which project skills should be available globally — finds skills not yet promoted and recommends which to symlink to ~/.claude/skills/
---

# Skill Promotion Audit

Find skills in this project that are not yet available globally and recommend whether to promote them.

## Context

- Skills directory: !`if [ -d skills ]; then echo "skills/ (repo root)"; elif [ -d .claude/skills ]; then echo ".claude/skills/"; else echo "NOT FOUND"; fi`
- Local skills: !`ls -1 skills/ 2>/dev/null || ls -1 .claude/skills/ 2>/dev/null | head -50`
- Global skills: !`ls -1 ~/.claude/skills/ 2>/dev/null | head -50`

## Instructions

### Step 0: Locate Skills

Skills may live in either `skills/` (at repo root, typical for the claude-skills repo) or `.claude/skills/` (typical for projects that adopted the framework). Check both and use whichever exists. If neither exists, tell the user and stop.

Set `SKILLS_DIR` to the detected path (relative to project root) for all subsequent steps.

### Step 1: Find Unpromoted Skills

Compare the local skills list against `~/.claude/skills/`. A skill is "promoted" if `~/.claude/skills/<name>` exists (as a symlink, directory, or file). List all skills that exist locally but not globally.

If `~/.claude/skills/` doesn't exist, create it:
```bash
mkdir -p ~/.claude/skills
```

### Step 2: Classify Each Unpromoted Skill

For each unpromoted skill, read its SKILL.md and classify it:

**Universal** — Works in any project, no project-specific dependencies:
- No references to project-specific infrastructure (databases, MCP servers, etc.)
- No references to specific personal data or integrations
- No hardcoded project paths
- General-purpose development workflow

**Project-specific** — Depends on this project's infrastructure or personal context:
- References project-specific tools, tables, or services
- References personal routines or integrations
- Contains hardcoded paths to this project

**Borderline** — Could be universal with minor changes:
- Has a small project dependency that could be made optional
- Core logic is universal but has one project-specific reference

### Step 3: Present Recommendations

Show a table:

```
| Skill | Classification | Recommendation |
|-------|----------------|----------------|
| /skill-name | Universal | Promote |
| /skill-name | Project-specific | Keep local |
| /skill-name | Borderline | Adapt then promote |
```

For borderline skills, explain what would need to change to make them universal.

### Step 4: Promote Approved Skills

After the user selects which skills to promote (or says "all"), create symlinks using the detected skills directory:

```bash
ln -sf "$(cd "$SKILLS_DIR/<name>" && pwd)" ~/.claude/skills/<name>
```

Use absolute paths for symlink targets so they work from any working directory.

### Step 5: Verify

Run `ls -la ~/.claude/skills/` to confirm all symlinks are valid and point to the right place.
