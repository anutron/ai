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
- OpenSpec project: !`test -d openspec && echo "yes" || echo "no"`

---

## Instructions

### 1. Triage (≤30 seconds, main thread)

You are a dispatcher, not a debugger. Do NOT read source code or investigate.

- Parse the user's description
- Run up to 3 `Glob`/`Grep` calls (paths only, no content reads) to locate likely files
- If the description is ambiguous about *what* is broken, echo back a 1-line interpretation and proceed — don't block on clarification
- If the description prescribes a *workflow* (e.g., "via a PR", "via a proper OpenSpec change", "with `--no-verify`", "as drift cleanup", "as a hotfix") and you would otherwise dispatch differently, stop and surface the mismatch to the user before dispatching. Do not silently substitute a different workflow.

#### Pattern-cleanup pre-flight

If the description contains pattern-cleanup keywords ("remove all", "clean up", "drop references to", "delete all", "legacy", "dead", "deprecated"), exceed the 3-call budget once: run a single comprehensive `Grep` for the pattern across the relevant scope (typically the named directory tree). Then surface the full extent to the user before dispatching:

> "You named A; the same pattern exists in B and C. Scope to all three or just A?"

Wait for the user's answer before creating the worktree. Pattern cleanup is the one class of bug where missing the full extent guarantees rework.

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

Before dispatching, do a one-line self-review: "Did I add anything to the agent prompt that the user didn't ask for, or omit anything they did ask for?" If yes, set a `merge_gate=divergence` flag for the completion handler (see Merge gate, below).

Use the `Agent` tool with `run_in_background: true` and `mode: "bypassPermissions"`:

```
## Bug Fix: <title>

### Context
- Main repo root: <$MAIN_REPO>
- Working directory: <worktree path>
- Branch: <SLUG>

### User's Exact Ask
<verbatim copy of $ARGUMENTS — the user's command-line instruction, unedited>

This section is the highest-priority guidance. If anything below conflicts with it (including the Spec-aware project branching), defer to this section.

### Bug Description
<user's description>

### Files Likely Involved
<from triage search, or "Explore the codebase to find the relevant code">

### Spec-aware project
<if openspec/ directory exists at the project root>
This project uses OpenSpec.

**Classify the bug before writing any code:**

- **Code drift** – the spec is correct; the code diverged from it.
- **Spec gap** – the spec does not cover the case this bug exposes; the expected behavior is new or missing.

**Code drift path:**
1. Identify the relevant base spec at `openspec/specs/<capability>/spec.md`
2. Confirm the spec describes the correct behavior the code should follow
3. Fix the code so it matches the existing base spec
4. Write or update a test that validates the correct behavior
5. Run all tests
6. Commit with `--no-verify` (no delta update is needed; include a note in the commit message explaining this is a drift fix, not a new capability)

**Spec gap path:**
1. Identify the capability name from the description, affected files, or failing test
2. Scaffold a change folder: `openspec new change fix-<short-slug>`
3. Write a delta at `openspec/changes/fix-<short-slug>/specs/<capability>/spec.md` that adds or modifies the relevant requirement and at least one scenario
4. Validate: `openspec validate fix-<short-slug> --strict`
5. Write a failing test that captures the new scenario
6. Implement the fix to pass the test
7. Run all tests
8. Commit with the delta file included alongside the code

Either path: include all delta or spec files (if any) in the commit.
</if openspec/ directory exists>
<if no openspec/ directory>
No spec management required. Implement the fix directly.
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

#### Followup capture

Every "out of scope" / "concerns" / "follow-up" item in the agent's report must resolve into one of three outcomes — they cannot be silently dropped:

- **Extend scope** — re-dispatch the agent on the same branch with the additional work (after user approval), OR
- **Capture as task** — call `TaskCreate` to track the followup, OR
- **Explicit won't-fix** — the user reviews and acknowledges the item as out of scope.

Surface the followups to the user as a short list and ask which outcome applies. If anything remains unresolved, set `merge_gate=concerns`.

#### Merge gate

Auto-merge is the default. Hold for one-line user confirmation when any of the following are true:

- `merge_gate=divergence` was set in step 3 (dispatcher prompt diverged from user's literal ask)
- Agent reported `DONE_WITH_CONCERNS`
- `merge_gate=concerns` was set during followup capture (work queued or pending decision)
- Project is OpenSpec (`test -d openspec`) and the fix touched files under `openspec/specs/**/*.md`

When gating, print one summary: "Agent did X, flagged Y, diverged on Z. Merge / extend scope / discard?" and wait for the user's call.

Once both reviews pass and the gate (if any) is cleared:

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
  📋 Specs: <Updated (openspec/changes/<name>/specs/<cap>/spec.md) | No behavioral changes | Code drift fixed | Skipped (no openspec/ dir)>
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
- **Defer to the user's literal workflow** — if their wording prescribes a process (e.g., "via a PR", "via an OpenSpec change", "with `--no-verify`", "as drift cleanup"), follow it. The list is examples, not exhaustive — any prescribed workflow wins over the dispatcher's judgment, including the drift-vs-gap classification embedded in the agent prompt. If the prescribed workflow doesn't make sense for the project, surface that to the user before dispatching.
- **Dispatch and return immediately** — except when a workflow-instruction mismatch or pattern-cleanup scope check requires confirmation (see Triage), or when the merge gate triggers on completion.
- **One bug, one agent, one worktree** — no queues, no sessions
- **Triage search budget**: max 3 Glob/Grep calls plus the pattern-cleanup pre-flight grep when triggered, zero file reads
