---
name: brainstorm
description: "You MUST use this before any creative work -- creating features, building components, adding functionality, or modifying behavior. Explores intent, designs the solution, scaffolds an OpenSpec change folder (proposal + design + delta specs + tasks), and hands off to execution."
user-invocable: true
tags: [spec]
---

# Brainstorm: From Idea to OpenSpec Change

Turn ideas into fully formed designs and an executable OpenSpec change through collaborative dialogue. Two phases — brainstorm (design the solution into the change folder) and planning (write deltas + tasks) — with one review gate (the change folder).

The output of this skill is a complete `openspec/changes/<name>/` folder containing:

- `proposal.md` – why and what changes
- `design.md` – architecture, decisions, alternatives, risks, discovery findings (freeform OpenSpec design doc)
- `specs/<capability>/spec.md` – delta specs (ADDED / MODIFIED / REMOVED requirements with scenarios)
- `tasks.md` – the implementation plan as a checklist (this IS what `/execute-plan` consumes)

## Arguments

- `$ARGUMENTS` – Optional: description of the feature or idea to develop. Becomes the seed for the change name.

## Hard gate

Do not invoke any implementation skill, write any code, scaffold any project (other than the OpenSpec change folder itself), or take any implementation action until the change folder is complete and the user has approved it. This applies to every project regardless of perceived simplicity. A todo list, a single-function utility, a config change — all of them go through this process. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short, but you must produce the change folder and get approval.

## Dynamic context

```
! test -d openspec && echo "OPENSPEC_ENABLED=true" || echo "OPENSPEC_ENABLED=false"
! test -d openspec && openspec list --specs --json 2>/dev/null | head -200
! test -d openspec && openspec list --changes --json 2>/dev/null | head -200
! test -f CLAUDE.md && head -50 CLAUDE.md
```

## Prerequisites

This skill is OpenSpec-only. The target project MUST have an `openspec/` directory. If it does not:

- If a legacy `.specs` file is present → suggest `/migrate-to-openspec` first.
- Otherwise → suggest `openspec init`.

Stop the skill until OpenSpec is initialized. Do not fall back to the legacy `specs/` flow.

---

# Phase 1: Brainstorm

Work through these steps in order. Each step completes before the next begins.

## Step 1: Explore project context

Read the project before asking questions. Priority order:

1. **Interview artifacts** – check for a `*_review/` directory with `summary.md` or `discussion.log` related to the topic. If found, read the summary (and discussion log if needed). If the interview happened in this same session, the context is already in conversation history — do not re-read.
2. **Base specs first** – if `openspec/specs/` has capabilities, read the relevant ones. Base specs are the source of truth; code is an implementation detail.
3. **Active changes** – run `openspec list --changes --json`. If another in-flight change touches related capabilities, read its proposal and deltas so you don't propose conflicting work.
4. **CLAUDE.md** – project instructions, conventions, stack.
5. **Code, docs, commits** – as needed to understand the current state.

Interview artifacts supplement but do not replace project exploration.

## Step 2: Assumption surfacing

Present your understanding before diving into questions:

> "Based on what I see, here are my assumptions:
> 1. [assumption]
> 2. [assumption]
> 3. [assumption]
>
> Correct me now or I'll proceed with these."

This front-loads alignment and often eliminates several clarifying questions.

## Step 3: Scope gate

Two assessments happen here.

### 3a. Interview check

After reading the project and surfacing assumptions, assess: does this topic require domain knowledge that isn't in the codebase?

Signs you need an interview first:

- The request references external systems, business processes, or organizational knowledge you can't see (CRM stages, vendor contracts, team workflows, compliance rules)
- You can't tell where the feature fits in the existing architecture because the "why" lives outside the code
- The request uses domain terms you'd need the user to define before you could even ask good design questions

If the topic needs an interview, call `AskUserQuestion`:

- **Question:** "This involves [specific external knowledge] that I can't see in the codebase. I'd design better with a fuller picture of the problem space. Should we start with an interview to get me up to speed?"
- **Options:** "Interview first (Recommended)" / "Skip, proceed with brainstorm"

If the user skips, proceed — they may know that the brainstorm questions will be enough.

If the topic is well-understood from the codebase and docs, skip this and proceed.

### 3b. Size check

Assess the size of the change. If it looks small (localized, well-understood, low risk), call `AskUserQuestion`:

- **Question:** "This looks like a small change. Want the full brainstorm process, or should I just confirm the approach and go?"
- **Options:** "Full brainstorm (Recommended)" / "Quick confirm"

Behavior:

