---
name: improve
description: Use at the end of a session to run a retrospective — improves the skills you used, fixes gaps you hit in the codebase, and writes down anything durable you learned.
user-invocable: true
---

# Improve: session retrospective

Analyze the current conversation to improve the skills involved, fix gaps the session exposed in the codebase, and capture durable knowledge before the context disappears.

## When to Use

Run `/improve` at the end of any session where:
- A skill needed manual fixes or workarounds to produce the right result
- You discovered a better pattern or approach mid-conversation
- A skill took multiple iterations to get right
- Something a skill file assumed turned out to be wrong
- You hit a gap in the codebase (missing docs, tests, error handling, config)

## Context

- Current repo: !`git rev-parse --show-toplevel 2>/dev/null | head -1`
- Skills directory: !`find .claude/skills -maxdepth 2 -name SKILL.md 2>/dev/null | head -30`

## Instructions

When `/improve` is invoked:

### Step 1: Identify Skills Used

Scan the full conversation for:
- Explicit skill invocations (slash commands)
- Implicit skill-like patterns — a workflow repeated by hand two or three times without a skill backing it
- Project instructions (CLAUDE.md or equivalent) that were followed, or should have been
- Recurring manual steps that could be codified into a new skill

List each one with a brief note on what it did in this session.

**Note:** If improvements were already applied earlier in the same session (from manual fixes or a prior `/improve` run), skip those and only propose net-new changes.

### Step 2: Extract Learnings per Skill

For each skill identified, analyze:

1. **What worked well** -- smooth execution, no issues
2. **Friction points** -- where did the user need to iterate, correct, or re-run?
3. **Technical discoveries** -- new knowledge about how the underlying tool/system actually works
4. **Incorrect assumptions** -- anything the skill file says that turned out wrong
5. **Missing capabilities** -- things the user asked for that the skill did not cover

### Step 3: Write the Improvement Report

Present the report inline in the conversation. If it's long enough to want a stable reference, write it to a scratch file too — but the review itself happens in-conversation via `AskUserQuestion`, not through a separate tool.

The report should contain ALL of the following sections:

```markdown
# Session Improvement Report — YYYY-MM-DD

## Skills Used
1. **/skill-name** — what it did in this session

## Proposed Skill Improvements

### /skill-name — N changes

#### 1. Change title
**Type:** fix | pattern | instruction | troubleshooting
**Why:** What friction this addresses (specific anecdote from session)
**Before:**
> Current text from the skill file (quote the relevant section)

**After:**
> Proposed replacement text

---

## Codebase Gaps Found

### 1. Gap title
**File:** path/to/file (or "new file needed")
**Friction:** How this gap caused problems during the session
**Proposed fix:** Description or diff of the fix

---

## New Skill Proposals

### /proposed-name
**What it does:** Brief description
**Pattern observed:** What happened in the session that suggests this skill
**Suggested location:** Project-only | User-global
**Why that location:** Classification reasoning

---

## Knowledge to Capture

### 1. Observation title
**Confidence:** high | medium | low
**Content:** The durable observation
**Destination:** Where it should live (see Step 5)

---
```

**Guidelines for the report:**
- Each proposed change should quote the actual before/after text so the user can evaluate without context-switching
- Codebase gaps should only include issues actually encountered, not speculative audits
- Knowledge items should not duplicate anything already in a README, CLAUDE.md, or existing notes

### Step 4: Review

Use `AskUserQuestion` to walk through the proposals. Default to applying everything unless told otherwise. For a report with many changes, group them and ask per-section rather than per-item.

### Step 5: Apply Approved Changes

Process the review results:

1. **Approved items** — Apply the change
2. **Items with comments/modifications** — Incorporate the feedback, then apply
3. **Rejected items** — Skip

For each section:
- **Skill improvements** — Edit the skill files with approved changes
- **Codebase gaps** — Apply the approved fixes
- **New skills** — Create `.claude/skills/<name>/SKILL.md`. If the location wasn't already decided in Step 3:
  - **Project-only** — lives in this repo's `.claude/skills/`, nowhere else
  - **User-global** — also copy or symlink to `~/.claude/skills/<name>` so it's available in every project
- **Knowledge** — append it somewhere durable. If the project already has a notes/memory convention, use that. Otherwise append to `.claude/learnings.md` (create it if missing) with a dated heading and a one-line summary. A flat markdown file a human can skim is the right amount of infrastructure for most projects — don't build a database for this.

**Classification guidance for new skills:**
- **User-global**: general workflows with no project-specific dependencies (testing, reviewing, debugging, git operations).
- **Project-only**: workflows specific to this repo (deploy scripts, project-specific generators, domain logic).

### Step 6: Summary

After applying changes, present a brief summary of what was done:

```
## Applied
- [skill] /skill-name: change description
- [gap] file: what was fixed
- [new] /skill-name: created at location
- [knowledge] observation

## Skipped
- reason for each skipped item
```

## What NOT to Improve

- Do not add session-specific details (specific file paths, one-off query results) into a skill meant to be reused
- Do not bloat skills with edge cases that will not recur
- Do not change the fundamental purpose or structure of a skill based on a single session
- Do not propose changes based on speculation -- only from actual session experience
- Do not propose edits to skills or plugins you don't own (third-party or vendored ones). You may name the shortcoming and suggest a local workaround — a wrapper skill, a project instruction, a pre/post step — but never edit their files directly.

## Philosophy: Compounding Improvement

Each `/improve` run should leave the system measurably better than it found it. The goal is not just fixing today's friction -- it is building a system that compounds: each session's learnings reduce friction in all future sessions.

- **Small bets, high frequency** -- Prefer small, targeted changes applied often over large rewrites applied rarely
- **Escalate, do not patch forever** -- If the same skill keeps getting patched, stop patching and restructure
- **Close the loop** -- Check whether past improvements actually helped. Revert what did not.
- **Widen the surface** -- Skills, codebase, and the improve process itself are all in scope

**Note:** The `/improve` skill itself is in scope for improvement. If this session revealed friction in the improve workflow, include it in the report.
