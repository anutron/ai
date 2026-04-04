---
name: brainstorm
description: "You MUST use this before any creative work -- creating features, building components, adding functionality, or modifying behavior. Explores intent, designs the solution, writes a strategic plan, and hands off to execution."
user-invocable: true
---

# Brainstorm: From Idea to Execution Plan

Turn ideas into fully formed designs and strategic implementation plans through collaborative dialogue. Two phases -- brainstorm (design the solution) and planning (map the execution) -- with one review gate (the plan).

## Arguments

- `$ARGUMENTS` - Optional: description of the feature or idea to develop

## Hard Gate

Do not invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to every project regardless of perceived simplicity. A todo list, a single-function utility, a config change -- all of them go through this process. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short, but you must present it and get approval.

## Dynamic Context

```
! test -f .specs && echo "SPECS_ENABLED=true; SPECS_DIR=$(grep '^dir:' .specs | cut -d' ' -f2 | tr -d ' ')" || echo "SPECS_ENABLED=false"
! test -f CLAUDE.md && head -50 CLAUDE.md
```

---

# Phase 1: Brainstorm

Work through these steps in order. Each step completes before the next begins.

## Step 1: Explore project context

Read the project before asking questions. Priority order:

1. **Specs first** -- if `.specs` exists, read the specs directory. Specs are the source of truth; code is an implementation detail. Understand the behavioral contract before looking at implementation.
2. **CLAUDE.md** -- project instructions, conventions, stack
3. **Code, docs, commits** -- as needed to understand the current state

If the project has no `.specs` file, note it. You may recommend adding one later, but do not interrupt the flow for it.

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

Assess the size of the change. If it looks small (localized, well-understood, low risk), ask via `AskUserQuestion`:

> "This looks like a small change. Want the full brainstorm process, or should I just confirm the approach and go?"

Options:
- **Full brainstorm** (default) -- continue with the complete flow
- **Quick confirm** -- skip to a brief approach confirmation, then proceed directly to planning

Only ask this for genuinely small changes. Medium and large changes always get the full process.

## Step 4: Visual companion offer

If upcoming questions will involve visual content (layouts, mockups, wireframes, diagrams, side-by-side comparisons), offer the browser companion via `AskUserQuestion`. This must be its own message -- do not combine it with any other content:

> "Some of what we're working on might be easier to show visually in a browser -- mockups, diagrams, layout comparisons. I can put together visuals as we go. This is token-intensive. Want to try it? (Requires opening a local URL)"

If declined, proceed with text-only brainstorming. If accepted, read the visual companion guide before continuing:

`skills/brainstorm/visual-companion.md`

**Per-question decision:** Even after the user accepts, decide for each question whether to use the browser or the terminal. The test: would the user understand this better by seeing it than reading it?

- **Use the browser** for content that is visual -- mockups, wireframes, layout comparisons, architecture diagrams, side-by-side visual designs
- **Use the terminal** for content that is text -- requirements questions, conceptual choices, tradeoff lists, scope decisions

A question about a UI topic is not automatically a visual question. "What does personality mean in this context?" is conceptual -- use the terminal. "Which wizard layout works better?" is visual -- use the browser.

Skip this step entirely if the topic has no visual dimension.

## Step 5: Clarifying questions

Ask questions one at a time. Prefer multiple choice when possible, but open-ended is fine too. Focus on purpose, constraints, and success criteria.

Before asking detailed questions, assess scope: if the request describes multiple independent subsystems, flag this immediately. Help decompose into sub-projects before refining details. Each sub-project gets its own brainstorm cycle.

**Logjam breakers** -- deploy these frameworks when the conversation stalls, not as mandatory steps:

- **Jobs to Be Done** -- "What job is the user hiring this feature to do?" Reframes the problem around outcomes instead of implementation.
- **First Principles** -- "What are the actual constraints vs. assumed ones?" Strips away inherited assumptions to find the real design space.

## Step 6: Silent pre-mortem

After gathering enough context, silently assess: what could go wrong? How big is the blast radius?

- **Small** (localized change, easy to revert, no data risk) -- proceed without comment
- **Large** (data loss risk, breaking change, cross-system impact, hard to revert) -- surface to the user before continuing:

> "Before we finalize: [risk description]. [Mitigation suggestion]. Want to proceed or adjust the approach?"

## Step 7: Propose approaches

Present 2-3 approaches with trade-offs. Lead with your recommended option and explain why. Be opinionated -- pick the best option and defend it. YAGNI ruthlessly.

## Step 8: Present design in sections

Once you understand what you're building, present the design. Scale each section to its complexity -- a few sentences if straightforward, more detail if nuanced. Cover as relevant: architecture, components, data flow, error handling, testing strategy.

Ask after each section whether it looks right so far via `AskUserQuestion`. Be ready to go back and revise.

**Design for isolation and clarity:**
- Break the system into smaller units with one clear purpose and well-defined interfaces
- Each unit should be understandable and testable independently
- Smaller, well-bounded units are also easier for agents to work with -- they reason better about code they can hold in context

