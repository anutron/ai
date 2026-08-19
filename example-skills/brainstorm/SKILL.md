---
name: brainstorm
description: Use before writing any non-trivial code — new features, redesigns, or behavior changes. Turns a rough idea into a written design and task plan through collaborative dialogue, with an explicit approval gate before implementation starts.
user-invocable: true
---

# Brainstorm: from idea to plan

Turn an idea into a design and an implementation plan through dialogue, before any code gets written. Two phases — design, then planning — with one real approval gate between "we've agreed what to build" and "now build it."

## What this produces

A folder at `docs/plans/<name>/` containing:

- `design.md` — the problem, the approach, the key decisions and trade-offs
- `tasks.md` — the implementation plan as a checklist, grouped into stages

Adjust the folder path to fit your project's conventions. The pattern — design doc, approval, task list, then handoff — matters more than the path.

## Arguments

- `$ARGUMENTS` — optional description of the idea or feature. Becomes the seed for the plan's name.

## Hard gate

Do not write implementation code, scaffold files, or take any implementation action until `design.md` exists and the user has approved the plan. This applies to every change regardless of perceived simplicity. A one-function utility and a config tweak both go through this — "simple" is exactly where unexamined assumptions cause the most wasted work. The design can be short, but it has to exist and be approved.

## Dynamic context

```
! test -f README.md && head -50 README.md
! test -f CLAUDE.md && head -50 CLAUDE.md
! find . -maxdepth 1 \( -name package.json -o -name go.mod -o -name Gemfile -o -name pyproject.toml -o -name Cargo.toml \) 2>/dev/null
! git log --oneline -10 2>/dev/null
```

---

# Phase 1: Design

Work through these steps in order. Each one completes before the next begins.

## Step 1: Explore project context

Read before asking questions: README/CLAUDE.md/docs, the code the idea touches, recent commits in that area, and any existing `docs/plans/*/design.md` that might overlap with this one.

## Step 2: Surface assumptions

Present your understanding before diving into questions:

> "Based on what I see, here's what I'm assuming:
> 1. [assumption]
> 2. [assumption]
> 3. [assumption]
>
> Correct me now or I'll proceed with these."

This front-loads alignment and often eliminates several clarifying questions.

## Step 3: Scope gate

Assess the size of the change. For a genuinely small, well-understood, low-risk change, call `AskUserQuestion`:

- **Question:** "This looks like a small change. Want the full design process, or should I just confirm the approach and go?"
- **Options:** "Full process (Recommended)" / "Quick confirm"

Only ask this for genuinely small changes. Anything medium or larger always gets the full process — don't ask, just proceed.

## Step 4: Clarifying questions

Ask one at a time. Prefer multiple choice, but open-ended is fine. Focus on purpose, constraints, and success criteria.

Before going deep, check scope: if the request bundles multiple independent pieces of work, say so now and help split it into separate design cycles — each piece gets its own `design.md`.

**Logjam breakers** — deploy these when the conversation stalls:

- **Jobs to be done** — "What job is the user hiring this feature to do?"
- **First principles** — "What's an actual constraint here, versus one we're just assuming?"

## Step 5: Silent pre-mortem

After gathering enough context, privately assess: what could go wrong, and how big is the blast radius?

- **Small** (localized, easy to revert, no data risk) — proceed without comment.
- **Large** (data loss risk, breaking change, hard to revert) — call `AskUserQuestion`:
  - **Question:** "Before we finalize: [risk description]. [mitigation suggestion]. Proceed with mitigation, or adjust the approach?"
  - **Options:** "Proceed with mitigation" / "Adjust approach"

## Step 6: Norms check

Before proposing approaches, say the problem space out loud and ask yourself: "what does this kind of problem usually look like, and what's the standard approach?"

If the user's framing skips an established practice — hashing for credential comparison, env vars for secrets, parameterized queries for SQL, tests for behavioral code, idempotency keys for retries, rate limiting on public endpoints, migrations for schema changes — surface it as an option even if they didn't ask. State the norm, state why it exists, then let them choose knowingly.

