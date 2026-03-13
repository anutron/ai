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

### Step 3: Propose Improvements

For each skill with learnings, draft specific changes:

- **Fix factual errors** (e.g., wrong library name, outdated API)
- **Add learned patterns** (e.g., "when exporting tables, use proportional column widths")
- **Add missing instructions** (e.g., "can also accept `--input` flag for existing files")
- **Add troubleshooting tips** (e.g., "if tables show whitespace, check for multi_cell usage")
- **Suggest new skills** if a recurring pattern does not have one yet

Present each proposed change as a before/after diff for the user to review.

### Step 4: Apply Improvements

1. Ask the user which changes to apply (default: all)
2. Edit the skill files with the approved changes
3. Summarize what was updated

### Step 5: Fix Codebase Gaps

Review the session for codebase gaps that were discovered or worked around but not fixed. These are issues in the project itself (not in skills):

- **Missing or outdated documentation** -- CLAUDE.md, README sections that are wrong, incomplete, or missing components used during the session
- **Missing tests** -- code paths exercised manually but with no test coverage
- **Missing error handling** -- failures that surfaced because a code path had no guard
- **Configuration gaps** -- env vars, CI steps, linter rules, or build config that caused friction
- **Undocumented patterns** -- conventions the codebase follows implicitly that tripped up work

For each gap found:
1. Describe the gap and how it caused friction
2. Propose a specific fix (as a diff when possible)
3. Apply after user approval

Only fix gaps that were actually encountered during the session. Do not speculatively audit the codebase.

### Step 6: Check for New Skill Opportunities

Look for patterns in the session not covered by any existing skill:
- Multi-step workflows that were done manually
- Recurring command sequences
- Integration patterns with MCP tools or external services

If found, propose a new skill with a brief description of what it would do.

**For each proposed skill, ask the user where it should live:**

1. **This project only** — Skill is specific to the current repo. Write to `.claude/skills/<name>/SKILL.md` in the current project.

2. **AI-RON (version-controlled, local)** — Skill is personal but not universal. Write to `~/Personal/AI-RON/.claude/skills/<name>/SKILL.md`. This keeps it in git but does not make it available in other projects.

3. **Global (via AI-RON)** — Skill is universal and useful everywhere. Write to `~/Personal/AI-RON/.claude/skills/<name>/SKILL.md` AND create a symlink at `~/.claude/skills/<name>` pointing to it. This keeps the source in git while making it available in all projects.

**Classification guidance:**
- **Global**: General dev workflows (testing, reviewing, debugging, git operations). No project-specific dependencies.
- **AI-RON**: Personal routines, Supabase memory integration, personal data sources. Depends on AI-RON infrastructure.
- **Project-only**: Workflows specific to the repo being worked in (deploy scripts, project-specific generators, domain logic).

### Step 7: Capture Knowledge to Memory

Review the session for durable knowledge worth preserving.

**What to capture:**
- Architectural decisions or constraints discovered during this session
- Project-specific patterns (naming conventions, API quirks, deploy procedures)
- Debugging insights (what caused a tricky bug, what the fix was)
- Tool/dependency behavior that was non-obvious
- People, entities, or relationships learned during the session

**How to write observations (in priority order):**

1. **If `memory-observe` MCP tool is available** — use it with the appropriate category and confidence level. This is the preferred method when working in projects with a memory MCP server.

2. **Otherwise — use auto-memory files.** Write to the project's auto-memory directory (typically `~/.claude/projects/<project-path>/memory/MEMORY.md` or topic-specific files like `debugging.md`, `patterns.md`). Use the `Edit` tool to append observations. Check existing content first to avoid duplicates.

Categories: `skill-pattern`, `debugging`, `architecture`, `tool-behavior`, `workflow`, `people`, `project-convention`

**Do NOT capture:**
- Anything already in CLAUDE.md
- Session-specific transients (file paths being worked on, temp state)
- Operational items (todos, plans in progress)
- Speculative conclusions from a single observation
- Information that duplicates existing observations

### Step 8: Summary

Present a final report:

```
# Session Improvement Report

## Skills Used
1. /skill-name -- what it did in this session

## Improvements Applied
### /skill-name -- N changes
1. **Change type: Title** -- description

## Codebase Gaps Fixed
1. **File: description** -- what was fixed

## New Skill Proposals
- /proposed-name -- what it would do

## Knowledge Captured
- [category] observation text (confidence: high/medium/low)
```

## What NOT to Improve

- Do not add session-specific details (specific file paths, query results)
- Do not bloat skills with edge cases that will not recur
- Do not change the fundamental purpose or structure of a skill
- Do not add improvements based on speculation -- only from actual session experience

## Philosophy: Compounding Improvement

Each `/improve` run should leave the system measurably better than it found it. The goal is not just fixing today's friction -- it is building a system that compounds: each session's learnings reduce friction in all future sessions.

- **Small bets, high frequency** -- Prefer small, targeted changes applied often over large rewrites applied rarely
- **Escalate, do not patch forever** -- If the same skill keeps getting patched, stop patching and restructure
- **Close the loop** -- Check whether past improvements actually helped. Revert what did not.
- **Widen the surface** -- Skills, codebase, knowledge, and the improve process itself are all in scope

**Note:** The `/improve` skill itself is in scope for improvement. If this session revealed friction in the improve workflow, include it in the report.
