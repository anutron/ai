---
name: ralph-review
description: "Use after implementing changes in an OpenSpec project to review implementation against the active change's deltas — auto-fixes confident issues, parks questions for the user"
tags: [quality]
---

# Ralph review (OpenSpec)

Autonomous self-review loop that runs after implementation. Reviews the full diff in a fresh context, classifies findings by confidence, auto-fixes what it can, commits, and repeats — until only questions for the user remain. Companion to `/ralph-loop` (which develops changes); this loop reviews them.

The review target is the **active OpenSpec change's delta specs**. Ralph compares the diff against the deltas under `openspec/changes/<active>/specs/<capability>/spec.md`. The base specs at `openspec/specs/<capability>/spec.md` provide context for what already exists; the deltas are the contract for what *this change* should do.

## Arguments

- `$ARGUMENTS` – Optional: change name, SHA, branch name, commit range, or natural language description of what to review.

Invocation forms:

```
/ralph-review                          → auto-detect active change + diff scope
/ralph-review <change-name>            → review against the named change's deltas
/ralph-review abc123                   → diff against specific SHA, infer change
/ralph-review "changes from this week" → natural language, agent interprets
```

User-provided arguments always win over auto-detection. If auto-detection is ambiguous, confirm with the user before proceeding.

## Context

- Current branch: !`git branch --show-current`
- Default branch ref: !`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | grep -v '^origin/HEAD$' | head -1`
- Git status: !`git status --short`
- OpenSpec project: !`test -d openspec && echo "yes" || echo "no"`
- Active changes: !`test -d openspec/changes && openspec list --changes --json 2>/dev/null || echo "none"`
- Worktree info: !`git rev-parse --show-toplevel && echo "---" && git worktree list --porcelain 2>/dev/null | head -20`
- Main repo root: !`git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //'`
- Project type: !`find . -maxdepth 1 \( -name go.mod -o -name Gemfile -o -name package.json -o -name Cargo.toml -o -name pyproject.toml \) 2>/dev/null | head -5`
- Test framework: !`find . -maxdepth 4 -name "*_test.*" -o -name "*.test.*" -o -name "*_spec.*" 2>/dev/null | head -10`

---

## Phase 0: Resolve scope

Before starting the review loop, resolve three things: pre-flight validate OpenSpec, identify the active change, and resolve the diff scope.

### Phase 0a: OpenSpec pre-flight

If the project has an `openspec/` directory:

1. Run `openspec validate --all --strict`. If validation fails, surface the errors and stop – ralph cannot review against malformed deltas. The user fixes validation, then re-runs `/ralph-review`.
2. Once a specific active change is resolved (Phase 0b), run `openspec validate <change-name> --type change --strict` as a second sanity check. Fail fast on issues.

If the project has no `openspec/` directory, skip OpenSpec checks and run in **conservative mode** (auto-fix only obvious bugs, security, lint).

### Phase 0b: Identify the active change

Use the active-change inference heuristic, in order, and stop at the first match:

1. **`$ARGUMENTS` is a change name** (a directory exists at `openspec/changes/<arg>/`) → use it.
2. **List active changes** via `openspec list --changes --json` (parses to `{changes: [{name, ...}]}`). If `openspec/changes/` does not exist, treat the result as `[]`.
3. **Exactly one active change** → use it.
4. **Multiple active changes** → read `git branch --show-current` and look for an exact match against any change `name`. Convention: branch name matches change name. If a match is found, use it.
5. **Multiple changes, no branch match** → ask the user via `AskUserQuestion`:

   ```
   Multiple OpenSpec changes are in flight. Which one are you reviewing?

   1. <change-1>
   2. <change-2>
   …
   ```

   Do not guess.
6. **Zero active changes** → error out. Tell the user:

   ```
   Ralph-review needs an active OpenSpec change to review against, but
   openspec/changes/ is empty.

   Either:
     - Create a change first via /brainstorm or `openspec new change <name>`
     - Or, if the diff is unrelated to spec'd behavior, run /review (general
       code review) instead.
   ```

   Stop. Do not start the loop.

This heuristic is shared with `/save-w-specs`. If you change it in one skill, mirror it in the other.

### Phase 0c: Resolve diff scope

Determine the set of changes to review:

