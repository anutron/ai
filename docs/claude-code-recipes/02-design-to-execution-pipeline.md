![The design-to-execution pipeline](recipe2_execution-pipeline-assembly.png)

# Recipe 2: The design-to-execution pipeline

## The idea

The natural instinct with an AI coding tool is to say "build me X" and let it go. This works for small tasks, but for anything substantial it produces code that doesn't match what you actually wanted – and you don't discover the mismatch until you're deep into debugging.

The fix is a document-driven pipeline that captures intent before code gets written. Each stage produces an artifact, each artifact has a specific purpose, and the whole chain lives in version control. The spec – a description of what the system should do – is always the source of truth. If the spec and the code disagree, the code is wrong.

> **Skills used in this recipe:** The pipeline described here is implemented as a set of open-source Claude Code skills available at [github.com/anutron/claude-skills](https://github.com/anutron/claude-skills). Each stage of the pipeline has corresponding skills referenced inline below.

## The artifact chain

### Brainstorm doc → intent

The brainstorm phase is a structured conversation between the user and Claude that produces a document capturing **what you want to change and why**. It's not a plan – it doesn't say how to build anything. It's a contract about intent.

A good brainstorm doc surfaces assumptions early, explores 2-3 approaches, and records the chosen direction with reasoning. It gets committed to git immediately.

> **Skills:** [`/brainstorm`](https://github.com/anutron/claude-skills) is the primary tool here. For blank-slate projects where you're starting from nothing, [`/kickoff`](https://github.com/anutron/claude-skills) runs a focused discovery conversation (project goals, stack selection) and then hands off to `/brainstorm` automatically – you don't need to invoke them separately. [`/interview`](https://github.com/anutron/claude-skills) is a separate skill useful when you need to extract domain knowledge from a person before designing anything.

### Plan → strategy

The plan reads the brainstorm doc and produces an execution strategy. It says which files to change, in what order, and what "done" looks like for each step.

The first step in every plan is the same: **update the specification to reflect the new intent.** If the brainstorm doc says button color should be configurable, step one of the plan is to go find the spec that says buttons are red and change it to say the color is configurable. The spec changes before the code does.

> **Skills:** `/brainstorm` produces the plan as its second phase. [`/execute-plan`](https://github.com/anutron/claude-skills) takes an approved plan and orchestrates implementation – dispatching agents, managing dependencies, and ensuring each stage completes before the next begins.

### Specifications → truth

Specs describe the system's behavior from the outside – what it does, not how it's built. "Button color is configurable by the user" is a spec statement. "There's a `colorConfig` prop on the Button component" is an implementation detail that doesn't belong in a spec.

The spec is the only artifact that matters for understanding **what is true right now**. Brainstorm docs and plans are history – they explain how you got here. The spec is the present tense.

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

4. **Enter the loop.** From here forward, changes flow through the pipeline: brainstorm → plan → spec update → code.

This survey can be done incrementally – you don't need to spec the entire codebase at once. Start with the areas you're actively changing and expand coverage over time.

> **Skills:** [`/spec-recommender`](https://github.com/anutron/claude-skills) is an open-source skill (not built into Claude) that reads code and proposes what the spec should say. It's designed for individual components – to bootstrap an entire codebase, tell Claude to use `/spec-recommender` iteratively across your significant components as a survey. A dedicated bulk-bootstrap skill doesn't exist, but `/spec-recommender` used in a loop is the mechanism.

## Version control is load-bearing

Every artifact in the pipeline must be in version control. This isn't about tidiness – it's structural:

- **Brainstorm docs** record why changes were proposed. When someone asks "why does this work this way?" six months later, the brainstorm doc has the answer.
- **Plans** record execution strategy. When a similar change comes up later, past plans show how the team approached it.
- **Specs** have a git history that shows how requirements evolved over time.
- **The diff between spec versions** is the clearest possible expression of what changed and why.

Without version control, the pipeline is just a conversation that evaporates when the session ends.

**Important note on plans:** By default, Claude Code's native `/plan` mode stores plans in `~/.claude/` – the user's home directory, outside the project. This means plans are invisible to git and lost when the session ends. To make plans durable, your CLAUDE.md rules should instruct Claude to write plans into the project's working directory (e.g., `specs/docs/`) and commit them. The brainstorm skill described here does this automatically, but if you're using Claude's built-in planning, you need to configure this explicitly.

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
         │  Brainstorm doc (what + why)               │
         │      │                                     │
         │      ▼                                     │
         │  Plan (how, step 1 = update spec)          │
         │      │                                     │
         │      ▼                                     │
         │  Spec updated (truth moves forward)        │
         │      │                                     │
         │      ▼                                     │
         │  Tests written from spec                   │
         │      │                                     │
         │      ▼                                     │
         │  Code implemented to pass tests            │
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
| Intent capture | `/brainstorm` | Structured design conversation → brainstorm.md + plan.md |
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
├── .specs                    # Marker file; presence opts the project into spec-driven dev
├── specs/
│   ├── feature-name.md       # Individual spec files (one per feature/component)
│   ├── docs/
│   │   └── YYYY-MM-DD-topic/
│   │       ├── brainstorm.md # Captured intent
│   │       └── plan.md       # Execution strategy
│   └── plans/
│       └── descriptive-name.md  # Archived plans (post-implementation reference)
└── ...
```

### The `.specs` marker file

A one-line file at the project root that opts into spec-driven development:

```
dir: specs
```

The `dir` field specifies where specs live (defaults to `specs/`). Detection is trivial: `test -f .specs && cat .specs`.

Projects without a `.specs` file do not use this pipeline. When working in a project that lacks one, recommend adding it.

### Spec format

Specs describe interface behavior, not implementation:

- **Purpose** – What this component exists to do
- **Interface** – Inputs, outputs, dependencies
- **Behavior** – What happens from the user's perspective
- **Test cases** – Concrete scenarios that validate the spec

Consider adopting an established spec format like [OpenSpec](https://github.com/Fission-AI/OpenSpec/) for consistency across teams.

### Brainstorm docs

Written during the brainstorm phase, committed immediately. Path: `specs/docs/YYYY-MM-DD-topic/brainstorm.md`.

Key properties:
- Records the user's intent, not Claude's interpretation
- Surfaces and resolves assumptions before any code is discussed
- Explores multiple approaches, recommends one
- Becomes the input for plan creation

### Plans

Written after the brainstorm doc is committed. Path: `specs/docs/YYYY-MM-DD-topic/plan.md`.

**Important:** Claude Code's native `/plan` mode stores plans in `~/.claude/`, outside the project and invisible to git. Configure your CLAUDE.md to instruct Claude to write plans into the project directory (e.g., `specs/docs/`) and commit them. The `/brainstorm` skill does this automatically, but if using built-in planning, add a rule like:

```markdown
## Plan storage
Plans must be written to `specs/docs/YYYY-MM-DD-topic/plan.md` and committed to git.
Never store plans in ~/.claude/ – they must live in the project repository.
```

Key properties:
- References the brainstorm doc via a `Design doc:` header field
- Step 1 is always: update specs to reflect new intent
- Subsequent steps are vertical slices (complete end-to-end paths, not horizontal layers)
- Each step specifies: files touched, dependencies, done criteria
- If the plan needs to deviate from the brainstorm, update the brainstorm doc first

After implementation, plans are archived to `specs/plans/` with a descriptive filename for future reference.

### Bootstrap workflow

When a user wants to adopt specs on an existing codebase:

1. Identify significant components (routes, models, services, CLI commands)
2. For each component, use `/spec-recommender` to read the code and propose a spec
3. Present each proposed spec to the user for confirmation or correction
4. Use `/spec-writer` to produce the final spec text
5. Commit confirmed specs as the baseline
6. From this point forward, follow the brainstorm → plan → spec → code pipeline

Do not attempt to spec the entire codebase at once – start with areas under active development.

### Spec maintenance rules

- Update specs before or on the same turn as any behavioral change – never batch for later
- If a brainstorm or plan execution produces code that wasn't explicitly in the spec but is easily inferred, fill in the gap and confirm with the user
- After every commit, report spec status:
  - `Specs: Updated (specs/foo.md)` – spec changes included
  - `Specs: No behavioral changes` – config/docs/cosmetic only
  - `Specs: Skipped (no .specs file)` – project doesn't use specs
