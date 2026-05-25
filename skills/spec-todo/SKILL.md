---
name: spec-todo
description: "List, pick, and execute deferred work items from .workflow/todo/. Use when the user asks about backlog, deferred work, or what needs doing."
tags: [spec]
---

# Spec todo

List and execute deferred work items. Items are created by `/ralph-review`, `/bugbash`, or manually — small marker files in `.workflow/todo/` that point to detailed analysis elsewhere.

## Arguments

- `$ARGUMENTS` - Optional: "list" (default), a filename to execute, or "add <description>" to create one manually

Invocation forms:
```
/spec-todo                              → list all items
/spec-todo list                         → same as above
/spec-todo 2026-03-29-data-race.md      → pick up and execute that item
/spec-todo add "Fix flaky test in auth" → create a new todo manually
```

## Context

- OpenSpec project: !`test -d openspec && echo "yes" || echo "no"`
- Todo directory: !`ls .workflow/todo/*.md 2>/dev/null | head -20 || echo "(empty)"`
- Current branch: !`git branch --show-current 2>/dev/null || echo '(not in a git repo)'`

---

## Mode: List (default)

If the project has no `openspec/` directory, tell the user this skill only works in OpenSpec projects and stop.

If `.workflow/todo/` is empty or doesn't exist, print "No deferred items." and stop.

Otherwise, read each marker file and display a summary table:

```
Deferred work items (.workflow/todo/):

  # | Created    | Severity | Title                          | Source
  1 | 2026-03-29 | medium   | Data race in plugin state      | ralph-review
  2 | 2026-03-28 | low      | Rename ambiguous variable      | ralph-review
  3 | 2026-03-27 | high     | Missing auth check on /admin   | bugbash

Pick a number to work on, or "done" to exit.
```

Use `AskUserQuestion` to let the user pick. If they pick a number, switch to Execute mode for that item.

## Mode: Execute

1. Read the full marker file
2. If it has a `source` field, read the source report and find the relevant section for full context
3. Read the affected files listed in the `files` field
4. Present a brief summary of the problem and proposed approach
5. Use `AskUserQuestion`:

```
How would you like to handle this?

1. Fix it now — I'll implement the fix in this session
2. Fixit — background it in a worktree via /fixit
3. Skip — come back to it later
4. Delete — this is no longer relevant
```

- **Fix it now** → Implement the fix, run tests, commit. Then delete the marker file and commit that deletion.
- **Fixit** → Dispatch via `/fixit` with the marker's context. On fixit completion, delete the marker file.
- **Skip** → Return to the list.
- **Delete** → Delete the marker file, commit: `Remove resolved todo: <title>`

After handling an item, return to the list (minus the handled item) until the user says "done" or the list is empty.

## Mode: Add

Create a new marker file manually:

1. Parse the description from `$ARGUMENTS` (everything after "add")
2. Generate a slug from the description
3. Use `AskUserQuestion` to ask for severity (low/medium/high)
4. Create the marker file:

```bash
mkdir -p .workflow/todo
```

```markdown
---
source: manual
created: YYYY-MM-DD
skill: manual
severity: {user's choice}
files: []
---

# {title from description}

{description}
```

5. Commit: `Add todo: <title>`

## Rules

- This skill only works in OpenSpec projects (`openspec/` directory exists). If no `openspec/` directory, tell the user and stop.
- Never modify the source report — it's historical record.
- Always delete marker files when work is completed, not before.
- The `.workflow/todo/` directory should be committed to git so it's visible across sessions.
