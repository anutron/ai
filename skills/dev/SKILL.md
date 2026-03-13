---
name: dev
description: Multi-agent iterative development with parallel testing and code review. Use for substantial implementation tasks.
---

# Iterative Development with Agent Team

Orchestrate a team of agents to implement code, run tests, and review changes in parallel -- iterating until clean. Teammates communicate directly with each other for faster feedback loops.

## Prerequisites

Agent teams must be enabled in Claude Code settings:

```
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

If agent teams are not enabled, report: "Agent teams required. Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to your Claude Code settings (env section)." and stop.

## Arguments

- `$ARGUMENTS` - Required: description of the development task to implement

If no arguments are provided, ask the user what they want to build.

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Project root: !`pwd`
- Project type: !`find . -maxdepth 1 \( -name go.mod -o -name Gemfile -o -name package.json -o -name Cargo.toml -o -name pyproject.toml -o -name setup.py -o -name requirements.txt -o -name Makefile \) 2>/dev/null | head -5`
- Recent commits: !`git log --oneline -5`
- Test files: !`find . -maxdepth 4 -name "*_test.*" -o -name "*.test.*" -o -name "*_spec.*" -o -name "test_*" 2>/dev/null | head -10`
- SPEC files: !`find . -path "*/specs/*.md" 2>/dev/null | head -10`
- CLAUDE.md: !`head -5 CLAUDE.md 2>/dev/null | head -5`

## Overview

You are the **lead coordinator** for a multi-agent development team. Your job is to orchestrate an iterative cycle: plan, implement, test, review, iterate.

**Task to implement:** $ARGUMENTS

You do NOT write code yourself. You coordinate teammates, route feedback, and produce the final summary.

**Team philosophy:** Teammates talk to each other directly -- not everything goes through the lead. The reviewer validates the implementer's plan before coding starts. The reviewer asks the tester to verify suspected bugs. During iterations, the tester and reviewer send feedback directly to the implementer. The lead monitors, consolidates, and decides when to stop.

---

## Phase 0: Setup and Plan Approval

1. **Clean working tree:** If there are uncommitted changes, commit them with message `"WIP: pre-dev-session state"` before proceeding. This ensures clean diffs during the session.

2. **Parse the task** from `$ARGUMENTS`. If unclear, ask the user for clarification before proceeding.

3. **Detect the project context** from the Context section above:
   - Language/framework (Rails, Next.js, Python, Node, Go, etc.)
   - Test framework (rspec, jest, pytest, etc.)
   - Build tool (bundle, yarn, npm, pip, etc.)
   - Linter (rubocop, eslint, ruff, etc.)

4. **Check for existing SPECs.** If the project has a `specs/` directory:
   - Read any SPEC files related to the task
   - The SPEC is the source of truth for behavior -- the implementation must conform to it
   - If no relevant SPEC exists and the project uses SPEC-driven development (check CLAUDE.md), create one and present it for approval before proceeding

5. **Explore the codebase** to understand relevant code, patterns, and conventions. Read key files related to the task. Understand the existing architecture before proposing changes.

6. **Present a plan to the user for approval.** Based on your exploration, write a concrete implementation plan and present it for the user to review. The plan must include:

   - **Goal:** One-sentence summary of the task.
   - **Approach:** How you intend to solve it (strategy, patterns to follow).
   - **Files to change:** List each file that will be created, modified, or deleted, with a brief description of the change.
   - **Testing strategy:** What tests will be added or run.
   - **Risks / trade-offs:** Anything the user should be aware of.

   **Wait for the user to approve the plan before proceeding.** If the user requests changes, revise and re-present until approved. Do NOT create the team or spawn agents until the user approves.

7. **Create the team** (clean up stale session first if needed):
   ```
   TeamDelete() -- ignore if no existing team
   TeamCreate(team_name: "dev-session", description: "Iterative dev: {brief task summary}")
   ```

8. **Create the task list** with TaskCreate:
   - "Plan: {task}" -- for implementer
   - "Validate plan" -- for reviewer, blocked by plan
   - "Implement: {task}" -- for implementer, blocked by plan validation
   - "Test implementation" -- for tester, blocked by implementation
   - "Code review" -- for reviewer, blocked by implementation

9. **Spawn all 3 teammates** in a single message with 3 Task tool calls. Use the agent briefings below for each teammate's prompt. Use `model: "sonnet"` for the tester. Include the approved plan in the implementer's briefing so they can skip redundant exploration.

10. **Initialize state:**
   ```
   iteration_round = 0
   max_rounds = 3
   ```

---

## Phase 1: Planning

Send the task and the user-approved plan to the implementer via SendMessage:

```
TASK: {full task description from $ARGUMENTS}

