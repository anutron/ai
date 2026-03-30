---
name: worktree
allowed-tools: Bash(git *), Bash(cd *), Bash(ls *), AskUserQuestion
description: Close a git worktree and merge it back to the main branch. Asks whether to merge or squash.
---

## Context

- Current directory: !`pwd`
- Current branch: !`git branch --show-current 2>/dev/null`
- Is worktree: !`git rev-parse --git-common-dir 2>/dev/null | grep -q '/worktrees/' && echo "yes" || echo "no"`
- Main repo: !`git worktree list 2>/dev/null | head -1 | awk '{print $1}'`
- Main branch: !`git -C "$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main"`
- Commits ahead: !`git log "$(git worktree list 2>/dev/null | head -1 | awk '{print $2}')..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' '`
- Uncommitted changes: !`git status --short 2>/dev/null`

## Prerequisites

You must be inside a git worktree (not the main working tree). If not, report: "Not in a worktree. Run this from inside a git worktree." and stop.

## Instructions

### Step 1: Gather info and handle uncommitted changes

Capture these variables (you'll need them for every subsequent step):

```bash
WORKTREE_PATH=$(pwd)
WORKTREE_DIR=$(basename "$WORKTREE_PATH")
WORKTREE_BRANCH=$(git branch --show-current)
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
MAIN_BRANCH=$(git -C "$MAIN_REPO" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "$MAIN_BRANCH" ]; then
  MAIN_BRANCH=$(git -C "$MAIN_REPO" branch --show-current)
fi
```

If there are uncommitted changes, stage and commit them with an appropriate message.

### Step 2: Choose merge mode

Use AskUserQuestion:

```
Question: "How do you want to merge <WORKTREE_BRANCH> (<N> commits) into <MAIN_BRANCH>?"
Options:
  - "Merge (preserve history)"
  - "Squash (single commit)"
```

### Step 3: Merge from the main repo

**CRITICAL: Run the merge command targeting the main repo with `git -C`. Do NOT `cd` to the main repo — the Bash tool's cwd is pinned to the worktree, and removing the worktree later would brick all subsequent commands.**

Stash any uncommitted changes on main:

```bash
git -C "$MAIN_REPO" stash 2>/dev/null
```

Then merge:

**If merge mode:**
```bash
git -C "$MAIN_REPO" merge "$WORKTREE_BRANCH" --no-edit
```

**If squash mode:**
```bash
git -C "$MAIN_REPO" merge --squash "$WORKTREE_BRANCH"
```
Then craft a commit message from the branch's overall changes and commit with a `Co-Authored-By` line:
```bash
git -C "$MAIN_REPO" commit -m "..."
```

### Step 4: Handle merge conflicts

If the merge has conflicts:
- Report the conflicting files
- Ask the user how to proceed (resolve, abort, or keep worktree)
- If abort: `git -C "$MAIN_REPO" merge --abort`, stop
- Do NOT force or auto-resolve

### Step 5: Verify and report

Verify the merge landed:

```bash
git -C "$MAIN_REPO" log -1 --oneline
```

If the commit is not there, STOP. Report the failure. Do not proceed.

If successful, restore any stashed changes:

```bash
git -C "$MAIN_REPO" stash pop 2>/dev/null
```

Then report:

```
Merged <WORKTREE_BRANCH> into <MAIN_BRANCH> (<mode>).
```

### Step 6: Tell user to clean up from another terminal

**CRITICAL: Do NOT run `git worktree remove` or `git branch -d` from this session.** The Bash tool's cwd is still inside the worktree directory. Removing it makes the cwd invalid, bricking all further shell commands in this session.

The merge is the critical step — once that succeeds, the work is safe on main. Cleanup is cosmetic and can happen from anywhere.

Tell the user:

```
Cleanup (run from another terminal):

cd <MAIN_REPO>
git worktree remove .claude/worktrees/<WORKTREE_DIR>
git worktree prune
git branch -d <WORKTREE_BRANCH>
```
