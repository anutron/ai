---
name: spec-recommender
description: "Use when code exists without spec coverage to detect gaps, infer intent, and present options — works standalone or invoked by ralph-review for spec drift resolution"
---

# Spec Recommender

Detects code without spec coverage, infers developer intent, and presents options when ambiguous. Invokes `/spec-writer` to produce the actual text. Works in three modes:

1. **Standalone** — analyze the current diff for unspec'd behavioral changes
2. **Gap audit** — check an existing spec file for coverage holes
3. **Programmatic** — process pre-identified drift items from ralph-review

## Arguments

- `$ARGUMENTS` - Optional: a spec file path to audit, or nothing (auto-detect from diff)

Examples:
```
/spec-recommender                    → analyze current diff for unspec'd behavior
/spec-recommender specs/auth.md      → audit this spec for gaps
```

When invoked programmatically by ralph-review, drift items are passed as structured input (no arguments needed).

## Context

- Current branch: !`git branch --show-current`
- Default branch ref: !`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | grep -v '^origin/HEAD$' | head -1`
- Git status: !`git status --short`
- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`
- Recent spec changes: !`git diff --name-only HEAD~10..HEAD -- specs/ 2>/dev/null | head -10`

---

## Phase 1: Determine Mode

```
IF invoked programmatically with drift items (structured input from ralph-review):
  Mode = "programmatic"
  Items are pre-identified — skip to Phase 2
  Spec file path is provided by the caller

ELSE IF $ARGUMENTS contains a path to a .md file that exists:
  Mode = "gap-audit"
  Target = the provided spec file
  Skip to "Gap Audit Mode" below

ELSE:
  Mode = "standalone"
  Resolve diff scope and find spec (see below)
```

### Standalone: Resolve Diff Scope

Same logic as ralph-review Phase 0a:

```
IF there are unstaged or staged changes (from git status context):
  Diff scope = working tree changes
  BASE = HEAD

ELSE IF current branch != default branch (main/master):
  Diff scope = branch changes vs default branch
  BASE = default branch

ELSE (on main/master, nothing unstaged):
  Diff scope = local vs origin
  BASE = origin/{default}
```

If no changes found, tell the user "No changes to analyze" and stop.

### Standalone: Find the Spec

```
IF .specs file exists:
  1. Find specs modified in the diff: git diff --name-only {BASE}...HEAD -- specs/
  2. Also check recently modified specs: ls -t specs/*.md | head -5
  3. Use the most relevant spec
  4. Read the FULL spec file
ELSE:
  Print: "No .specs file — cannot detect spec drift without a spec to compare against."
  Stop.
```

### Standalone: Detect Unspec'd Behavior

1. Read the full diff
2. For each behavioral change (new function, modified behavior, changed error handling):
   - Check if the spec mentions this behavior
   - If not → it's an unspec'd behavior, add to the gap list
3. Proceed to Phase 2 with the gap list

---

## Phase 2: Analyze Each Gap

For each unspec'd behavior (from standalone detection, gap audit, or programmatic input):

```
1. Read the code — understand what it actually does
   - Read the full function/method, not just the changed lines
   - Check the surrounding code for context

2. Read the existing spec section (if any)
   - What does the spec say about this area?
   - Is it silent, vague, or contradictory?

3. Infer intent from available signals:
   a. Code itself — variable names, comments, patterns
   b. Tests — does a test describe the expected behavior?
   c. Commit messages — does the commit explain the intent?
   d. PR description or plan — any documented rationale?

4. Classify the gap:
   - CLEAR: Intent is unambiguous from the signals above
     → prepare a single recommendation
   - AMBIGUOUS: Multiple valid interpretations exist
     → prepare 2-3 options for the user to choose from
```

---

## Phase 3: Present to User

Present each gap one at a time using `AskUserQuestion`.

### For CLEAR Items

```
New behavior: {description}
File: {file:line}

Recommend adding to {spec file} §{section}:
  "{draft spec text}"

Options:
1. Approve — write this to the spec
2. Edit — provide revised text
3. Skip — don't spec this behavior
```

### For AMBIGUOUS Items

```
New behavior: {description}
File: {file:line}

The code does X, but the intent could be:
A) {interpretation 1} — {why this reading makes sense}
B) {interpretation 2} — {why this reading makes sense}
C) Something else — describe what you intended
```

After the user picks an interpretation, confirm the spec text:
```
Based on your choice, the spec text would be:
  "{draft spec text}"

Options:
1. Approve
2. Edit
3. Skip
```

---

## Phase 4: Write Specs

For each approved item, invoke `/spec-writer`:

```
Invoke Skill("spec-writer") with:
  "{approved intent text} — write to {spec file path}, {append | insert after §{section}}"
```

After all items are processed, print a summary:

```
Spec Recommender Summary:
- {N} spec sections written
- {N} skipped
- Files modified: {list}
- Not committed. Use /save-w-specs to commit, or the caller will handle it.
```

---

## Gap Audit Mode

When invoked with a spec file path (`/spec-recommender specs/auth.md`):

```
1. Read the spec file completely

2. Identify the code files the spec describes:
   - Look at Interface section for module paths
   - Look at Architecture section for component names
   - Search the codebase for imports/references to the spec's subject
   - Use Grep to find files that implement what the spec describes

3. Read each relevant code file

4. For each code file, look for:
   - Functions/methods with behaviors the spec doesn't mention
   - Error handling not described in the spec
   - Edge cases not covered (nil inputs, empty collections, boundary values)
   - Vague spec sections that could mean multiple things
     (e.g., "handles errors appropriately" — what does that actually mean?)

5. For each gap found, proceed through Phase 2 → Phase 3 → Phase 4
```

---

## What This Skill Does NOT Do

- **No auto-fixing code** — that's ralph-review's job
- **No writing spec text directly** — delegates to `/spec-writer`
- **No committing** — the caller handles that
- **No contradiction detection between specs** — ralph-review's review sub-agent catches those
- **No nagging about adopting specs** — if there's no `.specs` file, it says so and stops
