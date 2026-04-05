---
name: ralph-review
description: "Use after implementing changes in a spec-driven project to review implementation against specs/plans — auto-fixes confident changes, parks questions for the user"
---

# Ralph Review

Autonomous self-review loop that runs after implementation. Reviews the full diff in a fresh context, classifies findings by confidence, auto-fixes what it can, commits, and repeats — until only questions for the user remain. Companion to `/ralph-loop` (which develops changes); this loop reviews them.

## Arguments

- `$ARGUMENTS` - Optional: spec/plan path, SHA, branch name, commit range, or natural language description of what to review

Invocation forms:
```
/ralph-review                          → auto-detect scope
/ralph-review specs/auth.md            → explicit spec, auto-detect diff
/ralph-review abc123                   → diff against specific SHA
/ralph-review "changes from this week" → natural language, agent interprets
```

User-provided arguments always win over auto-detection. If auto-detection is ambiguous, confirm with the user before proceeding.

## Context

- Current branch: !`git branch --show-current`
- Default branch ref: !`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | grep -v '^origin/HEAD$' | head -1`
- Git status: !`git status --short`
- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`
- Project type: !`find . -maxdepth 1 \( -name go.mod -o -name Gemfile -o -name package.json -o -name Cargo.toml -o -name pyproject.toml \) 2>/dev/null | head -5`
- Test framework: !`find . -maxdepth 4 -name "*_test.*" -o -name "*.test.*" -o -name "*_spec.*" 2>/dev/null | head -10`
- Recent spec changes: !`git diff --name-only HEAD~10..HEAD -- specs/ 2>/dev/null | head -10`
- Plan files: !`ls -t specs/plans/*.md 2>/dev/null | head -5`

---

## Phase 0: Resolve Scope

Before starting the review loop, resolve two things: what code to review (diff scope) and what to review it against (source of truth).

### Phase 0a: Resolve Diff Scope

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

### Phase 0b: Resolve Source of Truth

Determine what spec/plan to review against. **User-provided paths always win.**

```
IF $ARGUMENTS contains a path to a .md file:
  Use it directly as the source of truth (spec or plan, based on location)
  No confirmation needed

ELSE IF .specs file exists (spec-aware project):
  1. Find relevant specs from the diff:
     git diff --name-only {BASE}...HEAD -- specs/
  2. Also check recently modified specs:
     ls -t specs/*.md | head -5
  3. Use the most relevant spec as PRIMARY source of truth
  4. Read the FULL spec — not just the diff. The spec describes the whole system.
  5. Search for a plan (structural supplement):
     - specs/plans/ (project convention)
     - ~/.claude/plans/
     - ~/.claude/projects/*/plans/
  6. If plan found, note it as advisory context
  7. Auto-proceed — no user confirmation needed

