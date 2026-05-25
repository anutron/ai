---
name: spec-recommender
description: "Use when code exists without spec coverage to detect gaps, infer intent, and recommend OpenSpec capabilities + requirements. Output points the user at `openspec instructions specs` to scaffold the right structure."
tags: [spec]
---

# Spec Recommender

Detects code without OpenSpec coverage, infers developer intent, and **recommends capabilities + requirements** that should exist in `openspec/specs/`. Points the user at the OpenSpec workflow (`openspec new change` → `openspec instructions specs` → `/spec-writer`) to actually scaffold the structure. Works in three modes:

1. **Standalone** — analyze the current diff for unspec'd behavioral changes
2. **Capability gap audit** — check an existing capability spec for coverage holes
3. **Programmatic** — process pre-identified drift items from `/ralph-review` or `/spec-audit`

OpenSpec-only. Legacy `.specs` projects must run `/migrate-to-openspec` first.

## Arguments

- `$ARGUMENTS` - Optional: a capability name (or `openspec/specs/<capability>/spec.md` path) to audit, or nothing (auto-detect from diff)

Examples:

```
/spec-recommender                                 -> analyze current diff for unspec'd behavior
/spec-recommender authentication                  -> audit the `authentication` capability for gaps
/spec-recommender openspec/specs/auth/spec.md     -> same, by path
```

When invoked programmatically by `/ralph-review` or `/spec-audit`, drift items are passed as structured input (no arguments needed).

## Context

- OpenSpec project: !`test -d openspec && echo "yes" || echo "no openspec/ dir"`
- Current branch: !`git branch --show-current 2>/dev/null || echo '(not in a git repo)'`
- Default branch ref: !`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | grep -v '^origin/HEAD$' | head -1`
- Git status: !`git status --short 2>/dev/null || echo '(not in a git repo)'`
- Existing capabilities: !`openspec list --specs 2>/dev/null | head -10`
- Active changes: !`openspec list --changes 2>/dev/null | head -10`
- Recent base spec changes: !`git diff --name-only HEAD~10..HEAD -- openspec/specs/ 2>/dev/null | head -10`

---

## Prerequisites

- `openspec` CLI on `PATH` → otherwise: "OpenSpec CLI is required. Install with `npm install -g @openspec/cli`."
- `openspec/` directory exists in CWD → otherwise: "This project doesn't use OpenSpec. Run `openspec init` (or `/migrate-to-openspec` if it has a legacy `.specs` system) first."

---

## Phase 1: Determine Mode

```
IF invoked programmatically with drift items (structured input from ralph-review or spec-audit):
  Mode = "programmatic"
  Items are pre-identified — skip to Phase 2
  Capability/spec target is provided by the caller (or unset, meaning "recommend a new capability")

ELSE IF $ARGUMENTS contains a capability name OR a path to an existing `openspec/specs/<cap>/spec.md`:
  Mode = "capability-gap-audit"
  Resolve to the capability name
  Skip to "Capability Gap Audit Mode" below

ELSE:
  Mode = "standalone"
  Resolve diff scope and find the right capability (see below)
```

### Standalone: Resolve Diff Scope

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

### Standalone: Find the Capability

```
1. List capabilities via `openspec list --specs`.

2. Capabilities modified in the diff:
   git diff --name-only {BASE}...HEAD -- openspec/specs/
   For each path matching `openspec/specs/<cap>/spec.md`, capture <cap>.

3. If a single capability matches → use it.
   If multiple → ask the user which one (AskUserQuestion).
   If none → the diff might be code-only with no spec change yet; treat the diff as
   "unspec'd behavior" and recommend either an existing capability or a new one.
```

### Standalone: Detect Unspec'd Behavior

1. Read the full diff.
2. For each behavioral change (new function, modified behavior, changed error handling):
   - If a likely capability exists, fetch its current base spec via `openspec show <capability>` and check whether the behavior is mentioned.
   - If not → it's an unspec'd behavior. Add to the gap list with a candidate capability (existing or new).
3. Proceed to Phase 2 with the gap list.

---

## Phase 2: Analyze Each Gap

For each unspec'd behavior:

```
1. Read the code — understand what it actually does.
   - Read the full function/method, not just the changed lines.
   - Check the surrounding code for context.

2. Read the existing capability spec (if any) via `openspec show <capability>`.
   - What requirements already exist?
   - Is the behavior silent, vague, or contradictory in the spec?

3. Infer intent from available signals:
   a. Code itself — variable names, comments, patterns
   b. Tests — does a test describe the expected behavior?
   c. Commit messages — does the commit explain the intent?
   d. Proposal/design docs in `openspec/changes/` — any documented rationale?

4. Classify the gap:
   - CLEAR: Intent is unambiguous from the signals above
     → prepare a single recommendation
   - AMBIGUOUS: Multiple valid interpretations exist
     → prepare 2-3 options for the user to choose from

5. Decide capability shape:
   - Belongs in an existing capability → recommend `MODIFIED Requirements` (or `ADDED Requirements`) in that capability
   - Belongs in a new capability → recommend a kebab-case capability name + 1-N requirements for it
```