```
IF $ARGUMENTS contains a SHA, branch name, or commit range:
  Use that as the diff scope
  BASE = the provided reference
  Commands: git diff {BASE}...HEAD

ELSE IF there are unstaged or staged changes (from git status context):
  Diff scope = working tree changes
  BASE = HEAD
  Commands:
    git diff              (unstaged)
    git diff --cached     (staged)

ELSE IF current branch != default branch (main/master):
  Diff scope = branch changes vs default branch
  BASE = default branch
  Commands: git diff {default}...HEAD

ELSE (on main/master, nothing unstaged):
  Diff scope = local vs origin
  BASE = origin/{default}
  Commands: git diff HEAD...origin/{default}
```

If no changes are found in any of these, tell the user "Nothing to review" and stop.

### Phase 0d: Confidence tier

Based on what was found, set the confidence tier for the entire review:

```
IF active change resolved AND deltas exist  → tier = "spec"         (behavioral + structural + bugs/security/lint)
ELSE IF tasks.md exists in active change    → tier = "plan"         (structural + bugs/security/lint, deltas advisory)
ELSE                                        → tier = "conservative" (bugs/security/lint only)
```

In OpenSpec the deltas under `openspec/changes/<active>/specs/<capability>/spec.md` are the **spec source of truth** for the in-flight change. The base specs at `openspec/specs/<capability>/spec.md` provide context for unchanged behavior. `tasks.md` is the structural plan.

### Pre-loop setup

**Resolve the main repo root.** Ralph may be invoked from inside a git worktree. All durable artifacts (reviews, worktrees for fixes) must be written relative to the main repo, not the current worktree.

```bash
# MAIN_REPO is the root of the primary worktree (the original clone).
# CWD may be a secondary worktree — never nest worktrees inside worktrees.
MAIN_REPO=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
IS_WORKTREE=false
if [ "$(git rev-parse --show-toplevel)" != "$MAIN_REPO" ]; then
  IS_WORKTREE=true
fi
```

If `IS_WORKTREE` is true, all paths for `.claude/reviews/`, `.claude/worktrees/`, and `.gitignore` edits use `$MAIN_REPO` as the base — not the CWD. Git operations (diff, log, commit) still run in the CWD worktree as normal.

Record the starting point so ralph's own changes can be isolated later:

```bash
PRE_RALPH_SHA=$(git rev-parse HEAD)
```

Ensure the reviews directory exists and is gitignored:

```bash
mkdir -p "$MAIN_REPO/.claude/reviews"
# Add to .gitignore if not already covered (check in main repo)
if ! git check-ignore -q "$MAIN_REPO/.claude/reviews" 2>/dev/null; then
  echo ".claude/reviews/" >> "$MAIN_REPO/.gitignore"
fi
```

Print a status summary:

```
Ralph-review starting:
- Active change: {name}
- Delta files: {list of openspec/changes/<name>/specs/*/spec.md}
- Diff scope: {description of what's being reviewed}
- Confidence tier: {spec | plan | conservative}
- Pre-ralph SHA: {sha}
- Running in worktree: {yes — $CWD | no}
- Main repo: {$MAIN_REPO}
```

---

## Phase 1: Review loop

### Overview

The main thread orchestrates a loop of up to 3 iterations. Each iteration:

1. Spawns a fresh review sub-agent (clean context)
2. Receives structured findings
3. Triages findings (auto-fix / park / skip)
4. Executes auto-fixes
5. Runs tests
6. Commits
7. Checks termination conditions

### Large diff handling

If the diff exceeds 1500 lines or touches more than 15 files, split the review across 2-3 focused sub-agents by package area (e.g., daemon, TUI, plugins). Each agent reviews its subset of files. The main thread merges findings, deduplicates, and triages as normal. This produces more thorough reviews than a single agent scanning a massive diff.

For smaller diffs, a single review agent is sufficient.

### Gathering review data

Before the first loop iteration, collect everything the reviewer needs:

1. **Full diff:**

   ```bash
   git diff {BASE}...HEAD
   ```

2. **Changed files list:**

   ```bash
   git diff {BASE}...HEAD --name-only
   ```

3. **Read every changed file in its entirety.** The reviewer needs full context, not just diff hunks.

4. **Find dependent files** – files that import, require, or reference changed files. Use Grep to locate them. Read those too.

5. **Active-change deltas** – read every `openspec/changes/<active>/specs/<capability>/spec.md`. These are the contract for the in-flight change.

6. **Base specs** (context only) – for every capability touched by the active change, read `openspec/specs/<capability>/spec.md` so the reviewer understands what existed before the delta. The deltas describe *what is changing*; the base specs describe *what is*.

