# Claude Code Skills

Two things in one repo:

1. **Spec-driven development** — A complete workflow where specs are the source of truth, code implements specs, and a suite of skills keeps everything in sync. From idea to spec to plan to implementation to review.
2. **General-purpose skills** — Tools that make Claude Code smarter regardless of your workflow: session retrospectives, structured interviews, multi-agent debugging, PR automation, and more.

Steal what's useful. Most people point Claude at this repo and cherry-pick what fits their workflow.

## Spec-Driven Development

The core idea: **specs describe what you're building before you build it.** If the spec and the code disagree, the code has a bug.

### Why specs?

Without specs, Claude builds what it thinks you mean. With specs, Claude builds what you agreed on. The spec is a behavioral contract — inputs, outputs, edge cases, error handling — written in plain language. It survives context window resets, session handoffs, and the "what did we decide?" problem.

Specs also make Claude dramatically better at reviews. When `/ralph-review` can compare code against a spec, it catches behavioral drift that no amount of code-only review would find.

### The workflow

```
idea → spec → plan → test → implement → review
```

Each step has a skill. The system enforces the order.

**1. Idea → Spec**

You describe what you want. Claude writes a spec using `/spec-writer`, which owns the format and ensures consistency. The spec captures behavior, not implementation — what the system does, not how.

For new features, use `/brainstorm` to explore the design space before committing to a spec. For smaller changes, just describe what you want and the spec gets updated inline.

**2. Spec → Plan**

The spec says *what*. The plan says *how* and *in what order*. Plans break specs into ordered implementation steps, each small enough to verify independently. A good plan makes implementation mechanical.

Plans are archived in `specs/plans/` so architectural decisions are preserved for future sessions.

**3. Plan → Test**

Tests encode the spec's behavioral expectations in executable form. Write them before implementation. They should all fail at this point.

**4. Test → Implement**

Write code to pass the tests. The spec constrains what to build. The tests validate whether it's correct. `/execute-plan` dispatches each plan stage to an agent.

**5. Implement → Review**

`/ralph-review` runs an autonomous review loop: compares the code against the spec, auto-fixes what it's confident about, parks questions for you. When it finds behavior the spec doesn't describe, it flags spec drift. When it finds spec requirements without tests, it writes the tests.

**6. Commit**

`/save-w-specs` commits code and specs together, verifying that behavioral changes include spec updates. It also runs lightweight safety checks (secrets detection, gitignore violations) before committing.

### Setting up spec-driven development

**1. Opt in.** Create a `.specs` file at your project root:

```
dir: specs
```

That's it. One line. The `dir` field says where specs live (defaults to `specs/`).

**2. Install the skills.** Copy these to `~/.claude/skills/<name>/SKILL.md` or `.claude/skills/<name>/SKILL.md` in your project. Or, if you clone this repo, use the [/promote](skills/promote/SKILL.md) skill to symlink skills from a git-tracked working directory to `~/.claude/skills/` — that way updates are a `git pull` away.