PROJECT CONTEXT:
- Language: {detected language}
- Framework: {detected framework}
- Test framework: {detected test framework}
- Build: {detected build tool}
- Lint: {detected linter}

EXISTING SPEC (if any):
{contents of relevant SPEC file, or "None"}

APPROVED PLAN (already approved by the user):
{the plan approved in Phase 0, step 6}

INSTRUCTIONS:
1. Review the approved plan. You may refine implementation details, but the overall approach is set.
2. Send a brief implementation plan (specific code-level details) DIRECTLY to the reviewer for validation.
3. Wait for the reviewer's feedback before implementing.

Mark the "Plan" task as completed once your plan is sent.
```

**Wait** for the reviewer to validate the plan. The reviewer will message both the implementer and the lead with their verdict.

If the reviewer raises concerns, the lead tells the implementer to revise. Once the reviewer approves, proceed.

---

## Phase 2: Implementation

Send the go-ahead to the implementer via SendMessage:

```
Plan approved. Proceed with implementation.

INSTRUCTIONS:
1. Implement the changes following your approved plan.
2. Follow existing conventions in the codebase.
3. Run a basic sanity check: compile, lint, or syntax check if applicable.
4. When done, message me (the lead) AND the tester with:
   - Files changed (created/modified/deleted)
   - Summary of your approach
   - Any concerns or trade-offs you chose

Mark the "Implement" task as completed when done.
```

While the implementer works, send the tester a heads-up:

```
The implementer is working on: {brief task summary}

Their plan: {approved plan summary}

While you wait, explore the existing test suite to understand patterns, frameworks, and conventions. Be ready to run tests and write new ones as soon as the implementer finishes.

IMPORTANT: When writing new tests, create NEW test files rather than modifying files the implementer touched, to avoid conflicts.
```

**Wait** for the implementer to report back before proceeding.

---

## Phase 3: Parallel Testing and Review

Once the implementer finishes:

1. **Gather the changes:**
   - Run `git diff` to capture the full diff
   - Run `git diff --name-only` to list changed files
   - Read each changed file for full context

2. **Send review requests to BOTH agents simultaneously** via SendMessage:

### To tester:

```
Implementation complete. Here are the changes:

CHANGED FILES: {list}
DIFF:
{full git diff}

INSTRUCTIONS:
1. Run the existing test suite. Report pass/fail.
2. If tests fail, report which tests and why.
3. Identify changed code paths that lack test coverage.
4. Write new tests in NEW files (do not modify files the implementer changed).
5. Run all tests again and report final results.
6. The reviewer may also message you directly to write targeted tests for suspected bugs. Prioritize those.

Report to me (the lead) with:
- Test results: PASS or FAIL (with details)
- New tests written (if any)
- Coverage observations

Mark your task as completed.
```

### To reviewer:

```
TASK DESCRIPTION: {task}

CHANGED FILES WITH CONTENTS:
{file contents}

DIFF:
{full git diff}

Review the changes against ALL of the following checklists.

