---
name: spec-writer
description: "Use whenever writing or updating OpenSpec artifact text — thin orchestrator around `openspec instructions <artifact>`. Returns enriched templates plus project context per artifact (proposal, design, tasks, specs)."
tags: [spec]
---

# Spec Writer

Thin orchestrator around the OpenSpec CLI's `instructions` command. Takes a target artifact (proposal / design / tasks / specs) and an active change name, runs `openspec instructions <artifact> --change <name> --json`, and returns the enriched template plus project-specific context so the caller (or the user) can fill it in.

This skill is **OpenSpec-only**. It does not author the SPEC format directly — OpenSpec's own templates own that. The skill's job is to surface the right template at the right moment, augmented with hints from already-written specs in the current project.

## Arguments

- `$ARGUMENTS` - Either:
  - `<artifact>` (proposal | design | tasks | specs) – uses the active change inferred from the current branch
  - `<artifact> <change-name>` – explicit
  - Free-form natural language like "write a proposal for change auth-redesign" (parse out the artifact and change name)

Examples:

```
/spec-writer specs                            -> instructions for the active change's specs artifact
/spec-writer proposal auth-redesign           -> proposal artifact for the named change
/spec-writer "tasks for the migration change" -> tasks artifact, infer change from input
```

When invoked programmatically from another skill, the caller passes `{artifact, changeName}` directly.

## Context

- OpenSpec project: !`test -d openspec && echo "yes" || echo "no openspec/ dir"`
- Active changes: !`openspec list --changes 2>/dev/null | head -10`
- Current branch: !`git branch --show-current 2>/dev/null`
- Existing capability specs (for example references): !`openspec list --specs 2>/dev/null | head -10`

---

## Prerequisites

Fail immediately if any of these don't hold:

- `openspec` CLI is not on `PATH` → "OpenSpec CLI is required. Install with `npm install -g @openspec/cli` (or see https://github.com/Fission-AI/OpenSpec)."
- No `openspec/` directory in CWD → "This project doesn't use OpenSpec. Run `openspec init` (or `/migrate-to-openspec` if it has a legacy `.specs` system) first."
- No active changes when no change name is provided → "No active changes found. Create one with `openspec new change <name>`, or pass an explicit change name."

---

## Phase 1: Parse intent

```
1. Extract `artifact` from $ARGUMENTS:
   - Look for one of: proposal, design, tasks, specs
   - If none mentioned, ask the user which artifact they want via AskUserQuestion (offer the four options)

2. Extract `change-name`:
   IF $ARGUMENTS contains a kebab-case token that matches a name from `openspec list --changes`:
     -> use it
   ELSE IF current branch matches a change name from the list (or starts with one):
     -> use that
   ELSE IF exactly one active change exists:
     -> use it
   ELSE:
     -> AskUserQuestion to pick one from the list

3. (Optional) Extract any user-provided seed content / overrides from $ARGUMENTS for downstream use.
```

---

## Phase 2: Fetch enriched instructions

Run the OpenSpec CLI with `--json` so the output is structured and easy to enrich:

```bash
openspec instructions <artifact> --change <change-name> --json
```

The JSON contains: `changeName`, `artifactId`, `schemaName`, `changeDir`, `outputPath`, `description`, `instruction`, `template`, `dependencies` (with `done` flags + paths), and `unlocks`.

If the call fails:

- Missing artifact dependencies: surface the dependency list with `done`/`missing` status. Suggest creating dependencies first (e.g., proposal before specs, specs before tasks).
- Unknown change: re-prompt with the actual list from `openspec list --changes`.

---

## Phase 3: Enrich with project context

Augment the template with project-specific signal so the user (or the next skill) doesn't start from a blank page.

### For artifact = `specs`

- List **existing capabilities** in this project: `openspec list --specs` (a parsed view, not raw output).
- For any capability already mentioned in the change's `proposal.md` Capabilities list, fetch its current base spec via `openspec show <capability>` and include the requirement names verbatim — those are the requirements being modified, deltas must reference them by exact header.
- Include 1-2 short scenario examples drawn from `openspec/specs/<capability>/spec.md` files in this project so the writer matches the project's voice (`#### Scenario:` shape, WHEN/THEN cadence, units, etc.).
- Always remind the writer: scenarios use **exactly four `#`** characters; `### Scenario:` will fail silently.

