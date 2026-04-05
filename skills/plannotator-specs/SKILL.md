---
name: plannotator-specs
description: Interactive spec review via Plannotator. Use after writing a spec document (design doc, SPEC file) to let the user review it with inline annotations before committing. Auto-detects the most recently written spec file.
allowed-tools: Bash(plannotator:*)
---

# Spec Review via Plannotator

Review a spec document interactively using Plannotator annotations, then iterate on feedback until the user approves.

## Context

- Recent spec files: !`find specs -name "*.md" -type f 2>/dev/null | head -10`
- Git status: !`git status --short 2>/dev/null | head -20`

## Instructions

### Step 1: Identify the spec file

Determine which spec file to review:

1. If `$ARGUMENTS` is provided, use that as the file path
2. Otherwise, look at the conversation context for the most recently written or modified spec file (typically in `specs/`)
3. If still unclear, check `git status` for recently added or modified `.md` files in spec directories
4. If no spec file can be found, tell the user and stop

### Step 2: Open Plannotator

Run the plannotator annotate command on the identified spec file. The user will review it in their browser and leave inline comments.

If `$ARGUMENTS` was provided and you identified the file in step 1, run:

```bash
plannotator annotate <spec-file-path>
```

If `$ARGUMENTS` was not provided, you must first identify the file (step 1), then run the command with the resolved path.

### Step 3: Address feedback

After the user submits their annotations:

1. Read each annotation carefully
2. Make the requested changes to the spec file
3. Do NOT commit yet — the spec is still under review

### Step 4: Re-open for review

After addressing all comments, re-open the spec in Plannotator so the user can verify the changes and leave additional comments if needed.

### Step 5: Loop until approved

Repeat steps 3-4 until the user has no more comments. The user signals approval by submitting with no annotations or by saying they approve.

### Step 6: Return control

Once the user approves:

1. Tell the caller the spec is approved and ready
2. Do NOT commit the spec — let the calling workflow handle that

The spec file is now reviewed and ready for the next step in whatever workflow invoked this skill.
