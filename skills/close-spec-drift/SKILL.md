---
name: close-spec-drift
description: "Use when an OpenSpec base spec is correct but code or peripheral spec text has drifted from it — surfaces the full extent of the drift, scaffolds a thin change folder (proposal + tasks, no deltas), and hands off to /execute-plan. OpenSpec-only."
---

# Close Spec Drift

Targeted workflow for "make reality match the spec." The base spec at `openspec/specs/<capability>/spec.md` already describes the canonical post-cleanup state. The job is to delete dead code, scrub stale references, and commit – with traceability through a thin change folder but **no delta files**, because the spec is not changing in any way OpenSpec's delta system can express.

## When to use this skill

- A base spec mentions deleted files, retired endpoints, or removed classes that still appear in source.
- Code carries compat shims for a producer that is gone (the shim has no caller).
- Spec text in non-requirement sections (`## Purpose`, `## Notes`, `### Interface`) references things that were removed in a prior change.
- An audit (`.workflow/audits/<date>/gaps.md`) flagged drift gaps to close.

## When NOT to use this skill

- **New behavior or design** – use `/brainstorm`.
- **Spec gap** (behavior exists in code but is not described anywhere in the spec) – use `/brainstorm` or `/spec-recommender`.
- **Reverse drift** (the spec is wrong, the code is the canonical truth and the spec needs to be re-derived) – use `/spec-recommender`.
- **Project doesn't use OpenSpec** – use `/fixit`.
- **Bug fix where the right behavior is unclear** – use `/fixit` or `/brainstorm`.

The distinct value of `close-spec-drift` is the workflow guard (no deltas, `--no-verify` commit) plus exhaustive scope discovery before any work starts. If neither of those would change how you'd handle the cleanup, a different skill is the better fit.

## Arguments

`$ARGUMENTS` is flexible:

- **Capability name** – `/close-spec-drift annotation-client`. Scope to one capability's spec and its source files.
- **Audit gap IDs** – `/close-spec-drift ux-9, api-app-prod-3`. Reads `.workflow/audits/<latest-date>/gaps.md`, identifies the affected specs, and proceeds.
- **Free-text drift description** – `/close-spec-drift "legacy Node server references in scenario text"`. Skill greps for the symptom across `openspec/specs/` and source dirs.
- **Multiple capabilities** – `/close-spec-drift annotation-client, prototype-switcher`. Scoped sweep.

Optional flags:

- `--scope=cap` (default) – only edit the named capability's spec/code.
- `--scope=sweep` – grep across all of `openspec/specs/` for the same drift pattern; surface and ask before editing.
- `--in-thread` – skip the `/execute-plan` handoff and execute in the current thread (for very small cleanups).

If no arguments are provided, reply with a usage message and stop:

```
Usage:
  /close-spec-drift <capability>           – clean drift in one capability
  /close-spec-drift <gap-id-list>          – pull gaps from latest audit
  /close-spec-drift "<symptom phrase>"     – grep-driven sweep
  /close-spec-drift <a>, <b> [--scope=…]   – multi-capability scope
```

## Context

- OpenSpec project: !`test -d openspec && echo "yes" || echo "no openspec/ dir"`
- Latest audit: !`ls -1d .workflow/audits/* 2>/dev/null | sort | tail -1`
- Active changes: !`openspec list --changes 2>/dev/null | head -10`
- Existing capabilities: !`openspec list --specs 2>/dev/null | head -20`

## Prerequisites

Fail immediately and stop if any of these don't hold:

- No `openspec/` directory in CWD → "This project doesn't use OpenSpec. For drift cleanup outside OpenSpec, use `/fixit`."
- `openspec` CLI is not on `PATH` → "OpenSpec CLI is required. Install with `npm install -g @openspec/cli`."
- An OpenSpec change is already active on the current branch and is unrelated to this drift cleanup → ask the user whether to abort, or to add the cleanup as additional tasks on the existing change.

---

## Phase 1: Resolve inputs

Parse `$ARGUMENTS` into a normalized `{capabilities, symptom, source_files, audit_gaps}` shape:

1. **If `$ARGUMENTS` looks like a capability name or comma-separated capability list** (matches entries from `openspec list --specs`):
   - Capture as `capabilities`.
   - `symptom` is initially unknown – Phase 2 discovers it.