7. **`design.md` and `tasks.md`** (if present) – read both for structural context. `tasks.md` is the implementation plan.

8. **Test baseline:**
   - Detect the test framework from project type
   - Run the full test suite and record: PASS, FAIL (with details), or N/A
   - Run the linter if available and record: CLEAN, WARNINGS, or ERRORS

### Review sub-agent briefing template

Spawn a single review sub-agent using the `Agent` tool with `subagent_type="general-purpose"`. Do NOT use the 3-independent-reviewer pattern from `/rereview` — one thorough reviewer per loop is sufficient (3 reviewers × 3 loops = 9 agents is excessive).

Use the following prompt template:

````
You are a thorough code reviewer performing an autonomous review for the ralph-review loop.

MANDATE: Analyze every changed line. Classify every finding. When in doubt, flag it.

SUPPRESSION: Lines annotated with `// expected:` (or `# expected:` in Python/shell/YAML) have been reviewed and acknowledged by the user. Do not re-report findings on these lines unless the surrounding logic has materially changed since the comment was added. The comment text explains why the behavior is intentional — read it before deciding.

CONFIDENCE TIER: {confidence_tier}
- "spec": Active-change deltas are authoritative for the in-flight behavior. Base specs are context. tasks.md is advisory for structure.
- "plan": tasks.md is the best available context. No delta-based behavioral checks.
- "conservative": No deltas or plan. Only flag obvious bugs, security issues, and lint.

ACTIVE CHANGE: {change_name}
DIFF SCOPE: {diff_scope_description}
BASE: {base_ref}

ACTIVE-CHANGE DELTAS (the contract for this change):
{for each openspec/changes/<active>/specs/<cap>/spec.md, include path and full contents}

BASE SPECS (context — what existed before the change):
{for each touched capability, include openspec/specs/<cap>/spec.md path and contents, or "N/A — new capability"}

DESIGN / TASKS:
{contents of openspec/changes/<active>/design.md and tasks.md, if present}

FULL DIFF:
{full git diff}

CHANGED FILES (full contents):
{for each changed file, include filename and full contents}

DEPENDENT FILES (files that reference changed code):
{for each dependent file, include filename and full contents}

TEST BASELINE:
- Test suite result: {PASS / FAIL / N/A}
- Pre-existing failures: {list or "None"}
- Lint result: {CLEAN / WARNINGS / ERRORS}

---

## Your analyses

Perform ALL of the following. Do not skip any.

### 1. Behavior audit

For every modified function, method, type, or exported symbol:
- What was the old behavior? What is the new behavior?
- Is this change intentional and justified?
- Could any caller break due to the change?
- Are defaults, return types, error conditions, or side effects altered?

### 2. Delta compliance (spec tier only)

For every behavioral change:
- Does an active-change delta describe the expected behavior (in `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`, or `## RENAMED Requirements`)?
- Does the code match the delta's requirement + scenarios?
- Is there new behavior the deltas don't mention? (→ SPEC-DRIFT)
- Does the code contradict a delta scenario? (→ SPEC-DRIFT)
- For MODIFIED requirements, does the code reflect the new wording rather than the base spec's old wording?

### 3. Plan compliance (spec and plan tiers)

For structural decisions:
- Does the file organization match `tasks.md` and `design.md`?
- Are components placed where the plan specifies?
- Are patterns followed as the plan describes?

### 4. Regression risk

For each changed file:
- What depends on this file?
- Could the change break dependent code?
- Are edge cases from the old behavior still handled?
- Were error handling or concurrency patterns changed?

### 5. Security audit

Check: injection flaws, auth changes, credential exposure, input validation, XSS, insecure deserialization, vulnerable dependencies, error info leaks, missing rate limiting, crypto misuse, path traversal, SSRF.

### 6. Test coverage gaps

- Are behavior changes covered by tests?
- What test cases are missing?
- Are error paths and edge cases tested?
- If a delta scenario describes behavior and the code implements it correctly but tests are missing — that's a test gap, not spec drift. Classify as [AUTO-FIX] and write the tests.

### 7. Line-by-line diff review

For each hunk:
- Is removed code safe to remove?
- Is added code correct? Trace the logic.
- Off-by-one errors, nil/null risks, type mismatches?
- Boundary conditions handled?

---

## Classification

**Tag EVERY finding with exactly one of these:**