| Skill | What it does |
|-------|-------------|
| [spec-writer](skills/spec-writer/SKILL.md) | Write properly formatted spec text — single source of truth for the SPEC format |
| [spec-recommender](skills/spec-recommender/SKILL.md) | Detect code without spec coverage, infer intent, present options |
| [spec-audit](skills/spec-audit/SKILL.md) | Audit codebase spec coverage — inventory files and specs, map them, find behavioral gaps |
| [spec-todo](skills/spec-todo/SKILL.md) | List and execute deferred work items from `specs/todo/` |
| [ralph-review](skills/ralph-review/SKILL.md) | Autonomous review loop — compares code against specs, auto-fixes, flags drift |
| [save-w-specs](skills/save-w-specs/SKILL.md) | Spec-aware commits — verifies specs updated alongside behavioral changes |
| [plannotator-specs](skills/plannotator-specs/SKILL.md) | Interactive spec review with inline annotations (requires [Plannotator](https://github.com/anutron/plannotator)) |

**3. Install the rules.** Copy the relevant rule snippets to your project's CLAUDE.md (or use the [snippet compilation system](claude-rules/README.md)):

| Rule | What it does |
|------|-------------|
| [080-spec-driven-dev](claude-rules/snippets/global/080-spec-driven-dev.md) | Enforces spec-first order: spec → test → implement |
| [090-plan-archiving](claude-rules/snippets/global/090-plan-archiving.md) | Archives approved plans to `specs/plans/` |
| [040-plan-execution-handoff](claude-rules/snippets/global/040-plan-execution-handoff.md) | What to do after plan approval — archive, execute, or hand off |
| [070-testing](claude-rules/snippets/global/070-testing.md) | Test-driven development defaults |

**4. (Optional) Install the pre-commit hook.** Blocks commits when behavioral code changes don't include a spec update:

```bash
cp scripts/spec-check-hook.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Graceful degradation

Every skill checks for `.specs` at startup. Without it, they still work — they just skip spec-related behavior:

- `/ralph-review` without specs → reviews against plans or conservative mode (bugs/security only)
- `/save-w-specs` without specs → normal commit, no spec verification
- `/execute-plan` without specs → executes the plan, no spec cross-referencing

You can adopt individual skills without buying into the full spec system.

### Retrofitting specs onto existing code

If you have a codebase without specs, use `/spec-recommender` to scan for unspecified behavior and infer intent. It presents options — you approve, then `/spec-writer` produces the spec text. It's working backwards (you lose the original intent), but it gives you a starting point.

This works well for small-to-medium codebases. For large-scale applications, you'll likely need an additional harness to run `/spec-recommender` across modules systematically — the skill is designed for focused, per-file analysis, not whole-repo sweeps.

---

## All Skills

### Development

| Skill | Description |
|-------|-------------|
| [brainstorm](skills/brainstorm/SKILL.md) | You MUST use this before any creative work -- creating features, building components, adding functionality, or modifying behavior |
| [execute-plan](skills/execute-plan/SKILL.md) | Use when you have an approved plan ready to implement -- agent-driven development, worktree isolation, TDD, two-stage review |
| [fixit](skills/fixit/SKILL.md) | Use when the user reports a bug that can be fixed without blocking their current work -- backgrounds an agent in a worktree |
| [test](skills/test/SKILL.md) | Use after writing or modifying code to run targeted tests and identify coverage gaps, before claiming code works |
| [debug](skills/debug/SKILL.md) | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes -- multi-agent competing hypotheses |
| [bugbash](skills/bugbash/SKILL.md) | Use when the user wants to do a QA session or report multiple bugs -- agents fix them in parallel |
| [guard](skills/guard/SKILL.md) | Use before any git commit to check for secrets, security antipatterns, and test breakage |
| [unstaged](skills/unstaged/SKILL.md) | Use when the user wants to see what's changed or plan commits -- groups by logical commit themes |
| [close-worktree](skills/close-worktree/SKILL.md) | Use when done working in a git worktree and ready to merge it back to the main branch |
| [review](skills/review/SKILL.md) | Use when the user asks to review code, review current changes, or review a PR number |
| [rereview](skills/rereview/SKILL.md) | Use when a previous review missed something or the user wants a thorough second pass -- zero regressions |

### Discipline & Orchestration

These skills describe how agents should think and work. They're loaded by reference when other skills need them -- not typically invoked directly.

| Skill | Description |
|-------|-------------|
| [agent-driven-development](skills/agent-driven-development/SKILL.md) | Use when executing implementation plans with independent tasks -- worktree isolation, TDD discipline, two-stage review |
| [test-driven-development](skills/test-driven-development/SKILL.md) | Use when implementing any feature or bugfix, before writing implementation code |
| [verification-before-completion](skills/verification-before-completion/SKILL.md) | Use when about to claim work is complete, before committing or creating PRs -- evidence before assertions always |

### Git & PR

| Skill | Description |
|-------|-------------|
| [pr](skills/pr/SKILL.md) | Use when code is ready to ship -- opens a PR, waits for CI, fixes failures, addresses review comments, loops until green |
| [pr-respond](skills/pr-respond/SKILL.md) | Use when a PR has received review comments -- triages each comment (adopt/reject with reasoning) |
| [pr-dashboard](skills/pr-dashboard/SKILL.md) | Use when the user asks about PR status, open PRs, or review requests |
| [merge](skills/merge/SKILL.md) | Use when the user wants to merge the current branch to master -- merges via GitHub PR |
| [changelog](skills/changelog/SKILL.md) | Use when the user asks for a changelog, release notes, or summary of recent changes |

### General

| Skill | Description |
|-------|-------------|
| [interview](skills/interview/SKILL.md) | Use when the user wants to systematically review, audit, or evaluate something -- builds an inventory, walks through items one-by-one |
| [devils-advocate](skills/devils-advocate/SKILL.md) | Use when the user wants to stress-test an idea, plan, or approach -- challenges assumptions and finds weaknesses |
| [improve](skills/improve/SKILL.md) | Use at the end of a session to run a retrospective -- upgrades skills, fixes codebase gaps, captures knowledge |
| [handoff](skills/handoff/SKILL.md) | Use when switching repos, handing off work, or sharing context between agents |
| [write-skill](skills/write-skill/SKILL.md) | Use when creating a new skill or improving an existing one -- applies best practices for structure, dynamic context, and safety |
| [skill-audit](skills/skill-audit/SKILL.md) | Use after collecting usage data for a few weeks to identify dead weight -- recommends which skills to keep, prune, or consolidate |
| [promote](skills/promote/SKILL.md) | Use when checking which project skills should be available globally |
| [disk-cleanup](skills/disk-cleanup/SKILL.md) | Use when the user asks about disk space or storage -- scans for large consumers, never deletes without approval |
| [mcp-prune](skills/mcp-prune/SKILL.md) | Use when starting work in a project with many global MCP servers that waste context tokens |
| [upload-notion-image](skills/upload-notion-image/SKILL.md) | Use when embedding images in Notion pages -- uploads natively via the Notion API file upload flow |
| [set-topic](skills/set-topic/SKILL.md) | Set the session topic displayed in the [status line](bin/statusline.sh) |
| [list-skills](skills/list-skills/SKILL.md) | Use when you need a reminder of your toolkit -- quick reference of all available skills |

---

## Claude Rules

Version-controlled CLAUDE.md snippets with a compilation system. Rules are persistent behavioral instructions — they tell Claude how you want it to work in every conversation.

See [claude-rules/README.md](claude-rules/README.md) for setup.

| Snippet | Description |
|---------|-------------|
| `005-claudemd-management` | How CLAUDE.md files are compiled from snippets |
| `010-plan-formatting` | Markdown formatting requirements for structured output |
| `020-interaction-prefs` | Question-by-question and step-by-step interaction patterns |
| `040-plan-execution-handoff` | What to do after plan approval |
| `040-tech-stack` | Standard tech stack for new applications |
| `050-git-workflow` | Commit conventions and pre-commit hooks |
| `052-worktree-location` | Place git worktrees in `.claude/worktree/` within spec-driven projects |
| `055-session-topics` | Set status line topics for session identification |
| `060-plannotator-spec-review` | Interactive spec review via Plannotator |
| `070-testing` | Test-driven development defaults |
| `080-spec-driven-dev` | Spec-first development process |
| `090-plan-archiving` | Archive approved plans to `specs/plans/` |

---

## Extras

| File | Description |
|------|-------------|
| [statusline.sh](bin/statusline.sh) | Custom Claude Code status line — git status, session topic, terminal title |
| [log-skill-use.sh](hooks/log-skill-use.sh) | Hook: logs Skill tool invocations to `~/.claude/skill-usage.tsv` |
| [log-slash-command.sh](hooks/log-slash-command.sh) | Hook: logs user-typed `/commands` to the same TSV |

See [Workflow Guide](docs/workflow-guide.md) for how all the pieces fit together.

## Plugins I Use

| Plugin | Source | What it does |
|--------|--------|-------------|
| **ralph-loop** | `claude-plugins-official` | Iterative development loop — run tests and fix until green |
| **pr-review-toolkit** | `claude-plugins-official` | Comprehensive PR review using specialized agents |
| **commit-commands** | `claude-plugins-official` | Git workflow shortcuts — commit, push, PR creation |
| **github** | `claude-plugins-official` | GitHub MCP integration — issues, PRs, code search |
