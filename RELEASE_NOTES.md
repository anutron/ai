## v1.6.0 — 2026-04-08

New project creation workflow and tech stack blueprints.

**New skill**
- `/kickoff` — takes a user from "I have an idea" to a running first version. Runs a focused discovery interview (problem-first, not solution-first), assesses technical experience, recommends the lightest viable stack tier, then hands off to `/brainstorm` for design and build. Actively protects non-technical users from deploying to the internet.

**New docs**
- `docs/stack-spectrum.md` — four-tier tech stack blueprint: lightweight (HTML/CSS/JS prototypes), personal (Next.js + Prisma + MySQL), distributed (personal + Supabase), deployable (Rails + Next.js monorepo). Decision criteria table, upgrade triggers, and full scaffolding checklists for each tier.
- `docs/thanx-dev-system.md` — detailed reference for the deployable tier (1100 lines covering Rails, Grape, Next.js, DevBox, Docker, CI/CD, Terraform, auth).

**Updated**
- `publish.sh` — now syncs `docs/` directory (stack blueprints) alongside skills
- `040-tech-stack` rule — references the spectrum instead of embedding a monolithic Thanx stack description

---

## v1.5.0 — 2026-04-08

Portability fixes and interview/brainstorm handoffs.

**Portability**
- `execute-plan`, `improve`, `promote`, `bugbash` — removed hardcoded `~/Personal/AI-RON` and `/Users/aaron` paths. All published skills now use relative paths or dynamic resolution, so they work for anyone in any directory.

**Interview + brainstorm connection**
- `brainstorm` — new interview check at Step 3a: if the topic requires domain knowledge not in the codebase, recommends `/interview` first. Step 1 now reads interview artifacts (`*_review/` directories) when available.
- `interview` — new brainstorm exit ramp in Phase 2 wrap-up: offers to hand off to `/brainstorm` when the interview surfaces actionable problems. New "guarding the interview" section pushes back when users drift toward solutions before the knowledge transfer is complete.

---

## v1.4.0 — 2026-04-06

Worktree awareness for ralph-review and fixit.

**Updated skills**
- `ralph-review` — detects when running inside a git worktree and resolves `$MAIN_REPO` for all durable artifacts (reviews, fix worktrees, gitignore). Prevents nested worktree creation.
- `fixit` — same worktree awareness: creates fix worktrees relative to main repo root, not the current worktree.
- `spec-audit` — adds previous audit completeness check, audit directory versioning, and note on behavioral file counting.

---

## v1.3.0 — 2026-04-05

Spec-audit subagent enforcement.

**Updated skills**
- `spec-audit` — Phase 2 analysis now requires `Agent` tool for parallel module dispatch (no more inline work). Phase 3 gap resolution references `agent-driven-development` pattern for worktree isolation and proper subagent dispatch.

---

## v1.2.0 — 2026-04-05

Session topic enforcement and skill updates.

