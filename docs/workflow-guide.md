# Workflow guide

This is how the skills in this repo are meant to compose into a single development cycle. It assumes you have the toolkit installed – see the [README](../README.md) for setup.

## The why

Without discipline, the easy answer for AI coding is: describe a thing, let Claude implement, fix what's broken, ship. That works for one feature. It does not work for the tenth. Three things go wrong:

1. **The system drifts.** What you built last week disagrees with what you build today. Nothing tells you when.
2. **Plans get fuzzier as features get bigger.** "Add a button" is one prompt. "Build a campaign tool" is fifty. Without a written-down agreement on what you're building, Claude makes assumptions you only discover after it's coded.
3. **Code review becomes guesswork.** The purpose of a spec is to have a plain-English description of what you expect the code to do. Without one, you must infer intent from the code itself. If the code has a bug, you have nothing telling you what was intended – and "looks fine, I guess" is the best a reviewer can do.

The workflow exists to put a written behavioral contract – a spec – at the start of every change, keep it accurate as code lands, and use it as the reference for every review.

### The spec is the contract

A spec is plain-English language describing what the system should do – inputs, outputs, edge cases, error handling. Not how it's built. **If the spec and the code disagree, the code has a bug.**

The spec serves three jobs:

- **Before code:** it's the agreement between you and Claude on what's being built.
- **During code:** it's the constraint that prevents drift.
- **After code:** it's the reference for review.

### OpenSpec

The toolkit uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) as the spec system. OpenSpec is a convention plus a command line tool (a "CLI"):

- Base specs at `openspec/specs/<capability>/spec.md` are the source of truth.
- In-flight work lives in `openspec/changes/<name>/` as a folder containing proposal, design, tasks, and delta specs.
- The lifecycle is `change folder → deltas → tests → implement → archive`. Archive merges the deltas into the base specs and cleans up.

The CLI validates structure, scaffolds new changes, and refuses to archive a change that doesn't pass its checks. We didn't invent OpenSpec. The toolkit's skills (`/brainstorm`, `/execute-plan`, `/ralph-review`, `/spec-audit`, `/save-w-specs`) all adhere to it.

Projects opt in by creating an `openspec/` directory. Skills check for it; without it, they still work but skip spec-related behavior.

## The cycle

The skills compose into a single rhythm. Most of them auto-invoke – you don't have to type them (though you can). You describe what you want, and the workflow takes over.

```
idea → brainstorm → execute-plan → ralph-review → spec-audit → bugbash → ship
                                       (auto)         (auto)    (optional)
```

What each step does, what it produces, and how it hands off to the next:

### Step 0 (optional): /kickoff for greenfield projects

Use only when starting from scratch – an empty folder, no project yet. Skip when iterating on an existing project.

Kickoff runs a 5-8 question discovery conversation (one at a time), picks a tech stack tier from the spectrum (defaulting to the lightest that fits), and writes a discovery doc at `specs/docs/<date>-<topic>/discovery.md`. It then invokes `/brainstorm` directly, passing the discovery doc as the input artifact.

A separate skill, `/interview`, handles **standalone systematic reviews** of an existing system, feature, or domain. It builds an inventory, walks through items one at a time, and captures decisions as numbered artifacts. Unlike the rest of this workflow, interview logs the entire discussion to a file (`<topic>_review/discussion.log`) so the verbatim transcript survives across sessions. Use it when you want to audit, review, or evaluate something collaboratively – it's not part of the greenfield path.

### Step 1: /brainstorm – idea to written-down plan

When you describe something creative – adding a feature, changing behavior, building a new piece – `/brainstorm` triggers automatically (its frontmatter declares "use before any creative work"). You don't have to type it (though you can).

Brainstorm's one job: **turn a vague idea into a complete, written-down change folder.** It walks you through assumption surfacing, scope sizing, clarifying questions, proposing 2-3 approaches with tradeoffs, and presenting the design section by section.

**Input:** your idea, plus any prior discovery doc.

**Output:** a complete `openspec/changes/<name>/` folder:

- `proposal.md` – why and what changes
- `design.md` – architecture, decisions, alternatives, risks
- `specs/<capability>/spec.md` – delta specs (ADDED / MODIFIED / REMOVED requirements with scenarios)
- `tasks.md` – the implementation plan as a checklist (this is what `/execute-plan` consumes)

This is where most of your time should go. Skim the spec and the plan; engage deeply with the brainstorm itself. That's where misinterpretations get caught before any code is written.

**Handoff to execute-plan.** At the end, brainstorm asks via AskUserQuestion:

- **Copy to clipboard** (recommended) – copies `/execute-plan <name>` to your clipboard. You run `/clear` to wipe context, then paste in a fresh session.
- **Execute in this session** – continues without clearing.

Why clear? Because brainstorm conversations often explore options that don't make the final cut. If you went deep on option A before deciding on option B, and then ask execute-plan to build it, the context still contains all of option A's rationale – and execute-plan might drift toward it. Clearing leaves only the agreed plan.

### Step 2: /execute-plan – the implementation loop

`/execute-plan` reads the change folder and turns it into working code.

**Input:** a change name (or it auto-detects from the active changes / current branch).

**What it does:**

1. Parses `tasks.md` into a stage-based dependency graph.
2. Dispatches sub-agents in isolated worktrees to implement each stage.
3. Writes tests from the delta specs first – they should fail (the Prove-It Pattern).
4. Implements code until tests pass.
5. Runs a two-stage review per stage – spec compliance, then code quality.
6. Merges each stage back, ticks `tasks.md` checkboxes.
7. Archives the change via `openspec archive <name>` – deltas merge into base specs.

Execute-plan is autonomous once it starts. It does not ask you questions mid-flow.

**Output:** working code, passing tests, an archived change folder, and a set of commits with stage-prefixed messages.

**Handoff to quality gates.** When it finishes, execute-plan asks via AskUserQuestion: "Run quality checks?"

- **Both** (recommended) – runs `/ralph-review` and `/spec-audit` in parallel.
- **Ralph-review only**
- **Spec-audit only**
- **Done** – skip the gates.

### Step 3: /ralph-review – the gap finder (auto-prompted)

Ralph compares your implementation against the active change's spec deltas. Each iteration spawns one fresh review sub-agent with the full diff, the deltas, and the changed files in their entirety. The agent classifies every finding into AUTO-FIX, QUESTION, SPEC-DRIFT, or SKIP. The main thread triages, applies the AUTO-FIX items, commits, and loops up to three times.

What it does autonomously: when a finding is clearly an AUTO-FIX – the spec is unambiguous about the intended behavior and the code is wrong – ralph fixes it and re-reviews.

What it brings back to you: QUESTION items where the spec wasn't clear enough ("the spec says X but the code does Y; which is right?"), plus SPEC-DRIFT items where new behavior landed without a delta update. You resolve each one; ralph dispatches background fix agents (the same pattern as `/fixit`) to apply the chosen direction.

**Output:** a report at `.claude/reviews/<date>/ralph-review-report.md`, plus commits prefixed `ralph-review loop {N}: ...`.

There is, in practice, no review where ralph finds nothing. If you're not running it, you're shipping drift.

### Step 4: /spec-audit – the coverage check (auto-prompted)

Spec audit asks a different question than ralph: *does the project's code agree with the project's specs across the whole codebase?* It inventories code files and base specs, maps them many-to-many (a single capability often spans multiple files), then dispatches per-module agents that classify every behavioral branch as:

- **Covered** – the spec describes this behavior.
- **Uncovered (behavioral)** – the branch produces a distinct user-visible behavior that no requirement describes. This is a gap.
- **Uncovered (implementation)** – internal control flow (retries, defensive checks). No spec needed.
- **Contradicts** – the code does what the spec says it shouldn't, or vice versa.

It also surfaces *unimplemented spec promises* – requirements written but not built.

**Output:** `.workflow/audits/<date>/` with `index.md` (dashboard), `gaps.md` (sorted findings), per-module reports, and structured findings JSON. After the first audit, incremental mode is the default – only modules with changes since the last audit get re-analyzed.

**Handoff.** After the report, spec audit asks via AskUserQuestion whether to stop, address gaps individually (transitioning to `/spec-recommender`), address them in logical groups, or commit and move on.

Spec audit almost always finds something. It's looking at a different axis than ralph.

### Step 5 (optional): /bugbash – QA mode

Bugbash turns Claude into a continuous fix queue. You type `/bugbash` and start clicking around the running app. Every issue you mention – "this button should be on the right," "this text is wrong" – Claude takes as a bug ticket, dispatches a fix agent in an isolated worktree, and moves on. You keep reporting; fixes happen in parallel.

The board lives in `.bug-bash/` as folders – `todo/` → `investigating/` → `in-progress/` → `merged/` → `verified/`. Status transitions are file moves. Independent bugs (no file overlap) run in parallel; same-file conflicts serialize automatically.

Subcommands:

- `/bugbash status` – dashboard of bug counts by status.
- `/bugbash done` – wraps up the session and cleans up worktrees.
- `/bugbash report` – generates `.bug-bash/report.md` and opens it in Plannotator for acceptance testing. Annotate any fix that didn't actually work; unannotated bugs move to `verified/`, annotated ones become new bug tickets that re-enter the queue.

Bugbash pairs naturally with: ask Claude to generate a test plan for all unreleased changes, then walk that plan in the running app with bugbash open. Anything broken becomes a ticket. Anything that works gets a green annotation.

### Side-quest: /fixit – one-shot quick fixes

When a change is too small to brainstorm – "make the button red instead of blue" – `/fixit` is the shortcut.

**Input:** a natural-language bug description.

The main thread triages with a few path searches (no source-code reads), creates a worktree, and dispatches a background agent. In a spec-aware project, the agent first classifies the issue as a *code drift fix* (the spec is correct; the code diverged) or a *spec gap fix* (the spec doesn't cover the case), then implements per the matching path. Both paths include writing or updating a test.

The agent reports back with one of three statuses: `DONE`, `DONE_WITH_CONCERNS`, or `BLOCKED`. On `DONE`, the main thread runs two stages of review (spec, then code quality) before merging back. On conflict, the worktree is preserved for you to resolve. On failure, fixit reports what it tried.

Use fixit for changes where there is no design decision to make. Use brainstorm for anything with a "we could go either way" element. Fixit also runs under the hood inside `/ralph-review` and `/bugbash` to apply individual sub-fixes.

## The full rhythm

Putting it together:

1. You describe an idea (or run `/kickoff` if greenfield).
2. Brainstorm walks you to a written-down change folder. You review.
3. `/clear`, paste the execute-plan command in a fresh session.
4. Execute-plan implements. When done, accept the quality gates.
5. Ralph review fixes what it can, asks about what it can't. You resolve its questions.
6. Spec audit checks coverage. You confirm or correct.
7. (Optional) Spin up the app locally. Run bugbash. Walk the change in the app. Anything broken becomes a fix ticket.
8. When the quality gates are clean (and bugbash if you ran it), ship.

This isn't ceremony – every step earns its keep by catching something the previous step missed. Practical heuristic: run the quality gates 90% of the time. The 10% you can skip are tiny changes – a copy edit, a config tweak – where the gates would be overkill.

## Optional layers

The rhythm above works on a single repo with you as the only contributor. Two extra layers come into play when there's more structure.

### If you have continuous integration (CI)

When you push a branch and CI runs, you'll occasionally get failures. The `/pr` skill opens a PR (or uses an existing one) and watches CI in a loop, fixing failures and re-pushing until green. It also addresses unresolved review comments – including comments from any review tool you have configured – before reporting back.

```
/pr
```

Then walk away. CI fails → it reads the failure, makes a fix, pushes, polls again with exponential backoff. When `/pr` exits, the PR is mergeable.

### If you have a production branch

The convention worth adopting: `main` holds shipped-but-not-released code, `production` holds what's actually running. The two diverge by N commits at any time.

Why: rollback. When something breaks in production, you want a single commit or tag to revert to. Without a prod branch, you're guessing which of last week's main commits to roll back.

Pair this with version tagging on every push to production:

```
git tag v1.2.0
git push --tags
```

Now "what was running yesterday" has a name.

If you're solo on a repo, you may also want a personal staging branch – `<your-name>-staging` – that you push to main only after local QA. The advice changes once teammates are pushing to main; you don't want to block them on your QA.

## Skill reference

| Skill | When |
|-------|------|
| `/kickoff` | Greenfield, empty project, no idea yet committed to a stack |
| `/interview` | Standalone systematic review of an existing system, feature, or domain |
| `/brainstorm` | Auto-triggers on creative work; turns ideas into OpenSpec change folders |
| `/execute-plan` | Approved change folder → working code, autonomously |
| `/ralph-review` | Auto-prompted post-implementation; finds gaps against the active change's deltas |
| `/spec-audit` | Auto-prompted post-implementation; coverage audit across the whole project |
| `/fixit` | Tiny one-shot changes with no design decision to make |
| `/bugbash` | QA mode while clicking through a running app |
| `/pr` | Opens PR, watches CI, fixes failures until mergeable |

## A note on Plannotator

Several steps above – brainstorm review, spec review, bugbash report – work best with [Plannotator](https://github.com/anutron/plannotator), a browser-based inline annotation tool. When a skill opens Plannotator, you annotate the document with comments or approvals; Claude reads them back and acts on them.

If you don't have Plannotator installed, the workflows fall back to in-chat review – Claude shows you the doc, you respond in the conversation. The annotation experience is more precise, but the workflow doesn't require it.
