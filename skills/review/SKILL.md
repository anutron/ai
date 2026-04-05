---
name: review
description: Use when the user asks to review code, review current changes, or review a PR number
---

# Code Review

Shorthand for reviewing code. Routes to the right tool based on context.

## Arguments

- `$ARGUMENTS` - Optional: a PR number (e.g., `123`), PR URL, or nothing (review current uncommitted changes)

## Context

- Git status: !`git status --short`
- Current branch: !`git branch --show-current`

## Instructions

### Determine what to review

```
IF $ARGUMENTS is a PR number or PR URL:
  Use the pr-review-toolkit:review-pr skill to do a comprehensive PR review.
  Pass the PR number/URL as the argument.

ELSE IF there are uncommitted changes (from git status above):
  Use the code-review:code-review skill to review the current diff.

ELSE IF the current branch has commits ahead of the default branch:
  Use the code-review:code-review skill to review the branch diff.

ELSE:
  Tell the user: "Nothing to review -- no uncommitted changes and no commits ahead of the default branch."
```

### After review completes

Summarize:
- How many issues found (blocking / warning / info)
- Key concerns if any
- Whether the code is ready to ship