SECURITY:
- [ ] Injection flaws (SQL, command, XPath)
- [ ] Authentication/authorization issues
- [ ] Sensitive data exposure (secrets, PII, credentials in code or logs)
- [ ] Input validation and sanitization
- [ ] Cross-site scripting (XSS) potential
- [ ] Insecure deserialization
- [ ] Known vulnerable dependencies added
- [ ] Error handling exposing internals (stack traces, DB info)

ARCHITECTURE:
- [ ] Single Responsibility Principle -- does each unit do one thing?
- [ ] Separation of concerns -- are layers/boundaries respected?
- [ ] Coupling -- is it as loose as practical?
- [ ] Cohesion -- are related things grouped together?
- [ ] Consistency with existing codebase patterns
- [ ] Error handling strategy -- consistent with the rest of the project?
- [ ] No circular dependencies introduced

CLARITY:
- [ ] Function/method names clearly describe what they do
- [ ] Variable names are descriptive
- [ ] Comments where logic is non-obvious (but no redundant comments)
- [ ] Cyclomatic complexity -- any function doing too much?
- [ ] Dead code or unreachable branches
- [ ] Magic numbers/strings that should be named constants
- [ ] Consistent code style with the rest of the codebase

For each finding, classify as:
- BLOCKING: Must fix before this code ships
- WARNING: Should fix, real but lower risk
- INFO: Suggestion for improvement

IMPORTANT: If you suspect a specific bug (nil dereference, race condition, off-by-one, etc.), message the tester DIRECTLY and ask them to write a targeted test to prove or disprove it. Do not just flag it -- get evidence.

If no issues found, say so explicitly.

Report your findings to me (the lead). Mark your task as completed.
```

**Wait** for both agents to report back.

---

## Phase 4: Feedback Consolidation

Collect all reports and organize:

### BLOCKING Issues (must fix)
List each with: category (security/architecture/clarity), file, line/location, description.

### Test Results
- Status: PASS / FAIL
- Failures: list if any
- New tests: list if any

### WARNINGS (should address)
List each with: category, file, description.

### SUGGESTIONS (nice to have)
List each with: category, description.

### Decision Point

```
IF no BLOCKING issues AND tests PASS:
  → Proceed to Phase 6 (done)

IF BLOCKING issues exist AND iteration_round < max_rounds:
  → Proceed to Phase 5 (iteration)

IF iteration_round >= max_rounds:
  → Proceed to Phase 6 with remaining issues noted
```

---

## Phase 5: Iteration

```
iteration_round += 1
```

1. **Create iteration tasks:**
   - "Address feedback (round {N})" -- for implementer
   - "Re-test (round {N})" -- for tester

2. **Send consolidated feedback directly to the implementer AND the tester simultaneously:**

### To implementer:

```
ITERATION ROUND: {N} of {max_rounds}

BLOCKING ISSUES (fix these first):
{numbered list with category, file, line, description}

WARNINGS (address if straightforward):
{numbered list}

TEST FAILURES (if any):
{details}

Fix the blocking issues. Address warnings if they are quick wins.
When done, message me (the lead) AND the tester with your changes.
```

### To tester:

```
ITERATION ROUND {N}: The implementer is fixing these issues:
{brief summary of blocking issues and test failures}

Wait for the implementer to finish, then re-run the full test suite.
Report results to me (the lead).
```

3. **After implementer completes and tester re-tests:** Gather the new diff.
   - Only re-run the reviewer if it had BLOCKING issues (skip if clean)

4. **Return to Phase 4.**

---

## Phase 6: Shutdown and Summary

1. **Shut down all teammates:**
   ```
   For each of [implementer, tester, reviewer]:
     SendMessage(type: "shutdown_request", recipient: {name}, content: "Work complete. Shutting down.")
   ```
   Wait for confirmations.

2. **Clean up the team** with TeamDelete.

3. **Produce the final summary:**

```markdown
## Development Summary

### Task
{original task description}

### Changes Made
| File | Action | Description |
|------|--------|-------------|
| path/to/file | created/modified/deleted | brief description |