### For artifact = `proposal`

- If a `brainstorm.md` or other discovery document exists at `openspec/changes/<change>/` or `.workflow/docs/<date>-<topic>/`, surface the relevant excerpts the proposal should anchor on (the "why" framing, candidate capabilities).
- Include the kebab-case names of existing capabilities to help the writer reuse names in the Modified Capabilities section instead of inventing variants.

### For artifact = `design`

- Surface the proposal's `## Why` section (read `openspec/changes/<change>/proposal.md`) so the design doc threads from the same problem statement.
- Mention any `design-docs/` or relevant CLAUDE.md sections that constrain the technical approach (e.g., tech-stack tier, testing conventions).

### For artifact = `tasks`

- Read both `proposal.md` and `specs/**/*.md` in the change folder. Extract the capabilities + requirement names so tasks can be grouped per capability.
- If `design.md` exists, lift the section list as a checklist seed.
- Remind the writer: tasks must be `- [ ] X.Y Description` checkboxes (not bullets); `## N. Section` headings group them.

---

## Phase 4: Present the result

Output a structured response with three blocks:

1. **Where the file goes** – the absolute path from the JSON's `changeDir` + `outputPath`. (For `specs`, OpenSpec writes one file per capability under `<changeDir>/specs/<capability>/spec.md`; surface the list rather than one path.)

2. **The instructions** – the `instruction` field from the JSON (already includes pitfall callouts and examples).

3. **The enriched template** – the `template` field, but with placeholder comments replaced where project context provided concrete defaults (e.g., capability names from the proposal). Mark every remaining `<!-- … -->` clearly.

4. **Reminders** – pitfalls drawn from the artifact type (the four-hashtag scenario rule for specs; the checkbox shape for tasks; the dependency status from the JSON's `dependencies` array, e.g. "design.md is missing — consider running `/spec-writer design <change>` first if the change is non-trivial").

End with the exact CLI invocation the user would run if they want to regenerate the raw instructions:

```
openspec instructions <artifact> --change <change-name>
```

---

## Phase 5: Optional write-through

If `$ARGUMENTS` includes natural language like "write it to disk" or the caller passes `writeThrough: true`:

- For single-file artifacts (proposal / design / tasks): write the enriched template to the JSON's `<changeDir>/<outputPath>`. Do not overwrite an existing file unless the caller explicitly asks (`overwrite: true`).
- For `specs`: scaffold one `<changeDir>/specs/<capability>/spec.md` per capability listed in the proposal. Each gets the enriched delta template (`## ADDED Requirements`, etc.).

After writing, run `openspec validate <change-name> --strict` and surface any failures so the writer knows whether the structure parses.

If the caller does not request write-through, the skill simply prints the enriched template and stops. The caller (a human, `/brainstorm`, etc.) handles the file write.

---

## What this skill does NOT do

- **No format authorship** – the OpenSpec template is the source of truth; this skill never invents requirement shapes, scenario formats, or section headings.
- **No content invention** – it does not infer requirements from code; that's `/spec-recommender`'s job.
- **No commits** – the caller handles git.
- **No dual-mode logic** – legacy `.specs` projects must run `/migrate-to-openspec` first; this skill refuses without `openspec/`.
- **No interactive editing** – it's a generator. Iterating on the content is the caller's job (or use Plannotator via `/plannotator-specs` for review).

---

## Failure handling

| Failure | Action |
|---------|--------|
| `openspec` CLI missing | Fail with install instructions |
| No `openspec/` dir | Fail, suggest `openspec init` or `/migrate-to-openspec` |
| Unknown change name | Re-prompt with actual list from `openspec list --changes` |
| Artifact dependencies missing | Surface the dependency status, suggest the right `/spec-writer <dep>` invocation first |
| `openspec instructions` returns non-zero | Print stderr verbatim, abort |
| `openspec validate` fails after write-through | Show errors, leave file in place, do NOT auto-fix |