**New: Session topic enforcement system**
- `/set-topic` gains `--initial` flag — no-ops if topic already set, preventing Claude from overwriting the topic
- `/set-topic` now validates that the `remind-session-topic.sh` hook is installed and warns if missing
- New `Stop` hook (`remind-session-topic.sh`) reminds Claude to set the topic each turn, escalating after 5 turns
- Simplified `055-session-topics` rule snippet — direct instructions, no judgment calls
- README now includes full [Session Topics](#session-topics) setup guide

**Updated skills**
- `ralph-review` — replaced `/fixit` references with explicit background Agent dispatch pattern and prompt template
- `brainstorm` — upstream improvements
- `execute-plan` — upstream improvements

---

## v1.1.2 — 2026-04-05

Added `RELEASE_NOTES.md` changelog. The `/publish-skills` workflow now prepends release notes to this file on every publish.

Updated skill: `write-skill` — no functional change (already in v1.1.1), just the publish-skills workflow improvement.

---

## v1.1.1 — 2026-04-05

Closes the loop on v1.1.0's description rewrite. The `/write-skill` skill now enforces the "Use when..." convention:

- **Template example** changed from `One-line summary of what this skill does` to `Use when <trigger situation> -- <what the skill does>`
- **Field docs** now say descriptions MUST start with "Use when..." and warns that noun-phrase descriptions will never auto-trigger
- **Validation checklist** item updated from "Description is present and includes trigger keywords" to "Description starts with 'Use when...' (trigger pattern, not noun phrase)"

New skills created with `/write-skill` will follow the trigger-pattern convention by default.

---

## v1.1.0 — 2026-04-05

All 24 publishable skill descriptions rewritten from noun phrases to trigger patterns so Claude Code's skill router matches them to user intent.

- **Before:** `"Multi-agent competing hypotheses debugging"` — describes what the skill *is*
- **After:** `"Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes"` — tells Claude *when to use it*

This follows the [superpowers](https://github.com/obra/superpowers) convention where the `description` front-matter field acts as a routing instruction, not a label.

Updated skills (24): agent-driven-development, bugbash, changelog, close-worktree, debug, devils-advocate, disk-cleanup, execute-plan, fixit, guard, improve, merge, pr, pr-dashboard, promote, ralph-review, rereview, review, save-w-specs, spec-recommender, spec-writer, test, unstaged, write-skill

No new or removed skills. README skills table updated to match.

---

## v1.0.0 -- 2026-04-05

First tagged release. The repo has been in use for months, but this marks the shift from a loose skill collection to a coherent architecture with layered discipline skills, an orchestration pattern, and spec-driven development as the backbone.

### Architecture: agent-driven-development

The headline change is a new three-layer skill architecture, adapted from [superpowers](https://github.com/obra/superpowers) and merged with our own innovations:

**Discipline skills** -- how agents should think and work:

- **[test-driven-development](skills/test-driven-development/SKILL.md)** -- red-green-refactor with extensive rationalization tables that make it hard for Claude to skip TDD under pressure. Includes [testing anti-patterns](skills/test-driven-development/testing-anti-patterns.md) reference.
- **[verification-before-completion](skills/verification-before-completion/SKILL.md)** -- evidence before claims. No "should work now" -- run the command, read the output, then state the result.

**Orchestration pattern** -- how agents coordinate:

- **[agent-driven-development](skills/agent-driven-development/SKILL.md)** -- the implement-test-review loop. Fresh agent per task, worktree isolation for parallel execution, two-stage review (spec compliance then code quality), native Task dependencies with `addBlockedBy` for automatic sequencing. Includes [implementer](skills/agent-driven-development/implementer-prompt.md), [spec-reviewer](skills/agent-driven-development/spec-reviewer-prompt.md), and [code-quality-reviewer](skills/agent-driven-development/code-quality-reviewer-prompt.md) prompt templates.

**Updated user-facing skills** -- the things you actually invoke:

- **[execute-plan](skills/execute-plan/SKILL.md)** -- rewritten to use agent-driven-development. Plans are parsed into Task dependency graphs, stages run in parallel worktrees, execution is fully autonomous (no mid-run questions).
- **[fixit](skills/fixit/SKILL.md)** -- still fire-and-forget, now with the implement-test-review loop and debugging reference docs.
- **[bugbash](skills/bugbash/SKILL.md)** -- each bug gets its own worktree, agents run in parallel, Task system tracks progress.

**Retired:** `/dev` -- its planning was absorbed by `/brainstorm`'s quick-confirm path, its execution by `agent-driven-development`.

### Debugging reference docs

Three new reference docs for the [debug](skills/debug/SKILL.md) skill, auto-loaded by any skill involving bug fixing:

- [root-cause-tracing](skills/debug/root-cause-tracing.md) -- trace bugs backward through the call stack to find the original trigger
- [condition-based-waiting](skills/debug/condition-based-waiting.md) -- replace arbitrary timeouts with condition polling in tests
- [defense-in-depth](skills/debug/defense-in-depth.md) -- validate at every layer data passes through

### Brainstorm visual companion

The [brainstorm](skills/brainstorm/SKILL.md) skill now ships with the visual companion server -- a zero-dep Node.js HTTP server for browser-based mockups, diagrams, and side-by-side comparisons during brainstorming sessions. Previously this required the superpowers plugin.

- `scripts/server.cjs` -- WebSocket server with live reload
- `scripts/start-server.sh` / `stop-server.sh` -- lifecycle management
- `scripts/frame-template.html` -- CSS theme with dark mode, selection UI
- [spec-document-reviewer-prompt.md](skills/brainstorm/spec-document-reviewer-prompt.md) -- optional subagent review for complex specs

### Other changes

- `/brainstorm` plans now include explicit dependency information so `/execute-plan` can build Task graphs
- Removed all references to the superpowers plugin -- replaced by native skills
- Synced session-topics env var fallback and execute-plan stage overlap check
- Renamed close-worktree skill (was incorrectly named "worktree")
- Added worktree-location rule snippet
- Hardened bugbash (investigation gate), ralph-review (audit resolution tracking), spec-audit (incremental mode, module dispatch)

### Skill count

38 published skills, 12 rule snippets, 2 hooks, 1 status line script.