ELSE IF no .specs file, but plan found:
  Search for plans in:
    - specs/plans/
    - Files changed in the diff
    - ~/.claude/plans/
    - ~/.claude/projects/*/plans/
  Use AskUserQuestion: "No specs found. Found plan: {path}. Use as source of truth?"
  If user confirms → proceed with plan
  If user declines → conservative mode

ELSE (neither found):
  Print: "No spec or plan found. Running in conservative mode (auto-fix only obvious bugs, security, lint)."
  Use AskUserQuestion to offer: "Provide a spec/plan path, or continue in conservative mode?"
```

### Confidence Tier

Based on what was found, set the confidence tier for the entire review:

```
IF spec found       → tier = "spec"         (behavioral + structural + bugs/security/lint)
ELSE IF plan found  → tier = "plan"         (structural + bugs/security/lint)
ELSE                → tier = "conservative" (bugs/security/lint only)
```

### Pre-Loop Setup

Record the starting point so ralph's own changes can be isolated later:

```bash
PRE_RALPH_SHA=$(git rev-parse HEAD)
```

Ensure the reviews directory exists and is gitignored:

```bash
mkdir -p .claude/reviews
# Add to .gitignore if not already covered
if ! git check-ignore -q .claude/reviews 2>/dev/null; then
  echo ".claude/reviews/" >> .gitignore
fi
```

Print a status summary:

```
Ralph-review starting:
- Diff scope: {description of what's being reviewed}
- Source of truth: {spec path | plan path | "conservative mode"}
- Confidence tier: {spec | plan | conservative}
- Pre-ralph SHA: {sha}
```

---

## Phase 1: Review Loop

### Overview

The main thread orchestrates a loop of up to 3 iterations. Each iteration:
1. Spawns a fresh review sub-agent (clean context)
2. Receives structured findings
3. Triages findings (auto-fix / park / skip)
4. Executes auto-fixes
5. Runs tests
6. Commits
7. Checks termination conditions

### Large Diff Handling

If the diff exceeds 1500 lines or touches more than 15 files, split the review across 2-3 focused sub-agents by package area (e.g., daemon, TUI, plugins). Each agent reviews its subset of files. The main thread merges findings, deduplicates, and triages as normal. This produces more thorough reviews than a single agent scanning a massive diff.

For smaller diffs, a single review agent is sufficient.

### Gathering Review Data

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

4. **Find dependent files** — files that import, require, or reference changed files. Use Grep to locate them. Read those too.

5. **Spec contents** (if available): Read the full spec file. Not just the section that changed — the entire spec. The reviewer needs the whole system's behavioral contract.

6. **Plan contents** (if available): Read the plan file.

7. **Test baseline:**
   - Detect the test framework from project type
   - Run the full test suite and record: PASS, FAIL (with details), or N/A
   - Run the linter if available and record: CLEAN, WARNINGS, or ERRORS

### Review Sub-Agent Briefing Template

Spawn a single review sub-agent using the `Agent` tool with `subagent_type="general-purpose"`. Do NOT use the 3-independent-reviewer pattern from `/rereview` — one thorough reviewer per loop is sufficient (3 reviewers × 3 loops = 9 agents is excessive).

Use the following prompt template:

````
You are a thorough code reviewer performing an autonomous review for the ralph-review loop.

MANDATE: Analyze every changed line. Classify every finding. When in doubt, flag it.

SUPPRESSION: Lines annotated with `// expected:` (or `# expected:` in Python/shell/YAML) have been reviewed and acknowledged by the user. Do not re-report findings on these lines unless the surrounding logic has materially changed since the comment was added. The comment text explains why the behavior is intentional — read it before deciding.

CONFIDENCE TIER: {confidence_tier}
- "spec": Spec is authoritative for behavior. Plan is advisory for structure.
- "plan": Plan is the best available context. No spec-based behavioral checks.
- "conservative": No spec or plan. Only flag obvious bugs, security issues, and lint.

DIFF SCOPE: {diff_scope_description}
BASE: {base_ref}

SPEC CONTENTS:
{spec_contents or "No spec available."}

PLAN CONTENTS:
{plan_contents or "No plan available."}

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

## Your Analyses

Perform ALL of the following. Do not skip any.

### 1. Behavior Audit
For every modified function, method, type, or exported symbol:
- What was the old behavior? What is the new behavior?
- Is this change intentional and justified?
- Could any caller break due to the change?
- Are defaults, return types, error conditions, or side effects altered?

### 2. Spec Compliance (spec tier only)
For every behavioral change:
- Does the spec describe the expected behavior?
- Does the code match the spec?
- Is there new behavior the spec doesn't mention? (→ SPEC-DRIFT)
- Does the code contradict the spec? (→ SPEC-DRIFT)

### 3. Plan Compliance (spec and plan tiers)
For structural decisions:
- Does the file organization match the plan?
- Are components placed where the plan specifies?
- Are patterns followed as the plan describes?

### 4. Regression Risk
For each changed file:
- What depends on this file?
- Could the change break dependent code?
- Are edge cases from the old behavior still handled?
- Were error handling or concurrency patterns changed?

### 5. Security Audit
Check: injection flaws, auth changes, credential exposure, input validation, XSS, insecure deserialization, vulnerable dependencies, error info leaks, missing rate limiting, crypto misuse, path traversal, SSRF.

### 6. Test Coverage Gaps
- Are behavior changes covered by tests?
- What test cases are missing?
- Are error paths and edge cases tested?
- If the spec describes behavior and the code implements it correctly but tests are missing — that's a test gap, not spec drift. Classify as [AUTO-FIX] and write the tests.

### 7. Line-by-Line Diff Review
For each hunk:
- Is removed code safe to remove?
- Is added code correct? Trace the logic.
- Off-by-one errors, nil/null risks, type mismatches?
- Boundary conditions handled?

---

## Classification

**Tag EVERY finding with exactly one of these:**

**[AUTO-FIX]** — You are confident this should be fixed, AND one of:
- Spec explicitly states the expected behavior and code doesn't match
- Test exists that should pass but doesn't (and the fix is clear)
- **Spec describes behavior, code implements it correctly, but tests are missing** — write the tests (this is a coverage gap, not drift)
- Obvious bug: nil pointer, off-by-one, unclosed resource, type mismatch
- Security issue: injection, credential exposure, missing auth check
- Lint violation with unambiguous fix
- Plan explicitly specifies structure and code deviates

For each [AUTO-FIX], include:
- File and line number
- What's wrong
- What the fix should be (specific enough to implement)
- Why you're confident (cite spec section, test, or bug category)

**[QUESTION]** — Needs user judgment:
- Spec is silent on this behavior
- Spec and code contradict but unclear which is stale
- Multiple valid fixes exist
- Design concern not addressed by spec or plan
- Behavioral change that looks intentional but has no spec coverage

For each [QUESTION], include:
- File and line number (for the main thread's reference)
- **What's happening** — plain language summary accessible to someone who didn't write the code. Lead with the observable behavior, not the implementation. e.g., "the UI freezes briefly during X" not "functionA() calls sleep() on the main thread."
- **What could go wrong** — the consequence in terms of system behavior, not code mechanics. e.g., "users could see stale data" not "the backing array could be shared."
- **Tradeoffs** — what you gain and what you lose with each option. Every design choice has a reason it exists; surface that. e.g., "removing the delay makes the operation feel snappier but risks the previous process not fully completing before the new one starts."
- **Recommendation** — what you think should be done and why, informed by the tradeoffs. Take a position.
- **Options** — put the recommendation first, then alternatives

Frame questions for a user who may not know the codebase. The code was likely written by Claude, not the user. Explain the *so what*, not the *how*. Reference the spec and desired behavior, not implementation details.

**[SPEC-DRIFT]** — Behavioral code without spec coverage (spec tier only):
- New behavior with no spec mention
- Changed behavior that contradicts spec
- Code implemented without spec updates

For each [SPEC-DRIFT], include:
- File and line number
- What the code does
- What the spec says (or "spec is silent on this")
- Draft recommendation for what the spec should say

**[ACKNOWLEDGED]** — Suppressed by `// expected:` comment:
- The line has an `// expected:` (or `# expected:`) annotation
- The annotation's reasoning still holds given the current surrounding code
- Do NOT re-report these. List them in a separate "Acknowledged" section for transparency only.
- If the surrounding logic has materially changed and the annotation may be stale, reclassify as `[QUESTION]` with a note that the `// expected:` comment should be reviewed.

**[SKIP]** — Not actionable:
- Stylistic preference with no spec/plan opinion
- "Could be improved" without correctness impact

---

## Output Format

Structure your report as:

### Findings

{Numbered list, each tagged with classification}

1. **[AUTO-FIX]** `file.go:42` — Description. Fix: {specific fix}. Confidence: {spec §X / test / obvious bug}.
2. **[QUESTION]** `handler.go:15` — Description. Needs: {what judgment}.
3. **[SPEC-DRIFT]** `auth.go:88` — New rate limiting behavior. Spec is silent. Recommend: "Add to spec §4: ..."
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

### Phase 1b: Triage Findings

After the sub-agent returns its report, the main thread triages each finding. **The main thread is the safety check** — it validates that auto-fix classifications are actually supported by the spec/plan.

1. Parse findings by classification tag
2. For each `[AUTO-FIX]`: verify the spec/plan actually supports this fix. If you disagree with the classification, reclassify as `[QUESTION]`.
3. For each `[SPEC-DRIFT]`: collect into a separate drift list
4. For each `[QUESTION]`: collect into the parked list
5. For each `[SKIP]`: collect into the skipped list

**Confidence tier governs what qualifies as auto-fixable:**

| Finding | With Spec | Plan Only | Neither |
|---------|-----------|-----------|---------|
| Behavior doesn't match spec | AUTO-FIX | n/a | n/a |
| Missing error handling | AUTO-FIX (if spec covers errors) | QUESTION | QUESTION |
| Wrong file structure | AUTO-FIX (if plan specifies) | AUTO-FIX (if plan specifies) | SKIP |
| Nil pointer dereference | AUTO-FIX | AUTO-FIX | AUTO-FIX |
| "Should use different pattern" | QUESTION | QUESTION | SKIP |

**Principle:** Less documented intent → less auto-fix, more park.

### Phase 1c: Execute Auto-Fixes

For each `[AUTO-FIX]` finding:

1. Implement the fix as described in the finding
2. After ALL fixes for this iteration are applied, run the test suite
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

### Phase 1d: Loop Control

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

  1. Spawn fresh review sub-agent with full diff → receives findings
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

## Spec Drift Handling

**Only active when confidence tier is "spec"** (project has `.specs` file). When tier is "plan" or "conservative," skip this section entirely — findings that would be spec drift just go into the `[QUESTION]` bucket.

### What Counts as Spec Drift

- New behavior in code with no spec mention
- Changed behavior that contradicts the spec
- Code implemented without corresponding spec updates

**NOT drift:** Spec describes behavior, code implements it correctly, but tests are missing. That's a test coverage gap — the sub-agent should classify it as `[AUTO-FIX]` and write the tests.

### During the Loop

`[SPEC-DRIFT]` findings are collected separately from `[QUESTION]` findings. They do NOT block the loop — they accumulate across iterations. Each drift item records:

- File and line(s) where unspecified behavior exists
- What the code does
- What the spec says (or "spec is silent on this")
- A draft recommendation for what the spec should say

### Post-Report Resolution

When the user chooses to address spec drift (see Phase 3):

Present each drift item one at a time via `AskUserQuestion`. For each item, show the draft recommendation and ask the user to approve, edit, or reject.

After the user responds to each item:

1. **Update the spec inline** — spec text changes are fast (just writing markdown), so do them in the main thread. Use `/spec-recommender` → `/spec-writer` if available, otherwise write directly.
2. **If code changes are needed** to match the updated spec, dispatch via `/fixit` in background.
3. **Move to the next drift item immediately** — don't wait for the fixit to complete.

Apply the same conflict avoidance rule as questions: if two fixits would touch the same files, serialize them.

After all drift items are addressed and any in-flight fixits complete, offer: "Specs updated. Restart ralph-review to validate against updated specs? (y/n)"

---

## Phase 2: Final Report

After the loop exits, update audit trail (if applicable) and generate the report.

### Audit Resolution Tracking

If the project has spec audits (`specs/audits/`), check whether any of ralph's fixes resolve tracked audit findings:

1. Find the latest audit: `ls -d specs/audits/*/ | sort | tail -1`
2. Read the audit's `index.md` — look for a "Resolution Status" section
3. If one exists, check whether any findings ralph fixed (auto-fix or user-directed) correspond to open audit items (contradictions, behavioral gaps, unimplemented promises)
4. Update the resolution table: mark items as resolved with the commit SHA and resolution type (spec fix, code fix, audit false positive)
5. Update the counters (e.g., "Contradictions — 19/19 resolved" or "Behavioral Gaps — 5/142 resolved")

If no Resolution Status section exists, create one following this format:

```markdown
## Resolution Status

