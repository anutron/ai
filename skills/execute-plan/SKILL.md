---
name: execute-plan
description: Execute a plan with a team of agents, sparing tokens in the main thread by delegating as much as possible. Takes a plan URL or file path as argument.
---

# Execute Plan with Agent Team

Orchestrate a team of agents to execute a plan document. The main thread acts as a thin coordinator — reading the plan, breaking it into stages, and dispatching each stage to an agent. All heavy lifting (code exploration, implementation, testing) happens in agents.

## Prerequisites

Agent teams must be enabled in Claude Code settings:

```
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

If agent teams are not enabled, report: "Agent teams required. Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to your Claude Code settings (env section)." and stop.

## Arguments

- `$ARGUMENTS` - Required: URL or file path to the plan to execute

If no arguments are provided, find the most recently modified plan in `~/.claude/plans/` and respond with ONLY this message (no other actions):

```
Your plan is ready. Run /clear and then:

/execute-plan <path-to-most-recent-plan>
```

This ensures execution starts with a fresh context window. Do NOT proceed with execution — just print the message and stop.

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Project root: !`pwd`
- Available plans: !`ls -t ~/Personal/AI-RON/specs/plans/ 2>/dev/null | head -10`

---

## Phase 0: Load and Parse the Plan

1. **Resolve the plan source:**
   - If `$ARGUMENTS` is a file path → Read it directly
   - If `$ARGUMENTS` is a URL → Fetch it with WebFetch
   - If `$ARGUMENTS` is a plan name without path → Look in `~/Personal/AI-RON/specs/plans/`

2. **Parse the plan into stages.** Plans typically have numbered sections, phases, or steps. Extract:
   - **Stages**: Ordered list of discrete work chunks
   - **Dependencies**: Which stages depend on others (sequential vs parallelizable)
   - **Scope**: Files, directories, and repos each stage touches

3. **Present a brief execution summary to the user:**

   ```
   ## Execution Plan

   Loaded: {plan name/path}
   Stages: {N}

   1. {Stage name} — {1-line description}
   2. {Stage name} — {1-line description}
   ...

   Parallel opportunities: {which stages can run concurrently}
   Estimated agents needed: {count}
   ```

   **Immediately proceed to execution — do not wait for user approval.** The user invoked this skill intentionally; asking "Proceed?" wastes a round-trip.

---

## Phase 1: Execute Stages

For each stage (or group of parallel stages):

### Dispatch to Agent

Spawn an agent using the Agent tool with a detailed prompt containing:

```
## Stage {N}: {Stage Name}

### Context
- Plan: {plan name}
- Working directory: {path}
- Branch: {branch}

### Instructions
{Full text of this stage from the plan}

### Scope
Files to read first: {list from plan}
Files to create/modify: {list from plan}

### Constraints
- Follow existing codebase patterns and conventions
- Run tests after implementation if test infrastructure exists
- Commit completed work with a descriptive message referencing the plan stage
- If you encounter a blocker, report it clearly — do not guess or work around it silently

### Done Criteria
{What "done" looks like for this stage, extracted from the plan}
```

### Coordination Rules

- **Independent stages** → Spawn agents in parallel (multiple Agent calls in one message)
- **Dependent stages** → Wait for the dependency to complete, then spawn the next
- **Large stages** → Use `subagent_type` matching the work (e.g., `"feature-dev:code-architect"` for design, general-purpose for implementation)
- **Main thread stays thin** → Do NOT read implementation files yourself. Only read agent results and git status/diff to verify completion.

### Between Stages

After each agent completes:

1. **Read the agent's result** (returned automatically)
2. **Verify completion:** Run `git status` and `git log --oneline -3` to confirm commits landed
3. **Report progress to user:**
   ```
   ✓ Stage {N}: {name} — Complete
     {1-line summary of what the agent did}
   ```
4. **If the agent reported a blocker:** Present it to the user and ask how to proceed before continuing

---

## Phase 2: Verification

After all stages complete:

1. **Spawn a verification agent** to do a holistic check:

   ```
   Review the recent commits implementing this plan:

   PLAN:
   {full plan text}

   RECENT COMMITS:
   {git log --oneline showing all commits from this session}

   DIFF FROM START:
   {git diff from before execution started}

   Check:
   1. Are all plan stages addressed?
   2. Do the changes match the plan's intent?
   3. Are there any obvious gaps or issues?
   4. Do tests pass?

   Report: list of stages with status (DONE / PARTIAL / MISSING) and any concerns.
   ```

2. **Present the verification results to the user.**

---

## Phase 3: Summary

Produce a final summary:

```markdown
## Plan Execution Complete

### Plan
{plan name/path}

### Stages Executed
| # | Stage | Status | Summary |
|---|-------|--------|---------|
| 1 | {name} | ✓ / ⚠ / ✗ | {1-line} |
| 2 | {name} | ✓ / ⚠ / ✗ | {1-line} |

### Commits
{git log --oneline for all commits made during execution}

### Verification
{verification agent's assessment}

### Issues / Follow-ups
{any blockers, partial completions, or suggested next steps}
```

---

## Failure Handling

| Failure | Action |
|---------|--------|
| Plan file not found | List available plans and ask user to choose |
| Agent fails or errors | Report to user, ask whether to retry or skip |
| Stage produces no commits | Flag as potentially incomplete, ask user |
| Blocker reported by agent | Pause execution, present to user, wait for guidance |
| Git conflicts between parallel agents | Stop parallel execution, resolve conflicts, continue sequentially |

---

## Token Conservation Rules

The main thread's job is **coordination only**. Follow these strictly:

1. **Never read source code files yourself** — agents do that
2. **Never write or edit code yourself** — agents do that
3. **Only read**: plan files, agent results, git status/log/diff
4. **Keep messages to agents detailed** so they don't need to ask follow-ups
5. **Summarize, don't echo** — when reporting agent results to the user, summarize in 1-2 lines per stage
