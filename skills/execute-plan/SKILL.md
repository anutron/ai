---
name: execute-plan
description: "Use when an OpenSpec change is approved and ready to implement — executes the change's tasks.md with agent-driven development, worktree isolation, TDD discipline, two-stage review, native Task dependencies for parallel execution, and `openspec archive` at the end."
user-invocable: true
---

# Execute Plan (OpenSpec change)

Orchestrate execution of an approved OpenSpec change. The main thread acts as a thin coordinator — loading the change folder, parsing `tasks.md` into a task dependency graph, dispatching agents in worktrees, merging results, and archiving the change at the end. All implementation, review, and testing happens in agents.

## Arguments

- `$ARGUMENTS` – Required: the OpenSpec change NAME (kebab-case identifier, not a file path). Example: `/execute-plan add-fitbit-mcp-server`.

If no arguments are provided, find the most recently created in-flight change with `openspec list --changes --json` and respond with only this message (no other actions):

```
Your change is ready. Run /clear and then:

/execute-plan <change-name>
```

This ensures execution starts with a fresh context window. Do not proceed with execution — just print the message and stop.

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Project root: !`pwd`
- In-flight changes: !`openspec list --changes --json 2>/dev/null | head -200`

## Prerequisites

This skill is OpenSpec-only. The target project MUST have an `openspec/` directory. The named change MUST exist at `openspec/changes/<name>/`. If either check fails, exit with a clear error pointing the user at `/brainstorm` (to create the change) or `/migrate-to-openspec` (if a legacy `.specs` system is still in place).

---

## Phase 0: Load and parse the change

1. **Resolve the change.** Treat `$ARGUMENTS` as a kebab-case change name. Verify `openspec/changes/<name>/` exists. If not, list nearby names from `openspec list --changes --json` and exit with a suggestion.

2. **Load the change as JSON:**

   ```
   openspec show <name> --json
   ```

   Capture proposal, design, tasks, and the delta specs. These are the source of truth for what is being built.

3. **Validate the change before execution:**

   ```
   openspec validate <name> --strict
   ```

   If validation fails, surface the errors and stop. Do not execute against an invalid change.

4. **Read `design.md`.** The design doc captures architecture, decisions, alternatives, and risks. Agents need this alongside the deltas and tasks to make good implementation decisions.

5. **Read the delta specs** at `openspec/changes/<name>/specs/<capability>/spec.md`. Each scenario in the deltas becomes a candidate failing test in Stage 1.

6. **Parse `tasks.md` into stages.** OpenSpec tasks files use this structure:

   ```markdown
   ## 1. Tests

   - [ ] 1.1 Write failing tests from each scenario...
   - [ ] 1.2 ...

   ## 2. <First vertical slice>

   **Depends on:** Stage 1

   - [ ] 2.1 ...

   ## 3. <Next vertical slice>

   **Depends on:** Stage 1

   - [ ] 3.1 ...   <!-- parallel with stage 2 -->
   ```

   Both `## N. <name>` (canonical, emitted by `/brainstorm`) and `## Phase N: <name>` (legacy / hand-written) headings are accepted as stage boundaries. Phase-style files often omit the explicit `**Depends on:**` lines — that's fine; fall back to numerical ordering for those (Stage N depends on Stage N-1).

   Each H2 group is one stage. Extract:

   - **Stages**: ordered list of discrete work chunks (one per H2 group).
   - **Dependencies**: the `**Depends on:** Stage N[, Stage M]` line under each H2. If absent, infer from numerical order (Stage N depends on Stage N-1).
   - **Scope**: files, directories, and capabilities each stage touches (extract from the checkbox descriptions).

7. **Build a dependency graph.** For each stage, determine:

   - Which other stages must complete first (blockers from `**Depends on:**`)
   - Which stages are independent and can run in parallel (same blocker set, no shared files)
   - Stage 1 (tests) is always the foundation; everything else depends on at least Stage 1

---

## Worktree decision

Inspect the dependency graph from Phase 0 step 7. **If any stages share a blocker set** (siblings — multiple stages with the same `**Depends on:**` and no shared files, eligible to run concurrently), worktree mode is required. Notify the user, don't ask:

> **This change has parallel-eligible stages: <list>. Running in worktree mode at `.claude/worktree/<name>/` so they can execute concurrently.**