2. **If `$ARGUMENTS` looks like audit gap IDs** (kebab/numeric tokens like `ux-9`, `api-app-prod-3`, `tools-1`):
   - Read the latest `.workflow/audits/<date>/gaps.md` (or whichever path the audit uses; check `.workflow/audits/<date>/index.md` if `gaps.md` doesn't exist).
   - For each gap ID, extract the affected capability and a one-line symptom description.
   - If the audit file can't be found or a gap ID isn't present, fail with the path and the missing IDs.

3. **If `$ARGUMENTS` is free-text** (a phrase describing the drift):
   - Capture as `symptom`.
   - `capabilities` is initially `*` – Phase 2's grep determines which specs are affected.

Normalize the result into a working set the rest of the skill operates on.

---

## Phase 2: Surface the full extent of drift (mandatory pre-flight)

This phase is non-negotiable. Drift cleanup misses are almost always scope-discovery failures – the user named one place; the same pattern existed in three others. Surface everything before touching anything.

### 2a. Search the spec tree

Run a comprehensive `Grep` across `openspec/specs/` for the symptom (or, when scoped to a capability, for known stale tokens like deleted file names, removed class names, retired endpoints). Use the symptom as the grep pattern; for capability-driven invocations, derive a pattern from the capability's recent diff (e.g., recently deleted file basenames, removed function names – `git log -p openspec/specs/<cap>/spec.md` and `git log --name-status` on related source).

Capture:
- Every base spec file that contains a match.
- The line number and surrounding context (1-2 lines) for each match.
- For each match, classify as **Requirement-level** (under a `### Requirement: …` header) or **non-Requirement** (under `## Purpose`, `## Notes`, `### Interface`, etc.). The skill needs both, but they're handled differently downstream (see Phase 3).

### 2b. Search the source tree

Run a comprehensive `Grep` across the project's source directories (skipping `node_modules`, build outputs, and `.workflow/`) for:
- The same symptom tokens.
- The deleted file/function names (when discoverable from the spec text or the user input).

Capture:
- Every source file that contains a match.
- Line numbers and context.
- Whether the match is in a comment, a string, or executable code – the implications differ.

### 2c. Surface the full extent to the user

Print a concise summary table before doing anything else. Wait for confirmation:

```
Drift inventory for "<symptom or capability>":

Specs with stale references:
  openspec/specs/annotation-server/spec.md:42       (### Interface: legacy Node POST endpoint)
  openspec/specs/annotation-client/spec.md:58       (## Notes: "legacy Node server compatibility")
  openspec/specs/prototype-switcher/spec.md:11      (## Purpose: mentions tools/annotate/server.js)

Source with potentially-dead references:
  tools/annotate/src/api-client.js:204              (legacy producer compat shim)
  tools/annotate/src/helpers.js:88                  (normalizeAnnotation legacy branch)
  ux/src/lib/api/client.ts:155                      (legacy attribution path)
  ux/src/components/AnnotationList.tsx:33           (comment referencing removed server)

Out of scope (informational): 0 audit gaps unrelated to this symptom.

Scope this cleanup to all of the above? Or narrow it?
  [a] All – proceed with full sweep
  [b] Specs only – cleanup is text-only, skip source
  [c] Custom – I'll list which to include/exclude
```

Use `AskUserQuestion` with these options. The user's response is the **confirmed scope**, recorded as a structured list that downstream phases iterate over.

### 2d. Classify each match

Once scope is confirmed, classify every entry into one of three buckets. This determines what work the change folder describes:

- **Spec text drift (cheap)** – the file just contains stale text. Direct edit, no investigation needed.
- **Spec/code drift requiring investigation** – source code looks like a dead branch, but you can't be sure without reading it. The change folder will include an explicit "verify reachability" task before deletion.
- **Cross-spec drift** – the same stale reference appears in multiple specs. Each one is a separate edit but they all close together.

Display the classification:

```
Classification:
  Spec text drift:     3 files (annotation-server:42, annotation-client:58, prototype-switcher:11)
  Spec/code drift:     4 files (api-client.js, helpers.js, client.ts, AnnotationList.tsx)
                        ↳ requires reachability check before deletion
  Cross-spec drift:    yes (3 specs share the same stale references)
```

If the user wants to defer any classified items to follow-up tasks, capture that decision now (`TaskCreate` calls happen in Phase 5 once the change folder is open).

---

## Phase 3: Scaffold a thin change folder

The change folder exists for traceability. It does **not** contain delta files because the base spec is already correct – there is no requirement to add, modify, or remove. The pre-commit hook will object to behavioral code changes without staged delta files; that is expected, and the workflow guard below addresses it.

### 3a. Pick the change name

`close-spec-drift-<short-slug>` where `<short-slug>` is derived from the symptom or capability. Examples:

- `close-spec-drift-legacy-node-references`
- `close-spec-drift-annotation-client-shim`
- `close-spec-drift-audit-2026-05-04` (when audit-driven and spanning multiple gaps)

If the user passed a clear phrase in `$ARGUMENTS`, use it as the slug seed. Confirm the slug with the user via `AskUserQuestion` if there's any ambiguity (offer 2 candidates).

### 3b. Scaffold the change

```
openspec new change <change-name>
```

This creates `openspec/changes/<change-name>/` with the empty boilerplate.

### 3c. Generate the proposal

Call `spec-writer` to fetch the enriched proposal template:

```
/spec-writer proposal <change-name>
```

Fill in the template with drift-specific content:

- **Why** – describe the drift cluster: what is canonical (the base spec), what drifted (the listed files), what root event caused the drift (a prior change that didn't sweep all touchpoints, an unfinished cleanup, etc.). Cite audit gap IDs if applicable.
- **What Changes** – enumerate the cleanup, grouped by spec / by source file. For each entry, mark whether it's a direct edit or a "verify-then-edit" item.
- **Impact** – lists affected specs and source files. Explicitly note: "**No spec deltas — the base specs already describe the canonical post-cleanup state. This change closes drift, not new behavior.**" Cite which audit gap IDs (if any) this closes.

Write to `openspec/changes/<change-name>/proposal.md`.

Do **not** scaffold `openspec/changes/<change-name>/specs/` or any delta files. The change folder is intentionally thin.

### 3d. Generate the tasks

Call `spec-writer` to fetch the enriched tasks template:

```
/spec-writer tasks <change-name>
```

Fill in with drift-specific stages:

```markdown
## 1. Verify scope

- [ ] 1.1 Confirm dead code in {file:line} is unreachable (no callers)
- [ ] 1.2 Confirm spec text references in {spec:line} are stale (the named entity is gone from the codebase)

## 2. Apply cleanup

**Depends on:** Stage 1

- [ ] 2.1 Delete dead code in {files} (lines pinpointed in 1.1)
- [ ] 2.2 Edit non-Requirement sections in {specs} to remove stale references
- [ ] 2.3 Run `openspec validate --all --strict` – must pass with no spec changes parsed as deltas

## 3. Test and commit

**Depends on:** Stage 2

- [ ] 3.1 Run the project's test suite – nothing should break (drift cleanup is non-behavioral)
- [ ] 3.2 Commit with `git commit --no-verify` and a message that explicitly notes "drift fix, no delta needed"
```

For pure spec-text drift cleanups (no source code touched), Stage 1.1 and 2.1 are omitted; the tasks file becomes a 3-line cleanup.

For cross-spec drift, each spec gets its own line under 2.2 so the agent doesn't conflate them.

Write to `openspec/changes/<change-name>/tasks.md`.

### 3e. Validate the change folder

```
openspec validate <change-name> --strict
```

Without delta files, OpenSpec validates this as a "doc-only" change. If the validation flags missing deltas as an error, surface the message to the user and proceed (the validation is informational here – the workflow guard explicitly accepts this).

---

## Phase 4: Hand off

Two paths, picked via `AskUserQuestion`:

### Path A: `/execute-plan` (recommended for non-trivial sweeps)

Print the next step:

```
Change `<change-name>` scaffolded. Run /clear and then:

/execute-plan <change-name>
```

Copy the command to clipboard so the user can paste after `/clear`:

```bash
echo -n "/execute-plan <change-name>" | pbcopy
```

This is the standard handoff per the global plan execution guidance.

### Path B: In-thread execution (for tiny cleanups)

If the user picks `--in-thread`, or the cleanup is genuinely small (e.g., 1-3 spec text edits, no source files), execute the tasks here using the agent-driven-development pattern (see `skills/agent-driven-development/SKILL.md`). One worktree, one agent, two-stage review, merge back.

Apply the same workflow guards as `/fixit`:

- **User's Exact Ask** – pass `$ARGUMENTS` verbatim to the implementer agent as the highest-priority guidance.
- **Followup capture** – any "out of scope" findings the agent reports must resolve into extend-scope, `TaskCreate`, or explicit won't-fix.
- **Merge gate** – auto-merge if all clean; hold for confirmation if the agent flagged divergence, concerns, or touched anything beyond the confirmed scope.

In both paths, the implementer agent's prompt MUST include this workflow guard verbatim:

```
### Workflow guard: --no-verify is the right call here

This change has NO delta files. The base specs at openspec/specs/<cap>/spec.md
already describe the canonical post-cleanup state. The pre-commit hook will
object to behavioral code changes without staged deltas — that is expected.

Commit with: git commit --no-verify -m "..."

Include "drift fix, no delta needed" in the commit message body. Do not invent
phantom delta files just to satisfy the hook. Do not scaffold openspec/changes/
<name>/specs/ — that path stays empty.

If you discover that a change requires a delta (e.g., the spec is actually
wrong, or new behavior surfaced), STOP and report it — that's a different
class of work and belongs in a different change folder.
```

---

## Phase 5: Followup capture

Before declaring done, surface any items the user deferred in Phase 2c (or that the implementer agent flagged) and resolve each into one of:

- **Extend scope on this change** – re-dispatch with the additional cleanup; the same change folder absorbs it.
- **`TaskCreate` for follow-up** – capture as a task in the native task system so it isn't lost.
- **Explicit won't-fix** – the user reviews and acknowledges it as out of scope; the rationale goes into the proposal's `Out of scope` line.

These cannot be silently dropped in the agent's final report.

---

## Phase 6: Archive (when applicable)

If the cleanup is purely spec-text drift (no source code, no scenario changes), `openspec archive` is not strictly necessary – the base specs were edited directly and the change folder is just a paper trail. Leave the change folder in `openspec/changes/` for one cycle of audit-trail visibility, then archive on the next session:

```
openspec archive <change-name> --skip-specs --yes
```

`--skip-specs` is required because there are no deltas to merge into base specs.

If the cleanup touched source code, follow the same archival flow – `--skip-specs` still applies because no deltas exist.

Surface this to the user as a one-line reminder in the final summary; do not auto-archive.

---

## Workflow guards

These rules are non-negotiable and are referenced by the agent prompt above:

- **No phantom deltas.** If the base spec is correct, do not scaffold delta files just to satisfy the pre-commit hook. The hook is bypassed via `--no-verify` – that's the explicit, documented correct path for drift cleanup.
- **Scope discovery happens before work, not after.** Phase 2's grep sweep is mandatory. The agent must not "discover" cross-spec drift in its final report; the dispatcher surfaces it before dispatch.
- **Edit non-Requirement sections directly on the base spec.** Drift in `## Purpose`, `## Notes`, `### Interface`, etc. cannot be expressed as a delta. Direct edit + `openspec validate --all --strict` is the verification path.
- **Verify reachability before deleting code.** When source code looks dead, read enough to confirm no callers before deletion. Tasks 1.1 in the tasks template enforces this.
- **Defer to the user's literal ask.** If `$ARGUMENTS` named one capability and Phase 2 surfaces drift in three, the user's confirmation in 2c is the binding scope. Do not silently expand.

## What this skill does NOT do

- **No new behavior.** If the spec is wrong or behavior is missing, this is the wrong skill.
- **No delta authorship.** This skill never writes `openspec/changes/<name>/specs/<cap>/spec.md`. Use `/brainstorm` for changes that need deltas.
- **No code rewrites beyond deletion of dead branches.** If the cleanup turns into a refactor, abort and route to `/brainstorm`.
- **No spec-from-code derivation.** That's `/spec-recommender`'s job.

## Failure handling

| Failure | Action |
|---------|--------|
| `openspec/` missing | Fail with `/fixit` suggestion |
| Capability name unknown | List actual capabilities from `openspec list --specs`, ask user to pick |
| Audit gap IDs not found | Surface the audit path and missing IDs, abort |
| Phase 2 grep returns nothing | Tell the user the symptom isn't present; ask whether they want to refine or abort |
| Phase 2 grep returns far more than expected | Surface the inventory and pause; do not auto-proceed with mass edits |
| Active OpenSpec change unrelated to drift on current branch | Ask user whether to add tasks to it or stash and start fresh |
| Pre-commit hook blocks commit (despite `--no-verify` flag in instructions) | The agent didn't follow the workflow guard; re-dispatch with the workflow guard re-emphasized |
| `openspec validate` fails after spec text edits | The edits broke spec structure; revert and re-edit more carefully |
