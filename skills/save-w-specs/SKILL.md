---
name: save-w-specs
description: Save progress — update SPECs for any behavioral changes, then commit.
---

# Save Progress

Checkpoint your work by ensuring SPECs are current, then committing.

## Instructions

When `/save-w-specs` is invoked:

### 1. Identify Behavioral Changes

Scan the work done since the last commit for any behavioral code changes — new features, modified behavior, bug fixes, CLI changes, etc.

### 2. Update SPECs

For each behavioral change, check whether the relevant SPEC exists and is up to date:

- **SPEC exists but is stale** — update it to reflect the current behavior
- **SPEC doesn't exist yet** — create one in the appropriate `specs/` directory
- **No behavioral changes** (docs-only, config, etc.) — skip this step

SPEC locations:
- Applications in `~/Personal/applications/` → `<app>/specs/`
- AI-RON tools and CLIs → `~/Personal/AI-RON/specs/`
- Current repo (if different) → `./specs/`

### 3. Commit

Evaluate what has changed and commit only work that is complete and appropriate for committing. Leave in-progress or half-finished work unstaged.

- Group related changes into logical commits — don't lump unrelated work together
- SPEC updates can go with their corresponding code changes or in a separate commit if they span multiple features
- Stage specific files by name; never blindly `git add -A`
- If some changes are ready and others aren't, commit only the ready ones

## When NOT to Use

- Nothing has changed since the last commit
- You're in the middle of a multi-step change that isn't ready to checkpoint yet
