# Workflow guide

This is how the skills in this repo are meant to compose into a single development cycle. It assumes you have the toolkit installed – see the [README](../README.md) for setup. It does not assume CI, a production branch, or any particular team structure – those are conventions, addressed in their own sections at the end.

## The why

Without discipline, the easy answer for AI coding is: describe a thing, let Claude implement, fix what's broken, ship. That works for one feature. It does not work for the tenth. Three things go wrong:

1. **The system drifts.** What you built last week disagrees with what you build today. Nothing tells you when.
2. **Plans get fuzzier as features get bigger.** "Add a button" is one prompt. "Build a campaign tool" is fifty. Without a written-down agreement on what you're building, Claude makes assumptions you only discover after it's coded.
3. **You can't review what you didn't write down.** Code review without a behavioral contract degrades to "looks fine I guess."

The workflow exists to put a written behavioral contract – a spec – at the start of every change, keep it accurate as code lands, and use it as the reference for every review.

### The spec is the contract

A spec is plain-English language describing what the system should do – inputs, outputs, edge cases, error handling. Not how it's built. **If the spec and the code disagree, the code has a bug.**

The spec serves three jobs:

- **Before code:** it's the agreement between you and Claude on what's being built.
- **During code:** it's the constraint that prevents drift.
- **After code:** it's the reference for review.

### OpenSpec

The toolkit uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) as the spec system. OpenSpec is a convention plus a CLI:

- Base specs at `openspec/specs/<capability>/spec.md` are the source of truth.
- In-flight work lives in `openspec/changes/<name>/` as a folder containing proposal, design, tasks, and delta specs.
- The lifecycle is `change folder → deltas → tests → implement → archive`. Archive merges the deltas into the base specs and cleans up.

The CLI validates structure, scaffolds new changes, and refuses to archive a change that doesn't pass its checks. We didn't invent OpenSpec. The toolkit's skills (`/brainstorm`, `/execute-plan`, `/ralph-review`, `/spec-audit`, `/save-w-specs`) all adhere to it.

Projects opt in by creating an `openspec/` directory. Skills check for it; without it, they still work but skip spec-related behavior.

## The cycle

The skills compose into a single rhythm. Most of them auto-invoke – you don't type them. You describe what you want, and the workflow takes over.

```
idea → brainstorm → execute-plan → ralph-review → spec-audit → bugbash → ship
                                       (auto)         (auto)
```

What each one does:

### Greenfield only: /kickoff and /interview

You only need these when starting from scratch – an empty folder, no project yet. Skip both if you're iterating on an existing project.

- **`/kickoff`** asks you a few questions about what you're building, picks a tech stack tier from the spectrum, and hands off to brainstorm. Optimized for the moment when you don't yet have a project to attach a spec to.
- **`/interview`** is the engine kickoff uses to drag context out of you. Unlike everything else in this workflow, interview logs the full transcript to a file – you keep the verbatim discussion for future reference, plus a synthesized summary. Use it directly when you want a discovery conversation without committing to a project yet.

For everything else, skip straight to brainstorm.

### /brainstorm: getting the idea to a written-down plan

When you describe something creative – adding a feature, changing behavior, building a new piece – `/brainstorm` triggers automatically. You don't type it. Its frontmatter declares "use before any creative work," and Claude picks it up.

Brainstorm has one job: **turn a vague idea into a complete, written-down spec and plan.** It walks you through:

- Surfacing constraints, edge cases, and decisions you haven't made yet
- Writing the OpenSpec change folder (proposal, design, delta specs, tasks)
- Reviewing the result with you, often via inline annotation
- Asking permission to hand off to `/execute-plan`

This is where most of the time should go. Skim the spec and the plan; engage deeply with the brainstorm itself. That's where misinterpretations get caught before any code is written.

### The handoff: /clear before /execute-plan

Brainstorm ends by copying an `/execute-plan <change-name>` command to your clipboard. The recommended next step is `/clear` to wipe the conversation context, then paste the command in a fresh session.

Why clear? Because brainstorm conversations often explore options that don't make the final cut. If you went deep on "blue button" before deciding on "red button," and then ask execute-plan to build it, it has both the plan and the rich blue-button discussion in context – and might drift. Clearing the context window leaves only the plan you agreed on.

### /execute-plan: the implementation loop

`/execute-plan` reads the OpenSpec change folder and turns it into working code. It:

1. Parses `tasks.md` into a dependency graph.
2. Dispatches sub-agents in isolated worktrees to implement each stage.
3. Writes the tests from the delta specs first – they should fail.
4. Implements code until tests pass.
5. Runs a two-stage review per stage – spec compliance, then code quality.
6. Merges each stage back, ticks `tasks.md` checkboxes.
7. Archives the change via `openspec archive <name>`.

Execute-plan is autonomous once it starts. It doesn't ask you questions mid-flow. It runs until done.

When it finishes, it asks whether to run the quality gates: `/ralph-review`, `/spec-audit`, both, or skip. The recommended answer is "both."

### /ralph-review: the gap finder

Ralph review compares your implementation against the merged spec deltas. It uses three sub-agents that each do a fresh-eyes review independently, then the main agent reconciles their findings.

