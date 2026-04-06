---
name: spec-audit
description: "Audit codebase spec coverage — inventory files and specs, map them, dispatch agents to find behavioral gaps. Use when the user wants to check spec health or find coverage holes."
---

# Spec Audit

Comprehensive audit of spec coverage across a codebase. Inventories code and specs, maps them (many-to-many), dispatches agents to find behavioral gaps in both directions, and writes results to disk. For projects that have adopted specs but want to find where coverage has drifted.

Not for codebases with zero specs — that's a backfill task, not an audit.

## Arguments

- `$ARGUMENTS` - Optional: directory or module scope (e.g., `internal/auth/`, `src/api/`), or `--full` to force a full audit. Without arguments, audits the entire project (incremental if a previous audit exists).

## Context

- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`
- Project type: !`find . -maxdepth 1 \( -name go.mod -o -name Gemfile -o -name package.json -o -name Cargo.toml -o -name pyproject.toml \) 2>/dev/null | head -5`
- Spec files: !`find specs/ -name "*.md" -not -path "*/plans/*" -not -path "*/todo/*" -not -path "*/audits/*" 2>/dev/null | head -30`
- Code file count: !`find . \( -name "*.go" -o -name "*.ts" -o -name "*.py" -o -name "*.rb" -o -name "*.js" \) -not -name "*_test.go" -not -name "*.test.*" -not -name "*.spec.*" -not -path "*/test/*" -not -path "*/__tests__/*" | grep -v node_modules | grep -v vendor | wc -l`
- Last audit: !`ls -t specs/audits/*/index.md 2>/dev/null | head -1`
- Current date: !`date +%Y-%m-%d`

---

## Prerequisites

**Fail immediately if:**
- No `.specs` file exists → "This project doesn't use specs. Add a `.specs` file to opt in."
- No spec files found in the spec directory → "No spec files found. Write specs first, then audit. Use `/spec-recommender` to get started."
- Massive imbalance: more than 10x code files vs spec files AND specs appear to be file-organized (1:1 with code files) → Present the ratio and ask: "This project has {N} code files but only {M} specs. An audit would flag almost everything as uncovered. Consider running `/spec-recommender` first to build baseline coverage, then audit. Proceed anyway? (y/n)" **Skip this check if specs are feature-organized** (e.g., organized by area like `specs/core/`, `specs/plugin/`, `specs/builtin/`). Feature-organized specs routinely cover 10-20 code files each, making the raw ratio misleading. Instead, proceed to the mapping phase and assess actual coverage after mapping.

**Note on code file count:** The context section's `find` count may include non-behavioral files (vendored dependencies, generated bundles, prototype HTML). For the imbalance check, use the raw count as a signal but do not block on it if the project uses feature-organized specs. The inventory phase (Phase 1a) establishes the true count of behavioral source files.

---

## Phase 0: Incremental Detection

Before running the full audit pipeline, determine whether an incremental audit is possible. This phase decides the audit mode: **full**, **incremental**, or **no-op**.

### Step 1: Check for previous audit

```bash
LAST_AUDIT=$(ls -td specs/audits/*/inventory.json 2>/dev/null | head -1)
```

If no previous audit exists → **full audit**. Skip the rest of Phase 0.

### Step 2: Check for explicit overrides

- If `$ARGUMENTS` contains `--full` → **full audit** (strip `--full` from arguments before continuing)
- If `$ARGUMENTS` contains a scoped path (e.g., `src/api/`) → **scoped full audit** (no incremental, no SHA update at end — a scoped audit doesn't cover the full graph)

### Step 3: Read previous commit SHA

Read the `commit_sha` field from the previous audit's `inventory.json`.

If the field is missing or empty → **full audit** (legacy audit without SHA tracking).

### Step 3b: Verify previous audit completeness

Check that `mapping.json` exists in the previous audit directory. If it is missing → **full audit** with message: `"Previous audit at {date} is incomplete (no mapping). Running full audit."`

### Step 4: Compute changed files

```bash
git diff <previous_sha>..HEAD --name-only
```

If `git diff` fails (detached HEAD, shallow clone, etc.) → **full audit** with warning: `"Could not compute diff from {sha}. Running full audit."`

Filter the diff output to code files and spec files only (same extensions as the inventory scan: `*.go`, `*.ts`, `*.py`, `*.rb`, `*.js`, and `specs/*.md`).

If no code or spec files changed → **no-op**:
```
No spec-relevant changes since last audit ({sha}, {date}). Run `/spec-audit --full` to re-audit everything.
```
Stop here. Do not proceed to Phase 1.

### Step 5: Check auto-escalation triggers

Escalate to **full audit** (with reason printed) if any of these are true:

1. **Spec files were added or deleted** (not just modified — check `git diff --diff-filter=AD` for spec files):
   ```
   Spec files added/deleted since last audit. Running full audit.
   ```

2. **Affected modules exceed 30% of total modules** (computed after the graph walk in Step 6):
   ```
   Significant changes detected ({N}% of modules affected). Running full audit.
   ```

### Step 6: Graph walk — determine affected modules

Walk the mapping graph bidirectionally using the previous audit's `mapping.json`:

1. **Changed code file** → find its mapped spec sections → find all other code files mapped to those same sections
2. **Changed spec file** → find all code files mapped to it

Collect all affected files, then group by module directory to get the affected module set.

If affected modules exceed 30% of the previous audit's total modules → auto-escalate (Step 5.2).

### Step 7: Print incremental summary

```
Incremental audit: {N} files changed since {sha} ({date})
Affected modules: {list of module paths}
Unaffected modules: {N} (skipped)
```

Set `$AUDIT_MODE = incremental` and `$AFFECTED_MODULES` for use in later phases.

---

## Phase 1: Inventory

### 1a: Deterministic scan (no LLM)

Enumerate all code files and spec files. For each code file, extract:
- File path
- Exported functions/methods/classes (language-aware: use `grep` for signatures)
- Language

For each spec file, extract:
- File path
- Section headings (each heading is a potential behavior unit)

**Audit directory naming:** Use `specs/audits/{date}/` for the first audit on a given day. If an audit directory for today already exists, append a version suffix: `{date}_v2`, `{date}_v3`, etc. Never overwrite a previous audit — preserve all results for delta comparison.

Write to `specs/audits/{date}/inventory.json`:

```json
{
  "date": "YYYY-MM-DD",
  "commit_sha": "<current HEAD short SHA — run `git rev-parse --short HEAD`>",
  "scope": "full | incremental | <scoped path>",
  "code_files": [
    {
      "path": "internal/auth/handler.go",
      "language": "go",
      "exports": ["Authenticate", "RefreshToken", "Logout"]
    }
  ],
  "spec_files": [
    {
      "path": "specs/authentication.md",
      "sections": ["Purpose", "Login Flow", "Token Refresh", "Error Handling"]
    }
  ],
  "counts": {
    "code_files": 47,
    "spec_files": 12,
    "exports": 183
  }
}
```

### 1b: LLM-assisted mapping

The deterministic scan can't map feature-organized specs to technically-organized code. Use an agent to build the many-to-many map.

Spawn a single agent with the full list of code files (paths + exports) and spec files (paths + sections). Its job:

```
Given these code files and spec files, produce a mapping.

For each code file, list which spec file(s) and section(s) describe its behavior.
For each spec file, list which code file(s) implement its described behavior.

Code files may map to multiple specs (a handler might touch auth, sessions, and rate limiting).
Spec files may map to multiple code files (an "authentication" spec may be implemented across handler, middleware, and token service).
Some code files may have no spec mapping (utility code, infrastructure).
Some spec sections may have no code mapping (planned but unbuilt, or dead specs).

Output as JSON:
{
  "code_to_spec": {
    "internal/auth/handler.go": [
      {"spec": "specs/authentication.md", "sections": ["Login Flow", "Error Handling"]},
      {"spec": "specs/rate-limiting.md", "sections": ["Per-User Limits"]}
    ]
  },
  "spec_to_code": {
    "specs/authentication.md": {
      "Login Flow": ["internal/auth/handler.go", "internal/middleware/session.go"],
      "Token Refresh": ["internal/auth/token.go"],
      "Account Lockout": []
    }
  },
  "unmapped_code": ["internal/utils/helpers.go", "internal/config/loader.go"],
  "unmapped_spec_sections": [
    {"spec": "specs/authentication.md", "section": "Account Lockout", "status": "no implementation found"}
  ]
}
```

The agent should read spec files to understand their scope, and skim code files (exports + package/module structure) to understand what they do. It does NOT need to read every line of code — just enough to determine the mapping.

**IMPORTANT:** The mapping agent must use exact file paths as provided in the inventory. It should NOT guess or construct filenames based on conventions — projects vary (e.g., `eventbus.go` vs `event_bus.go`, `governed_runner.go` vs `governed.go`). If unsure of a filename, verify with Glob before including it in the mapping.

Write the mapping to `specs/audits/{date}/mapping.json`.

**Important: `commit_sha` write rules:**
- **Full audit** and **incremental audit**: Write current HEAD SHA to `inventory.json` at the end of the audit.
- **Scoped audit** (user passed a directory path like `src/api/`): Do NOT write `commit_sha`. A scoped audit doesn't cover the full graph, so storing HEAD would cause the next incremental audit to skip changes in unscoped modules.

### 1b½: Incremental scope determination (incremental mode only)

**Skip this section entirely if `$AUDIT_MODE` is not `incremental`.** Go straight to Phase 1c.

Using the fresh `mapping.json` from Phase 1b and the changed file list from Phase 0 Step 4, walk the mapping graph:

1. For each **changed code file**: look up its mapped spec sections in `code_to_spec` → collect all other code files that map to those same spec sections (via `spec_to_code`)
2. For each **changed spec file**: look up all code files mapped to it (via `spec_to_code`)
3. Union all affected files, then group by module directory → this is `$AFFECTED_MODULES`

Now check the 30% escalation threshold:
- Count total modules in the fresh inventory (group all code files by directory)
- If `|$AFFECTED_MODULES| / |total modules| > 0.30` → auto-escalate to full audit with message and restart from Phase 1c as a full audit

If still incremental, skip Phase 1c entirely — the scope is `$AFFECTED_MODULES`, auto-determined.

### 1c: Scope negotiation (full audit only)

**Skip this section if `$AUDIT_MODE` is `incremental`.** The scope is already determined by Phase 1b½.

Present a dashboard to the user:

```
Spec audit inventory: {N} code files, {M} spec files

Mapping:
  {X} code files mapped to specs
  {Y} code files with no spec coverage
  {Z} spec sections with no implementation

Estimated effort:
  Full audit:       ~{N} agent dispatches
  Mapped only:      Audit {X} files that have specs (find coverage gaps)
  Unmapped only:    Review {Y} files with no spec (discovery)
  Spec gaps only:   Check {Z} unimplemented spec sections
  Custom:           Pick specific files or directories

How would you like to proceed?
```

Use `AskUserQuestion` to let the user choose scope. Record their choice.

---

## Phase 2: Analysis

### Agent dispatch

For the scoped set of files, **group by module directory** (e.g., `internal/agent/`, `internal/builtin/commandcenter/`). Each agent receives all files in a module plus their mapped spec sections. This produces coherent per-module reports and is far more efficient than per-file dispatch.

**Use the `Agent` tool** to dispatch each module as a subagent. Launch in parallel batches of 3-5 (multiple `Agent` calls in a single message). Analysis agents are read-only so they don't need worktree isolation — but they must be subagents, not inline work. For large modules (15+ files), keep them as single agents — they share spec context and can identify cross-file patterns. For tiny modules (1-3 files), combine related modules into a single agent.

Each agent receives:

- All code files in the module (full contents)
- Their mapped spec file(s) and relevant sections (full contents)
- The mapping context (what other modules implement the same spec sections)

Each agent's job:

````
You are analyzing spec coverage for a single code module.

CODE FILE: {path}
{full file contents}

MAPPED SPECS:
{for each mapped spec, full contents of relevant sections}

MAPPING CONTEXT:
{which other files also implement these spec sections}

## Your analysis

### 1. Extract the behavior tree

For every function/method in this file, enumerate the distinct behavioral paths:
- What are the different outcomes this function can produce?
- What conditions lead to each outcome?
- Focus on behaviors that produce different outputs, side effects, or state changes.
- Do NOT enumerate defensive coding, retry logic, or internal control flow that doesn't change the external behavior.

### 2. Classify each branch

For each behavioral branch, classify:

**[COVERED]** — The spec explicitly describes this behavior.
  Cite the spec section and quote the relevant text.

**[UNCOVERED-BEHAVIORAL]** — This branch produces a distinct output or side effect that no spec describes.
  This is a gap. The spec should describe this behavior.
  Frame it as an intent question: "Because {code does X}, it means {Y for the user/system}. The spec doesn't mention this. Is this intentional behavior that should be documented?"

**[UNCOVERED-IMPLEMENTATION]** — This branch is internal implementation detail (retry, caching, defensive checks) that doesn't need spec coverage.
  Briefly note why it's implementation detail.

**[CONTRADICTS]** — The code does something the spec explicitly says it shouldn't, or vice versa.
  Cite both the spec text and the code behavior.

### 3. Check spec→code direction

For each spec section mapped to this file:
- Is every described behavior actually implemented?
- Are there spec promises that this file should fulfill but doesn't?

### 4. Output

Write your report as markdown. Structure:

```markdown
# {file path}

## Summary
- Behavioral branches: {N}
- Covered: {N}
- Uncovered (behavioral): {N}
- Uncovered (implementation detail): {N}
- Contradictions: {N}
- Unimplemented spec promises: {N}

## Branch Coverage

### {function name}

1. **[COVERED]** {branch description}
   Spec: {spec file} § {section} — "{quoted text}"

2. **[UNCOVERED-BEHAVIORAL]** {branch description}
   Because {what the code does}, it means {what this implies for the system}.
   The spec doesn't mention this. Intent question: {framed as a choice}

3. **[UNCOVERED-IMPLEMENTATION]** {branch description}
   Implementation detail: {why this doesn't need spec coverage}

## Unimplemented Spec Promises

- {spec file} § {section}: "{quoted spec text}" — no implementation found in this file
```
````

Each agent writes its report to `specs/audits/{date}/modules/{slug}.md` and returns a one-line summary:

```
{file path}: {covered}/{total} branches covered, {N} behavioral gaps, {N} contradictions
```

### Consolidation

After all agents complete, the coordinator reads only the one-line summaries. It writes:

**`specs/audits/{date}/gaps.md`** — All uncovered-behavioral and contradiction findings, sorted by severity (contradictions first, then uncovered-behavioral grouped by module).

**`specs/audits/{date}/index.md`** — Summary dashboard.

**Incremental mode adjustments:**
- The Coverage by Module table includes **only analyzed modules** — untouched modules are omitted entirely (no staleness markers, no placeholders)
- The Summary counts reflect only the analyzed modules, with a note: `"(incremental — {N} of {M} modules analyzed)"`
- The Delta section compares against the previous audit's results **for the same modules only** — not the full previous audit
- Add a line at the top: `"Incremental audit from {previous_sha} to {current_sha}"`

```markdown
# Spec Audit — {date}

## Summary
- Modules analyzed: {N}
- Total behavioral branches: {N}
- Covered by specs: {N} ({%})
- Behavioral gaps: {N}
- Implementation detail (no spec needed): {N}
- Contradictions: {N}
- Unimplemented spec promises: {N}

## Coverage by Module

| Module | Branches | Covered | Gaps | Contradictions |
|--------|----------|---------|------|----------------|
| {path} | {N} | {N} ({%}) | {N} | {N} |

## Top Gaps (by impact)

1. **{module}** — {description framed as intent question}
2. **{module}** — {description}
...

## Unimplemented Spec Promises

1. **{spec}** § {section} — {what's promised but not built}
...

## Delta from Last Audit

{If a previous audit exists at specs/audits/*, diff against it:}
- New gaps since last audit: {N}
- Gaps resolved since last audit: {N}
- New modules added: {N}
- Coverage trend: {improving/declining/stable}

{If no previous audit: "First audit — no delta available."}
```

### Terminal output

Print only the summary dashboard to the terminal. Point to the full report:

```
Full report: specs/audits/{date}/index.md
Module reports: specs/audits/{date}/modules/
```

---

## Phase 3: Resolution (optional)

**When resolving gaps (options 2 and 3 below), follow the `agent-driven-development` pattern** (`skills/agent-driven-development/SKILL.md`): worktree-per-task isolation, subagent dispatch via the `Agent` tool, and merge back. Each gap or gap-cluster becomes a task. Independent gaps run in parallel worktrees.

After displaying the summary, present options via `AskUserQuestion`:

```
What would you like to do with the findings?

1. Stop here — use the audit files as input to future sessions
2. Address gaps — transition to /spec-recommender on selected gaps
3. Address gaps in logical groups — cluster related gaps and tackle them together
4. Commit the audit and move on
```

### Option 1: Stop

Commit the audit directory and exit:

```bash
git add specs/audits/{date}/
git commit -m "Spec audit: {covered}% coverage, {N} gaps found"
```

### Option 2: Address gaps individually

For each gap, invoke `/spec-recommender` with the gap context. The recommender infers intent and presents options. Frame recommendations at the system level:

- "Because {module} doesn't interact with {component}, it means {consequence}. Is it your intent that it should always {behavior}? Or did you intend for it to {alternative A} or {alternative B}?"
- Not: "Function X returns null, did you intend that?"

After each gap is addressed (spec written or dismissed), update the audit report to reflect the resolution.

### Option 3: Address gaps in logical groups

Cluster related gaps before presenting them:
- Gaps in the same module
- Gaps that touch the same spec
- Gaps that represent related system behaviors (e.g., all error handling gaps, all auth-related gaps)

Present each cluster as a group. The user addresses the cluster holistically — the spec update covers all gaps in the cluster at once.

### Option 4: Commit and move on

Same as option 1.

---

## Failure Handling

| Failure | Action |
|---------|--------|
| No `.specs` file | Fail with message, suggest adding one |
| No spec files | Fail with message, suggest `/spec-recommender` |
| Massive imbalance (>10:1 code:spec) | Warn, ask to proceed |
| Agent fails on a module | Note in report, continue with others |
| Mapping agent produces bad mapping | Flag unmapped files, let analysis agents note when their mapping seems wrong |
| Previous audit missing | Skip delta section |
| User cancels mid-audit | Commit whatever's been written so far, note "partial audit" in index |

## Graceful Degradation

| Available | Behavior |
|-----------|----------|
| Specs + spec-recommender + spec-writer | Full experience: audit, gap resolution, spec production |
| Specs only | Audit works fully. Gaps reported, user writes specs manually |
| No specs | Refuses to run. Recommends `/spec-recommender` first |
