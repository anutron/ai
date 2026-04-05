---
name: save-w-specs
description: Use when ready to commit completed work — saves progress and verifies specs were updated alongside behavioral changes in spec-driven projects (but never derives specs from code)
---

# Save Progress

Checkpoint your work by committing completed changes.

## Context

- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`
- Git status: !`git status --short`

## Instructions

When `/save-w-specs` is invoked:

### 1. Check for Behavioral Changes

Scan the work done since the last commit for behavioral code changes — new features, modified behavior, bug fixes, CLI changes, etc.

### 2. Spec Compliance Check (if `.specs` file exists)

If the project has a `.specs` file at its root:

- For each behavioral change, check whether the relevant spec was **already updated** as part of the work
- If specs were updated alongside code: proceed to commit
- If behavioral changes exist but no spec was updated: **warn the user**

```
⚠️ Behavioral changes detected but no spec updates found.
   Changed: <list of behavioral files>
   Specs should have been written BEFORE the code, not after.
   Options:
   1. Commit anyway (spec debt)
   2. Update specs first, then commit
```

**NEVER derive specs from the code.** If specs weren't written as part of the workflow, that's a process gap to flag — not something to paper over by reverse-engineering specs now.

### 3. Commit

Evaluate what has changed and commit only work that is complete and appropriate for committing. Leave in-progress or half-finished work unstaged.

- Group related changes into logical commits — don't lump unrelated work together
- Spec updates go with their corresponding code changes
- Stage specific files by name; never blindly `git add -A`
- If some changes are ready and others aren't, commit only the ready ones

### 4. Report Spec Status

After committing, report:

- `📋 Specs: Updated (specs/foo.md)` — if spec changes were included
- `📋 Specs: No behavioral changes` — if only config/docs/cosmetic changes
- `📋 Specs: Skipped (no .specs file)` — if the project doesn't use specs
- `📋 Specs: ⚠️ Missing (behavioral changes without spec updates)` — if the user chose to commit anyway

## When NOT to Use

- Nothing has changed since the last commit
- You're in the middle of a multi-step change that isn't ready to checkpoint yet
