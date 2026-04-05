---
name: bugbash
description: Use when the user wants to do a QA session or report multiple bugs — interactive session where bugs are reported conversationally and agents fix them in parallel
---

# Bug Bash

Run an interactive QA session where you report bugs and a team of agents fixes them in parallel. Each bug becomes a task tracked via `TaskCreate`, gets its own worktree, and follows the agent-driven-development pattern. Fixes auto-merge back to the current branch.

**Execution pattern:** Each bug fix follows agent-driven-development pattern. Read `skills/agent-driven-development/SKILL.md`.

## Prerequisites

Agent teams must be enabled in Claude Code settings:

```
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

If agent teams are not enabled, report: "Agent teams required. Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to your Claude Code settings (env section)." and stop.

## Arguments

- `$ARGUMENTS` - Optional subcommand: `status`, `done`, `report`, or empty to start/continue

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Project root: !`pwd`
- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`
- Existing bugs: !`for d in todo in-progress blocked merged verified failed conflict; do files=$(find .bug-bash/$d -name 'bug-*.md' 2>/dev/null); [ -n "$files" ] && echo "[$d]" && echo "$files"; done; true`

---

## Directory Layout

Bugs live in status folders — the folder IS the status. No need to read files to rebuild state.

```
.bug-bash/
  todo/              # Queued, waiting for investigation + agent slot
    bug-001.md
    bug-003.md
  investigating/     # Investigation agent analyzing (foreground, pre-dispatch)
    bug-004.md
  in-progress/       # Fix agent actively working
    bug-002.md
  blocked/           # Agent stopped — needs user input before continuing
  merged/            # Fix merged, awaiting acceptance testing
  verified/          # Passed acceptance testing — done
  failed/            # Agent couldn't fix
  conflict/          # Merge conflict, needs manual resolution
  attachments/       # Screenshots/images, organized by bug number
    001/
      screenshot-1.png
    002/
  report.md          # Generated report for Plannotator regression testing
```

**Status transitions = `mv`:**
```bash
mv .bug-bash/todo/bug-001.md .bug-bash/investigating/   # investigation started
mv .bug-bash/investigating/bug-001.md .bug-bash/in-progress/  # investigation done, fix dispatched
mv .bug-bash/investigating/bug-001.md .bug-bash/blocked/      # high-risk conflict, needs user input
mv .bug-bash/in-progress/bug-001.md .bug-bash/merged/   # fix merged
mv .bug-bash/in-progress/bug-001.md .bug-bash/failed/   # agent failed
mv .bug-bash/in-progress/bug-001.md .bug-bash/conflict/  # merge conflict
mv .bug-bash/in-progress/bug-001.md .bug-bash/blocked/   # agent needs user input
mv .bug-bash/blocked/bug-001.md .bug-bash/in-progress/   # user unblocked, re-dispatch
mv .bug-bash/merged/bug-001.md .bug-bash/verified/       # passed acceptance testing
```

---

## Starting a Session

When invoked with no arguments (or the session is already active):

