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

For new features, use the [**superpowers**](https://github.com/obra/superpowers) plugin's brainstorming flow to explore the design space before committing to a spec (`/plugin install superpowers@claude-plugins-official`). For smaller changes, just describe what you want and the spec gets updated inline.

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
| [brainstorm](skills/brainstorm/SKILL.md) | Explore intent, design the solution, write a strategic plan, and hand off to execution |
| [dev](skills/dev/SKILL.md) | Multi-agent iterative development with parallel testing and code review |
| [execute-plan](skills/execute-plan/SKILL.md) | Execute a plan with a team of agents, delegating to spare tokens in the main thread |
| [fixit](skills/fixit/SKILL.md) | Fire-and-forget bug fix — backgrounds an agent in a worktree to fix and merge back |
| [test](skills/test/SKILL.md) | Intelligent test runner that targets changed code and identifies coverage gaps |
| [debug](skills/debug/SKILL.md) | Multi-agent competing hypotheses debugging |
| [bugbash](skills/bugbash/SKILL.md) | Interactive QA — report bugs conversationally, agents fix them in parallel using worktrees |
| [guard](skills/guard/SKILL.md) | Pre-commit safety check for secrets, security antipatterns, and test breakage |
| [unstaged](skills/unstaged/SKILL.md) | Show uncommitted changes grouped by logical commit themes |
| [close-worktree](skills/close-worktree/SKILL.md) | Close a git worktree and merge it back to the main branch |
| [review](skills/review/SKILL.md) | Quick code review shorthand — reviews current changes or a PR number |
| [rereview](skills/rereview/SKILL.md) | Re-review with fresh eyes — zero regressions, slow and thorough |

### Git & PR

| Skill | Description |
|-------|-------------|
| [pr](skills/pr/SKILL.md) | Open a PR, wait for CI, fix failures, address review comments, loop until green |
| [pr-respond](skills/pr-respond/SKILL.md) | Read PR review feedback, triage each comment (adopt/reject with reasoning) |
| [pr-dashboard](skills/pr-dashboard/SKILL.md) | Show open PRs, review requests, and recently closed PRs |
| [merge](skills/merge/SKILL.md) | Merge current branch to master via GitHub PR merge |
| [changelog](skills/changelog/SKILL.md) | Generate an intelligent changelog from recent commits |

### General

| Skill | Description |
|-------|-------------|
| [interview](skills/interview/SKILL.md) | Claude-led Q&A that systematically extracts context from you — builds an inventory of a system, walks through each item, captures decisions as artifacts |
| [devils-advocate](skills/devils-advocate/SKILL.md) | Challenge proposals with structured counter-arguments before committing to an approach |
| [improve](skills/improve/SKILL.md) | End-of-session retrospective — upgrade skills, fix codebase gaps, capture knowledge |
| [handoff](skills/handoff/SKILL.md) | Generate a handoff prompt to pass context to another agent thread |
| [write-skill](skills/write-skill/SKILL.md) | Create or improve a Claude Code skill with best practices |
| [skill-audit](skills/skill-audit/SKILL.md) | Analyze skill usage logs and recommend which to keep, prune, or consolidate |
| [promote](skills/promote/SKILL.md) | Audit project skills and recommend which to promote to global |
| [disk-cleanup](skills/disk-cleanup/SKILL.md) | Scan local disk for large storage consumers and identify cleanup opportunities |
| [mcp-prune](skills/mcp-prune/SKILL.md) | Analyze active MCP servers and disable irrelevant ones for the current project |
| [upload-notion-image](skills/upload-notion-image/SKILL.md) | Upload local images to Notion pages natively via the Notion API file upload flow |
| [set-topic](skills/set-topic/SKILL.md) | Set the session topic displayed in the [status line](bin/statusline.sh) |
| [list-skills](skills/list-skills/SKILL.md) | Quick reference of all available skills |

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
| **superpowers** | `claude-plugins-official` | Brainstorming, TDD, plan writing/execution, systematic debugging, code review |
| **ralph-loop** | `claude-plugins-official` | Iterative development loop — run tests and fix until green |
| **pr-review-toolkit** | `claude-plugins-official` | Comprehensive PR review using specialized agents |
| **commit-commands** | `claude-plugins-official` | Git workflow shortcuts — commit, push, PR creation |
| **github** | `claude-plugins-official` | GitHub MCP integration — issues, PRs, code search |
