---
name: fixit
description: Fire-and-forget bug fix — backgrounds an agent in a worktree to fix a bug and merge it back without breaking your stride.
---

# Fixit

One-shot background bug fix. Describe the bug, an agent spins up a worktree, fixes it, merges back, and reports what it did.

## Arguments

- `$ARGUMENTS` — **Required.** Natural language description of the bug to fix.

If no arguments provided, reply: `Usage: /fixit <describe the bug>` and stop.

## Context

- Current branch: !`git branch --show-current`
- Project root: !`pwd`

---

## Instructions

### 1. Triage (≤30 seconds, main thread)

You are a dispatcher, not a debugger. Do NOT read source code or investigate.

- Parse the user's description
- Run up to 3 `Glob`/`Grep` calls (paths only, no content reads) to locate likely files
- If the description is ambiguous, echo back a 1-line interpretation and proceed — don't block on clarification

### 2. Create Worktree

```bash
# Pick a short slug from the bug description
SLUG="fixit-<short-slug>"
git worktree add -b "$SLUG" ".claude/worktrees/$SLUG" HEAD
```

If the branch already exists, clean up first:
```bash
git worktree remove ".claude/worktrees/$SLUG" --force 2>/dev/null
git branch -D "$SLUG" 2>/dev/null
```

### 3. Dispatch Background Agent

Use the `Agent` tool with `run_in_background: true` and `mode: "bypassPermissions"`:

```
## Bug Fix: <title>

### Context
- Project root: <project root>
- Working directory: <worktree path>
- Branch: <SLUG>

### Bug Description
<user's description>

### Files Likely Involved
<from triage search, or "Explore the codebase to find the relevant code">

### Instructions
1. Explore the codebase to understand the problem
2. Implement the fix
3. Run tests if test infrastructure exists (check Makefile, README, package.json, etc.)
4. Commit with message: "Fix: <short description>"
5. If you can't figure it out, commit nothing and report what you tried

### Constraints
- Work ONLY in your worktree directory
- Follow existing codebase patterns
- Keep the fix minimal — don't refactor surrounding code
- If tests fail after your fix, investigate and resolve
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

### Success Path

```bash
git checkout <original-branch>
git merge <SLUG> --no-edit
```

**If merge succeeds:**
```bash
git worktree remove ".claude/worktrees/$SLUG" --force
git branch -D "$SLUG"
```

Report to user:
```
✅ Fixit merged: <short title>
  <1-2 line summary of what the agent changed>
```

**If merge conflicts:**
```bash
git merge --abort
```

Report to user:
```
⚠️ Fixit conflict: <short title>
  Worktree preserved at .claude/worktrees/<SLUG> for manual resolution.
```

### Failure Path

If the agent couldn't fix it:
```bash
git worktree remove ".claude/worktrees/$SLUG" --force
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
