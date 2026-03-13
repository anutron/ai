---
name: unstaged
description: Show uncommitted/unstaged changes grouped by logical commit themes.
---

# Unstaged Changes Overview

Show all uncommitted and unstaged changes in the current repo, grouped by logical commit themes.

## Context

- Git status: !`git status --short`
- Current branch: !`git branch --show-current`
- Staged diff summary: !`git diff --cached --stat`
- Unstaged diff summary: !`git diff --stat`
- Untracked files: !`git ls-files --others --exclude-standard`

## Instructions

### 1. Gather all changes

Collect everything that's uncommitted:
- **Staged changes** — files added to the index but not yet committed
- **Unstaged changes** — modified tracked files not yet staged
- **Untracked files** — new files not yet tracked by git

If there are no changes at all, say "Working tree is clean — nothing to commit." and stop.

### 2. Read the diffs

Read the actual diffs (not just file names) to understand what changed:
- `git diff` for unstaged changes
- `git diff --cached` for staged changes
- For untracked files, read enough of each to understand its purpose

### 3. Group by theme

Analyze the changes and group them into **logical commits** — sets of changes that belong together conceptually. For each group, provide:

- **Theme name** — a short label (e.g., "Add user auth middleware", "Fix pagination bug")
- **Suggested commit message** — imperative mood, concise
- **Files** — list of files in this group with a one-line summary of each change
- **Status** — whether files are staged, unstaged, or untracked

### 4. Output format

```
## 🔀 Uncommitted Changes (N files)

### 1. [Theme Name]
> Suggested commit: `Add user auth middleware`

| Status | File | Change |
|--------|------|--------|
| M (unstaged) | src/auth.ts | Added JWT validation logic |
| A (staged) | src/middleware.ts | New auth middleware |
| ?? | src/auth.test.ts | Tests for auth module |

### 2. [Theme Name]
> Suggested commit: `Fix pagination off-by-one`

| Status | File | Change |
|--------|------|--------|
| M (unstaged) | src/list.ts | Fixed offset calculation |

---
**Summary:** N files changed across M themes
```

### 5. Notes

- If a file could belong to multiple themes, pick the best fit and note the ambiguity
- If all changes are clearly one theme, just show one group
- Keep descriptions brief — one line per file max
- Use standard git status codes: M (modified), A (added), D (deleted), R (renamed), ?? (untracked)
