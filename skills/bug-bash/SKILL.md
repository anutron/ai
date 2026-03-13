---
name: bug-bash
description: Interactive QA session — report bugs conversationally, agents fix them in parallel using worktrees.
---

# Bug Bash

Run an interactive QA session where you report bugs and a team of up to 3 agents fixes them in parallel. Each agent works in an isolated git worktree. Fixes auto-merge back to the current branch.

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
- Existing bugs: !`for d in todo in-progress blocked merged verified failed conflict; do files=$(find .bug-bash/$d -name 'bug-*.md' 2>/dev/null); [ -n "$files" ] && echo "[$d]" && echo "$files"; done; true`

---

## Directory Layout

Bugs live in status folders — the folder IS the status. No need to read files to rebuild state.

```
.bug-bash/
  todo/              # Queued, waiting for agent slot
    bug-001.md
    bug-003.md
  in-progress/       # Agent actively working
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
mv .bug-bash/todo/bug-001.md .bug-bash/in-progress/    # dispatched
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
     mkdir -p .bug-bash/{todo,in-progress,blocked,merged,verified,failed,conflict,attachments}
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

**YOU ARE AN INTAKE CLERK, NOT AN ENGINEER.**

This is the most important rule of bug bash. When a user reports a bug:

- **NEVER** use Read, Grep, Glob, or any code exploration tools
- **NEVER** investigate the bug yourself — that's the agent's job
- **NEVER** suggest a fix approach or speculate about root causes in the bug spec
- **ONLY** use the user's words, screenshots, and your general project knowledge (from memory/CLAUDE.md) to write the bug spec

If you catch yourself thinking "let me just check one file to write a better spec" — STOP. That's the agent's job. A vague spec that dispatches in 10 seconds beats a precise spec that cost 5 minutes of context.

### Step 1: Assess Clarity

Parse the user's description. A dispatchable bug needs at minimum:
- **What's broken** — the observable problem
- **Where** — enough context to find it (component name, page, file, behavior)

### Step 2: Adaptive Follow-up

- **If clear enough** (has what + where): proceed to Step 3 immediately
- **If vague**: ask 1-2 targeted questions, one at a time:
  - "What specifically is broken — what do you see vs what you expect?"
  - "Any idea which files or components are involved?"
- **Never more than 2 questions.** After that, dispatch with what you have.

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
<ONLY if user named specific files. Otherwise: "Unknown — agent should explore">
```

Do NOT add a "Fix Approach" section. The agent will figure it out.

**Note:** No `status:` field in frontmatter — the folder is the status.

### Step 5: Dispatch or Queue

- **If a slot is available** (fewer than 3 active agents): dispatch immediately
- **If all 3 slots are full**: leave in `todo/`, tell user:
  ```
  BUG-<NNN> queued — all 3 agent slots in use. Will dispatch when a slot frees up.
  ```

### Step 6: Confirm to User

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
git worktree add -b bug-bash/BUG-<NNN> .claude/worktrees/bug-bash-<NNN> HEAD
```

If branch name exists (from a previous failed attempt), remove it first:
```bash
git worktree remove .claude/worktrees/bug-bash-<NNN> --force 2>/dev/null
git branch -D bug-bash/BUG-<NNN> 2>/dev/null
```

### Spawn Agent

Use the Agent tool with `run_in_background: true` and `mode: "bypassPermissions"`:

```
## Bug Fix: BUG-<NNN> — <title>

### Context
- Project root: <project root>
- Working directory: <worktree path>
- Branch: bug-bash/BUG-<NNN>
- Bug spec: <absolute path to .bug-bash/in-progress/bug-<NNN>.md>

### Bug Description
<full contents of bug.md Description section>

### Expected Behavior
<from bug.md>

### Attachments
<list attachment paths from .bug-bash/attachments/<NNN>/ if any — read/view these for visual context>

### Files Likely Involved
<from bug.md, or "Explore the codebase to find the relevant code">

### Instructions
1. Read the bug spec and any attachments
2. Explore the codebase to understand the problem
3. Implement the fix
4. Run tests if test infrastructure exists (look for Makefile, test commands in README, etc.)
5. **Write resolution to the bug file** (see Resolution Documentation below)
6. Commit your changes with message: "Fix BUG-<NNN>: <title>"
7. If you hit uncertainty that requires a human decision, STOP and report (see Blocked Bugs below)

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

### Step 1: Read Result

The agent's result message will indicate success or failure.

### Step 2: Merge (on success)

```bash
# Make sure we're on the main branch
git checkout <original-branch>

# Merge the bug fix
git merge bug-bash/BUG-<NNN> --no-edit
```

**If merge succeeds:**
- Move bug file:
  ```bash
  mv .bug-bash/in-progress/bug-<NNN>.md .bug-bash/merged/
  ```
- Clean up:
  ```bash
  git worktree remove .claude/worktrees/bug-bash-<NNN> --force
  git branch -D bug-bash/BUG-<NNN>
  ```
- Report to user:
  ```
  BUG-<NNN> merged: <title>
    <1-line summary of what the agent did>
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
    Worktree preserved at .claude/worktrees/bug-bash-<NNN> for manual resolution.
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

### Step 5: Free Slot and Dispatch Next

- Remove from slots
- If `todo/` has pending bugs, dispatch the next one

---

## Status Dashboard

When invoked with `status` argument, or user says "status":

Get status by listing each folder (no file reads needed for counts):

```bash
ls .bug-bash/todo/ .bug-bash/in-progress/ .bug-bash/blocked/ .bug-bash/merged/ .bug-bash/verified/ .bug-bash/failed/ .bug-bash/conflict/ 2>/dev/null
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
/Users/aaron/.claude/skills/bug-bash/generate-report.sh <project-root>
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
  - Keep the original in `merged/` (the code change was merged, it just didn't fully work)

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

### Same-file Conflicts

If two bugs likely touch the same file:
- **Before dispatching**: check if an in-progress bug lists overlapping files
- **If overlap detected**: keep the second bug in `todo/` with a note: "Waiting for BUG-<NNN> to merge first (same files)"
- **After first merges**: dispatch the second, which will be based on the updated code

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

---

## Token Conservation

The main thread is a coordinator, not an engineer. This is a HARD rule, not a guideline.

### Forbidden Tools During Intake

When processing a bug report, you MUST NOT use:
- `Read` (on source code — bug files and agent output are fine)
- `Grep`
- `Glob`
- `Agent` with subagent_type=Explore

### Allowed Tools

- `Bash` — only for: git commands, mkdir, mv, file copy, worktree management
- `Write` — only for: bug files
- `Read` — only for: bug files, agent output files, git log/diff output
- `Agent` — only for: dispatching fix agents

### Rationale

Every line of source code you read in the main thread is wasted context. The fix agents have full context windows of their own. A bug spec that says "Agent should explore" is perfectly fine — that's literally what agents are for.

### Summary Rules

1. **Never read source code yourself** — agents do that
2. **Never write fixes yourself** — agents do that
3. **Never investigate root causes yourself** — agents do that
4. **Only read**: bug files, agent results, git status/log/diff
5. **Keep agent prompts detailed** so they work autonomously
6. **Bug reports to user are 1-2 lines max** — don't echo back everything
