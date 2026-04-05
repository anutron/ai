---
name: promote
description: Use when checking which AI-RON skills should be available globally — finds skills not yet promoted and recommends which to symlink to ~/.claude/skills/
---

# Skill Promotion Audit

Find skills in AI-RON that are not yet available globally and recommend whether to promote them.

## Context

- AI-RON skills: !`ls -1 .claude/skills/ 2>/dev/null | head -40`
- Global skills (symlinks): !`ls -la ~/.claude/skills/ 2>/dev/null | grep "^l" | awk '{print $NF, "->", $NF}' | head -40`
- Global skill names: !`ls -1 ~/.claude/skills/ 2>/dev/null | head -40`

## Instructions

### Step 1: Find Unpromoted Skills

Compare the AI-RON skills list against the global symlinks. Identify skills that exist in AI-RON but have no symlink in `~/.claude/skills/`.

### Step 2: Classify Each Unpromoted Skill

For each unpromoted skill, read its SKILL.md and classify it:

**Universal** — Works in any project, no AI-RON-specific dependencies:
- No references to Supabase, memory-query, or AI-RON tables
- No references to specific personal data (Fitbit, Things, Granola)
- No references to AI-RON file paths or project structure
- General-purpose development workflow

**AI-RON-specific** — Depends on AI-RON infrastructure or personal context:
- References memory-query MCP tool or Supabase tables
- References personal routines (daily-rhythm, weekly-rhythm)
- References AI-RON-specific files or directories
- References personal integrations (Nexonia, Fitbit)

**Borderline** — Could be universal with minor changes:
- Has a small AI-RON dependency that could be made optional
- Core logic is universal but has one personal reference

### Step 3: Present Recommendations

Show a table:

```
| Skill | Status | Classification | Recommendation |
|-------|--------|----------------|----------------|
| /skill-name | Not promoted | Universal | Promote |
| /skill-name | Not promoted | AI-RON-specific | Keep local |
| /skill-name | Not promoted | Borderline | Adapt then promote |
```

For borderline skills, explain what would need to change to make them universal.

### Step 4: Promote Approved Skills

After the user selects which skills to promote, create symlinks:

```bash
ln -sf ~/Personal/AI-RON/.claude/skills/<name> ~/.claude/skills/<name>
```

Report the final state of `~/.claude/skills/`.

### Step 5: Verify

Run `ls -la ~/.claude/skills/` to confirm all symlinks are valid and point to the right place.
