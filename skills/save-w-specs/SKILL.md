---
name: save-w-specs
description: Use when ready to commit completed work — saves progress and verifies that behavioral code changes are accompanied by deltas in an active OpenSpec change (but never derives specs from code)
---

# Save progress (OpenSpec)

Checkpoint your work by committing completed changes. In OpenSpec projects, gate the commit on whether an in-flight change's deltas describe the diff.

## Context

- OpenSpec project: !`test -d openspec && echo "yes" || echo "no"`
- Active changes: !`test -d openspec/changes && openspec list --changes --json 2>/dev/null || echo "none"`
- Current branch: !`git branch --show-current`
- Git status: !`git status --short`

## Instructions

When `/save-w-specs` is invoked, walk the steps below in order. Do not skip steps even if you think the diff is "obviously" non-behavioral – the gate runs every time.

### 1. Detect OpenSpec project

```
IF the working tree has an openspec/ directory at the repo root:
  Project uses OpenSpec → continue with the gate
ELSE:
  Skip the gate entirely. Go straight to step 5 (commit) and report
  "Specs: Skipped (no openspec/ dir)".
```

### 2. Identify the active change

The "active change" is the OpenSpec change folder whose deltas describe the diff you are about to commit. Use this heuristic, in order, and stop at the first match:

1. **List active changes** via `openspec list --changes --json` (parses to `{changes: [{name, ...}]}`). If the `openspec/changes/` directory does not exist, treat the result as `[]`.
2. **Exactly one active change** → use it.
3. **Multiple active changes** → read `git branch --show-current` and look for an exact match against any change `name`. Convention: branch name matches change name. If a match is found, use it.
4. **Multiple changes, no branch match** → ask the user via `AskUserQuestion`:

   ```
   Multiple OpenSpec changes are in flight. Which one does this commit belong to?

   1. <change-1>
   2. <change-2>
   …
   N. None of these (block / bypass)
   ```

   Do not guess.
5. **Zero active changes** → there is no delta target for behavioural code. Skip ahead to step 4 with `active_change = none`; the gate handles this case explicitly.

Record the resolved `active_change` (or `none`) before continuing.

### 3. Classify staged + unstaged changes

Walk the diff (`git diff --name-only HEAD` plus `git diff --cached --name-only`) and bucket each path:

- **Behavioral code** – extensions: `*.go`, `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.py`, `*.rb`, `*.rake`, `*.sh`, `*.bash`. Excluding test files (`*_test.go`, `*.test.ts`, `*.test.js`, `*.spec.ts`, `*.spec.js`, `*_test.py`, `tests/**/*.py`, `test/**`).
- **Active-change deltas** – paths matching `openspec/changes/<active_change>/specs/*/spec.md`. Only counts when the path is inside the resolved active change folder.
- **Always-allowed** – everything else, including:
  - `*.md` (other than spec deltas), `*.json`, `*.yaml`, `*.yml`, `*.toml`, `*.css`, `*.lock`
  - `go.mod`, `go.sum`, `package.json`, `package-lock.json`, `pnpm-lock.yaml`
  - `.gitignore`, `.cursorrules`, `.claude/**`, `.workflow/**`
  - Test files (see above)
  - Files under `openspec/specs/**` (base spec edits, e.g. archive landings) – allowed without an active change

This list mirrors `scripts/spec-check-hook.sh` so the skill and the hook agree on what counts.

### 4. Apply the gate

Decide the outcome from the buckets and the resolved active change:

- **No behavioural code changed** → pass. Final report: `Specs: No behavioral changes`.
- **Behavioural code changed AND active-change delta files modified** → pass. Final report: `Specs: Updated (<delta paths>)`.
- **Behavioural code changed, active change resolved, but no deltas modified** → warn:

  ```
  Behavioral changes detected but no deltas updated in the active change.
    Active change: <name>
    Changed code: <list>
    Expected delta location: openspec/changes/<name>/specs/<capability>/spec.md

  Specs should have been written BEFORE the code, not after.

  Options:
    1. Update deltas in the active change, then re-run /save-w-specs (recommended)
    2. Commit anyway (spec debt – will report Specs: Missing)
  ```

  Use `AskUserQuestion` for the choice. Never silently fall through.

- **Behavioural code changed AND no active change exists** → warn:

  ```
  Behavioral changes detected but no active OpenSpec change is in flight.
    Changed code: <list>

  OpenSpec requires deltas in an active change folder before behavioral code
  lands. Choose one:

    1. Create a new change first (run /brainstorm or `openspec new change <name>`)
    2. Commit anyway with --no-verify (spec debt)
  ```

  Use `AskUserQuestion`. If the user picks (1), stop and let them create the change; do not auto-commit. If the user picks (2), proceed and pass `--no-verify` to the commit so the pre-commit hook does not block.

**NEVER derive deltas from the code.** If deltas were not written as part of the workflow, that is a process gap to flag – not something to paper over by reverse-engineering deltas after the fact.

### 5. Commit

Evaluate what has changed and commit only work that is complete and appropriate for committing. Leave in-progress or half-finished work unstaged.

- Group related changes into logical commits – do not lump unrelated work together.
- Delta updates travel with their corresponding code changes.
- Stage specific files by name; never blindly `git add -A`.
- If some changes are ready and others are not, commit only the ready ones.

**Pre-commit hook failures.** The hook at `scripts/spec-check-hook.sh` enforces the same active-change rule. If it blocks a commit, the skill's gate should already have caught it – investigate before bypassing. Bypass with `--no-verify` only when the changes are genuinely non-behavioral (import reordering, comment edits) or when the user explicitly chose "commit anyway" in step 4.

### 6. Report spec status

After the commit succeeds, print one of:

- `Specs: Updated (<delta paths>)` – deltas in the active change were modified alongside code
- `Specs: No behavioral changes` – only config/docs/cosmetic/test changes
- `Specs: Skipped (no openspec/ dir)` – project does not use OpenSpec
- `Specs: Missing` – user chose to commit anyway with spec debt

Keep the message exactly in this format; downstream tooling and `080-spec-driven-dev.md` reference these strings.

## Active-change inference heuristic

The five-step heuristic in step 2 (one change → use it; multiple → branch match; otherwise ask; zero → block) is shared with `/ralph-review`. Both skills implement the same logic locally; if you change the heuristic in one, mirror it in the other. The pre-commit hook (`scripts/spec-check-hook.sh`) is intentionally simpler – it only checks whether *any* active-change delta is staged – and does not need branch inference.

## When NOT to use

- Nothing has changed since the last commit.
- You are mid-stage in a multi-step change that is not ready to checkpoint yet.
- You want to land a base-spec edit (e.g. an `openspec archive` result) – that landing should already include the merged deltas, so the gate passes naturally; just run `git commit` directly.