- **Full brainstorm** – continue with the complete flow.
- **Quick confirm** – skip to a brief approach confirmation, then proceed directly to planning.

Only ask this for genuinely small changes. Medium and large changes always get the full process.

## Step 4: Visual companion offer

If upcoming questions will involve visual content (layouts, mockups, wireframes, diagrams, side-by-side comparisons), call `AskUserQuestion` as its own message — do not combine it with any other content:

- **Question:** "Some of what we're working on might be easier to show visually in a browser — mockups, diagrams, layout comparisons. This is token-intensive. Want to try it?"
- **Options:** "Text only" / "Use browser visuals"

If declined, proceed with text-only brainstorming. If accepted, read `skills/brainstorm/visual-companion.md` before continuing.

**Per-question decision:** even after the user accepts, decide for each question whether to use the browser or the terminal. The test: would the user understand this better by seeing it than reading it?

Skip this step entirely if the topic has no visual dimension.

## Step 5: Clarifying questions

Ask questions one at a time. Prefer multiple choice when possible, but open-ended is fine too. Focus on purpose, constraints, and success criteria.

Before asking detailed questions, assess scope: if the request describes multiple independent subsystems, flag it immediately. Help decompose into sub-projects before refining details. Each sub-project gets its own brainstorm cycle and its own OpenSpec change.

**Logjam breakers** — deploy these frameworks when the conversation stalls:

- **Jobs to Be Done** – "What job is the user hiring this feature to do?"
- **First Principles** – "What are the actual constraints vs. assumed ones?"

## Step 6: Silent pre-mortem

After gathering enough context, silently assess: what could go wrong? How big is the blast radius?

- **Small** (localized change, easy to revert, no data risk) – proceed without comment.
- **Large** (data loss risk, breaking change, cross-system impact, hard to revert) – call `AskUserQuestion`:
  - **Question:** "Before we finalize: [risk description]. [Mitigation suggestion]. Want to proceed or adjust the approach?"
  - **Options:** "Proceed with mitigation" / "Adjust approach"

## Step 7: Norms check

Before proposing approaches, name the problem space out loud and ask: "what does this kind of problem usually look like, and what's the standard professional approach?"

If the user's framing skips a well-established solution — hashing for credential comparison, env vars for secrets, parameterized queries for SQL, tests for behavioral code, idempotency keys for retries, rate limiting for public endpoints, migrations for schema changes — surface it as an option even if they didn't ask for it. State the norm, state why it exists, then let the user choose knowingly.

Skip when the problem space has no relevant industry norm, or when the user has explicitly opted into a non-standard approach earlier in the conversation.

## Step 8: Propose approaches

Present 2-3 approaches with trade-offs, informed by the norms surfaced in Step 7. Lead with your recommended option and explain why. Be opinionated. YAGNI ruthlessly.

## Step 9: Present design in sections

Once you understand what you're building, present the design. Scale each section to its complexity. Cover as relevant: architecture, components, data flow, error handling, testing strategy.

Ask after each section whether it looks right so far via `AskUserQuestion`. Be ready to go back and revise.

**Design for isolation and clarity:**

- Break the system into smaller units with one clear purpose and well-defined interfaces.
- Each unit should be understandable and testable independently.
- Smaller, well-bounded units are also easier for agents to work with.

**Working in existing codebases:**

- Explore current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work, include targeted improvements as part of the design.
- Apply Chesterton's Fence: understand why existing code exists before changing or removing it.
- Do not propose unrelated refactoring.

**Acceptance criteria per behavioral section:**

For each design section that describes externally-observable behavior, propose acceptance criteria as one-line `it should X` statements. These will become OpenSpec scenarios in Phase 2 — write them in a form that maps cleanly to `WHEN ... THEN ...`.

Rules:

- **Pair with behavioral sections only.** Skip sections that are pure architecture, rationale, convention, or technology choice.
- **One criterion per distinct behavior.** Two criteria are distinct if you can imagine an implementation that satisfies one and fails the other.
- **Stop at redundancy.**
- **Behavior, not internals.**

If a section produces zero criteria and isn't pure architecture/rationale, that's a signal the section is too vague. Sharpen the section, not the criteria.

## Step 10: Pick a change name and scaffold the OpenSpec change folder

Derive a kebab-case change name from the topic (e.g. `add-fitbit-mcp-server`, `granola-auto-record`, `fix-statusline-flicker`). The name must:

- Be unique among existing changes (`openspec list --changes --json`)
- Describe the change as an action (verb-led: `add-`, `update-`, `remove-`, `fix-`, `refactor-`)
- Match what will eventually become the git branch name

