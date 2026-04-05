---
name: execute-plan
description: "Use when you have an approved plan ready to implement — executes with agent-driven development, worktree isolation, TDD discipline, two-stage review, and native Task dependencies for parallel execution"
user-invocable: true
---

# Execute Plan

Orchestrate plan execution using the agent-driven-development pattern. The main thread acts as a thin coordinator — parsing the plan into a task dependency graph, dispatching agents in worktrees, and merging results. All implementation, review, and testing happens in agents.

## Arguments

- `$ARGUMENTS` - Required: URL or file path to the plan to execute

If no arguments are provided, find the most recently modified plan in `~/Personal/AI-RON/specs/plans/` and respond with only this message (no other actions):

```
Your plan is ready. Run /clear and then:

/execute-plan <path-to-most-recent-plan>
```

This ensures execution starts with a fresh context window. Do not proceed with execution — just print the message and stop.

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Project root: !`pwd`
- Available plans: !`ls -t ~/Personal/AI-RON/specs/plans/ 2>/dev/null | head -10`

---

## Phase 0: Load and Parse

1. **Resolve the plan source:**
   - If `$ARGUMENTS` is a file path, read it directly
   - If `$ARGUMENTS` is a URL, fetch it with WebFetch
   - If `$ARGUMENTS` is a plan name without path, look in `~/Personal/AI-RON/specs/plans/`

2. **Parse the plan into stages.** Plans typically have numbered sections, phases, or steps. Extract:
   - **Stages**: Ordered list of discrete work chunks
   - **Dependencies**: Which stages depend on others (explicit "depends on stage N" or implicit from ordering)
   - **Scope**: Files, directories, and repos each stage touches

3. **Build a dependency graph.** For each stage, determine:
   - Which other stages must complete first (blockers)
   - Which stages are independent and can run in parallel
   - Dependency signals: explicit mentions ("after stage 2"), shared file scope, or logical ordering (tests before integration)

---

## Phase 1: Create Task Graph

Use native `TaskCreate` with `addBlockedBy` to build the full dependency graph upfront. Every stage becomes a task. Independent stages share no blockers and become eligible simultaneously.

```
TaskCreate("Stage 1: Update specs", ...)
TaskCreate("Stage 2: Write failing tests", ..., addBlockedBy: [stage-1-id])
TaskCreate("Stage 3: Implement auth module", ..., addBlockedBy: [stage-2-id])
TaskCreate("Stage 4: Implement API routes", ..., addBlockedBy: [stage-2-id])  <- parallel with stage 3
TaskCreate("Stage 5: Integration tests", ..., addBlockedBy: [stage-3-id, stage-4-id])
```

Present a brief execution summary:

```
## Execution Plan

Loaded: {plan name/path}
Stages: {N}

1. {Stage name} — {1-line description}
2. {Stage name} — {1-line description} [blocked by: 1]
3. {Stage name} — {1-line description} [blocked by: 2]
4. {Stage name} — {1-line description} [blocked by: 2]  <- parallel with 3
5. {Stage name} — {1-line description} [blocked by: 3, 4]

Parallel opportunities: {which stages can run concurrently}
```

Immediately proceed to execution — do not wait for user approval. The user invoked this skill intentionally.

---

## Phase 2: Execute

For each unblocked task (or group of simultaneously unblocked tasks):

### Worktree Setup

1. Create a worktree at `.claude/worktree/<task-slug>/`
2. If `.claude/worktree/` does not exist yet, create it and add it to `.gitignore`

### Dispatch Implementer

Spawn a fresh agent in the worktree following the agent-driven-development loop. The agent prompt includes:

- The full stage text from the plan
- File scope (what to read, what to create/modify)
- Done criteria extracted from the plan
- Reference to TDD discipline (`skills/test-driven-development/SKILL.md`)
- Reference to self-verification (`skills/verification-before-completion/SKILL.md`)
- For bug-fix stages: reference to `skills/debug/root-cause-tracing.md` and `skills/debug/defense-in-depth.md`

The implementer reports one of: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`.

### Handle Status

Handle all statuses internally per the autonomous execution rules (see below). Never ask the user.

### Two-Stage Review

After the implementer finishes:

1. **Dispatch spec reviewer** — checks implementation matches the plan's intent for this stage. Uses the prompt template at `skills/agent-driven-development/spec-reviewer-prompt.md`.
2. If issues found: implementer fixes, spec reviewer re-reviews. Loop until clean.
3. **Dispatch code quality reviewer** — checks implementation is well-built. Uses the prompt template at `skills/agent-driven-development/code-quality-reviewer-prompt.md`.
4. If issues found: implementer fixes, quality reviewer re-reviews. Loop until clean.

Spec compliance must pass before code quality review begins.

### Merge

After both reviews pass:

1. Switch to the main working branch
2. Merge the worktree branch
3. If textual conflicts: resolve and run the full test suite
4. If tests fail after merge (semantic conflict): re-dispatch the task against the updated base
5. Clean up the worktree branch and directory

### Parallel Execution

Independent tasks (no dependency between them) run in parallel:

- Each gets its own worktree
- Each gets its own implementer agent
- Reviews can also run in parallel across different tasks
- Merges happen sequentially (first-done merges first; subsequent tasks rebase if needed)

### Task Completion

Mark each task complete in the native Task system. Dependents auto-unblock and become eligible for dispatch.

If an agent completed work belonging to a later stage (overlap detected via file diff), mark that later stage as done and skip dispatching it.

---

## Phase 3: Summary

Produce one final report after all tasks complete:

```markdown
## Plan Execution Complete

### Plan
{plan name/path}

### Stages Executed
| # | Stage | Status | Summary |
|---|-------|--------|---------|
| 1 | {name} | Done | {1-line} |
| 2 | {name} | Done | {1-line} |
| 3 | {name} | Parked | {reason} |

### Commits
{git log --oneline for all commits made during execution}

### Quality Notes
{Any DONE_WITH_CONCERNS observations, reviewer feedback worth noting}

### Concerns
{Parked tasks with reasons, blockers that could not be resolved, semantic conflicts encountered}
```

---

## Autonomous Execution

Once execution starts (phases 1-3), the controller never asks the user anything. Handle all statuses internally:

- **DONE** — proceed to spec review
- **DONE_WITH_CONCERNS** — read the concerns. If about correctness or scope, address before review. If observations ("this file is getting large"), note for the final report and proceed to review.
- **NEEDS_CONTEXT** — provide the missing context from the plan, specs, or codebase and re-dispatch
- **BLOCKED** — escalation ladder:
  1. Provide more context and re-dispatch
  2. Re-dispatch with a more capable model
  3. Break the task into smaller pieces
  4. Park the task and note it in the final report

One summary at the end. No mid-execution interruptions.

## Model Selection

Use the least powerful model that can handle each role:

| Signal | Model |
|--------|-------|
| Touches 1-2 files with complete spec | haiku |
| Touches multiple files with integration concerns | sonnet |
| Requires design judgment or broad codebase understanding | default (most capable) |
| Review roles (spec compliance, code quality) | default (most capable) |

---

## Token Conservation

The main thread's job is coordination only:

1. Never read source code files yourself — agents do that
2. Never write or edit code yourself — agents do that
3. Only read: plan files, agent results, git status/log/diff
4. Keep messages to agents detailed so they don't need follow-ups
5. Summarize, don't echo — when reporting results, summarize in 1-2 lines per stage

---

## Reference

Execution follows the agent-driven-development pattern. Read `skills/agent-driven-development/SKILL.md` for the full loop, and dispatch agents using the prompt templates in `skills/agent-driven-development/`.
