---
name: agent-driven-development
description: "Use when executing implementation plans with independent tasks — orchestration pattern for worktree isolation, TDD discipline, and two-stage review. Referenced by execute-plan, fixit, and bugbash."
---

# Agent-Driven Development

A reusable orchestration loop for agent-driven implementation. Skills like `execute-plan`, `fixit`, and `bugbash` reference this pattern rather than defining their own execution mechanics. It combines worktree isolation, TDD discipline, and two-stage review (spec compliance then code quality). Fresh agent per task to prevent context pollution.

## Why This Pattern

Delegating implementation to fresh agents with isolated context produces better results than accumulating work in one long session. The controller curates exactly what each agent needs -- no more, no less. This preserves the controller's own context for coordination while keeping each agent focused.

The two-stage review (spec compliance, then code quality) catches different failure modes: building the wrong thing vs. building the right thing poorly. Both reviews are mandatory, and spec compliance must pass before code quality review begins.

## The Core Loop

For each task in the plan:

1. **Create worktree** -- `.claude/worktree/<task-slug>/`
2. **Dispatch implementer agent** with task context + TDD reference
3. Implementer follows TDD (`skills/test-driven-development/SKILL.md`), self-reviews per verification-before-completion (`skills/verification-before-completion/SKILL.md`)
4. Implementer reports status: `DONE` | `DONE_WITH_CONCERNS` | `NEEDS_CONTEXT` | `BLOCKED`
5. **Handle status** (see Autonomous Execution below)
6. **Dispatch spec reviewer** -- checks implementation matches spec
7. If issues: implementer fixes, spec reviewer re-reviews (loop until clean)
8. **Dispatch code quality reviewer** -- checks implementation is well-built
9. If issues: implementer fixes, quality reviewer re-reviews (loop until clean)
10. **Merge worktree** back to main branch
    - Clean merge: done
    - Textual conflict: controller resolves and runs tests
    - Semantic conflict (tests fail after merge): re-dispatch against updated base
11. **Mark task complete** in native Task system -- dependents auto-unblock

## Task Coordination via Native Tasks

Use `TaskCreate` with `addBlockedBy` to build dependency graphs. The controller creates all tasks upfront from the plan. Tasks become eligible for execution when all their blockers complete.

```
TaskCreate("Update specs", ...)
TaskCreate("Write failing tests", ..., addBlockedBy: [spec-task-id])
TaskCreate("Implement auth module", ..., addBlockedBy: [test-task-id])
TaskCreate("Implement API routes", ..., addBlockedBy: [test-task-id])  <- parallel with above
TaskCreate("Integration tests", ..., addBlockedBy: [auth-id, api-id])
```

This naturally expresses the dependency graph. Independent tasks (auth module and API routes above) become eligible simultaneously and can run in parallel worktrees.

## Worktree-Per-Task Isolation

Every task gets its own worktree at `.claude/worktree/<task-slug>/`. This provides:

- **Maximum parallelism** -- independent tasks run simultaneously without file conflicts
- **Clean rollback** -- if a task fails, delete the worktree, no cleanup needed
- **Isolated state** -- each agent sees a consistent snapshot, not half-finished work from another task

### First-time setup

If `.claude/worktree/` does not exist in the project:

1. Create the directory
2. Add `.claude/worktree/` to the project's `.gitignore` (append if not already present)

### Merge strategy

After an agent completes a task and passes both reviews:

1. Switch to the main working branch
2. Merge the worktree branch
3. If textual conflicts arise, resolve them and run the full test suite
4. If tests fail after merge (semantic conflict), the merge introduced an incompatibility -- re-dispatch the task against the updated base
5. Clean up the worktree branch and directory

## Autonomous Execution

Once execution starts, the controller never asks the user anything. Handle all statuses internally:

- **DONE** -- proceed to spec review
- **DONE_WITH_CONCERNS** -- read the concerns. If they're about correctness or scope, address before review. If they're observations ("this file is getting large"), note them for the final report and proceed to review.
- **NEEDS_CONTEXT** -- provide the missing context from the plan, specs, or codebase and re-dispatch
- **BLOCKED** -- escalation ladder:
  1. Provide more context and re-dispatch with the same model
  2. Re-dispatch with a more capable model
  3. Break the task into smaller pieces
  4. Park the task and note it in the final report

One summary at the end. No mid-execution interruptions.

## Model Selection

Use the least powerful model that can handle each role. This conserves cost and increases speed.

- **Mechanical tasks** (1-2 files, clear spec, isolated function): use `model: "haiku"`
- **Integration tasks** (multi-file coordination, pattern matching, judgment calls): use `model: "sonnet"`
- **Architecture, design, and review tasks**: use the most capable model (default)

### Complexity signals

| Signal | Model |
|--------|-------|
| Touches 1-2 files with complete spec | haiku |
| Touches multiple files with integration concerns | sonnet |
| Requires design judgment or broad codebase understanding | default (most capable) |
| Review roles (spec compliance, code quality) | default (most capable) |

## Parallel Execution

When multiple tasks are unblocked simultaneously (no dependency between them), dispatch them in parallel:

- Each gets its own worktree
- Each gets its own implementer agent
- Reviews can also run in parallel across different tasks
- Merges happen sequentially to avoid conflicts (first-done merges first, subsequent tasks rebase if needed)

The Task system handles this naturally -- when a blocking task completes, all tasks it was blocking become eligible. The controller dispatches all eligible tasks at once.

## Debugging Integration

For bug-fix tasks, the implementer agent should also read:

- `skills/debug/root-cause-tracing.md` -- systematic hypothesis-driven debugging
- `skills/debug/defense-in-depth.md` -- making fixes robust against related failures

Include these references in the implementer's dispatch prompt when the task involves diagnosing or fixing bugs (as opposed to greenfield implementation).

## Prompt Templates

The following prompt templates define agent behavior. The controller provides task-specific context when dispatching each agent.

- `./implementer-prompt.md` -- implementation agent instructions
- `./spec-reviewer-prompt.md` -- spec compliance reviewer instructions
- `./code-quality-reviewer-prompt.md` -- code quality reviewer instructions

## Red Flags

Never:

- Skip reviews (spec compliance or code quality)
- Proceed with unfixed review issues
- Dispatch parallel agents to the same worktree
- Start code quality review before spec compliance passes
- Move to the next task while either review has open issues
- Let implementer self-review replace actual review (both are needed)
- Ignore agent escalations -- if an agent says it's stuck, something needs to change
- Accept "close enough" on spec compliance -- if the reviewer found issues, they must be fixed
- Skip review re-loops -- reviewer found issues means implementer fixes means reviewer re-reviews
- Ask the user questions mid-execution -- handle everything internally, report at the end
- Force the same model to retry without changes when blocked

If a reviewer finds issues:

1. Implementer (same agent) fixes them
2. Reviewer reviews again
3. Repeat until approved

If an agent fails a task:

1. Dispatch a fix agent with specific instructions
2. Do not fix manually in the controller (context pollution)
