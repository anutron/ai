---
name: spec-audit
description: "Audit codebase spec coverage – inventory OpenSpec capabilities, map them to code, dispatch agents to find behavioral gaps. Use when the user wants to check spec health or find coverage holes."
tags: [spec]
---

# Spec Audit

Comprehensive audit of spec coverage across an OpenSpec-driven codebase. Inventories code and base specs (`openspec/specs/<capability>/spec.md`), maps them (many-to-many), dispatches agents to find behavioral gaps in both directions, and writes results to disk. For projects that have adopted OpenSpec but want to find where coverage has drifted.

Not for codebases with zero specs – that's a backfill task, not an audit.

OpenSpec-only. Legacy `specs/*.md` projects must run `/migrate-to-openspec` before this skill works.

## Arguments

```
$ARGUMENTS - Optional:
  <directory>       Scoped full audit
  --full            Force full audit
  --reconfigure     Re-run bootstrap (regenerate .audit-config.json)
```

When `openspec/.audit-config.json` exists, Phase 0.5's bootstrap step is skipped but the drift step still runs every time. `--reconfigure` forces bootstrap to run again.

## Context

- OpenSpec project: !`test -d openspec && echo "yes" || echo "no openspec/ dir"`
- Project type: !`find . -maxdepth 1 \( -name go.mod -o -name Gemfile -o -name package.json -o -name Cargo.toml -o -name pyproject.toml \) 2>/dev/null | head -5`
- Base specs: !`openspec list --specs 2>/dev/null | head -20`
- Active changes (excluded from audit corpus): !`openspec list --changes 2>/dev/null | head -10`
- Code file count: !`find . \( -name "*.go" -o -name "*.ts" -o -name "*.py" -o -name "*.rb" -o -name "*.js" \) -not -name "*_test.go" -not -name "*.test.*" -not -name "*.spec.*" -not -path "*/test/*" -not -path "*/__tests__/*" | grep -v node_modules | grep -v vendor | wc -l`
- Last audit: !`ls -t .workflow/audits/*/index.md 2>/dev/null | head -1`
- Current date: !`date +%Y-%m-%d`

---

## Prerequisites

**Fail immediately if:**

- No `openspec/` directory exists → "This project doesn't use OpenSpec. Run `openspec init` (or `/migrate-to-openspec` if it has a legacy `.specs` system) first."
- `openspec` CLI is not on `PATH` → "OpenSpec CLI is required. Install with `npm install -g @openspec/cli` (or see https://github.com/Fission-AI/OpenSpec)."
- No base specs found via `openspec list --specs` → "No OpenSpec capabilities found. Write specs first with `openspec new change <name>` and `/spec-writer`, then audit. Use `/spec-recommender` to get started."
- Massive imbalance: more than 10x code files vs spec files AND specs appear to be file-organized (1:1 with code files) → Present the ratio and ask: "This project has {N} code files but only {M} capabilities. An audit would flag almost everything as uncovered. Consider running `/spec-recommender` first to build baseline coverage, then audit. Proceed anyway? (y/n)" **Skip this check if specs are feature-organized.** Feature-organized capabilities routinely cover 10-20 code files each, making the raw ratio misleading. Instead, proceed to the mapping phase and assess actual coverage after mapping.

**Note on code file count:** The context section's `find` count may include non-behavioral files (vendored dependencies, generated bundles, prototype HTML). For the imbalance check, use the raw count as a signal but do not block on it if the project uses feature-organized specs. The inventory phase (Phase 1a) establishes the true count of behavioral source files.

---

## Phase 0a: Pre-flight – validate base specs

Before any audit work, verify the OpenSpec base specs are structurally valid. A drifted base spec poisons everything downstream — fail fast here so users fix structural issues before spending tokens on agent dispatch.

```bash
openspec validate --all --strict --json
```

Parse the JSON output. If `summary.totals.failed > 0`:

- Print the failing items with their issue messages.
- Exit with: "Base specs failed validation. Fix structural issues (`openspec validate --all --strict` for details), then re-run `/spec-audit`."

Active-change deltas are NOT audited as if they were current state — they describe future state. The `--all` flag validates both base specs and changes; treat change-validation failures as informational (note them in the report) but do not block the audit on them.

---

## Phase 0: Incremental Detection

