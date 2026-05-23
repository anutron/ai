# Spec-driven development

> **As of v1.22.0 the spec-driven workflow runs on [OpenSpec](https://github.com/Fission-AI/OpenSpec).** Specs live under `openspec/specs/<capability>/spec.md`, in-flight work lives in `openspec/changes/<name>/`, and the lifecycle is `change folder → deltas → tests → implement → archive`. The rewritten skills (`/brainstorm`, `/execute-plan`, `/save-w-specs`, `/ralph-review`, `/spec-audit`, `/spec-writer`, `/spec-recommender`, `/spec-todo`) operate on this layout.
>
> **Want the previous, `.specs`-based workflow?** Check out the [`legacy-spec-system`](https://github.com/anutron/claude-skills/tree/legacy-spec-system) tag – it points at the v1.21.0 commit, the last release before the OpenSpec conversion. Existing legacy `.specs` projects keep working against the rewritten skills (they exit cleanly when no `openspec/` directory is present); to migrate, use [`/migrate-to-openspec`](../skills/migrate-to-openspec/SKILL.md).

The core idea: **specs describe what you're building before you build it.** If the spec and the code disagree, the code has a bug.

## Why specs?

Without specs, Claude builds what it thinks you mean. With specs, Claude builds what you agreed on. The spec is a behavioral contract – inputs, outputs, edge cases, error handling – written in plain language. It survives context window resets, session handoffs, and the "what did we decide?" problem.

Specs also make Claude dramatically better at reviews. When `/ralph-review` can compare code against a spec, it catches behavioral drift that no amount of code-only review would find.

## The workflow

```
idea → spec → plan → test → implement → review
```

Each step has a skill. The system enforces the order.

**1. Idea → spec**

You describe what you want. Claude writes a spec using `/spec-writer`, which owns the format and ensures consistency. The spec captures behavior, not implementation – what the system does, not how.

For new features, use `/brainstorm` to explore the design space before committing to a spec. For smaller changes, just describe what you want and the spec gets updated inline.

**2. Spec → plan**

The spec says *what*. The plan says *how* and *in what order*. Plans break specs into ordered implementation steps, each small enough to verify independently. A good plan makes implementation mechanical.

In OpenSpec the plan IS the change folder's `tasks.md`, archived by `openspec archive <name>` at the end of the change.

**3. Plan → test**

Tests encode the spec's behavioral expectations in executable form. Write them before implementation. They should all fail at this point.

**4. Test → implement**

Write code to pass the tests. The spec constrains what to build. The tests validate whether it's correct. `/execute-plan` dispatches each plan stage to an agent.

**5. Implement → review**

`/ralph-review` runs an autonomous review loop: compares the code against the spec, auto-fixes what it's confident about, parks questions for you. When it finds behavior the spec doesn't describe, it flags spec drift. When it finds spec requirements without tests, it writes the tests.

**6. Commit**

`/save-w-specs` commits code and specs together, verifying that behavioral changes include spec updates. It also runs lightweight safety checks (secrets detection, gitignore violations) before committing.

## Setting up spec-driven development

**1. Opt in.** Initialize OpenSpec at your project root:

```
openspec init
```

This creates the `openspec/` directory. Skills check for it on startup.

**2. Install the skills.** Copy these to `~/.claude/skills/<name>/SKILL.md` or `.claude/skills/<name>/SKILL.md` in your project. Or, if you clone this repo, use the [/promote](../skills/promote/SKILL.md) skill to symlink skills from a git-tracked working directory to `~/.claude/skills/` – that way updates are a `git pull` away.

| Skill | What it does |
|-------|-------------|
| [migrate-to-openspec](../skills/migrate-to-openspec/SKILL.md) | One-time migration from a legacy `.specs` project to OpenSpec – preserves Given/When/Then fidelity, archives originals at `.workflow/legacy-specs/` |
| [close-spec-drift](../skills/close-spec-drift/SKILL.md) | When an OpenSpec base spec is correct but code or peripheral spec text drifted from it – surfaces full extent of drift, scaffolds a thin change folder (no deltas), hands off to /execute-plan |
| [spec-writer](../skills/spec-writer/SKILL.md) | Thin orchestrator around `openspec instructions <artifact>` – returns enriched proposal/design/tasks/specs templates with project context |
| [spec-recommender](../skills/spec-recommender/SKILL.md) | Detect code without spec coverage, infer intent, recommend OpenSpec capabilities + requirements |
| [spec-audit](../skills/spec-audit/SKILL.md) | Audit OpenSpec coverage – inventory capabilities, map to code, dispatch agents to find behavioral gaps |
| [spec-todo](../skills/spec-todo/SKILL.md) | List and execute deferred work items from `.workflow/todo/` |
| [ralph-review](../skills/ralph-review/SKILL.md) | Autonomous review loop – compares implementation against the active OpenSpec change's deltas, auto-fixes, parks questions |
| [save-w-specs](../skills/save-w-specs/SKILL.md) | Spec-aware commits – verifies behavioral code changes carry deltas in an active OpenSpec change |
| [plannotator-specs](../skills/plannotator-specs/SKILL.md) | Interactive spec review with inline annotations (requires [Plannotator](https://github.com/anutron/plannotator)) |

**3. Install the rules.** Copy the relevant rule snippets to your project's CLAUDE.md (or use the [snippet compilation system](../claude-rules/README.md)):

| Rule | What it does |
|------|-------------|
| [080-spec-driven-dev](../claude-rules/snippets/global/080-spec-driven-dev.md) | Enforces OpenSpec spec-first order: change folder → deltas → tests → implement → archive |
| [085-openspec-migration-prompt](../claude-rules/snippets/global/085-openspec-migration-prompt.md) | Suggests `/migrate-to-openspec` when encountering legacy `.specs` projects |
| [040-plan-execution-handoff](../claude-rules/snippets/global/040-plan-execution-handoff.md) | What to do after plan approval – archive, execute, or hand off |
| [070-testing](../claude-rules/snippets/global/070-testing.md) | Test-driven development defaults |

**4. (Optional) Install the pre-commit hook.** Blocks commits when behavioral code changes don't include a spec update:

```bash
cp scripts/spec-check-hook.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Graceful degradation

Every skill checks for `openspec/` at startup. Without it, they still work – they just skip spec-related behavior:

- `/ralph-review` without specs → reviews against plans or conservative mode (bugs/security only)
- `/save-w-specs` without specs → normal commit, no spec verification
- `/execute-plan` without specs → executes the plan, no spec cross-referencing

You can adopt individual skills without buying into the full spec system.

## Retrofitting specs onto existing code

If you have a codebase without specs, use `/spec-recommender` to scan for unspecified behavior and infer intent. It presents options – you approve, then `/spec-writer` produces the spec text. It's working backwards (you lose the original intent), but it gives you a starting point.

This works well for small-to-medium codebases. For large-scale applications, you'll likely need an additional harness to run `/spec-recommender` across modules systematically – the skill is designed for focused, per-file analysis, not whole-repo sweeps.