### Contradictions — {resolved}/{total} resolved ({date})

| # | Issue | Resolution | Commit |
|---|-------|-----------|--------|
| 1 | {short description} | {resolution type} — {detail of what changed} | `{sha}` |

### Behavioral Gaps — {resolved}/{total} resolved

{same table format, or "Not yet started."}

### Unimplemented Spec Promises — {resolved}/{total} resolved

{same table format, or "Not yet started."}
```

**Resolution conventions:**
- **Resolution types:** "Spec fix", "Code fix", "Audit false positive" (audit was wrong — spec/code already agreed)
- **Resolution detail:** Brief description after the type (e.g., "Spec fix — removed all Threads references", "Code fix — added daemonAware interface")
- **Commit column:** SHA of the fix commit. Use `—` if no commit was needed (e.g., audit false positive)
- **Date in heading:** Include the date when items were resolved (e.g., `(2026-03-30)`)
- **Counters:** Keep `{resolved}/{total}` current in each subsection heading

This keeps the audit as the single durable record of what was found and what was done about it. Future sessions can read the audit index to know what's already resolved without re-investigating.

### Report File

```bash
mkdir -p .claude/reviews/$(date +%Y-%m-%d)
```

Write the report to `.claude/reviews/YYYY-MM-DD/ralph-review-report.md` AND display it in the terminal.

### Report Template

```markdown
# Ralph Review Report

