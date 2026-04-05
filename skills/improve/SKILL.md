---
name: improve
description: End-of-session retrospective that upgrades skills, fixes codebase gaps, and captures durable knowledge
---

# Improve Skills and Capture Knowledge

Analyze the current conversation to improve skills, fix codebase gaps, and capture durable knowledge in the memory database.

## When to Use

Run `/improve` at the end of any session where:
- Skills were invoked and required manual fixes or workarounds
- You discovered better patterns or approaches mid-conversation
- A skill produced output that needed multiple iterations to get right
- Technical assumptions in a skill turned out to be wrong
- You learned something that would make a skill work better next time
- You hit a codebase gap (missing docs, tests, error handling, or config)

## Context

- Current repo: !`git rev-parse --show-toplevel 2>/dev/null | head -1`
- Skills directory: !`find .claude/skills -maxdepth 2 -name SKILL.md 2>/dev/null | head -30`
- Recent observations: !`echo "SELECT category, observation, confidence FROM observations ORDER BY created_at DESC LIMIT 5" | head -5`

## Instructions

When `/improve` is invoked:

### Step 1: Identify Skills Used

Scan the full conversation for:
- Explicit skill invocations (`/dev`, `/pr`, `/test`, `/debug`, etc.)
- Implicit skill-like patterns (e.g., PDF generation even without `/pdf`, data export workflows)
- CLAUDE.md instructions that were followed or should have been followed
- Recurring manual steps that could be codified into a skill

List each skill used with a brief note on what it did in this session.

**Note:** If improvements were already applied earlier in the same session (e.g., from manual fixes or a prior `/improve` run), skip those and only propose net-new changes.

### Step 2: Extract Learnings per Skill

For each skill identified, analyze:

1. **What worked well** -- smooth execution, no issues
2. **Friction points** -- where did the user need to iterate, correct, or re-run?
3. **Technical discoveries** -- new knowledge about how the underlying tool/script works
4. **Incorrect assumptions** -- anything the skill file says that turned out wrong
5. **Missing capabilities** -- things the user asked for that the skill did not cover

### Step 3: Write the Improvement Report

**Check if Plannotator is available** by looking for `/plannotator-annotate` in the available skills list. The review flow changes depending on whether it's present:

- **With Plannotator:** Write the report to a file, open it for inline annotation review, then apply approved changes.
- **Without Plannotator:** Present the report inline in the conversation, ask which changes to apply (default: all), then apply.

If Plannotator is available, write the full report to `~/.claude/improve-reports/YYYY-MM-DD/improve-report.md`. Structure it for easy annotation — each proposal should be independently reviewable.

If Plannotator is NOT available, you can still write the report to a file for reference, but present the key proposals inline and use `AskUserQuestion` to get approval.

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
**Suggested location:** AI-RON | Global | Project-only
**Why that location:** Classification reasoning

---

## Knowledge to Capture

### 1. Observation title
**Category:** skill-pattern | debugging | architecture | tool-behavior | workflow | people | project-convention
**Confidence:** high | medium | low
**Content:** The durable observation
**Destination:** memory file path or memory-observe MCP call

---
```

**Guidelines for the report:**
- Each proposed change should quote the actual before/after text so Aaron can evaluate without context-switching
- Codebase gaps should only include issues actually encountered, not speculative audits
- Knowledge items should not duplicate CLAUDE.md or existing memory entries
- New skill proposals should include the classification reasoning (Global/AI-RON/Project-only)

### Step 4: Review

**With Plannotator:** Invoke `/plannotator-annotate` on the report file:

```
/plannotator-annotate ~/.claude/improve-reports/YYYY-MM-DD/improve-report.md
```

This lets the user review each proposal with inline comments — approving, rejecting, or modifying individual items without a back-and-forth conversation.

**Without Plannotator:** Present each proposed change as a before/after diff inline. Use `AskUserQuestion` to ask which changes to apply (default: all). For many changes, group them and ask per-section rather than per-item.

### Step 5: Apply Approved Changes

Process the review results (Plannotator annotations or inline answers):

1. **Approved items (no annotation, or explicit approval)** — Apply the change
2. **Items with comments/modifications** — Incorporate the feedback, then apply
3. **Rejected items** — Skip

For each section:
- **Skill improvements** — Edit the skill files with approved changes
- **Codebase gaps** — Apply the approved fixes
- **New skills** — Create the skill files in the approved locations. For each new skill, ask where it should live if not specified in the report:
  - **This project only** — `.claude/skills/<name>/SKILL.md` in current project
  - **AI-RON (version-controlled, local)** — `~/Personal/AI-RON/.claude/skills/<name>/SKILL.md`
  - **Global (via AI-RON)** — AI-RON path AND symlink at `~/.claude/skills/<name>`
- **Knowledge** — Write to memory using the approved destination (memory-observe MCP or auto-memory files)

**Classification guidance for new skills:**
- **Global**: General dev workflows (testing, reviewing, debugging, git operations). No project-specific dependencies.
- **AI-RON**: Personal routines, Supabase memory integration, personal data sources. Depends on AI-RON infrastructure.
- **Project-only**: Workflows specific to the repo being worked in (deploy scripts, project-specific generators, domain logic).

**Memory guidelines:**
- Categories: `skill-pattern`, `debugging`, `architecture`, `tool-behavior`, `workflow`, `people`, `project-convention`
- Do NOT capture: anything already in CLAUDE.md, session-specific transients, operational todos, speculative conclusions, duplicate observations

### Step 6: Summary

After applying changes, present a brief summary of what was done:

```
## Applied
- [skill] /skill-name: change description
- [gap] file: what was fixed
- [new] /skill-name: created at location
- [knowledge] category: observation

## Skipped
- reason for each skipped item
```

## What NOT to Improve

- Do not add session-specific details (specific file paths, query results)
- Do not bloat skills with edge cases that will not recur
- Do not change the fundamental purpose or structure of a skill
- Do not add improvements based on speculation -- only from actual session experience
- Do not recommend changes to plugins (plannotator, pr-review-toolkit, feature-dev, baker_st, chrome-devtools-mcp, etc.). You may name plugin shortcomings and propose local workarounds (wrapper skills, CLAUDE.md instructions, pre/post hooks), but never propose edits to plugin skill files themselves.

## Philosophy: Compounding Improvement

Each `/improve` run should leave the system measurably better than it found it. The goal is not just fixing today's friction -- it is building a system that compounds: each session's learnings reduce friction in all future sessions.

- **Small bets, high frequency** -- Prefer small, targeted changes applied often over large rewrites applied rarely
- **Escalate, do not patch forever** -- If the same skill keeps getting patched, stop patching and restructure
- **Close the loop** -- Check whether past improvements actually helped. Revert what did not.
- **Widen the surface** -- Skills, codebase, knowledge, and the improve process itself are all in scope

**Note:** The `/improve` skill itself is in scope for improvement. If this session revealed friction in the improve workflow, include it in the report.
