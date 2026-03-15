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

### Step 3: Switch to main repo and merge

**CRITICAL: `cd` to the main repo FIRST. All remaining work happens from there.**

```bash
cd "$MAIN_REPO"
```

Stash any uncommitted changes on main (note whether the stash actually saved anything):

```bash
git stash 2>/dev/null
```

Then merge:

**If merge mode:**
```bash
git checkout "$MAIN_BRANCH" && git merge "$WORKTREE_BRANCH" --no-edit
```

**If squash mode:**
```bash
git checkout "$MAIN_BRANCH" && git merge --squash "$WORKTREE_BRANCH"
```
Then craft a commit message from the branch's overall changes and commit with a `Co-Authored-By` line.

### Step 4: Handle merge conflicts

If the merge has conflicts:
- Report the conflicting files
- Ask the user how to proceed (resolve, abort, or keep worktree)
- If abort: `git merge --abort`, stop
- Do NOT force or auto-resolve

### Step 5: Verify and report

Verify the merge landed:

```bash
git log -1 --oneline
```

If the commit is not there, STOP. Report the failure. Do not proceed.

If successful, restore any stashed changes:

```bash
git stash pop 2>/dev/null
```

Then report:

```
Merged <WORKTREE_BRANCH> into <MAIN_BRANCH> (<mode>).
You are now on <MAIN_BRANCH> in <MAIN_REPO>.
```

### Step 6: Ask about cleanup

**Do NOT automatically clean up the worktree.** Ask the user:

```
Question: "Want me to remove the worktree and branch?"
Options:
  - "Yes, clean up"
  - "No, keep it"
```

**Only if they say yes:**

```bash
git worktree remove "$WORKTREE_PATH" && git branch -D "$WORKTREE_BRANCH" && git worktree prune
```

Do NOT use `--force`. If removal fails, investigate and report — don't retry with force.

**IMPORTANT:** Only remove THIS worktree. Never run `git worktree prune` without `git worktree remove` first — prune only cleans up already-deleted directories, but running it carelessly can affect other worktrees.

If they say no, remind them the worktree is still at `<WORKTREE_PATH>` and the branch is `<WORKTREE_BRANCH>`.