## Summary
- **Loops completed:** {N} of 3 ({clean exit | max iterations reached})
- **Confidence tier:** {Spec | Plan | Conservative}
- **Source of truth:** {spec path | plan path | None}
- **Diff scope:** {description}
- **Pre-ralph SHA:** {PRE_RALPH_SHA} (use `git diff {PRE_RALPH_SHA}...HEAD` to see ralph's changes)

## Auto-Fixed
### Loop 1
1. {description} (source: {spec §X | plan | obvious bug})

### Loop 2
1. {description}

{Or "No auto-fixes were needed — code passed review cleanly."}

## Spec Drift
1. **New behavior:** {description} — spec is silent
   - Recommendation: {draft spec text}
2. **Contradiction:** Spec says {X}, code does {Y}
   - Need user input: which is correct?

{Or "No spec drift detected." or "N/A (no spec in use)"}

## Questions for You
1. {description} — {why the agent couldn't fix it}
2. {description} — {what judgment is needed}

{Or "No questions — all findings were resolved."}

## Skipped
- {N} stylistic suggestions (details in full report file)

## Ralph's Changes
- Commits: {N} ({SHA list})
- Files modified: {N}
- Tests: {passing | failing (details)}
```

---

## Phase 3: Post-Report Interaction

After displaying the report, present review options via `AskUserQuestion`. Only show options that have items.

```
What would you like to review?

1. Spec drift ({N} items)
2. Questions for you ({N} items)
3. Skipped findings ({N} items)
4. Ralph's changes ({N} commits, {N} files)
5. Done — accept as-is
```

### Option 1: Spec Drift

See "Spec Drift Handling → Post-Report Resolution" above.

### Option 2: Questions for You

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
3. Add to spec — this behavior is intentional, capture it
4. Defer — park this for a future session
```

After the user answers, dispatch the work in the background and immediately present the next question. The user's attention is the bottleneck — don't make them watch serial implementation.

**Dispatching by answer type:**

- **Fix it** → Use `/fixit` to background the fix in a worktree. Compose the fixit description from the finding + the user's answer. Move to the next question immediately.
- **Ignore** → Offer to add an `// expected:` comment to the relevant line(s) so future reviews don't re-report the same finding. Show the proposed annotation for approval (e.g., `// expected: broadcastMessage ignores handled bool`). If the user approves, add the comment and commit it. If they decline, skip silently. Either way, move to next finding.
- **Add to spec** → Update the spec file inline (this is fast — just text), then `/fixit` the implementation in background if code changes are needed. Move to the next question immediately.
- **Defer** → Create a todo marker in `specs/todo/` (see "Todo Markers" below). Move to the next question immediately.

**Conflict avoidance:** Before dispatching a `/fixit`, check if a previously dispatched fixit from this session touches the same file(s). If so, wait for that fixit to complete before dispatching the new one — concurrent worktrees editing the same files will cause merge conflicts. Independent files can run in parallel.

**After all questions are answered:** Wait for any in-flight fixits to complete and report their results. Then re-present the remaining review options.

### Option 3: Skipped Findings

Show the full list in the terminal. Ask via `AskUserQuestion`:

```
Any findings to promote?

1. Promote specific items (enter numbers)
2. None — keep all skipped
```

Promoted items get reclassified and handled per their new bucket (fix or question).

### Option 4: Ralph's Changes

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

### Loop Until Done

After completing any option, re-present the remaining options (minus completed ones) until the user picks Done or all options are exhausted.

---

## Todo Markers

When the user defers a finding (question or spec drift item), create a marker file in `specs/todo/`. These markers are lightweight pointers — they capture enough context to pick up the work in a new session without duplicating the full analysis.

### Format

```bash
mkdir -p specs/todo
```

Filename: `YYYY-MM-DD-slug.md` (sorts chronologically, human-scannable).

```markdown
---
source: .claude/reviews/YYYY-MM-DD/ralph-review-report.md
created: YYYY-MM-DD
skill: ralph-review
severity: low | medium | high
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
- Commit the marker in the same commit as other ralph-review changes, or standalone if the loop is done.

### Lifecycle

When the work is completed (via `/fixit`, `/spec-todo`, or manual fix), delete the marker file and commit the deletion alongside the fix.

---

## Failure Handling

| Failure | Action |
|---------|--------|
| No changes to review | Tell user and stop |
| Sub-agent fails to spawn | Retry once. If still fails, report error and stop |
| Sub-agent returns empty/malformed report | Note in summary, exit loop, produce report with what we have |
| Test suite fails to run | Note in report as increased risk, continue loop |
| Auto-fix breaks tests | Revert fix, reclassify as [QUESTION], continue |
| All findings are [SKIP] | Clean exit, report "No actionable issues found" |
| Max iterations with ongoing fixes | Flag in report: "May need another pass" |
| No spec AND no plan AND no `.specs` | Conservative mode — auto-fix only bugs/security/lint |
| User cancels mid-loop | Committed fixes stay (already committed). Report what was done so far |

## Graceful Degradation

| Available | Behavior |
|-----------|----------|
| Specs + spec-recommender + spec-writer | Full experience: review, fix, drift resolution, spec production |
| Specs only | Loop works fully. Drift reported, user writes specs manually |
| Plan only | Plan-advisory mode. No spec drift detection |
| Nothing | Conservative mode. Auto-fixes only obvious bugs/security/lint |
| No plannotator | Terminal report + GitHub PR option. No Plannotator annotation |

`/spec-recommender` and `/spec-writer` are available as companion skills. If they are not present in a given project, ralph-review degrades gracefully — spec drift items are reported as plain markdown recommendations instead of going through the interactive intent-resolution flow.