Before running the full audit pipeline, determine whether an incremental audit is possible. This phase decides the audit mode: **full**, **incremental**, or **no-op**.

### Step 1: Check for previous audit

```bash
LAST_AUDIT=$(ls -td .workflow/audits/*/inventory.json 2>/dev/null | head -1)
```

If no previous audit exists → **full audit**. Skip the rest of Phase 0.

### Step 2: Check for explicit overrides

- If `$ARGUMENTS` contains `--full` → **full audit** (strip `--full` from arguments before continuing)
- If `$ARGUMENTS` contains `--reconfigure` → force Phase 0.5 bootstrap to run again (strip from arguments before continuing)
- If `$ARGUMENTS` contains a scoped path (e.g., `src/api/`) → **scoped full audit** (no incremental, no SHA update at end – a scoped audit doesn't cover the full graph)

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

Filter the diff output to code files and base spec files only (extensions from the inventory scan: `*.go`, `*.ts`, `*.py`, `*.rb`, `*.js`, and `openspec/specs/**/spec.md`). **Ignore** any changes under `openspec/changes/` — those are in-flight deltas, not current-state base specs.

If no code or base-spec files changed → **no-op**:

```
No spec-relevant changes since last audit ({sha}, {date}). Run `/spec-audit --full` to re-audit everything.
```

Stop here. Do not proceed to Phase 1.

### Step 5: Check auto-escalation triggers

Escalate or rescope based on what changed in `openspec/specs/`:

1. **Base spec files were deleted or renamed** → **full audit** (mapping invalidated):

   ```
   Base spec files deleted/renamed since last audit. Running full audit.
   ```

2. **Base spec files were added only** (no deletions or renames) – use deterministic scoping instead of escalating:

   1. For each newly added spec, run:

      ```bash
      audit.sh spec-modules openspec <spec-file>
      ```

      The CLI is deterministic: it reads YAML frontmatter `covers: [...]` if present, otherwise falls back to filename token-overlap match against module names from `.audit-config.json`. For OpenSpec, the "filename" is the capability name (parent directory of `spec.md`).

   2. If the CLI returns a non-empty list → scope = those modules ∪ modules with code changes since last audit. No LLM, no user prompt.

   3. If the CLI returns an empty list → fall back to a single small LLM call ("read this spec, return module names from this list"). Use `subagent_type: general-purpose`. Persist the result to `mapping_cache` so we never re-do it.

   4. Append the new spec to those modules' `specs` arrays via `audit.sh add-spec`.

3. **Base spec files were modified only** → existing incremental flow (unchanged).

4. **Affected modules exceed 30% of total modules** (computed after the graph walk in Step 6) → **full audit**:

   ```
   Significant changes detected ({N}% of modules affected). Running full audit.
   ```

### Step 6: Graph walk – determine affected modules

Walk the mapping graph bidirectionally using the previous audit's `mapping.json`:

1. **Changed code file** → find its mapped capability sections → find all other code files mapped to those same sections
2. **Changed base spec file** → find all code files mapped to it

Collect all affected files, then group by module directory to get the affected module set.

If affected modules exceed 30% of the previous audit's total modules → auto-escalate (Step 5.4).

### Step 7: Print incremental summary

```
Incremental audit: {N} files changed since {sha} ({date})
Affected modules: {list of module paths}
Unaffected modules: {N} (skipped)
```

Set `$AUDIT_MODE = incremental` and `$AFFECTED_MODULES` for use in later phases.

---

## Phase 0.5: Configuration

Per-project audit configuration lives at `openspec/.audit-config.json`. The config records modules (each with `paths` and `specs`), behavioral file extensions, exclude patterns, project-specific pitfalls, test suite commands, and a mapping cache. The LLM never authors this JSON directly – all reads/writes go through `audit.sh` subcommands.

**Spec-dir argument throughout:** `audit.sh` takes `<spec-dir>` as `openspec` for OpenSpec projects. The CLI resolves all spec files under `openspec/specs/<capability>/spec.md` and writes config to `openspec/.audit-config.json`.

### First run (config absent, or `--reconfigure` passed)

1. Run `audit.sh init-tree openspec` – deterministic dirwalk that produces a draft config:

   - Modules from top-level behavioral directories.
   - Extensions detected from project markers (`Gemfile` → ruby, `package.json` → js/ts, `go.mod` → go, etc).
   - Excludes seeded with common patterns (`node_modules`, `dist/`, `.next/`, `*.bundle.*`, vendored dirs).
   - Specs matched per module by capability-name token overlap.
   - Test suites detected from filesystem markers (`*/Gemfile`, `*/package.json` with `scripts.test`, `*/go.mod`, `devbox.json` wrapping).

2. **Refinement step (LLM):** Spawn one subagent with `subagent_type: general-purpose` (it needs Read+Bash+Write to call `audit.sh`). Its job is to review the draft config, read the base spec files (`openspec/specs/<capability>/spec.md`), and skim a few representative code files, then:

   - Add semantic `pitfalls` (e.g. "two `Prototype` classes coexist", deprecated-but-used files, dual-mode systems).
   - Refine `specs` arrays per module if filename matching produced obvious mismatches.
   - Suggest module merges/splits the heuristic got wrong.
   - It calls `audit.sh add-pitfall`, `audit.sh add-spec`, `audit.sh remove-module`, etc – never edits JSON directly.

3. Continue to Phase 1. No user prompt.

### Every subsequent run (config exists, no `--reconfigure`)

1. Run `audit.sh detect-drift openspec` – emits files outside any configured module's `paths`.

2. Run `audit.sh assign-drift openspec` – for each drifted file, find the configured module whose path prefix matches longest. If a unique match exists, auto-add the new directory to that module's `paths`.

3. Files with no clear match → small subagent with `subagent_type: general-purpose` decides: either creates a new module via `audit.sh add-module` or appends to a borderline candidate via `audit.sh add-path`.

4. Print a one-line summary of what changed.

---

## Phase 1: Inventory

### 1a: Deterministic scan (no LLM)

Run the inventory CLI:

```bash
audit.sh inventory openspec > "$AUDIT_DIR/inventory.json"
```

The CLI honors `extensions` and `excludes` from `.audit-config.json` and emits the schema below. **It scans only `openspec/specs/<capability>/spec.md` files** — active-change deltas at `openspec/changes/<change>/specs/<capability>/spec.md` are excluded automatically (the CLI restricts the spec walk to the `specs/` subdirectory of the spec-dir).

**Audit directory naming:** Use `.workflow/audits/{date}/` for the first audit on a given day. If an audit directory for today already exists, append a version suffix: `{date}_v2`, `{date}_v3`, etc. Never overwrite a previous audit – preserve all results for delta comparison.

`inventory.json` schema (produced by the CLI – kept here for downstream phases):

```json
{
  "date": "YYYY-MM-DD",
  "commit_sha": "<current HEAD short SHA – run `git rev-parse --short HEAD`>",
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
      "path": "openspec/specs/authentication/spec.md",
      "capability": "authentication",
      "sections": ["Purpose", "Requirements", "Polling Loop", "Token Refresh"]
    }
  ],
  "counts": {
    "code_files": 47,
    "spec_files": 12,
    "exports": 183
  }
}
```

**`commit_sha` write rules:**

- **Full audit** and **incremental audit**: Write current HEAD SHA to `inventory.json` at the end of the audit.
- **Scoped audit** (user passed a directory path like `src/api/`): Do NOT write `commit_sha`. A scoped audit doesn't cover the full graph, so storing HEAD would cause the next incremental audit to skip changes in unscoped modules.

### 1b: LLM-assisted mapping

The deterministic scan can't map feature-organized capabilities to technically-organized code. Use an agent to build the many-to-many map.

Spawn a single agent (`subagent_type: general-purpose`) with the full list of code files (paths + exports) and base spec files (paths + sections). Its job:

```
Given these code files and base spec files, produce a mapping.

For each code file, list which capability spec(s) and section(s) describe its behavior.
For each capability spec, list which code file(s) implement its described behavior.

Code files may map to multiple capabilities (a handler might touch auth, sessions, and rate limiting).
Capability specs may map to multiple code files (an "authentication" capability may be implemented across handler, middleware, and token service).
Some code files may have no spec mapping (utility code, infrastructure).
Some requirements may have no code mapping (planned but unbuilt, or dead requirements).

Output as JSON:
{
  "code_to_spec": {
    "internal/auth/handler.go": [
      {"spec": "openspec/specs/authentication/spec.md", "capability": "authentication", "sections": ["Login Flow", "Error Handling"]},
      {"spec": "openspec/specs/rate-limiting/spec.md", "capability": "rate-limiting", "sections": ["Per-User Limits"]}
    ]
  },
  "spec_to_code": {
    "openspec/specs/authentication/spec.md": {
      "Login Flow": ["internal/auth/handler.go", "internal/middleware/session.go"],
      "Token Refresh": ["internal/auth/token.go"],
      "Account Lockout": []
    }
  },
  "unmapped_code": ["internal/utils/helpers.go", "internal/config/loader.go"],
  "unmapped_spec_sections": [
    {"spec": "openspec/specs/authentication/spec.md", "section": "Account Lockout", "status": "no implementation found"}
  ]
}
```

The agent should read base spec files to understand their scope, and skim code files (exports + package/module structure) to understand what they do. It does NOT need to read every line of code – just enough to determine the mapping. It MUST NOT read or consider files under `openspec/changes/` — those describe in-flight future state and are out of scope for this audit.

**Mapping cache.** The mapping result is persisted in `openspec/.audit-config.json` under `mapping_cache` (keyed by spec file, valued by `{sha, modules}`). On full audits:

- For each base spec, compare its current content hash (`git hash-object <spec>`) against the cached SHA.
- Specs unchanged since last audit → skip mapping, reuse cached `modules` list.
- Specs new or modified → mapping agent runs only on those.

On `--reconfigure` or when no cache exists, mapping runs over all specs.

**IMPORTANT:** The mapping agent must use exact file paths as provided in the inventory. It should NOT guess or construct filenames based on conventions – projects vary (e.g., `eventbus.go` vs `event_bus.go`, `governed_runner.go` vs `governed.go`). If unsure of a filename, verify with Glob before including it in the mapping.

Write the mapping to `.workflow/audits/{date}/mapping.json`.

### 1b½: Incremental scope determination (incremental mode only)

**Skip this section entirely if `$AUDIT_MODE` is not `incremental`.** Go straight to Phase 1c.

Using the fresh `mapping.json` from Phase 1b and the changed file list from Phase 0 Step 4, walk the mapping graph:

1. For each **changed code file**: look up its mapped capability sections in `code_to_spec` → collect all other code files that map to those same sections (via `spec_to_code`)
2. For each **changed base spec file**: look up all code files mapped to it (via `spec_to_code`)
3. Union all affected files, then group by module directory → this is `$AFFECTED_MODULES`

Now check the 30% escalation threshold:

- Count total modules in the fresh inventory (group all code files by directory)
- If `|$AFFECTED_MODULES| / |total modules| > 0.30` → auto-escalate to full audit with message and restart from Phase 1c as a full audit

If still incremental, skip Phase 1c entirely – the scope is `$AFFECTED_MODULES`, auto-determined.

### 1c: Scope negotiation (full audit only)

**Skip this section if `$AUDIT_MODE` is `incremental`.** The scope is already determined by Phase 1b½.

Present a dashboard to the user:

```
Spec audit inventory: {N} code files, {M} capabilities

Mapping:
  {X} code files mapped to capabilities
  {Y} code files with no spec coverage
  {Z} requirement sections with no implementation

Estimated effort:
  Full audit:       ~{N} agent dispatches
  Mapped only:      Audit {X} files that have specs (find coverage gaps)
  Unmapped only:    Review {Y} files with no spec (discovery)
  Spec gaps only:   Check {Z} unimplemented requirements
  Custom:           Pick specific files or directories

How would you like to proceed?
```

Use `AskUserQuestion` to let the user choose scope. Record their choice.

---

## Phase 2: Analysis

### Symbol index

Before agent dispatch, build a per-module symbol index so each agent has cross-module context:

```bash
audit.sh symbols openspec > "$AUDIT_DIR/symbols.json"
```

The CLI emits a per-module list of symbols (classes, modules, exported functions, methods) detected via language-aware grep.

### Branch enumeration (deterministic floor)

Before each module agent runs, the coordinator invokes `audit.sh count-branches <file>` for each file in the module. The CLI emits one entry per `if`, `else`, `elsif`, `case`/`when`, `try`/`catch`/`rescue`, ternary, and early `return`. The agent receives this list and only **classifies** each branch (covered / uncovered-behavioral / uncovered-implementation / contradicts) – it does not enumerate them. This is faster, more consistent, and gives the verification pass a stable index.

### Agent dispatch

For the scoped set of files, **group by module directory** (e.g., `internal/agent/`, `internal/builtin/commandcenter/`). Each agent receives all files in a module plus their mapped capability sections. This produces coherent per-module reports and is far more efficient than per-file dispatch.

**Use the `Agent` tool** to dispatch each module as a subagent. Always pass `subagent_type: general-purpose` – module agents need to write findings JSON and call `audit.sh`, which requires Write+Bash. Launch in parallel batches of 3-5 (multiple `Agent` calls in a single message). Analysis agents are read-only with respect to source code, but they must Write their own report and findings JSON, so they must be subagents (not inline work) of type `general-purpose`. For large modules (15+ files), keep them as single agents – they share spec context and can identify cross-file patterns. For tiny modules (1-3 files), combine related modules into a single agent.

Each agent receives:

- All code files in the module (full contents)
- Their mapped capability spec(s) and relevant sections (full contents)
- The mapping context (what other modules implement the same requirements)
- The deterministic branch list for each file (from `audit.sh count-branches`)
- **Other modules' symbols** (from `symbols.json`) – so the agent doesn't falsely flag a symbol as missing when it lives in a different module
- **Pitfalls list** (from `.audit-config.json`) – so the agent knows about project-specific gotchas

Each agent's job:

````
You are analyzing spec coverage for a single code module.

CODE FILE: {path}
{full file contents}

MAPPED CAPABILITY SPECS:
{for each mapped spec, full contents of relevant sections from openspec/specs/<capability>/spec.md}

MAPPING CONTEXT:
{which other files also implement these requirement sections}

DETERMINISTIC BRANCH LIST:
{output of `audit.sh count-branches` for each file – one entry per conditional/case/rescue/early-return}

OTHER MODULES' SYMBOLS:
{symbols.json entries for every module other than this one}

PITFALLS:
{the `pitfalls` array from .audit-config.json}

## Your analysis

### 1. Use the deterministic branch list

You are given a precomputed branch list per file. Do NOT re-enumerate branches. Your job is to **classify** each branch from that list.

- Skip purely defensive coding, retry logic, or internal control flow that doesn't change external behavior – classify those as `uncovered-implementation`.
- Focus your judgment on which branches produce distinct outputs, side effects, or state changes.

### 2. Classify each branch

For each branch, classify:

**[COVERED]** – The capability spec explicitly describes this behavior.
  Cite the requirement section and quote the relevant text.

**[UNCOVERED-BEHAVIORAL]** – This branch produces a distinct output or side effect that no requirement describes.
  This is a gap. The capability spec should describe this behavior.
  Frame it as an intent question: "Because {code does X}, it means {Y for the user/system}. The spec doesn't mention this. Is this intentional behavior that should be documented?"

**[UNCOVERED-IMPLEMENTATION]** – This branch is internal implementation detail (retry, caching, defensive checks) that doesn't need spec coverage.
  Briefly note why it's implementation detail.

**[CONTRADICTS]** – The code does something the requirement explicitly says it shouldn't, or vice versa.
  Cite both the requirement text and the code behavior.

  **Spec-misreading guard.** Before classifying anything as a contradiction, scan the relevant requirement for trigger phrases: `fallback`, `falls back to`, `reserved`, `reserved for future`, `TODO`, `to be implemented`, `planned`, `planned feature`, `deprecated`, `currently only`, `for now`, `not yet implemented`. If any of these appear in the requirement describing the behavior in question, the code matching that documented state is **NOT** a contradiction – it's the documented current state.

  Worked example: if the requirement says "Currently only `last_edited` is implemented; `last_viewed` is reserved and falls back to `last_edited`" and the code falls back from `last_viewed` to `last_edited`, that is **covered**, not a contradiction.

### 3. Check spec→code direction

For each requirement section mapped to this file:

- Is every described behavior actually implemented?
- Are there spec promises that this file should fulfill but doesn't?

### 4. Cross-module symbol awareness

If you encounter a symbol referenced by code in your module that you can't find in your scope:

- First, check the `OTHER MODULES' SYMBOLS` index. If the symbol appears there, it's defined in another module – do NOT flag it as missing.
- Only emit a `missing-symbol` finding if the symbol is absent from both your module AND the cross-module symbol index.

### 5. Output – two artifacts

You MUST emit BOTH outputs:

#### 5a. Markdown report at `.workflow/audits/{date}/modules/{slug}.md`

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
   Spec: `openspec/specs/{capability}/spec.md` § {requirement} – "{quoted text}"

2. **[UNCOVERED-BEHAVIORAL]** {branch description}
   Because {what the code does}, it means {what this implies for the system}.
   The spec doesn't mention this. Intent question: {framed as a choice}

3. **[UNCOVERED-IMPLEMENTATION]** {branch description}
   Implementation detail: {why this doesn't need spec coverage}

## Unimplemented Spec Promises

- `openspec/specs/{capability}/spec.md` § {requirement}: "{quoted spec text}" – no implementation found in this file
```

#### 5b. Structured findings JSON at `.workflow/audits/{date}/modules/{slug}.findings.json`

```json
{
  "branch_summary": {
    "total": 87,
    "covered": 84,
    "uncovered_behavioral": 2,
    "contradictions": 1,
    "unimplemented_promises": 1
  },
  "findings": [
    {
      "id": "annotate-client-1",
      "type": "contradiction",
      "severity": "low",
      "code_location": "tools/annotate/src/comment-ui.js:130",
      "spec_location": "openspec/specs/annotation-client/spec.md:296",
      "description": "Spec promises addReply sends {text, author}; code sends {text} only.",
      "referenced_symbols": []
    },
    {
      "id": "api-endpoints-2",
      "type": "missing-symbol",
      "code_location": "api/app/api/v1/prototypes.rb:125",
      "description": "Prototype.html_for referenced but I didn't find it in my scope.",
      "referenced_symbols": ["Prototype.html_for"]
    }
  ]
}
```

Rules for findings JSON:

- Every "missing"/"doesn't exist" claim MUST populate `referenced_symbols` with the exact symbols you couldn't find.
- Phrase descriptions as "I didn't find X in my scope" – never "X doesn't exist".
- The spec-misreading guard above also applies here: do not emit a `contradiction` finding when the requirement uses any of the trigger phrases for the behavior in question.
````

Each agent writes both files and returns a one-line summary:

```
{file path}: {covered}/{total} branches covered, {N} behavioral gaps, {N} contradictions
```

---

## Phase 2.5: Verification

After all module agents complete and before consolidation, the coordinator verifies findings to suppress false positives.

For each finding across every `modules/{slug}.findings.json`:

- If `referenced_symbols` is empty → skip (nothing to verify).
- For each symbol in `referenced_symbols`:

  ```bash
  audit.sh verify-finding openspec <symbol>
  ```

  The CLI greps the symbol across the repo, honoring `excludes` from the config.

- If the symbol is found anywhere outside the agent's module → mark the finding as `verified_false_positive: true` and add `actual_location` (file:line where the symbol was found).
- If the symbol is genuinely absent everywhere → mark `verified: true`.

After verification, the coordinator regenerates `modules/{slug}.md` from the structured findings:

- Verified findings appear in their normal sections.
- Verified false positives appear in a separate "False Positives" subsection at the bottom of the module report.

`gaps.md` and `index.md` split into two sections:

- **Verified gaps** – findings the coordinator could not refute.
- **Verified false positives** – findings the coordinator disproved via symbol lookup.

Coverage tables count verified gaps only.

---

## Phase 3: Consolidation

After all agents complete and verification has run, the coordinator reads the one-line summaries plus the verified findings JSON. It writes:

**`.workflow/audits/{date}/gaps.md`** – All verified uncovered-behavioral and contradiction findings, sorted by severity (contradictions first, then uncovered-behavioral grouped by module). False positives appear in a separate section.

**`.workflow/audits/{date}/index.md`** – Summary dashboard.

**Incremental mode adjustments:**

- The Coverage by Module table includes **only analyzed modules** – untouched modules are omitted entirely (no staleness markers, no placeholders)
- The Summary counts reflect only the analyzed modules, with a note: `"(incremental – {N} of {M} modules analyzed)"`
- The Delta section compares against the previous audit's results **for the same modules only** – not the full previous audit
- Add a line at the top: `"Incremental audit from {previous_sha} to {current_sha}"`

```markdown
# Spec Audit – {date}

## Summary

- Modules analyzed: {N}
- Total behavioral branches: {N}
- Covered by specs: {N} ({%})
- Behavioral gaps (verified): {N}
- Implementation detail (no spec needed): {N}
- Contradictions (verified): {N}
- Unimplemented spec promises: {N}
- False positives suppressed: {N}

## Coverage by Module

| Module | Branches | Covered | Gaps | Contradictions |
|--------|----------|---------|------|----------------|
| {path} | {N} | {N} ({%}) | {N} | {N} |

## Top Gaps (by impact)

1. **{module}** – {description framed as intent question}
2. **{module}** – {description}
...

## Unimplemented Spec Promises

1. **`openspec/specs/{capability}/spec.md`** § {requirement} – {what's promised but not built}
...

## Verified False Positives

{Findings disproved by Phase 2.5 symbol verification, with actual_location.}

## Delta from Last Audit

{If a previous audit exists at .workflow/audits/*, diff against it:}

- New gaps since last audit: {N}
- Gaps resolved since last audit: {N}
- New modules added: {N}
- Coverage trend: {improving/declining/stable}

{If no previous audit: "First audit – no delta available."}
```

### Terminal output

Print only the summary dashboard to the terminal. Point to the full report:

```
Full report: .workflow/audits/{date}/index.md
Module reports: .workflow/audits/{date}/modules/
```

---

## Phase 4: Resolution (optional)

**When resolving gaps (options 2 and 3 below), follow the `agent-driven-development` pattern** (`skills/agent-driven-development/SKILL.md`): worktree-per-task isolation, subagent dispatch via the `Agent` tool, and merge back. Each gap or gap-cluster becomes a task. Independent gaps run in parallel worktrees.

After displaying the summary, present options via `AskUserQuestion`:

```
What would you like to do with the findings?

1. Stop here – use the audit files as input to future sessions
2. Address gaps – transition to /spec-recommender on selected gaps
3. Address gaps in logical groups – cluster related gaps and tackle them together
4. Commit the audit and move on
```

### Option 1: Stop

Commit the audit directory and exit:

```bash
git add .workflow/audits/{date}/
git commit -m "Spec audit: {covered}% coverage, {N} gaps found"
```

### Option 2: Address gaps individually

For each gap, invoke `/spec-recommender` with the gap context. The recommender infers intent and presents options. Frame recommendations at the system level:

- "Because {module} doesn't interact with {component}, it means {consequence}. Is it your intent that it should always {behavior}? Or did you intend for it to {alternative A} or {alternative B}?"
- Not: "Function X returns null, did you intend that?"

After each gap is addressed (capability spec written or dismissed), update the audit report to reflect the resolution.

### Option 3: Address gaps in logical groups

Cluster related gaps before presenting them:

- Gaps in the same module
- Gaps that touch the same capability
- Gaps that represent related system behaviors (e.g., all error handling gaps, all auth-related gaps)

Present each cluster as a group. The user addresses the cluster holistically – the spec update covers all gaps in the cluster at once.

### Option 4: Commit and move on

Same as option 1.

---

## Failure Handling

| Failure | Action |
|---------|--------|
| No `openspec/` directory | Fail with message, suggest `openspec init` or `/migrate-to-openspec` |
| `openspec` CLI missing | Fail with install instructions |
| `openspec validate --all --strict` reports failures on base specs | Fail with the failing items, suggest fix |
| No base specs found | Fail with message, suggest `/spec-recommender` |
| Massive imbalance (>10:1 code:spec) | Warn, ask to proceed |
| Agent fails on a module | Note in report, continue with others |
| Mapping agent produces bad mapping | Flag unmapped files, let analysis agents note when their mapping seems wrong |
| Previous audit missing | Skip delta section |
| User cancels mid-audit | Commit whatever's been written so far, note "partial audit" in index |
| `audit.sh` missing or non-executable | Fail with message: "audit.sh not found at .claude/skills/spec-audit/audit.sh – reinstall the skill." |

## Graceful Degradation

| Available | Behavior |
|-----------|----------|
| Specs + spec-recommender + spec-writer | Full experience: audit, gap resolution, spec production |
| Specs only | Audit works fully. Gaps reported, user writes specs manually |
| No specs | Refuses to run. Recommends `/spec-recommender` first |