### Test Results
- **Status:** PASS / FAIL / N/A
- **New tests written:** {count} -- {brief descriptions}
- **Coverage notes:** {observations from tester}

### Review Sign-off

| Category | Status | Key Notes |
|----------|--------|-----------|
| Security | APPROVED / CONCERNS | {1-line summary} |
| Architecture | APPROVED / CONCERNS | {1-line summary} |
| Clarity | APPROVED / CONCERNS | {1-line summary} |

### Iterations
- **Rounds completed:** {N}
- **Key feedback addressed:** {brief summary of what changed between rounds}

### Remaining Items
{Any unresolved warnings/suggestions, or "None -- all clear"}

### Diff
{git diff --stat output}
```

---

## Agent Briefing Templates

When spawning teammates in Phase 0, use these prompts:

### Implementer

```
You are the IMPLEMENTER on a development team. You write code.

YOUR TEAMMATES:
- Lead: coordinates the team. Sends you tasks and consolidates feedback.
- Reviewer: reviews your plan and code. You send your plan directly to them.
- Tester: runs tests and writes new ones. You notify them when you finish coding.

WORKFLOW:
1. You will receive a task from the lead.
2. Explore the codebase and draft a plan.
3. Send your plan DIRECTLY to the reviewer (not the lead) for validation.
4. Wait for the reviewer's approval, then implement.
5. When done, message BOTH the lead AND the tester with your changes.

During iterations, you may receive feedback from the lead with issues to fix.
Address blocking issues first, then warnings.

Always use TaskUpdate to mark tasks completed.
```

### Tester

```
You are the TESTER on a development team. You ensure code works correctly.

YOUR TEAMMATES:
- Lead: coordinates the team. Sends you review requests.
- Implementer: writes the code. Will message you when changes are ready.
- Reviewer: reviews code quality. May message you directly to write targeted tests for suspected bugs -- prioritize those requests.

WORKFLOW:
1. You will get a heads-up about the task while the implementer works. Use this time to explore the existing test suite.
2. When the implementer finishes, run the full test suite.
3. Write new tests in NEW files (avoid modifying files the implementer touched).
4. If the reviewer messages you with a suspected bug, write a targeted test for it and report results back to the reviewer AND the lead.
5. Report results to the lead.

Be specific: report exact test names, failure messages, and line numbers.

Always use TaskUpdate to mark tasks completed.
```

### Reviewer

```
You are the CODE REVIEWER on a development team. You review for security, architecture, and clarity.

YOUR TEAMMATES:
- Lead: coordinates the team. Sends you code to review.
- Implementer: writes the code. They will send you their plan for early validation.
- Tester: runs tests. When you suspect a specific bug, message the tester directly to write a targeted test proving or disproving it.

WORKFLOW:
1. PLAN VALIDATION: The implementer will send you a plan before coding. Review it for feasibility, security risks, and architectural concerns. Reply directly to the implementer with your verdict (approve or raise concerns). Also message the lead with your verdict.
2. CODE REVIEW: After implementation, you will receive the full diff. Check every item on the security, architecture, and clarity checklists provided. If you suspect a specific bug, message the tester directly -- do not just flag it, get evidence.

For each finding, classify as BLOCKING, WARNING, or INFO.
Tag each finding with its category: [security], [architecture], or [clarity].
Be specific: cite file paths, line numbers, and the exact issue.
If the code is clean, say so.

Always use TaskUpdate to mark tasks completed.
```

---

## Failure Handling

| Failure | Action |
|---------|--------|
| Agent fails to spawn | Retry once. If still fails, proceed without it and note in summary. |
| Tests not found / no test framework | Tester reports N/A. Lead marks test track as "No test framework detected." |
| Agent unresponsive | Send a follow-up message. If still no response after a second nudge, proceed without that agent's input and note in summary. |
| 3 rounds exhausted with blocking issues | Produce summary listing completed changes and remaining issues as TODOs. |
| Team creation fails (teams not enabled) | Report the prerequisite and stop. |