What it does autonomously: when it finds a problem where the spec is clear about the intended behavior and the code is wrong, it fixes it. Then it re-reviews. Loops until clean.

What it brings back to you: a short list of questions where the spec wasn't clear enough – "the spec says X but the code does Y; which one is right?" These usually mean the plan needed more detail. You answer the questions; it applies the fixes.

There is, in practice, no review where ralph finds nothing. If you're not running it, you're shipping drift.

### /spec-audit: the alignment check

Spec audit asks a different question than ralph: *does the code agree with the spec*, where ralph asks *does the code do what the spec described*.

Two common findings:

- **Implementation drift:** the spec said do A and C; the code does A, B, C because B was needed to make A and C work. The audit asks: is B's behavior worth specifying, or was it an implementation detail? Usually the spec gets updated.
- **Conflicting requirements:** the spec said A, B, C; implementation found B and C can't coexist. The audit surfaces the conflict and asks you to resolve.

Spec audit almost always finds something. It's looking at a different axis than ralph.

### /fixit: one-shot quick fixes

When a change is too small to brainstorm – "make the button red instead of blue" – `/fixit` is the shortcut. It:

1. Creates a worktree.
2. Writes the spec change.
3. Updates the test.
4. Changes the code.
5. Reviews its own work.
6. Merges back to main.
7. Reports a confidence score for the change it made.

If confidence is high, fixit is silent – the change is done and merged. If confidence is intermediate, the main thread surfaces the change for you to approve. If confidence is low – it can't tell which button you meant – it doesn't ship anything and asks for clarification.

Fixit is for changes where there is no design decision to make. Use brainstorm for anything with a "we could go either way" element.

### /bugbash: QA mode

Bugbash turns Claude into a continuous fixit queue. You type `/bugbash` and start clicking around the running app. Every issue you mention – "this button should be on the right," "this text is wrong" – Claude takes as a bugbash ticket, dispatches a fixit job in a worktree, and moves on.

The mode tracks tickets in a `.bugbash/` folder structured like a kanban board – to-do → investigating → in-progress → merged. At the end:

- `/bugbash status` – count of resolved vs unresolved tickets.
- `/bugbash report` – text summary of the run.
- `/bugbash review` – opens Plannotator with the list of fixes for regression testing. Annotate each one as "good" or "not yet." Not-yet items respawn as fixit jobs.

Bugbash pairs naturally with: ask Claude to generate a test plan for all unreleased changes, then walk that plan in the running app with bugbash open. Anything broken becomes a ticket. Anything that works gets a green annotation.

## The full rhythm

Putting it together:

1. You describe an idea, or run `/kickoff` if greenfield.
2. Brainstorm walks you to a written-down change folder. You review.
3. `/clear`, paste the execute-plan command in a fresh session.
4. Execute-plan implements. When done, accept the quality gates.
5. Ralph review fixes what it can, asks about what it can't. You resolve its questions.
6. Spec audit checks alignment. You confirm or correct.
7. Spin up locally. Run bugbash. Walk the change in the app. Anything broken becomes a fixit ticket.
8. When bugbash is clean, ship.

This isn't ceremony – every step earns its keep by catching something the previous step missed. Practical heuristic: run the quality gates 90% of the time. The 10% you can skip are tiny changes – a copy edit, a config tweak – where the gates would be overkill.

## Optional layers

The rhythm above works on a single repo with you as the only contributor. Two extra layers come into play when there's more structure.

### If you have CI

When you push a branch and CI runs, you'll occasionally get failures. Treat them like another quality gate – the `/pr` skill opens the PR and watches CI in a loop, fixing failures and re-pushing until green. You don't have to babysit it.

```
/pr
```

Then walk away. CI fails → it reads the failure, makes a fix, pushes, waits. It also watches for review-tool feedback such as CodeRabbit and addresses comments as they arrive. When it exits, the PR is mergeable.

### If you have a prod branch

The convention worth adopting if you don't already: `main` holds shipped-but-not-released code, `production` holds what's actually running. The two diverge by N commits at any time.

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
| `/interview` | Discovery conversations where you want a transcript |
| `/brainstorm` | Auto-triggers on any creative work; turns ideas into change folders |
| `/execute-plan` | Approved brainstorm → working code, autonomously |
| `/ralph-review` | Auto-prompted post-implementation; finds gaps against the spec |
| `/spec-audit` | Auto-prompted post-implementation; finds drift between code and spec |
| `/fixit` | Tiny one-shot changes with no design decision to make |
| `/bugbash` | QA mode while clicking through a running app |
| `/pr` | Opens PR, watches CI, fixes failures until mergeable |

## A note on Plannotator

Several steps above – brainstorm review, spec review, bugbash review – work best with [Plannotator](https://github.com/anutron/plannotator), a browser-based inline annotation tool. When a skill opens Plannotator, you annotate the document with comments or approvals; Claude reads them back and acts on them.

If you don't have Plannotator installed, the workflows fall back to terminal-based review – Claude shows you the doc, you respond in chat. The annotation experience is more precise, but the workflow doesn't require it.