Skip this when there's no relevant norm, or the user already explicitly opted into a non-standard approach.

## Step 7: Propose approaches

Present 2-3 approaches with trade-offs. Lead with your recommended option and say why. Be opinionated. Apply YAGNI ruthlessly.

## Step 8: Present the design in sections

Cover what's relevant: architecture, components, data flow, error handling, testing strategy. Ask after each section whether it looks right via `AskUserQuestion`; be ready to revise.

**Design for isolation and clarity:**

- Break the system into small units with one clear purpose and a well-defined interface.
- Each unit should be understandable and testable on its own.

**Working in an existing codebase:**

- Explore current structure before proposing changes. Follow existing patterns.
- Apply Chesterton's Fence: understand why existing code exists before changing or removing it.
- Don't propose unrelated refactoring.

**Acceptance criteria:**

For each section describing externally-observable behavior, write one-line `it should X` criteria. Skip sections that are pure architecture, rationale, or technology choice. One criterion per distinct behavior — two criteria are distinct if you can imagine an implementation that satisfies one and fails the other. If a behavioral section produces zero criteria, that's a signal the section is too vague; sharpen the section, not the criteria.

## Step 9: Write `design.md`

Write `docs/plans/<name>/design.md`. Suggested headings: Context, Goals, Non-Goals, Approach (with alternatives considered), Risks, Open Questions, Acceptance Criteria.

**Self-review before showing it:**

1. Placeholder scan — any "TBD" or incomplete sections? Fix them.
2. Internal consistency — do sections contradict each other?
3. Scope check — is this one focused change, or does it need to split into more?
4. Ambiguity check — could any decision be read two ways? Pick one and make it explicit.

Call `AskUserQuestion`:

- **Question:** "Design captured at `docs/plans/<name>/design.md`. Want to review it before I write the task plan, or go straight there?"
- **Options:** "Straight to the plan (Recommended)" / "Let me review first"

---

# Phase 2: Plan

## Step 1: Write `tasks.md`

Checkbox format, grouped into stages:

```markdown
## 1. Tests

- [ ] 1.1 Write failing tests for each acceptance criterion in design.md

## 2. <first vertical slice>

**Depends on:** Stage 1

- [ ] 2.1 ...
- [ ] 2.2 ...

## 3. <next vertical slice>

**Depends on:** Stage 1

- [ ] 3.1 ...   <!-- can run in parallel with stage 2 -- both only depend on 1 -->
```

Key principles:

- **Stage 1 is always "write failing tests"**, derived from the design's acceptance criteria — prove the gap exists before closing it.
- **Remaining stages are vertical slices** — each delivers one complete end-to-end path, not a horizontal layer.
- **Note `**Depends on:**`** under each stage so independent stages can be worked in parallel.

## Step 2: Present for approval

This is the one real review gate. Call `EnterPlanMode`, present `tasks.md` (plus a short summary of `design.md`) as the plan, and let the user review and approve it there. `ExitPlanMode` being accepted is the approval signal — don't write any implementation code before that happens.

**If review feedback changes the approach** — exit plan mode, update `design.md` first, then `tasks.md` to match, and re-enter plan mode for re-review. The two files must agree at the moment of approval.

## Step 3: Handoff

Once approved, ask via `AskUserQuestion` whether to start implementing now in this session or hand this plan to a separate session/agent. Proceed accordingly.

---

# Key principles

- The design doc exists and is approved before any code is written.
- One question at a time; multiple choice preferred over open-ended.
- YAGNI ruthlessly; always explore 2-3 alternatives before settling.
- Vertical slices, not horizontal layers.
- Tests first — prove the gap exists before closing it.
- Chesterton's Fence — understand why existing code exists before changing it.
- `design.md` and `tasks.md` must agree at the moment of approval.