1. **Initialize if needed:**
   - Create status folders:
     ```bash
     mkdir -p .bug-bash/{todo,investigating,in-progress,blocked,merged,verified,failed,conflict,attachments}
     ```
   - Add `.bug-bash/` to `.gitignore` if not already there (append, don't overwrite)
   - Initialize internal state:
     ```
     next_bug_id = 1 (or max existing + 1 if resuming)
     slots = [] (max 3)
     queue = [] (pending bugs in todo/)
     ```
   - To find next_bug_id when resuming:
     ```bash
     ls .bug-bash/*/bug-*.md 2>/dev/null | sed 's/.*bug-\([0-9]*\)\.md/\1/' | sort -n | tail -1
     ```

2. **Print welcome:**
   ```
   Bug Bash started. Report bugs and I'll dispatch fix agents.

   - Describe a bug to report it
   - /bug-bash status — see dashboard
   - /bug-bash done — wrap up session
   ```

3. **Wait for bug reports.** The user will describe bugs in natural language, possibly with screenshots.

---

## Bug Intake (when user describes a bug)

**YOU ARE A TRIAGE NURSE, NOT A SURGEON.**

Your job is to produce a high-quality bug spec so the fix agent can work autonomously. You locate the problem area but never investigate root causes or propose fixes.

- **NEVER** use `Read` on source code files
- **NEVER** investigate the bug or suggest a fix approach
- **ALLOWED** during triage: targeted `Glob`/`Grep` to locate relevant files (see Step 2)
- **ONLY** use the user's words, screenshots, search results, and general project knowledge to write the bug spec

### Step 1: Classify Clarity

Parse the user's description and classify into one of three tiers:

| Tier | Signal | Example |
|------|--------|---------|
| **Clear** | User names files/component + expected vs actual | "SidebarCount.tsx shows stale count after adding items" |
| **Locatable** | Behavior described, location unknown | "The sidebar count is wrong" |
| **Ambiguous** | Unclear what's broken, or multiple interpretations | "The sidebar is messed up" |

### Step 2: Triage by Tier

**Clear** (user named files/component + expected vs actual):
→ Proceed to Step 3 immediately.

**Locatable** (behavior described, location unknown):
→ Run up to 3 `Glob`/`Grep` calls to identify likely files by name or keyword.
→ Do NOT `Read` file contents — just find file paths.
→ Add results to "Files Likely Involved" in the bug spec.
→ Proceed to Step 3.

**Ambiguous** (unclear what's broken, or multiple interpretations):
→ Echo back a 1-line interpretation: `"Filing as: <your interpretation>. Correct?"`
→ If user confirms or doesn't correct: proceed to the **Locatable** step above.
→ If user clarifies: update understanding, proceed.
→ Max 1 clarification round, then dispatch with best understanding.

### Step 3: Save Attachments

If the user provided screenshots or images:
1. Create the attachments directory: `.bug-bash/attachments/<NNN>/`
2. Copy each image to `.bug-bash/attachments/<NNN>/screenshot-<N>.png` (or original extension)
3. Note filenames for the bug spec

If the image is provided as a file path, copy it. If pasted inline, save it to the directory.

### Step 4: Write Bug File

Create `.bug-bash/todo/bug-<NNN>.md`:

```markdown
---
id: BUG-<NNN>
title: <short title>
reported: <ISO timestamp>
agent_id:
worktree_branch: bug-bash/BUG-<NNN>
attachments:
  - <filename if any>
---

## Description
<what's broken, from user's report — their words, not your investigation>

## Expected Behavior
<what should happen instead>

## Files Likely Involved
<from user + triage search results. If neither produced anything: "Unknown — agent should explore">
```

Do NOT add a "Fix Approach" section. The agent will figure it out.

**Note:** No `status:` field in frontmatter — the folder is the status.

### Create Task

After writing the bug file, create a task to track it:

```
TaskCreate("Fix BUG-<NNN>: <title>", description: "<1-line summary>")
```

If a bug depends on another bug finishing first (e.g., same-file overlap), use `addBlockedBy` to express the dependency. Independent bugs have no blockers and can execute in parallel.

### Step 5: Investigate or Fast-Path

**Clear tier bugs skip investigation.** If the user named files, described expected vs actual behavior, and the fix is likely isolated (cosmetic, config, single-file), go directly to Step 6 (Dispatch). The investigation gate exists to catch dependency conflicts — Clear tier bugs have low conflict risk by definition.

**Locatable and Ambiguous tier bugs require investigation.** Run a read-only investigation agent in the background. This catches dependency conflicts without blocking bug intake — you keep accepting new bugs while investigations run.

**Move to investigating:**
```bash
mv .bug-bash/todo/bug-<NNN>.md .bug-bash/investigating/
```

**Dispatch an Explore agent (`run_in_background: true`):**

```
Investigate BUG-<NNN>: <title>

Bug description: <from bug.md>
Expected behavior: <from bug.md>
Files likely involved: <from bug.md>

Your job is READ-ONLY investigation. Do NOT write code or propose fixes.

Answer these questions:
1. What is the root cause? (read the relevant code, trace the bug)
2. What functions/methods would need to change?
3. What OTHER code depends on those functions? (grep for callers, check interfaces)
4. Could fixing this break anything else? (list specific concerns)
5. Is the user's expected behavior compatible with other behaviors in the system?

Report format:
- **Root cause:** 1-2 sentences
- **Files to change:** list with line numbers
- **Dependencies:** other code that calls/uses the affected code
- **Risk:** low (isolated change) | medium (has callers but change is compatible) | high (conflicts with other behavior)
- **Conflicts:** any specific concerns about the fix breaking other things
```

**Do NOT wait for the investigation to return.** Continue accepting bug reports. When the investigation agent completes (you'll be notified), process its findings:

- **Risk: low** → Append `## Investigation` section to bug file, auto-dispatch fix agent
- **Risk: medium** → Append findings, dispatch fix agent with dependency warnings in prompt
- **Risk: high** → Report to user:
  ```
  BUG-<NNN> has conflicts: <1-line summary>
    <brief explanation of what might break>
    Dispatch anyway? (y/n)
  ```
  Move to `blocked/` until user responds. If user approves, move back to `investigating/` → dispatch fix agent with conflict context.

### Step 6: Dispatch or Queue

- **If a slot is available** (fewer than 3 active agents): dispatch immediately
- **If all 3 slots are full**: leave in `todo/`, tell user:
  ```
  BUG-<NNN> queued — all 3 agent slots in use. Will dispatch when a slot frees up.
  ```

### Step 7: Confirm to User

```
BUG-<NNN>: <title>
Status: dispatched (agent working in worktree) | queued (waiting for slot)
```

Keep it short — the user wants to keep reporting bugs, not read paragraphs.

---

## Dispatching an Agent

When dispatching a bug to an agent:

### Move to in-progress

```bash
mv .bug-bash/todo/bug-<NNN>.md .bug-bash/in-progress/
```

### Create Worktree

```bash
git worktree add -b bug-bash/BUG-<NNN> .claude/worktree/bug-bash-<NNN> HEAD
```

If branch name exists (from a previous failed attempt), remove it first:
```bash
git worktree remove .claude/worktree/bug-bash-<NNN> --force 2>/dev/null
git branch -D bug-bash/BUG-<NNN> 2>/dev/null
```

### Rebase Worktree (if other merges landed)

If other bug fixes have been merged to the main branch since the worktree was created, rebase to pick up those changes:

```bash
git -C .claude/worktree/bug-bash-<NNN> rebase main
```

This prevents agents from working against stale code that references APIs changed by earlier bug fixes.

### Spawn Agent

Each bug fix follows the agent-driven-development pattern. The implementer agent follows TDD (`skills/test-driven-development/SKILL.md`), self-reviews per verification-before-completion (`skills/verification-before-completion/SKILL.md`), and references debugging docs for root cause analysis.

Use the Agent tool with `run_in_background: true` and `mode: "bypassPermissions"`:

```
## Bug Fix: BUG-<NNN> — <title>

### Context
- Project root: <project root>
- Working directory: <worktree path>
- Branch: bug-bash/BUG-<NNN>
- Bug spec: <absolute path to .bug-bash/in-progress/bug-<NNN>.md>

### Execution Pattern
This bug fix follows agent-driven-development. Read `skills/agent-driven-development/SKILL.md`.

For debugging, also read:
- `skills/debug/root-cause-tracing.md` — systematic hypothesis-driven debugging
- `skills/debug/defense-in-depth.md` — making fixes robust against related failures

### Bug Description
<full contents of bug.md Description section>

### Expected Behavior
<from bug.md>

### Attachments
<list attachment paths from .bug-bash/attachments/<NNN>/ if any — read/view these for visual context>

### Files Likely Involved
<from bug.md, or "Explore the codebase to find the relevant code">

### Spec-Aware Project
<if .specs file exists in project root>
This project uses specs. The spec directory is: <dir from .specs file, default "specs">

**You MUST follow spec-first order:**
1. Find the relevant spec in the specs directory
2. Add the bug's failing case to the spec
3. Write/update a test that reproduces the bug
4. Implement the fix to pass the test
5. Include the spec file in your commit
</if .specs file exists>
<if no .specs file>
No spec management required.
</if>

### Investigation Findings
<from the ## Investigation section of the bug file, if present>
<include root cause, files to change, and any dependency warnings>

### Instructions
1. Read the bug spec, any attachments, and the investigation findings
2. Read the debugging docs listed above for systematic root cause analysis
3. Read the project's CLAUDE.md for architecture conventions and testing requirements
4. Explore the codebase to understand the problem (investigation gives you a head start)
5. **Check dependencies** — if the investigation flagged callers or risks, verify your fix doesn't break them
6. If this is a spec-aware project (see above), follow spec-first order
7. Otherwise: implement the fix directly
8. **Run targeted tests** for the packages/files you changed (e.g., `go test ./internal/tui/...`, `npm test -- --testPathPattern=sidebar`). Do NOT run the full project test suite — the coordinator runs that after merge. If you can't identify targeted tests, run the full suite as a fallback.
9. Self-review per `skills/verification-before-completion/SKILL.md` before declaring done
10. **Write resolution to the bug file** (see Resolution Documentation below)
11. Commit your changes with message: "Fix BUG-<NNN>: <title>"
12. Report status: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED

### Resolution Documentation
Before committing, append these sections to the bug file:

## Resolution
<what you found (root cause) and what you changed>

## Files Changed
<list of files modified with 1-line description each>

## Choices Made
<any decisions where you picked between alternatives without asking — explain what you chose and why>

## Uncertainties
<anything you're not confident about, or areas that may need follow-up>

### Constraints
- Work ONLY in your worktree directory: <worktree path>
- Follow existing codebase patterns and conventions
- Do not modify files outside the scope of this bug
- If tests fail after your fix, investigate and resolve
- Keep the fix minimal — don't refactor surrounding code
```

### Update State

- Add to slots: `{bug_id: NNN, agent_id: <id>}`
- Update bug file frontmatter: `agent_id: <id>`

---

## On Agent Completion

When a background agent reports back:

### Step 1: Handle Status

Process the agent's reported status per agent-driven-development:

- **DONE** -- proceed to merge
- **DONE_WITH_CONCERNS** -- read concerns. If correctness/scope issues, re-dispatch with fix instructions. If observations, note for final report and proceed to merge.
- **NEEDS_CONTEXT** -- provide missing context from investigation findings or codebase and re-dispatch
- **BLOCKED** -- follow escalation: provide more context and re-dispatch, then try a more capable model, then break the task down, then park and note in final report

Execution is autonomous -- the controller handles all statuses internally without asking the user.

### Step 2: Merge (on success)

```bash
# Make sure we're on the main branch
git checkout <original-branch>

# Merge the bug fix
git merge bug-bash/BUG-<NNN> --no-edit
```

**If merge succeeds:**
- Do NOT rebuild immediately — rebuilds are batched. The coordinator runs a single full build + test after all pending merges complete, or when the user requests it (e.g., via `status`, `report`, or `done`). This avoids rebuilding N times for N merges.
- Move bug file:
  ```bash
  mv .bug-bash/in-progress/bug-<NNN>.md .bug-bash/merged/
  ```
- Clean up:
  ```bash
  git worktree remove .claude/worktree/bug-bash-<NNN> --force
  git branch -D bug-bash/BUG-<NNN>
  ```
- Report to user:
  ```
  BUG-<NNN> merged: <title>
    <1-line summary of what the agent did>
    📋 Specs: <Updated (specs/foo.md) | Skipped (no .specs file)>
  ```

**If merge conflicts:**
- `git merge --abort`
- Move bug file:
  ```bash
  mv .bug-bash/in-progress/bug-<NNN>.md .bug-bash/conflict/
  ```
- Report to user:
  ```
  BUG-<NNN> conflict: <title>
    Worktree preserved at .claude/worktree/bug-bash-<NNN> for manual resolution.
    Conflicting files: <list>
  ```

### Step 3: Handle Failure

If the agent reports it couldn't fix the bug:
- Move bug file:
  ```bash
  mv .bug-bash/in-progress/bug-<NNN>.md .bug-bash/failed/
  ```
- Clean up worktree
- Report to user:
  ```
  BUG-<NNN> failed: <title>
    Agent reported: <brief reason>
  ```

### Step 4: Handle Blocked

If the agent reports it's blocked (needs a decision from the user):
- Move bug file:
  ```bash
  mv .bug-bash/in-progress/bug-<NNN>.md .bug-bash/blocked/
  ```
- The agent should have appended a `## Blocked` section to the bug file explaining what decision is needed
- Report to user:
  ```
  BUG-<NNN> blocked: <title>
    Agent needs input: <brief description of decision needed>
  ```
- Free the slot for other work

**To unblock:** User provides the decision. Coordinator updates the bug file with the answer, moves it back to `todo/`, and re-dispatches with the additional context.

### Step 5: Free Slot, Mark Task Complete, and Dispatch Next

- Remove from slots
- Mark the task complete in the native Task system -- this auto-unblocks any bugs that were waiting on this one (e.g., same-file overlap dependencies)
- If `todo/` has pending bugs, dispatch the next one
- Multiple bugs can execute in parallel -- each in its own worktree, each with its own agent. Dispatch all unblocked bugs simultaneously up to the slot limit.

---

## Status Dashboard

When invoked with `status` argument, or user says "status":

Get status by listing each folder (no file reads needed for counts):

```bash
ls .bug-bash/todo/ .bug-bash/investigating/ .bug-bash/in-progress/ .bug-bash/blocked/ .bug-bash/merged/ .bug-bash/verified/ .bug-bash/failed/ .bug-bash/conflict/ 2>/dev/null
```

Read titles only from in-progress, blocked, and todo bugs for the table. Print:

```
## Bug Bash Status

| # | Bug | Status |
|---|-----|--------|
| 001 | <title> | verified |
| 002 | <title> | merged |
| 003 | <title> | in-progress |
| 004 | <title> | blocked |
| 005 | <title> | todo |

Active: <N>/3 slots (count of in-progress/)
Queue: <N> todo
Blocked: <N> (needs user input)
Merged: <N> (awaiting acceptance testing)
Verified: <N> (passed acceptance testing)
Issues: <N> failed, <N> conflict
```

---

## Wrap-up

When invoked with `done` argument, or user says "done" or "wrap up":

### Step 1: Wait for Active Agents

If agents are still running (files in `in-progress/`):
```
<N> agents still working. Waiting for completion before wrap-up...
```
Wait for all active agents to complete (check with TaskOutput).

### Step 2: Final Summary

```
## Bug Bash Complete

### Results
| # | Bug | Status | Summary |
|---|-----|--------|---------|
| 001 | <title> | merged | <1-line> |
| 002 | <title> | merged | <1-line> |
| 003 | <title> | conflict | needs manual merge |

### Stats
- Reported: <N>
- Fixed & merged: <N>
- Failed: <N>
- Conflicts: <N>

### Commits
<git log --oneline showing all bug-bash merge commits>

### Unresolved
<list any conflict or failed bugs with details>
```

### Step 3: Cleanup

- Remove `.bug-bash/` directory (after confirming no files in `conflict/` — if conflicts exist, keep it)
- Remove any remaining worktrees:
  ```bash
  git worktree list | grep bug-bash | awk '{print $1}' | xargs -I{} git worktree remove {} --force
  git branch --list 'bug-bash/*' | xargs -I{} git branch -D {}
  ```

---

## Report (Acceptance Testing)

When invoked with `report` argument, or user asks for a report/regression test:

### Step 1: Prepare Environment

Before the user tests, ensure the project is built and up to date. Check the project's CLAUDE.md, README, and Makefile (if present) for build/install instructions. For example, a Go project with a Makefile might need `make build && make install`; a Node project might need `npm run build`.

If the build fails, report the error and stop — don't proceed with a stale build.

### Step 2: Generate Report

Run the report generator script:
```bash
/Users/aaron/.claude/skills/bugbash/generate-report.sh <project-root>
```

This parses all `merged/` bug files and writes `.bug-bash/report.md` with title, fix summary, test guidance, and files changed for each bug. Runs in under a second.

If the script is missing or fails, fall back to writing the report manually using the format below. **Only include bugs in `merged/`** — skip `verified/` (already passed) and other statuses.

```markdown
# Bug Bash — Regression Testing

Instructions: Test each bug below. Add an inline comment on any that fail.
Bugs without comments are assumed to PASS and will be moved to verified.

---

## BUG-<NNN>: <title> [needs testing]

- **What was fixed:** <1-2 line summary from Resolution section>
- **How to test:** <specific repro steps>
- **Files changed:** <files changed>

---
(repeat for each merged/ bug)
```

For bugs without a `## Resolution` section, use `git log --grep="BUG-<NNN>"` to reconstruct.

### Step 3: Open Plannotator

Invoke `plannotator:plannotator-annotate` with `.bug-bash/report.md`.

### Step 4: Process Annotations

When annotations come back:

- **Annotated bugs = FAILED regression.** For each:
  - File a new bug (next ID) referencing the original as `related:`
  - Move the new bug to `todo/` for dispatch
  - Move the original to `failed/` — it didn't pass acceptance testing, so it shouldn't clutter the dashboard

- **Unannotated bugs = PASSED.** Move to `verified/`:
  ```bash
  mv .bug-bash/merged/bug-<NNN>.md .bug-bash/verified/
  ```

### Step 5: Report Summary

After processing annotations, print:
```
## Acceptance Testing Results

Passed: <N> (moved to verified/)
Failed: <N> (new bugs filed)
Remaining: <N> (still in merged/, not yet tested)
```

Then dispatch any new bugs from failures.

---

## Collision Avoidance

Since each agent works in its own worktree on its own branch, code-level collisions are rare. However:

### Same-file Overlap Check (HARD GATE)

**Before dispatching every bug**, check if any in-progress bug lists overlapping files in its "Files Likely Involved" section:

```bash
# For each file in the new bug's "Files Likely Involved":
grep -l "<filename>" .bug-bash/in-progress/bug-*.md 2>/dev/null
```

- **If overlap detected**: DO NOT dispatch. Keep the bug in `todo/` with a note: "Waiting for BUG-<NNN> to merge first (same files: <list>)". Tell the user.
- **After the blocking bug merges**: auto-dispatch the waiting bug (it will be based on the updated code via the worktree rebase step).
- **If overlap is uncertain** (e.g., "Unknown — agent should explore"): dispatch anyway. The merge step catches conflicts.

This is not optional. Dispatching two agents that touch the same file wastes both agents' work when the second merge conflicts.

### Merge Order

Merge in completion order (first done, first merged). If a later merge conflicts because an earlier merge changed the same area, follow the conflict flow above.

---

## Failure Handling

| Failure | Action |
|---------|--------|
| Worktree creation fails | Report error, keep bug in `todo/`, retry on next dispatch cycle |
| Agent errors or crashes | Move to `failed/`, free slot, report to user |
| Agent blocked / needs decision | Move to `blocked/`, free slot, report question to user |
| Merge conflict | Abort merge, move to `conflict/`, preserve worktree, report to user |
| All 3 slots full | Leave in `todo/`, dispatch when slot frees |
| User reports bug during agent completion handling | Finish merge first, then process new bug |
| `.bug-bash/` already exists on start | Resume session — `ls` each folder to rebuild state |
| Agent references non-existent APIs | Move to `failed/`, append `## Hallucinated APIs` section to bug file listing what was hallucinated and what the correct API is. Include this context in any re-dispatch prompt. |

---

## Token Conservation

The main thread is a coordinator, not an engineer. This is a HARD rule, not a guideline.

### Forbidden Tools (During Triage)

When processing a bug report, you MUST NOT use:
- `Read` on source code files (bug files and agent output are fine)

### Investigation Phase (Between Triage and Dispatch)

- `Agent` with subagent_type=Explore and `run_in_background: true` — **REQUIRED** for the investigation gate (Step 5)
- Investigation runs in the background — does NOT block bug intake
- When the investigation agent completes, review its risk assessment and dispatch or block accordingly
- After investigation, append findings to the bug file for the fix agent

### Allowed During Triage (Locatable/Ambiguous bugs only)

- `Glob` — up to 2 calls to find relevant files by name/pattern
- `Grep` — up to 1 call to locate a component/function by keyword
- **Total: max 3 search calls per bug, zero file reads**
- Goal: populate "Files Likely Involved" so the agent has a starting point

### Always Allowed

- `Bash` — only for: git commands, mkdir, mv, file copy, worktree management
- `Write` — only for: bug files
- `Read` — only for: bug files, agent output files, git log/diff output
- `Agent` — only for: dispatching fix agents

### Rationale

Every line of source code you read in the main thread is wasted context. But a few targeted file-path searches (~50 tokens) dramatically improve agent success rates by giving them a starting point instead of "explore everything." The line is: **locate, don't investigate.**

### Summary Rules

1. **Never read source code yourself** — agents do that (triage + investigation)
2. **Never write fixes yourself** — fix agents do that
3. **Investigate before dispatching** — except Clear tier bugs which skip investigation
4. **Locate relevant files** with up to 3 Glob/Grep calls per bug during triage (paths only, no content)
5. **Review investigation findings** before dispatching fix agents — block on high-risk conflicts
6. **Check file overlap** before dispatching — serialize agents that touch the same files
7. **Agents run targeted tests** — only for the packages they changed, not the full suite
8. **Batch rebuilds** — don't rebuild after each merge. One build after all merges land.
9. **Only read**: bug files, agent results, investigation output, git status/log/diff
10. **Keep agent prompts detailed** so they work autonomously — include investigation findings
11. **Bug reports to user are 1-2 lines max** — don't echo back everything