Run:

```
openspec new change <name> --description "<one-line summary>"
```

This creates `openspec/changes/<name>/` with `.openspec.yaml` and `README.md`. Subsequent steps fill in the artifacts.

## Step 11: Write `design.md`

The brainstorm doc IS `openspec/changes/<name>/design.md`. Fetch the OpenSpec design template:

```
openspec instructions design --change <name>
```

The native template covers Context / Goals / Non-Goals / Decisions / Risks / Trade-offs / Migration Plan / Open Questions. Use those headings for content that fits.

For content that doesn't fit OpenSpec's native template, add freeform `## ...` headings under or alongside the native sections. Useful additions:

- `## Alternatives considered` — the 2-3 approaches from Step 8 with trade-offs
- `## Discovery findings` — what you learned while exploring the codebase
- `## Acceptance criteria` — the per-section `it should X` criteria captured during Step 9, organized by section

Use `/spec-writer` if available to produce structured prose (proposal/design/tasks/specs). Commit the file once the design is captured.

**Design self-review** — check the written doc with fresh eyes:

1. Placeholder scan: any "TBD", "TODO", incomplete sections? Fix them.
2. Internal consistency: do sections contradict each other? Does the architecture match the feature descriptions?
3. Scope check: is this focused enough for a single change, or does it need decomposition into multiple changes?
4. Ambiguity check: could any requirement be interpreted two ways? Pick one and make it explicit.
5. Acceptance criteria coverage: does every behavioral section have its `it should X` criteria captured? Skip this check for topics with no testable behavior.

Fix issues inline.

**Optional spec document reviewer** — for complex change folders (multiple capabilities, cross-cutting concerns, or significant architectural decisions), consider dispatching a reviewer subagent using the prompt template at `skills/brainstorm/spec-document-reviewer-prompt.md`.

**User review offer** — call `AskUserQuestion`:

- **Question:** "Design captured at `openspec/changes/<name>/design.md` and committed. Want to review it before I move to planning?"
- **Options:** "Proceed to planning (Recommended)" / "Review in Plannotator"

Behavior:

- **Proceed to planning** – move straight to Phase 2.
- **Review in Plannotator** – launch `/plannotator-annotate` on `design.md`. Address annotations (rewrite sections immediately for questions; discuss only if the annotation explicitly says so). Re-open in Plannotator until approved. Then proceed to Phase 2.

---

# Phase 2: Planning (proposal + deltas + tasks)

Invoked automatically after `design.md` is approved.

## Step 1: Read `design.md`

Read the captured design as the input — not conversation history. The design is the captured intent.

## Step 2: Write `proposal.md`

Fetch the OpenSpec proposal template:

```
openspec instructions proposal --change <name>
```

Fill in:

- **Why** – 1-2 sentences from the design's Context.
- **What Changes** – bullet list of additions, modifications, removals. Mark breaking changes with **BREAKING**.
- **Capabilities** – the critical section.
  - **New Capabilities** – list capabilities being introduced (kebab-case names). Each becomes a new `openspec/specs/<name>/spec.md` once archived.
  - **Modified Capabilities** – existing capabilities under `openspec/specs/` whose requirements are changing. Cross-check against `openspec list --specs --json`. Leave empty if none.
- **Impact** – affected code, APIs, dependencies.

Commit `proposal.md`.

## Step 3: Write delta specs at `openspec/changes/<name>/specs/<capability>/spec.md`

For each capability listed in the proposal's Capabilities section, write a delta spec. Fetch the OpenSpec specs template:

```
openspec instructions specs --change <name>
```

Delta operations (use H2 headers):

- `## ADDED Requirements` – for new behavior on a brand-new capability.
- `## MODIFIED Requirements` – for changed behavior. MUST include the FULL updated requirement (copy the entire block from the base spec at `openspec/specs/<capability>/spec.md`, then edit). Header text must match exactly.
- `## REMOVED Requirements` – for removals. MUST include `**Reason**` and `**Migration**` lines.
- `## RENAMED Requirements` – use FROM:/TO: format for name-only changes.

Format inside each section:

- `### Requirement: <name>` – use SHALL/MUST normative language, never should/may.
- One paragraph or short prose describing the requirement.
- `#### Scenario: <name>` – every requirement MUST have at least one scenario. Use exactly four hashtags. Body uses `- **WHEN** ...` and `- **THEN** ...`.

