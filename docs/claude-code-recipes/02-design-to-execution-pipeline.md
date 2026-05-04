![The design-to-execution pipeline](recipe2_execution-pipeline-assembly.png)

# Recipe 2: The design-to-execution pipeline

> **OpenSpec workflow (v1.22.0+).** The skills described here now run on [OpenSpec](https://github.com/Fission-AI/OpenSpec). Specs live under `openspec/specs/<capability>/spec.md`, in-flight work lives in `openspec/changes/<name>/`, and the lifecycle is `change folder → deltas → tests → implement → archive`.
>
> **Want the previous workflow?** The [`legacy-spec-system`](https://github.com/anutron/claude-skills/tree/legacy-spec-system) tag points at the v1.21.0 commit – the last release using the `.specs`-based system. To migrate an existing legacy project, use [`/migrate-to-openspec`](../../skills/migrate-to-openspec/SKILL.md).

## The idea

The natural instinct with an AI coding tool is to say "build me X" and let it go. This works for small tasks, but for anything substantial it produces code that doesn't match what you actually wanted – and you don't discover the mismatch until you're deep into debugging.

The fix is a document-driven pipeline that captures intent before code gets written. Each stage produces an artifact, each artifact has a specific purpose, and the whole chain lives in version control. The spec – a description of what the system should do – is always the source of truth. If the spec and the code disagree, the code is wrong.

> **Skills used in this recipe:** The pipeline described here is implemented as a set of open-source Claude Code skills available at [github.com/anutron/claude-skills](https://github.com/anutron/claude-skills). Each stage of the pipeline has corresponding skills referenced inline below.

## The artifact chain

### Brainstorm doc → intent

The brainstorm phase is a structured conversation between the user and Claude that produces a document capturing **what you want to change and why**. It's not a plan – it doesn't say how to build anything. It's a contract about intent.

A good brainstorm doc surfaces assumptions early, explores 2-3 approaches, and records the chosen direction with reasoning. It gets committed to git immediately. In the OpenSpec workflow, `/brainstorm` scaffolds an OpenSpec change folder under `openspec/changes/<name>/` containing `proposal.md`, `design.md`, `tasks.md`, and delta specs at `openspec/changes/<name>/specs/<capability>/spec.md`.

> **Skills:** [`/brainstorm`](https://github.com/anutron/claude-skills) is the primary tool here. For blank-slate projects where you're starting from nothing, [`/kickoff`](https://github.com/anutron/claude-skills) runs a focused discovery conversation (project goals, stack selection) and then hands off to `/brainstorm` automatically – you don't need to invoke them separately. [`/interview`](https://github.com/anutron/claude-skills) is a separate skill useful when you need to extract domain knowledge from a person before designing anything.

### Plan → strategy

The plan reads the brainstorm doc and produces an execution strategy. It says which files to change, in what order, and what "done" looks like for each step. In the OpenSpec workflow this lives in `openspec/changes/<name>/tasks.md`.

The first step in every plan is the same: **update the delta specs to reflect the new intent.** If the brainstorm doc says button color should be configurable, step one of the plan is to update the delta spec at `openspec/changes/<name>/specs/<capability>/spec.md` before any code is written. The spec changes before the code does.

> **Skills:** `/brainstorm` produces `tasks.md` as part of the change folder. [`/execute-plan`](https://github.com/anutron/claude-skills) takes an OpenSpec change name and orchestrates implementation – dispatching agents, managing dependencies, and ensuring each stage completes before the next begins.

### Specifications → truth

Specs describe the system's behavior from the outside – what it does, not how it's built. "Button color is configurable by the user" is a spec statement. "There's a `colorConfig` prop on the Button component" is an implementation detail that doesn't belong in a spec.

The spec is the only artifact that matters for understanding **what is true right now**. Brainstorm docs and plans are history – they explain how you got here. The spec is the present tense.

In the OpenSpec workflow, base specs live at `openspec/specs/<capability>/spec.md` and represent the current state of the system. In-flight changes carry delta specs at `openspec/changes/<name>/specs/<capability>/spec.md` that describe the future state. When a change is complete, `openspec archive <name>` merges the deltas into the base specs and removes the change folder.

Key properties of specs:

- **Behavioral, not structural** – describe what the system does, not how it's implemented
- **Always current** – updated before or on the same turn as any behavioral change
- **Source of truth** – if spec and code disagree, the code needs fixing
- **Rebuildable** – you should be able to reconstruct the system from specs alone

> **Skills:** [`/spec-writer`](https://github.com/anutron/claude-skills) owns the spec format and produces consistent spec text. [`/spec-audit`](https://github.com/anutron/claude-skills) audits spec coverage across a codebase – inventories files, maps them to specs, and finds behavioral gaps.

### Review and quality

After implementation, review skills verify the work against the specs and catch regressions.

> **Skills:** [`/ralph-review`](https://github.com/anutron/claude-skills) and [`/rereview`](https://github.com/anutron/claude-skills) are complementary. `/ralph-review` is the loop-based autonomous version – it reviews against specs, auto-fixes confident changes, parks questions, and iterates. `/rereview` is the same kind of fresh-eyes review with competing independent reviewers, but as a single-shot pass – useful as a one-off when you want a deeper independent check, but you lose the auto-fix-and-iterate behavior. [`/test`](https://github.com/anutron/claude-skills) runs targeted tests and identifies coverage gaps. [`/guard`](https://github.com/anutron/claude-skills) is a pre-commit safety check for secrets and security antipatterns. [`/verification-before-completion`](https://github.com/anutron/claude-skills) enforces an evidence-before-claims gate – you must run verification commands before asserting that work is done.

### Saving work

> **Skills:** [`/save-w-specs`](https://github.com/anutron/claude-skills) commits completed work while verifying that specs were updated alongside any behavioral changes. It's the spec-aware version of git commit.

### The flow

```
  Intent               Strategy             Truth               Code
┌──────────┐        ┌──────────┐        ┌──────────┐        ┌──────────┐
│Brainstorm│───────▶│   Plan   │───────▶│   Spec   │───────▶│  Build   │
│   doc    │        │          │        │ (updated)│        │          │
└──────────┘        └──────────┘        └──────────┘        └──────────┘
     │                   │                   │                    │
     ▼                   ▼                   ▼                    ▼
  committed           committed           committed           committed
  to git              to git              to git              to git
```

Every artifact is committed. The git history tells the full story: why a change was proposed, how it was planned, what the spec said before and after, and what code was written to implement it.

## Bootstrapping: what if you already have code?

The pipeline assumes specs exist before code, but most organizations already have a codebase with no specs. You don't need to start from scratch – you need to establish a baseline.

The bootstrap process:

1. **Survey the existing code.** For each significant component, ask Claude to read the code and propose what the spec *should* say. Claude can infer intent – "this module handles authentication via OAuth2, supports Google and GitHub providers, and stores tokens in an encrypted cookie."

2. **Confirm or correct.** The user reviews each proposed spec and says whether it accurately captures the intent or if it's an accident of implementation. "Yes, we intended to support Google and GitHub" is a confirmation. "Actually, GitHub was a prototype we never finished" is a correction.

3. **Commit the baseline.** Once confirmed, these become your specs. They represent what is true today, whether or not it was originally intentional.

4. **Enter the loop.** From here forward, changes flow through the pipeline: change folder → deltas → tests → implement → archive.

This survey can be done incrementally – you don't need to spec the entire codebase at once. Start with the areas you're actively changing and expand coverage over time.

> **Skills:** [`/spec-recommender`](https://github.com/anutron/claude-skills) is an open-source skill (not built into Claude) that reads code and proposes what the spec should say. It's designed for individual components – to bootstrap an entire codebase, tell Claude to use `/spec-recommender` iteratively across your significant components as a survey. A dedicated bulk-bootstrap skill doesn't exist, but `/spec-recommender` used in a loop is the mechanism.

## Version control is load-bearing

Every artifact in the pipeline must be in version control. This isn't about tidiness – it's structural:

- **Brainstorm docs** record why changes were proposed. When someone asks "why does this work this way?" six months later, the brainstorm doc has the answer.
- **Plans** record execution strategy. When a similar change comes up later, past plans show how the team approached it.
- **Specs** have a git history that shows how requirements evolved over time.
- **The diff between spec versions** is the clearest possible expression of what changed and why.

Without version control, the pipeline is just a conversation that evaporates when the session ends.

**Important note on plans:** By default, Claude Code's native `/plan` mode stores plans in `~/.claude/` – the user's home directory, outside the project. This means plans are invisible to git and lost when the session ends. To make plans durable, use `/brainstorm` (which stores `tasks.md` inside the change folder at `openspec/changes/<name>/tasks.md`) or configure your CLAUDE.md to write plans into the project directory and commit them.

---

## Diagram

```
         Bootstrap (existing codebases)
         ┌────────────────────────┐
         │ Code ──▶ Spec proposal │
         │    User confirms/corrects
         │         ──▶ Baseline spec
         └────────────┬───────────┘
                      │ (one-time)
                      ▼
         Steady-state loop
         ┌────────────────────────────────────────────┐
         │                                            │
         │  User intent                               │
         │      │                                     │
         │      ▼                                     │
         │  Change folder created (proposal.md,       │
         │  design.md, tasks.md + delta specs)        │
         │      │                                     │
         │      ▼                                     │
         │  Delta specs updated (truth moves forward) │
         │      │                                     │
         │      ▼                                     │
         │  Tests written from deltas                 │
         │      │                                     │
         │      ▼                                     │
         │  Code implemented to pass tests            │
         │      │                                     │
         │      ▼                                     │
         │  openspec archive → deltas merged to base  │
         │      │                                     │
         │      ▼                                     │
         │  All artifacts committed to git            │
         │      │                                     │
         │      └──────────────── (next change) ──▶   │
         │                                            │
         └────────────────────────────────────────────┘
```

---

## Technical reference for Claude

When helping a user implement this pipeline, follow these conventions:

### Skills reference

These skills are available at [github.com/anutron/claude-skills](https://github.com/anutron/claude-skills):

| Stage | Skills | Purpose |
|-------|--------|---------|
| Starting from scratch | `/kickoff`, `/interview` | Discovery, domain knowledge extraction |
| Intent capture | `/brainstorm` | Structured design conversation → OpenSpec change folder (proposal, design, tasks, delta specs) |
| Spec writing | `/spec-writer` | Produces spec text in consistent format |
| Spec bootstrap | `/spec-recommender` | Proposes specs from existing code (use iteratively for surveys) |
| Spec coverage | `/spec-audit` | Audits codebase for unspecified behavior |
| Execution | `/execute-plan` | Orchestrates plan stages with agent dispatch |
| Review | `/ralph-review`, `/rereview` | Autonomous review against specs; fresh-eyes second pass |
| Testing | `/test`, `/test-driven-development` | Targeted test runs; TDD discipline |
| Safety | `/guard`, `/verification-before-completion` | Pre-commit checks; evidence-before-claims |
| Committing | `/save-w-specs` | Spec-aware git commit |

### Directory structure

```
project/
├── openspec/                 # Presence of this directory opts the project into spec-driven dev
│   ├── specs/
│   │   └── <capability>/
│   │       └── spec.md       # Base spec for a capability (source of truth)
│   └── changes/
│       └── <name>/
│           ├── proposal.md   # Why this change is happening
│           ├── design.md     # How it will be built
│           ├── tasks.md      # Execution plan (step-by-step)
│           └── specs/
│               └── <capability>/
│                   └── spec.md  # Delta spec (future state during this change)
└── ...
```

### Opting in

Detection is trivial: `test -d openspec`. Projects without an `openspec/` directory do not use this pipeline. When working in a project that lacks one, recommend running `openspec init` (or `/migrate-to-openspec` if a legacy `.specs`-based system is present).

### Spec format

Specs describe interface behavior, not implementation:

- **Purpose** – What this component exists to do
- **Interface** – Inputs, outputs, dependencies
- **Behavior** – What happens from the user's perspective
- **Test cases** – Concrete scenarios that validate the spec

This follows the [OpenSpec](https://github.com/Fission-AI/OpenSpec/) format for consistency across teams.

### Brainstorm docs and design artifacts

Written during the brainstorm phase, committed immediately as part of the change folder at `openspec/changes/<name>/`.

Key properties:
- `proposal.md` – records the user's intent, not Claude's interpretation; surfaces and resolves assumptions
- `design.md` – explores multiple approaches, recommends one
- `tasks.md` – the execution plan; step 1 is always to update the delta specs before any code is written
- Delta specs at `openspec/changes/<name>/specs/<capability>/spec.md` describe the future state

**Important:** Claude Code's native `/plan` mode stores plans in `~/.claude/`, outside the project and invisible to git. The `/brainstorm` skill writes `tasks.md` directly into the change folder and commits it automatically.

Key properties of `tasks.md`:
- References the brainstorm artifacts
- Step 1 is always: update delta specs to reflect new intent
- Subsequent steps are vertical slices (complete end-to-end paths, not horizontal layers)
- Each step specifies: files touched, dependencies, done criteria
- If the plan needs to deviate, update `proposal.md` or `design.md` first

After implementation, run `openspec archive <name>` to merge deltas into base specs. The change folder is removed.

### Bootstrap workflow

When a user wants to adopt specs on an existing codebase:

1. Run `openspec init` to scaffold the `openspec/` directory (or `/migrate-to-openspec` from a legacy `.specs` system)
2. Identify significant components (routes, models, services, CLI commands)
3. For each component, use `/spec-recommender` to read the code and propose a spec
4. Present each proposed spec to the user for confirmation or correction
5. Use `/spec-writer` to produce the final spec text at `openspec/specs/<capability>/spec.md`
6. Commit confirmed specs as the baseline
7. From this point forward, follow the change folder → deltas → tests → implement → archive lifecycle

Do not attempt to spec the entire codebase at once – start with areas under active development.

### Spec maintenance rules

- Update delta specs before or on the same turn as any behavioral change – never batch for later
- If implementation produces behavior not explicitly in the delta spec but easily inferred, fill in the gap and confirm with the user
- After every commit, report spec status:
  - `Specs: Updated (openspec/changes/<name>/specs/<cap>/spec.md)` – delta changes included
  - `Specs: No behavioral changes` – config/docs/cosmetic only
  - `Specs: Skipped (no openspec/ dir)` – project doesn't use OpenSpec