**Working in existing codebases:**
- Explore current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work, include targeted improvements as part of the design
- Apply Chesterton's Fence: understand why existing code exists before changing or removing it
- Do not propose unrelated refactoring

## Step 9: Write brainstorm doc

Always written. Save to `specs/docs/<date>-<topic>/brainstorm.md` where `<date>` is today's date (YYYY-MM-DD) and `<topic>` is a short kebab-case descriptor.

Use `/spec-writer` if available to produce spec text. Commit the document immediately.

**Spec self-review** -- check the written doc with fresh eyes:
1. Placeholder scan: any "TBD", "TODO", incomplete sections, vague requirements? Fix them.
2. Internal consistency: do sections contradict each other? Does the architecture match the feature descriptions?
3. Scope check: is this focused enough for a single implementation plan, or does it need decomposition?
4. Ambiguity check: could any requirement be interpreted two ways? Pick one and make it explicit.

Fix issues inline. No need to re-review -- just fix and move on.

**User review offer** -- via `AskUserQuestion`:

> "Brainstorm doc written to `<path>` and committed. Want to review it before I move to planning?"

Options:
- **No, proceed to planning** (default) -- move straight to Phase 2
- **Yes, let me review** -- wait for the user's feedback, revise if needed, then proceed

---

# Phase 2: Planning

Invoked automatically after the brainstorm doc is written (or after user review if they opted in).

## Step 1: Read the brainstorm doc

Read the written brainstorm doc as input -- not conversation history. The brainstorm doc is the captured intent.

## Step 2: Write the plan

Save to `specs/docs/<date>-<topic>/plan.md` (same directory as the brainstorm doc). This plan is strategic -- English only, no code. It tells the executing agent what to build and in what order, not how to write it line by line.

Structure:

```markdown
# <Feature Name> -- Implementation Plan

**Goal:** <Restated from the brainstorm>

**Assumptions and boundaries:**
- What's in scope
- What's not in scope
- What we're relying on (existing infrastructure, APIs, libraries)

## Stages

### Stage 1: Update specs

Update or create spec files from the brainstorm doc. <Describe which specs change and what the changes capture.>

### Stage 2: Write failing tests

Write tests from the updated specs before any implementation. Tests must fail first -- this proves the behavioral gap exists (Prove-It Pattern).

<Describe what gets tested, what the key assertions are, what frameworks to use.>

### Stage 3: <First vertical slice>

<What this stage delivers -- one complete end-to-end path. What files/areas it touches. Done criteria. Dependencies on prior stages.>

### Stage N: <Next vertical slice>

<Same structure. Each stage is a vertical slice delivering one complete path, not a horizontal layer.>
```

Key principles for stages:
- **Stage 1 is always "update specs"** from the brainstorm doc
- **Stage 2 is always "write failing tests"** from the updated specs
- **Remaining stages are implementation** -- one vertical slice each
- **Vertical slices** -- each stage delivers one complete end-to-end path, not horizontal layers
- **Prove-It Pattern** -- tests must fail first, proving the behavioral gap exists, then implement to make them pass
- **Chesterton's Fence** -- understand why existing code exists before changing or removing it

Commit the plan immediately after writing.

## Step 3: Present plan for review

This is the one real review gate in the entire workflow. The user reads the strategy and approves or requests changes. Present the plan and wait for approval.

## Step 4: Execution handoff

After plan approval, offer the choice via `AskUserQuestion`:

> "Plan approved. Ready to execute. Two options:"

Options:
- **Copy to clipboard** (default) -- copy `/execute-plan <plan-path>` to the clipboard and tell the user to run `/clear` and paste. Claude cannot execute `/clear` itself.
- **Execute in this session** -- run `/execute-plan` right here without clearing context (good for small plans or when current context is valuable)

For clipboard: `echo -n "/execute-plan <plan-path>" | pbcopy`

---

# Post-Execution Quality Gates

After `/execute-plan` finishes and reports its summary, offer quality gates via `AskUserQuestion`:

> "Implementation complete. Want to run quality checks?"

Options:
- **Both** (recommended) -- run `/ralph-review` and `/spec-audit` in parallel
- **Ralph-review only** -- autonomous review loop comparing implementation against specs
- **Spec-audit only** -- audit spec coverage, find behavioral gaps
- **Done** -- skip quality gates

These are token-heavy, so they are opt-in. But offering them at the natural completion point makes them easy to reach.

---

# Key Principles

- **One question at a time** -- do not overwhelm with multiple questions
- **Multiple choice preferred** -- easier to answer than open-ended when possible
- **YAGNI ruthlessly** -- remove unnecessary features from all designs
- **Explore alternatives** -- always propose 2-3 approaches before settling
- **Incremental validation** -- present design, get approval before moving on
- **Spec is source of truth** -- if it's not in the spec, it doesn't exist
- **Vertical slices** -- each implementation stage delivers one complete end-to-end path
- **Prove-It Pattern** -- tests must fail before implementation, proving the gap exists
- **Chesterton's Fence** -- understand why existing code exists before changing it
