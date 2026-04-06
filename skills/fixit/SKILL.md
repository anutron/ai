---
name: fixit
description: Use when the user reports a bug or issue that can be fixed without blocking their current work — backgrounds an agent in a worktree to fix and merge back without breaking stride
---

# Fixit

One-shot background bug fix. Describe the bug, an agent spins up a worktree, fixes it, merges back, and reports what it did.

## Arguments

- `$ARGUMENTS` — **Required.** Natural language description of the bug to fix.

If no arguments provided, reply: `Usage: /fixit <describe the bug>` and stop.

## Context

- Current branch: !`git branch --show-current`
- Project root: !`pwd`
- Main repo root: !`git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //'`
- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`

---

## Instructions

### 1. Triage (≤30 seconds, main thread)

You are a dispatcher, not a debugger. Do NOT read source code or investigate.

- Parse the user's description
- Run up to 3 `Glob`/`Grep` calls (paths only, no content reads) to locate likely files
- If the description is ambiguous, echo back a 1-line interpretation and proceed — don't block on clarification

### 2. Create Worktree

Resolve the main repo root first — fixit may be invoked from inside a worktree. Worktrees must be created relative to the main repo, never nested inside another worktree.

```bash
MAIN_REPO=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')

# Pick a short slug from the bug description
SLUG="fixit-<short-slug>"
git worktree add -b "$SLUG" "$MAIN_REPO/.claude/worktrees/$SLUG" HEAD
```

If the branch already exists, clean up first:
```bash
git worktree remove "$MAIN_REPO/.claude/worktrees/$SLUG" --force 2>/dev/null
git branch -D "$SLUG" 2>/dev/null
```

### 3. Dispatch Background Agent

Use the `Agent` tool with `run_in_background: true` and `mode: "bypassPermissions"`:

```
## Bug Fix: <title>

### Context
- Main repo root: <$MAIN_REPO>
- Working directory: <worktree path>
- Branch: <SLUG>

### Bug Description
<user's description>

### Files Likely Involved
<from triage search, or "Explore the codebase to find the relevant code">

### Spec-Aware Project
<if .specs file exists in project root>
This project uses specs. The spec directory is: <dir from .specs file, default "specs">

**You MUST follow spec-first order:**
1. Find the relevant spec in the specs directory
2. Add the bug's failing case to the spec
3. Write/update a test that reproduces the bug
4. Implement the fix to pass the test
5. Run all tests
6. Commit with message: "Fix: <short description>"

Include the spec file in your commit.
</if .specs file exists>
<if no .specs file>
No spec management required.
</if>

### Debugging References
Read these before investigating:
- `skills/debug/root-cause-tracing.md` — systematic hypothesis-driven debugging
- `skills/debug/defense-in-depth.md` — making fixes robust against related failures

### Instructions
Implementation follows agent-driven-development pattern for a single task. Read `skills/agent-driven-development/SKILL.md`.

1. Explore the codebase to understand the problem (use root-cause-tracing approach)
2. If this is a spec-aware project (see above), follow spec-first order
3. Otherwise: implement the fix directly
4. Follow TDD discipline per `skills/test-driven-development/SKILL.md`
5. Self-review per `skills/verification-before-completion/SKILL.md`
6. Run tests if test infrastructure exists (check Makefile, README, package.json, etc.)
7. Commit with message: "Fix: <short description>"
8. If you can't figure it out, commit nothing and report what you tried
9. Report status: DONE | DONE_WITH_CONCERNS | BLOCKED

### Constraints
- Work ONLY in your worktree directory
- Follow existing codebase patterns
- Keep the fix minimal — don't refactor surrounding code
- If tests fail after your fix, investigate and resolve
- Apply defense-in-depth: make the fix robust, not just sufficient
```

### 4. Confirm to User

Print one line and move on:

```
Fixit dispatched — agent working on "<short title>" in background.
```

Do NOT wait for the agent. Return control to the user immediately.

---

## On Agent Completion

When the background agent reports back:

### Success Path — Two-Stage Review

Before merging, run both reviews from agent-driven-development (see prompt templates in `skills/agent-driven-development/`):

1. **Spec reviewer** — dispatch with `spec-reviewer-prompt.md`. Checks the fix matches spec intent. If issues found, implementer fixes, reviewer re-reviews until clean.
2. **Code quality reviewer** — dispatch with `code-quality-reviewer-prompt.md`. Checks code quality. Same fix/re-review loop.

Spec compliance must pass before code quality review begins.

Once both reviews pass:

```bash
git checkout <original-branch>
git merge <SLUG> --no-edit
```

**If merge succeeds:**
```bash
git worktree remove "$MAIN_REPO/.claude/worktrees/$SLUG" --force
git branch -D "$SLUG"
```

Report to user:
```
✅ Fixit merged: <short title>
  <1-2 line summary of what the agent changed>
  📋 Specs: <Updated (specs/foo.md) | No behavioral change | Skipped (no .specs file)>
```

**If merge conflicts:**
```bash
git merge --abort
```

Report to user:
```
⚠️ Fixit conflict: <short title>
  Worktree preserved at $MAIN_REPO/.claude/worktrees/<SLUG> for manual resolution.
```

### Failure Path

If the agent couldn't fix it:
```bash
git worktree remove "$MAIN_REPO/.claude/worktrees/$SLUG" --force
git branch -D "$SLUG"
```

Report to user:
```
❌ Fixit failed: <short title>
  <brief reason from agent>
```

---

## Rules

- **Never read source code in the main thread** — agents do that
- **Never investigate root causes** — agents do that
- **Never block the user** — dispatch and return immediately
- **One bug, one agent, one worktree** — no queues, no sessions
- **Triage search budget**: max 3 Glob/Grep calls, zero file reads