Map the per-section `it should X` acceptance criteria from `design.md` to scenarios verbatim where possible. Don't paraphrase; tighten WHEN/THEN structure but keep the behavior identical.

After writing all delta files, validate:

```
openspec validate <name> --strict
```

Fix any structural errors before continuing. Commit deltas.

## Step 4: Write `tasks.md` (the plan)

`tasks.md` IS the implementation plan that `/execute-plan` consumes. Fetch the template:

```
openspec instructions tasks --change <name>
```

The OpenSpec tasks file uses checkbox format: `- [ ] N.M Task description`. Group related tasks under `## N. Group name` headers. Each top-level group is one stage in `/execute-plan`'s task graph.

Adapt the AI-RON staging conventions to OpenSpec checkbox layout:

```markdown
## 1. Tests

- [ ] 1.1 Write failing tests from each scenario in `specs/<capability>/spec.md`
- [ ] 1.2 Confirm every `it should X` criterion has a failing test (Prove-It Pattern)

## 2. <First vertical slice>

**Depends on:** Stage 1

- [ ] 2.1 ...
- [ ] 2.2 ...

## 3. <Next vertical slice>

**Depends on:** Stage 1

- [ ] 3.1 ...   <!-- parallel with stage 2 because both depend only on 1 -->
```

Key principles for stages:

- **Stage 1 is always "write failing tests"** derived from the deltas. No explicit "update specs" stage — deltas are already written in Step 3.
- **Remaining stages are implementation** — one vertical slice each.
- **Vertical slices** — each stage delivers one complete end-to-end path, not horizontal layers.
- **Prove-It Pattern** — tests must fail first, proving the behavioral gap exists.
- **Chesterton's Fence** — understand why existing code exists before changing or removing it.
- **Dependencies** — note `**Depends on:**` lines under each stage's H2 so `/execute-plan` can build a dependency graph. Stages with the same dependency can run in parallel.

Add a `**Design doc:**` line at the top of `tasks.md` pointing at `openspec/changes/<name>/design.md`. The executing agent reads both.

Commit `tasks.md`.

**Design consistency check:** before committing the plan, compare `tasks.md` against `design.md` and the deltas. If any decision in the plan differs from the design — new architecture, changed flow, different technical approach — update `design.md` first to reflect the current decision, commit it, then update the deltas if needed, then commit `tasks.md`. The change folder is a living set of artifacts; they must agree at the moment of approval.

**Validate the whole change:**

```
openspec validate <name> --strict
```

Must pass before review.

## Step 5: Present plan for review

This is the one real review gate in the entire workflow. The user reads the strategy and approves or requests changes.

After the change folder is fully written and validated, call `EnterPlanMode` and present the contents of `tasks.md` (plus a brief `proposal.md` + key delta excerpts) as the plan-mode content. `ExitPlanMode` becomes the user's approval signal.

**Feedback that changes requirements:** if plan review produces feedback that changes the design — architecture, data model, flows, technical approach — exit plan mode, update `design.md` first and commit, update the deltas to match and commit, amend `tasks.md` and commit, then re-enter plan mode for re-review. The artifacts must be consistent at approval.

## Step 6: Execution handoff

After plan approval (`ExitPlanMode` accepted), call `AskUserQuestion`:

- **Question:** "Change `<name>` approved and ready to execute. How do you want to proceed?"
- **Options:** "Copy to clipboard (Recommended)" / "Execute in this session"

Behavior:

- **Copy to clipboard** – run `echo -n "/execute-plan <name>" | pbcopy` and tell the user to run `/clear` and paste. Claude cannot execute `/clear` itself. The argument is the change NAME, not a path.
- **Execute in this session** – invoke `/execute-plan <name>` here without clearing context (good for small changes or when current context is valuable).

---

# Key principles

- **OpenSpec change folder is the unit of work** – everything for the change lives at `openspec/changes/<name>/`.
- **One question at a time** – do not overwhelm with multiple questions.
- **Multiple choice preferred** – easier to answer than open-ended when possible.
- **YAGNI ruthlessly** – remove unnecessary features from all designs.
- **Explore alternatives** – always propose 2-3 approaches before settling.
- **Incremental validation** – present design, get approval before moving on.
- **Specs are source of truth** – if it's not in the deltas (or the base specs they modify), it doesn't exist.
- **Vertical slices** – each implementation stage delivers one complete end-to-end path.
- **Prove-It Pattern** – tests must fail before implementation, proving the gap exists.
- **Chesterton's Fence** – understand why existing code exists before changing it.
- **`openspec validate <name> --strict` must pass before approval** – never present an invalid change folder for review.
