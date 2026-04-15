## v1.18.0 — 2026-04-14

Promote skill now recognizes personal-global skills.

**Changed**
- `skills/promote/SKILL.md` — Added "Personal-global" classification for prefixed skills (`airon-*`, `thanx-*`) that are useful globally but excluded from publishing. Promotion and publishing are now explicitly documented as orthogonal axes.

---

## v1.17.1 — 2026-04-12

Polish pass on the adoption recipes.

**Changed**
- `docs/claude-code-recipes/00-overview.md` — section headers now link to their docs, each section gets a "Read recipe N" footer link and an HR separator for clearer navigation
- `docs/claude-code-recipes/recipe4_data-proxy-glovebox.png` — replaced with a final illustration that has the correct glove box geometry (gloves attached to the box wall, robot arms enter through ports)

---

## v1.17.0 — 2026-04-12

Adoption recipes for organizations + writing-style rule.

**Added**
- `docs/claude-code-recipes/` — A 5-doc set of opinionated patterns for orgs scaling Claude Code adoption. Each recipe pairs an approachable description with a technical reference for Claude:
  - **00-overview** — Goal and recipe index
  - **01-skills-and-project-organization** — Personal workshop pattern, three sharing tiers (steal/clone/plugin)
  - **02-design-to-execution-pipeline** — Brainstorm → plan → spec → code workflow
  - **03-security-plugin** — Policy injection, active guardrails, compliance observability
  - **04-data-proxy** — Three tiers of proxy sophistication, credential isolation
- `claude-rules/snippets/global/015-writing-style.md` — Writing style: sentence case titles, en-dash never em-dash

---

## v1.16.0 — 2026-04-11

Uncapped bugbash agent parallelism.

**Changed**
- `/bugbash` — removed the artificial 3-agent slot cap. All non-conflicting bugs now dispatch simultaneously, matching `/execute-plan`'s approach. The only remaining gate is file-overlap conflicts between in-progress bugs.

---

## v1.15.0 — 2026-04-11

Portability fix for kickoff skill.

**Changed**
- `/kickoff` — replaced dynamic `docs/stack-spectrum.md` file read with a static reference to CLAUDE.md system instructions, making the skill work correctly in any project directory.

---

## v1.14.0 — 2026-04-11

Optional worktree isolation for plan execution.

**Changed**
- `/execute-plan` — added a worktree decision point before execution begins. Users can choose to run the entire plan in an isolated worktree, useful when running multiple coding workstreams simultaneously. Default remains executing on the current branch.

---

## v1.13.0 — 2026-04-11

Guardrails for design doc consistency and spec-aware commits.

**Changed**
- `/brainstorm` — added design doc consistency check before committing plans, and feedback-changes-requirements guidance during plan review. Brainstorm doc stays in sync with the plan as the living design record.
- `/save-w-specs` — added pre-commit hook failure guidance: investigate before bypassing, rendering/layout changes to spec'd UI components are behavioral and need spec updates.

---

## v1.12.0 — 2026-04-11

Brainstorm UX upgrade and Go CLI track.

**Changed**
- `/brainstorm` — all 6 user-facing decision points now use `AskUserQuestion` tool calls instead of blockquotes that rendered as plain text (interview check, size check, visual companion, pre-mortem, review offer, execution handoff)
- Stack spectrum — added Go CLI track (Cobra + Bubbletea for TUI)
- `/setup` — added permissions step to onboarding wizard

---

## v1.11.0 — 2026-04-09

Adoption cleanup and version-check simplification.

**Changed**
- Removed all AI-RON references from published skills and docs — skills now use relative paths and generic language
- Version check simplified to a single version-string comparison (installed stamp vs plugin.json) instead of file hashes and timestamps
- Version stamp renamed to `.anutron-claude-skills-version` to avoid ambiguity
- Removed `publish.sh` from public repo (internal-only sync tool)

---

## v1.10.0 — 2026-04-09

Plugin support and interactive setup wizard.

**New**
- Plugin manifest (`.claude-plugin/plugin.json`) — repo is now installable as a Claude Code plugin via `/plugin install claude-skills@anutron/claude-skills`
- `/setup` skill — interactive onboarding wizard that walks users through rules (replace/inject), hooks, and statusline installation
- SessionStart hook (`version-check.sh`) — nudges users to re-run `/setup` when plugin updates change installed components
- Three adoption paths in README: plugin install, clone + promote, or steal

**Changed**
- `publish.sh` now handles `plugin-only/` skills (skills that exist only in the published repo)
- Statusline default topic changed from "AI-RON" to neutral "topic mode: auto (/set-topic to set)" in grey

---

## v1.9.0 — 2026-04-09

Adoption fixes — quick-start guide, promote skill, and statusline default.

**Changed**
- `/promote` now detects skills in either `skills/` (repo root) or `.claude/skills/` (project convention), fixing the "none of the 38 skills are promoted" issue for adopters cloning this repo
- Added quick-start guide to README with 5-step adoption flow (clone, compile rules, promote, hooks, statusline)
- Clarified that hooks and statusline are terminal-only (steps 1-3 work in VS Code, JetBrains, desktop app too)
- Statusline default topic changed from "AI-RON" to neutral "topic mode: auto" so it works for everyone

---

## v1.8.0 — 2026-04-09

Inject mode for claude-rules — non-destructive CLAUDE.md management.

**New feature**
- `compile.sh link` now asks before overwriting an existing `~/.claude/CLAUDE.md`. Two options: **replace** (symlink, current behavior) or **inject** (append a managed section between begin/end markers, preserving user content). On recompile, only the managed section updates.

**Changed**
- `publish.sh` now syncs `compile.sh` and `variables.env` alongside rule snippets, keeping the published claude-rules in sync with the source
- Updated quick-start and claude-rules README to document inject mode

---

## v1.7.0 — 2026-04-09

Three new skills, publish cleanup.

**New skills**
- `/logo` — generates 6 distinct SVG logo alternatives (minimal, geometric, organic, structural, conceptual, bold) and a dark-themed comparison page for side-by-side review
- `/software-best-practices` — post-implementation quality checker calibrated for personal projects. Runs tests, checks linting, validates run scripts, and iterates on failures. Includes goal-drift prevention to catch yak-shaving.
- `/steal` — scans tracked GitHub repos for reusable skills, patterns, and techniques. Evaluates new repos on the fly, tracks sources for incremental rescans, and adapts stolen skills to your environment.

**Changed**
- `publish.sh` — cleaned EXCLUDE array: removed stale entries (`refresh-command-center`, `todo-agent`), published previously excluded skills

---

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