---

## Phase 3: Present to User

Present each gap one at a time using `AskUserQuestion`. Frame recommendations as **OpenSpec capabilities and requirements**, not as raw text.

### For CLEAR Items

```
New behavior: {description}
File: {file:line}

Recommend adding to capability `{capability}` (existing):
  Requirement: {requirement name (Title Case, action-oriented)}
  Description: {one-line SHALL/MUST statement}
  Scenarios:
    - WHEN {trigger} / THEN {outcome}
    - {edge case if applicable}

Operation: ADDED Requirements (or MODIFIED Requirements if updating in place)

Options:
1. Approve — record this recommendation
2. Edit — provide revised name/description/scenarios
3. Skip — don't spec this behavior
```

### For NEW CAPABILITY items

```
New behavior: {description}
File: {file:line}

Recommend a NEW capability:
  Name: {kebab-case-name}
  One-liner: {what this capability covers}
  Initial requirements:
    1. {requirement name}
       SHALL/MUST {description}
    2. {requirement name}
       SHALL/MUST {description}

Bootstrap commands:
  openspec new change add-{kebab-case-name}
  /spec-writer proposal add-{kebab-case-name}
  /spec-writer specs add-{kebab-case-name}

Options:
1. Approve — record this recommendation
2. Edit — adjust capability name or requirements
3. Skip — don't spec this behavior
```

### For AMBIGUOUS Items

```
New behavior: {description}
File: {file:line}

The code does X, but the intent could be:
A) {interpretation 1} — {why this reading makes sense} → capability `{cap-A}`, requirement `{name-A}`
B) {interpretation 2} — {why this reading makes sense} → capability `{cap-B}`, requirement `{name-B}`
C) Something else — describe what you intended
```

After the user picks an interpretation, confirm the recommendation as a CLEAR item and move on.

---

## Phase 4: Hand off to OpenSpec

Spec-recommender does NOT write spec files directly. After all approved recommendations are collected, present a single hand-off block per change scope:

### If recommendations target **existing capabilities** only

The user should fold them into an active change. Output:

```
Recommended deltas for capability `{capability}`:

## ADDED Requirements

### Requirement: {name}
{description}

#### Scenario: {scenario name}
- **WHEN** {trigger}
- **THEN** {outcome}

...

To apply:
  - If a change is already active for this capability, add these to its delta spec at:
      openspec/changes/<change>/specs/{capability}/spec.md
  - Otherwise create one:
      openspec new change <change-name>
      /spec-writer specs <change-name>
    then paste the deltas above.
```

### If recommendations include a **new capability**

```
Recommended new capability: `{kebab-case-name}`

Bootstrap:

  openspec new change add-{kebab-case-name}

Then run:

  /spec-writer proposal add-{kebab-case-name}
  /spec-writer specs add-{kebab-case-name}

Pre-filled requirements (paste into the delta spec):

## ADDED Requirements

### Requirement: {name 1}
{description}

#### Scenario: ...

### Requirement: {name 2}
...
```

After printing the hand-off block, print a summary:

```
Spec Recommender Summary:
- {N} recommendations targeting existing capabilities
- {N} recommendations proposing new capabilities
- {N} skipped
- Next: run the bootstrap commands above, then `/spec-writer specs <change-name>`
- Not committed. The caller (or you) handles git after the change is scaffolded.
```

---

## Capability Gap Audit Mode

When invoked with a capability name or `openspec/specs/<cap>/spec.md` path:

```
1. Run `openspec show <capability>` to fetch the full requirement/scenario tree.

2. Identify the code files this capability describes:
   - Look at the spec's overview and requirement text for module paths.
   - Search the codebase for imports/references to the capability's subject (Grep).
   - Cross-check `openspec/.audit-config.json` (if present) for `modules[].specs`
     mappings — that's the most reliable answer.

3. Read each relevant code file.

4. For each code file, look for:
   - Functions/methods with behaviors no requirement covers
   - Error handling not described in any scenario
   - Edge cases not covered (nil inputs, empty collections, boundary values)
   - Vague requirements that could mean multiple things
     (e.g., "handles errors appropriately" — what does that actually mean?)

5. For each gap found, proceed through Phase 2 → Phase 3 → Phase 4.
```

---

## What This Skill Does NOT Do

- **No code authoring** — that's `/ralph-review`'s job for confident drift, or the user's for new features.
- **No spec text writing** — outputs structured recommendations; uses `/spec-writer` (or the user) to actually scaffold via `openspec instructions specs`.
- **No commits** — the caller handles that.
- **No legacy spec mode** — `.specs` projects must run `/migrate-to-openspec` first.
- **No nagging about adopting OpenSpec** — if there's no `openspec/` directory, it says so and stops.
- **No contradiction detection between requirements** — `/ralph-review`'s sub-agent catches those.