If the dependency graph is **fully sequential** (each stage depends only on the previous one), ask:

> **How do you want to run this change?**
>
> - **Execute on current branch** (recommended) — stages run here, commits land on this branch as they complete.
> - **Execute in a worktree** — creates an isolated branch so you can keep working or run another agent in this session.

Default to "current branch" for sequential changes if the user doesn't have a preference. The branch name should match the change name (`<name>`) wherever possible — this is the convention `/save-w-specs` and the pre-commit hook use to identify the active change.

When worktree mode is in effect (either auto-selected for parallel changes or chosen by the user):

1. Create a worktree at `.claude/worktree/<name>/` for the overall execution.
2. All per-stage worktrees nest inside that (`.claude/worktree/<name>/<task-slug>/`).
3. After all stages complete and merge to the worktree's branch, present the result for the user to merge back to their original branch (via `/close-worktree` or manual merge).

**Why current-branch mode can't parallelize:** it has one working directory. Two implementer agents writing to the same tree would clobber each other. Worktrees give each agent isolated state — the only way parallel-eligible stages actually run in parallel.

---

## Phase 1: Create task graph

Use native `TaskCreate` with `addBlockedBy` to build the full dependency graph upfront. Every stage from `tasks.md` becomes a task. Independent stages share no blockers and become eligible simultaneously.

```
TaskCreate("Stage 1: Write failing tests", ...)
TaskCreate("Stage 2: Implement auth module", ..., addBlockedBy: [stage-1-id])
TaskCreate("Stage 3: Implement API routes", ..., addBlockedBy: [stage-1-id])  <- parallel with Stage 2
TaskCreate("Stage 4: Integration tests", ..., addBlockedBy: [stage-2-id, stage-3-id])
```

Present a brief execution summary:

```
## Execution Plan

Change: <name>
Capabilities touched: <comma-separated from deltas>
Design doc: openspec/changes/<name>/design.md
Tasks: openspec/changes/<name>/tasks.md
Stages: <N>

1. {Stage name} — {1-line description}
2. {Stage name} — {1-line description} [blocked by: 1]
3. {Stage name} — {1-line description} [blocked by: 1]  <- parallel with 2
4. {Stage name} — {1-line description} [blocked by: 2, 3]

Parallel opportunities: {which stages can run concurrently}
```

After the worktree decision (see above), proceed to execution — do not wait for additional approval. The user invoked this skill intentionally.

---

## Phase 2: Execute

For each unblocked task (or group of simultaneously unblocked tasks):

### Worktree setup

1. Create a worktree at `.claude/worktree/<task-slug>/` (or nested under the per-change worktree if worktree mode was chosen).
2. If `.claude/worktree/` does not exist yet, create it and add to `.gitignore`.

### Dispatch implementer

Spawn a fresh agent in the worktree following the agent-driven-development loop. The agent prompt includes:

- The full stage text from `tasks.md` (the H2 group + its checkbox items)
- The full `design.md` contents — agents need both architecture context and execution detail
- The relevant delta spec(s) at `openspec/changes/<name>/specs/<capability>/spec.md` — these are the behavioral contract; scenarios are the test list
- File scope (what to read, what to create/modify, derived from the stage's checkbox descriptions)
- Done criteria for the stage (all checkboxes in the H2 group complete; for Stage 1, all scenario tests fail in the expected way)
- Reference to TDD discipline (`skills/test-driven-development/SKILL.md`)
- Reference to self-verification (`skills/verification-before-completion/SKILL.md`)
- For bug-fix stages: reference to `skills/debug/root-cause-tracing.md` and `skills/debug/defense-in-depth.md`

The implementer reports one of: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`.

### Handle status

Handle all statuses internally per the autonomous execution rules (see below). Never ask the user.

### Review (with test-only fast-path)

**Implementer self-verification runs first, regardless of stage type.** Before reporting `DONE`, the implementer must run the project's linter and test suite (per `verification-before-completion`) and include the captured output in their result. Lint and trivial test failures must never reach review — they're cheap to catch in the implementer's own loop.

**Test-only stages** — stages that produce only test files (no production code). Detect by either:

- The stage is the canonical "## 1. Tests" section, OR
- The implementer's diff touches only test-like paths (`*_test.go`, `**/spec/**`, `**/__tests__/**`, `**/*.test.{ts,tsx,js,jsx}`, `**/test_*.py`, `**/tests/**`, etc.)

For test-only stages, run **one combined review pass** that covers both spec compliance and test correctness:

1. Dispatch a single reviewer with the spec-reviewer prompt PLUS instructions to also flag test-correctness issues (wrong assertions, missing edge cases that the deltas imply, misuse of test fixtures, brittle setup) and obvious structural problems (duplicated test bodies, hard-coded values that should be derived from the scenario).
2. Verify every scenario in the relevant delta has a corresponding test.
3. Verify the tests fail in the expected way (not from import errors, syntax errors, or fixture wiring problems — they should fail because the production code doesn't yet implement the behavior).
4. If issues found: implementer fixes, reviewer re-reviews. **Cap at one fix loop** for test-only stages — if the second pass still has blocking issues, escalate (per the BLOCKED ladder) rather than looping further. Test code that's still wrong after one fix is a signal the deltas themselves are unclear; surface it.
5. Skip the separate code quality reviewer entirely.

Rationale: test code with no production code to validate against has limited "quality" surface. The cheap stuff (lint, syntax) is caught by implementer self-verification; the substantive stuff (scenario coverage, correctness, structure) is caught by the combined pass. Two full review cycles before any production code lands is over-rotated.

**All other stages** — full two-stage review:

1. **Dispatch spec reviewer** — checks implementation matches the change's deltas (every scenario in the relevant delta has a corresponding passing test, behavior matches `**WHEN**`/`**THEN**`). Uses `skills/agent-driven-development/spec-reviewer-prompt.md`. Provide the delta specs and the design doc as inputs.
2. If issues found: implementer fixes, spec reviewer re-reviews. Loop until clean.
3. **Dispatch code quality reviewer** — checks implementation is well-built. Uses `skills/agent-driven-development/code-quality-reviewer-prompt.md`.
4. If issues found: implementer fixes, quality reviewer re-reviews. Loop until clean.

Spec compliance must pass before code quality review begins.

### Update `tasks.md` checkboxes

After both reviews pass for a stage, the implementer (or controller, if simpler) checks the corresponding `- [ ]` items off in `openspec/changes/<name>/tasks.md` (`- [ ]` → `- [x]`). The pre-commit hook expects deltas to travel with code; the tasks file ticks travel separately and document progress.

### Merge

After both reviews pass:

1. Switch to the main working branch (or the per-change worktree branch in worktree mode)
2. Merge the per-stage worktree branch
3. If textual conflicts: resolve and run the full test suite
4. If tests fail after merge (semantic conflict): re-dispatch the task against the updated base
5. Clean up the per-stage worktree branch and directory

### Parallel execution

Independent tasks (no dependency between them) run in parallel:

- Each gets its own worktree
- Each gets its own implementer agent
- Reviews can also run in parallel across different tasks
- Merges happen sequentially (first-done merges first; subsequent tasks rebase if needed)

### Task completion

Mark each task complete in the native Task system. Dependents auto-unblock and become eligible for dispatch.

If an agent completed work belonging to a later stage (overlap detected via file diff), mark that later stage as done and skip dispatching it. Update the corresponding `tasks.md` checkboxes.

---

## Phase 3: Validate the integrated change

After every stage's task is complete and merged:

1. Run the project's full test suite. All scenario-derived tests must pass.
2. Run `openspec validate <name> --strict`. Must pass.
3. Confirm every checkbox in `openspec/changes/<name>/tasks.md` is `- [x]`. Any unchecked item is a parked task.

If anything fails, route the failure back into Phase 2 (re-dispatch the affected stage with the failure as new context).

---

## Phase 4: Quality gates

Before archiving, offer quality checks via `AskUserQuestion`:

> "Change `<name>` ready. Run quality checks before archiving?"

Options:

- **Both** (recommended) — run `/ralph-review` and `/spec-audit`. Ralph reviews against the active deltas; ralph closes the gate (archives) when done.
- **Ralph-review only** — autonomous review loop against active deltas. Ralph closes the gate when done.
- **Spec-audit only** — audit spec coverage. Execute-plan closes the gate after.
- **Done** — skip checks. Execute-plan closes the gate immediately.

Handoff logic:

- **Both / Ralph-review only**: invoke `/ralph-review`. Ralph owns the rest of the flow — it runs the review loop, addresses findings, and archives the change at its Done step. Stop here. Do not proceed to Phase 5 or Phase 6. If "Both" was chosen, also dispatch `/spec-audit` in parallel before handing off.
- **Spec-audit only**: run it, then proceed to Phase 5.
- **Done**: proceed to Phase 5.

Quality gates are token-heavy, so opt-in — but offering them while the change is still active (deltas intact, reviewable) makes them actually usable.

---

## Phase 5: Archive the change

Skipped if the user chose ralph-review in Phase 4 — ralph closes the gate.

Otherwise:

```
openspec archive <name> --yes
```

This:

- Merges the change's deltas (`openspec/changes/<name>/specs/<capability>/spec.md`) into the base specs at `openspec/specs/<capability>/spec.md`.
- Removes the change folder.
- For doc-only or infrastructure-only changes that intentionally have no spec deltas, pass `--skip-specs`.

After archiving, run `openspec validate --all --strict` to confirm the merged base specs are still valid.

If the archive fails (e.g. validation errors when merging deltas), surface the error, fix the deltas, re-run, and continue.

---

## Phase 6: Summary

Skipped if ralph-review took over — ralph produces its own completion summary.

Otherwise, produce one final report after archiving:

```markdown
## Change Execution Complete

### Change

`<name>` — archived

### Capabilities touched

- `<capability-1>` — <ADDED | MODIFIED | REMOVED requirements summary>
- `<capability-2>` — ...

### Stages executed

| # | Stage | Status | Summary |
|---|-------|--------|---------|
| 1 | {name} | Done | {1-line} |
| 2 | {name} | Done | {1-line} |
| 3 | {name} | Parked | {reason} |

### Commits

{git log --oneline for all commits made during execution}

### Quality notes

{Any DONE_WITH_CONCERNS observations, reviewer feedback worth noting}

### Concerns

{Parked tasks with reasons, blockers that could not be resolved, semantic conflicts encountered}
```

---

## Autonomous execution

Once execution starts (Phases 1-4), the controller never asks the user anything. Handle all statuses internally:

- **DONE** — proceed to spec review.
- **DONE_WITH_CONCERNS** — read the concerns. If about correctness or scope, address before review. If observations ("this file is getting large"), note for the final report and proceed to review.
- **NEEDS_CONTEXT** — provide the missing context from the design, deltas, or codebase and re-dispatch.
- **BLOCKED** — escalation ladder:
  1. Provide more context and re-dispatch.
  2. Re-dispatch with a more capable model.
  3. Break the task into smaller pieces.
  4. Park the task and note it in the final report. Do not auto-archive a change with parked tasks — surface them and let the user decide.

One summary at the end. No mid-execution interruptions — except the quality gate offer after the summary (see Phase 6).

## Model selection

Use the least powerful model that can handle each role:

| Signal | Model |
|--------|-------|
| Touches 1-2 files with complete deltas | haiku |
| Touches multiple files with integration concerns | sonnet |
| Requires design judgment or broad codebase understanding | default (most capable) |
| Review roles (spec compliance, code quality) | default (most capable) |

---

## Token conservation

The main thread's job is coordination only:

1. Never read source code files yourself — agents do that.
2. Never write or edit code yourself — agents do that.
3. Only read: `openspec show` JSON, `tasks.md`, `design.md`, deltas, agent results, git status/log/diff.
4. Keep messages to agents detailed so they don't need follow-ups.
5. Summarize, don't echo — when reporting results, summarize in 1-2 lines per stage.

---

## Reference

Execution follows the agent-driven-development pattern. Read `skills/agent-driven-development/SKILL.md` for the full loop, and dispatch agents using the prompt templates in `skills/agent-driven-development/`.

The change's tasks.md IS the plan — there is no separate plan file. The deltas at `openspec/changes/<name>/specs/<capability>/spec.md` are the behavioral contract that reviewers compare implementation against. The `design.md` carries architecture and rationale. Together they replace the legacy `specs/docs/<date>-<topic>/{brainstorm,plan}.md` pair.