**[AUTO-FIX]** — You are confident this should be fixed, AND one of:
- A delta scenario explicitly states the expected behavior and code doesn't match
- Test exists that should pass but doesn't (and the fix is clear)
- **Delta describes behavior, code implements it correctly, but tests are missing** — write the tests (this is a coverage gap, not drift)
- Obvious bug: nil pointer, off-by-one, unclosed resource, type mismatch
- Security issue: injection, credential exposure, missing auth check
- Lint violation with unambiguous fix
- `tasks.md` explicitly specifies structure and code deviates

For each [AUTO-FIX], include:
- File and line number
- What's wrong
- What the fix should be (specific enough to implement)
- Why you're confident (cite delta requirement/scenario, base spec, test, or bug category)

**[QUESTION]** — Needs user judgment:
- Deltas are silent on this behavior
- Deltas and code contradict but unclear which is stale
- Multiple valid fixes exist
- Design concern not addressed by deltas or `tasks.md`
- Behavioral change that looks intentional but has no delta coverage

For each [QUESTION], include:
- File and line number (for the main thread's reference)
- **What's happening** — plain language summary accessible to someone who didn't write the code. Lead with the observable behavior, not the implementation. e.g., "the UI freezes briefly during X" not "functionA() calls sleep() on the main thread."
- **What could go wrong** — the consequence in terms of system behavior, not code mechanics. e.g., "users could see stale data" not "the backing array could be shared."
- **Tradeoffs** — what you gain and what you lose with each option. Every design choice has a reason it exists; surface that. e.g., "removing the delay makes the operation feel snappier but risks the previous process not fully completing before the new one starts."
- **Recommendation** — what you think should be done and why, informed by the tradeoffs. Take a position.
- **Options** — put the recommendation first, then alternatives

Frame questions for a user who may not know the codebase. The code was likely written by Claude, not the user. Explain the *so what*, not the *how*. Reference deltas and desired behavior, not implementation details.

**[SPEC-DRIFT]** — Behavioral code without delta coverage (spec tier only):
- New behavior with no delta mention
- Changed behavior that contradicts a delta scenario
- Code implemented without delta updates

For each [SPEC-DRIFT], include:
- File and line number
- What the code does
- What the deltas say (or "deltas are silent on this")
- Draft recommendation for what the delta should say (which capability, ADDED/MODIFIED, requirement text, scenarios)

**[ACKNOWLEDGED]** — Suppressed by `// expected:` comment:
- The line has an `// expected:` (or `# expected:`) annotation
- The annotation's reasoning still holds given the current surrounding code
- Do NOT re-report these. List them in a separate "Acknowledged" section for transparency only.
- If the surrounding logic has materially changed and the annotation may be stale, reclassify as `[QUESTION]` with a note that the `// expected:` comment should be reviewed.

**[SKIP]** — Not actionable:
- Stylistic preference with no delta or plan opinion
- "Could be improved" without correctness impact

---

## Output format

Structure your report as:

### Findings

{Numbered list, each tagged with classification}

1. **[AUTO-FIX]** `file.go:42` — Description. Fix: {specific fix}. Confidence: {delta requirement / scenario / test / obvious bug}.
2. **[QUESTION]** `handler.go:15` — Description. Needs: {what judgment}.
3. **[SPEC-DRIFT]** `auth.go:88` — New rate limiting behavior. Deltas are silent. Recommend: "Add to delta `openspec/changes/<active>/specs/auth/spec.md`: ..."
4. **[SKIP]** `utils.go:20` — Could use a more descriptive variable name.

### Summary

- AUTO-FIX count: {N}
- QUESTION count: {N}
- SPEC-DRIFT count: {N}
- ACKNOWLEDGED count: {N}
- SKIP count: {N}
- Regression confidence: HIGH / MEDIUM / LOW

Do NOT rush. Analyze every changed line. False positives are acceptable; false negatives are not.
````

### Phase 1b: Triage findings

After the sub-agent returns its report, the main thread triages each finding. **The main thread is the safety check** — it validates that auto-fix classifications are actually supported by the deltas / `tasks.md`.

1. Parse findings by classification tag.
2. For each `[AUTO-FIX]`: verify the delta or `tasks.md` actually supports this fix. If you disagree with the classification, reclassify as `[QUESTION]`.
3. For each `[SPEC-DRIFT]`: collect into a separate drift list.
4. For each `[QUESTION]`: collect into the parked list.
5. For each `[SKIP]`: collect into the skipped list.

**Confidence tier governs what qualifies as auto-fixable:**

| Finding | With deltas | tasks.md only | Neither |
|---------|-------------|---------------|---------|
| Behavior doesn't match delta scenario | AUTO-FIX | n/a | n/a |
| Missing error handling | AUTO-FIX (if delta covers errors) | QUESTION | QUESTION |
| Wrong file structure | AUTO-FIX (if `tasks.md` specifies) | AUTO-FIX (if `tasks.md` specifies) | SKIP |
| Nil pointer dereference | AUTO-FIX | AUTO-FIX | AUTO-FIX |
| "Should use different pattern" | QUESTION | QUESTION | SKIP |

**Principle:** Less documented intent → less auto-fix, more park.

### Phase 1c: Execute auto-fixes

For each `[AUTO-FIX]` finding:

1. Implement the fix as described in the finding.
2. After ALL fixes for this iteration are applied, run the test suite.
3. **If build succeeds and tests pass:**
   - First verify the build: `go build ./... 2>&1` (or the project's build command)
   - If build fails: revert changes, reclassify the offending fix as `[QUESTION]` with note: "Auto-fix broke build: {error}"
   - If build passes, run the test suite
   - If tests pass: commit with message: `ralph-review loop {N}: {summary of fixes}`
   - Record which findings were fixed
4. **If tests fail:**
   - Check test output to identify which fix likely broke things
   - Revert: `git reset --soft HEAD` (undo the staging, keep changes)
   - Then `git checkout -- .` to discard the changes
   - Reclassify the offending fix as `[QUESTION]` with note: "Auto-fix broke tests: {failure details}"
   - Re-apply remaining fixes (if any), re-test, re-commit
5. **If zero auto-fixes this iteration:** exit the loop (clean termination)

### Phase 1d: Loop control

```
iteration = 0
max_iterations = 3
all_fixed = []       # accumulated across all loops
all_parked = []      # [QUESTION] findings
all_skipped = []     # [SKIP] findings
all_drift = []       # [SPEC-DRIFT] findings

WHILE iteration < max_iterations:
  iteration += 1
  Print: "Ralph-review loop {iteration} of {max_iterations}..."

  1. Spawn fresh review sub-agent with full diff + deltas → receives findings
  2. Triage findings (Phase 1b)
  3. IF no [AUTO-FIX] findings this iteration:
       Print: "No auto-fixable issues found. Exiting loop."
       BREAK
  4. Execute auto-fixes (Phase 1c) → commit
  5. Append fixed items to all_fixed
  6. Merge new [QUESTION] into all_parked (deduplicate)
  7. Merge new [SKIP] into all_skipped (deduplicate)
  8. Merge new [SPEC-DRIFT] into all_drift (deduplicate)

IF iteration == max_iterations AND auto_fixes were made in last loop:
  Note: "Max iterations reached — may need another pass"
```

---

## Spec drift handling

**Only active when confidence tier is "spec"** (project has an openspec/ directory and an active change with deltas). When tier is "plan" or "conservative," skip this section entirely — findings that would be spec drift just go into the `[QUESTION]` bucket.

### What counts as spec drift

- New behavior in code with no delta mention in the active change
- Changed behavior that contradicts an existing delta scenario
- Code implemented without corresponding delta updates

**NOT drift:** Delta describes behavior, code implements it correctly, but tests are missing. That's a test coverage gap — the sub-agent should classify it as `[AUTO-FIX]` and write the tests.

### During the loop

`[SPEC-DRIFT]` findings are collected separately from `[QUESTION]` findings. They do NOT block the loop — they accumulate across iterations. Each drift item records:

- File and line(s) where unspecified behavior exists
- What the code does
- What the deltas say (or "deltas are silent on this")
- A draft recommendation for what the delta should say (capability, operation, requirement text, scenarios)

### Post-report resolution

When the user chooses to address spec drift (see Phase 3):

Present each drift item one at a time via `AskUserQuestion`. For each item, show the draft recommendation and ask the user to approve, edit, or reject.

Same background dispatch pattern as Questions — handle the user's response and present the next drift item in the same response.

After the user responds to each item:

1. **Update the delta inline** – delta edits are fast (just markdown), so do them in the main thread. Use `/spec-recommender` → `/spec-writer` if available, otherwise edit `openspec/changes/<active>/specs/<capability>/spec.md` directly. Prefer `## ADDED Requirements` for new behavior; copy the full requirement block when using `## MODIFIED Requirements`.
2. **Validate the change** – run `openspec validate <active> --type change --strict` after each delta edit. Fail loudly if the edit broke validation; revert if needed.
3. **If code changes are needed** to match the updated delta, dispatch a background fix agent using the same process described in Phase 3 ("Dispatching a background fix agent"). Print "Fix dispatched in background. Moving to the next drift item."
4. **Show the next drift item immediately** in the same response — don't wait for the fix to complete.

Apply the same conflict avoidance rule as questions: if two fixes would touch the same files, serialize them.

After all drift items are addressed and any in-flight fixes complete, offer: "Deltas updated. Restart ralph-review to validate against updated deltas? (y/n)"

---

## Phase 2: Final report

After the loop exits, generate the report.

### Report file

```bash
mkdir -p "$MAIN_REPO/.claude/reviews/$(date +%Y-%m-%d)"
```

Write the report to `$MAIN_REPO/.claude/reviews/YYYY-MM-DD/ralph-review-report.md` AND display it in the terminal. Always use the main repo root for reviews — never write them inside a worktree.

### Report template

```markdown
# Ralph review report

## Summary

- **Loops completed:** {N} of 3 ({clean exit | max iterations reached})
- **Confidence tier:** {Spec | Plan | Conservative}
- **Active change:** {name | None}
- **Delta files reviewed:** {list of openspec/changes/<active>/specs/*/spec.md}
- **Diff scope:** {description}
- **Pre-ralph SHA:** {PRE_RALPH_SHA} (use `git diff {PRE_RALPH_SHA}...HEAD` to see ralph's changes)

## Auto-fixed

### Loop 1

1. {description} (source: {delta requirement / scenario / `tasks.md` / obvious bug})

### Loop 2

1. {description}

{Or "No auto-fixes were needed — code passed review cleanly."}

## Spec drift

1. **New behavior:** {description} — deltas are silent
   - Recommendation: {draft delta text — capability, operation, requirement, scenarios}
2. **Contradiction:** Delta scenario says {X}, code does {Y}
   - Need user input: which is correct?

{Or "No spec drift detected." or "N/A (no active change)"}

## Questions for you

1. {description} — {why the agent couldn't fix it}
2. {description} — {what judgment is needed}

{Or "No questions — all findings were resolved."}

## Skipped

- {N} stylistic suggestions (details in full report file)

## Ralph's changes

- Commits: {N} ({SHA list})
- Files modified: {N}
- Tests: {passing | failing (details)}
```

---

## Phase 3: Post-report interaction

After displaying the report, present review options via `AskUserQuestion`. Only show options that have items.

```
What would you like to review?

1. Spec drift ({N} items)
2. Questions for you ({N} items)
3. Skipped findings ({N} items)
4. Ralph's changes ({N} commits, {N} files)
5. Done — accept as-is
```

### Option 1: Spec drift

See "Spec drift handling → Post-report resolution" above.

### Option 2: Questions for you

Present each finding one at a time via `AskUserQuestion`. Frame every question for someone who didn't write the code — the user likely directed Claude to build it, not hand-authored it. Lead with the situation and consequence, not implementation details.

```
Question {N} of {total}: {short descriptive title}

{What's happening — plain language, 2-3 sentences. No jargon, no line numbers
in the narrative. Explain the situation as you would to a product owner.}

{What could go wrong — the consequence in terms of system behavior.
e.g., "users could see stale data" not "the goroutine reads a shared pointer."}

{Tradeoffs — what you gain vs. what you lose with each option. Surface why
the current behavior might exist before recommending a change.}

Recommendation: {What Ralph thinks should be done and why, informed by
the tradeoffs. Take a position.}

1. Accept recommendation — {what that means concretely}
2. Ignore — mark as expected with an inline comment so future reviews skip it
3. Add to delta — this behavior is intentional, capture it in the active change
4. Defer — park this for a future session
```

After the user answers each item, dispatch any work in the background and present the next question in the same response. Every response that handles a user answer contains both:

1. The background dispatch (Agent tool call with `run_in_background: true`)
2. The next `AskUserQuestion` for the next item

**Dispatching by answer type:**

- **Fix code** → Dispatch a background fix agent following fixit's process (see dispatch template below). Print "Fix dispatched in background. Moving to the next item." then immediately show the next question.
- **Update delta** → Edit `openspec/changes/<active>/specs/<capability>/spec.md` inline in the main thread (just markdown, fast). Run `openspec validate <active> --type change --strict` after the edit. If code changes are also needed to match the updated delta, dispatch a background fix agent. Move to next item immediately.
- **Ignore** → Offer to add an `// expected:` comment to the relevant line(s) so future reviews don't re-report the same finding. Show the proposed annotation for approval (e.g., `// expected: broadcastMessage ignores handled bool`). If the user approves, add the comment and commit it. If they decline, skip silently. Either way, move to next finding.
- **Add to delta** → Same as "update delta" — capture the intentional behavior in the active change's deltas, then dispatch a background fix agent if code changes are needed. Move to the next question immediately.
- **Defer** → Create a todo marker in `.workflow/todo/` (see "Todo markers" below). Move to the next question immediately.

### Dispatching a background fix agent

Each fix follows the same process as `/fixit` — worktree isolation, spec-first ordering, agent-driven-development, two-stage review, and proper merge/cleanup. Read `.claude/skills/fixit/SKILL.md` for the full pattern.

**Step 1: Triage.** Run up to 3 Glob/Grep calls (paths only) to locate likely files. Do not read source code.

**Step 2: Create worktree.** Always create worktrees relative to `$MAIN_REPO`, never inside the current worktree.

```bash
SLUG="ralph-fix-<short-slug>"
git worktree add -b "$SLUG" "$MAIN_REPO/.claude/worktrees/$SLUG" HEAD
```

If the branch already exists, clean up first:

```bash
git worktree remove "$MAIN_REPO/.claude/worktrees/$SLUG" --force 2>/dev/null
git branch -D "$SLUG" 2>/dev/null
```

**Step 3: Dispatch.** Use the Agent tool with `run_in_background: true` and `mode: "bypassPermissions"`:

````
## Ralph-review fix: <short title>

### Context

- Main repo root: <$MAIN_REPO>
- Working directory: <worktree path>
- Branch: <SLUG>
- Active OpenSpec change: <change name>

### Issue

<finding description — what's wrong, what should change, and why>

### Affected files

<file paths and line numbers from the finding>

### Delta context

<relevant delta from openspec/changes/<active>/specs/<cap>/spec.md, or "No delta context">

### User direction

<what the user chose — "fix code", "update delta", their specific instructions>

### OpenSpec project

This project uses OpenSpec. Active change: <change name>.

**You MUST follow spec-first order:**

1. Read the active-change deltas at `openspec/changes/<active>/specs/<capability>/spec.md`
2. Update the relevant delta to reflect the expected behavior (if needed)
3. Validate: `openspec validate <active> --type change --strict`
4. Write/update a test that validates the delta scenario
5. Implement the fix to pass the test
6. Run all tests
7. Commit with message: "ralph-review: <short description>"

Include the delta file in your commit.

### Debugging references

Read these before investigating:

- `.claude/skills/debug/root-cause-tracing.md` — systematic hypothesis-driven debugging
- `.claude/skills/debug/defense-in-depth.md` — making fixes robust against related failures

### Instructions

Implementation follows agent-driven-development pattern for a single task. Read `.claude/skills/agent-driven-development/SKILL.md`.

1. Explore the codebase to understand the problem
2. Follow spec-first order above
3. Follow TDD discipline per `.claude/skills/test-driven-development/SKILL.md`
4. Self-review per `.claude/skills/verification-before-completion/SKILL.md`
5. Run tests
6. Commit with message: "ralph-review: <short description>"
7. Report status: DONE | DONE_WITH_CONCERNS | BLOCKED

### Constraints

- Work ONLY in your worktree directory
- Follow existing codebase patterns
- Keep the fix minimal — don't refactor surrounding code
- If tests fail after your fix, investigate and resolve
````

**Step 4: Print one line and move on** — do not wait for the agent.

**On agent completion:** Follow the same completion flow as `/fixit` — two-stage review (spec reviewer → code quality reviewer), merge to original branch, worktree cleanup. Report result to user when done.

**Conflict avoidance:** Before dispatching, check if a previously dispatched fix from this session touches the same file(s). If so, wait for that fix to complete before dispatching the new one — concurrent worktrees editing the same files will cause merge conflicts. Independent files can run in parallel.

**After all items are answered:** Wait for any in-flight fixes to complete and report their results. Then re-present the remaining review options.

### Option 3: Skipped findings

Show the full list in the terminal. Ask via `AskUserQuestion`:

```
Any findings to promote?

1. Promote specific items (enter numbers)
2. None — keep all skipped
```

Promoted items get reclassified and handled per their new bucket (fix or question).

### Option 4: Ralph's changes

Use `AskUserQuestion` to ask how to review:

```
How would you like to review ralph's changes?

1. Show diff in terminal
2. Open in Plannotator (annotate the report)
3. Create GitHub PR
```

- **Terminal diff:** `git diff {PRE_RALPH_SHA}...HEAD`
- **Plannotator** (only offer if available — check `which plannotator 2>/dev/null`): `plannotator annotate .claude/reviews/YYYY-MM-DD/ralph-review-report.md`
- **GitHub PR:** `gh pr create` with the ralph-review report as the PR body

### Option 5: Done

Accept everything and exit. Print:

```
Ralph-review complete.
- {N} issues auto-fixed across {N} loops
- {N} questions parked for you
- {N} spec drift items {resolved | pending}
- Report saved to: .claude/reviews/YYYY-MM-DD/ralph-review-report.md
```

### Loop until done

After completing any option, re-present the remaining options (minus completed ones) until the user picks Done or all options are exhausted.

---

## Active-change inference heuristic

The six-step heuristic in Phase 0b ($ARGUMENTS → list → 1 → branch match → ask → 0 = error) is shared with `/save-w-specs`. Both skills implement the same logic locally; if you change the heuristic in one, mirror it in the other.

---

## Todo markers

When the user defers a finding (question or spec drift item), create a marker file in `.workflow/todo/`. These markers are lightweight pointers — they capture enough context to pick up the work in a new session without duplicating the full analysis.

### Format

```bash
mkdir -p .workflow/todo
```

Filename: `YYYY-MM-DD-slug.md` (sorts chronologically, human-scannable).

```markdown
---
source: .claude/reviews/YYYY-MM-DD/ralph-review-report.md
created: YYYY-MM-DD
skill: ralph-review
severity: low | medium | high
active_change: <change name at the time the marker was created>
files:
  - path/to/affected/file.go
  - path/to/other/file.go
---

# Short title

1-3 sentence description of what needs to happen and why.

See source report for full analysis.
```

### Rules

- Keep the body short — the source report has the details.
- The `files` list helps the `/spec-todo` skill estimate conflicts and scope.
- The `severity` comes from the finding's classification context (security → high, design question → medium, style → low).
- The `active_change` field records which change was in flight; useful when the deferred item is picked up later and the change has since archived.
- Commit the marker in the same commit as other ralph-review changes, or standalone if the loop is done.

### Lifecycle

When the work is completed (via `/fixit`, `/spec-todo`, or manual fix), delete the marker file and commit the deletion alongside the fix.

---

## Failure handling

| Failure | Action |
|---------|--------|
| No changes to review | Tell user and stop |
| `openspec validate --all --strict` fails in Phase 0a | Surface errors, stop, do not start the loop |
| No active change in `openspec/changes/` | Error and stop (see Phase 0b step 6) |
| Sub-agent fails to spawn | Retry once. If still fails, report error and stop |
| Sub-agent returns empty/malformed report | Note in summary, exit loop, produce report with what we have |
| Test suite fails to run | Note in report as increased risk, continue loop |
| Auto-fix breaks tests | Revert fix, reclassify as [QUESTION], continue |
| All findings are [SKIP] | Clean exit, report "No actionable issues found" |
| Max iterations with ongoing fixes | Flag in report: "May need another pass" |
| No openspec/ AND no plan | Conservative mode — auto-fix only bugs/security/lint |
| User cancels mid-loop | Committed fixes stay (already committed). Report what was done so far |

## Graceful degradation

| Available | Behavior |
|-----------|----------|
| OpenSpec + active change with deltas + spec-recommender + spec-writer | Full experience: review, fix, drift resolution, delta production |
| OpenSpec + active change with deltas only | Loop works fully. Drift reported, user writes deltas manually |
| OpenSpec but no active change | Phase 0b errors out — user must create a change first or run `/review` |
| `tasks.md` only (no deltas) | Plan-advisory mode. No spec drift detection |
| No openspec/ directory | Conservative mode. Auto-fixes only obvious bugs/security/lint |
| No plannotator | Terminal report + GitHub PR option. No Plannotator annotation |

`/spec-recommender` and `/spec-writer` are companion skills. If they are not present in a given project, ralph-review degrades gracefully — spec drift items are reported as plain markdown recommendations instead of going through the interactive intent-resolution flow.
