## v1.32.0 — 2026-06-01

**Sandbox-aware `/fixit` and `/bugbash`: landing-tier and OpenSpec routing fixes**

Field feedback from running `/fixit` inside a sandboxed worktree surfaced five gaps, all now fixed in `agent-driven-development/sandbox-mode.md`, `fixit`, and `bugbash`:

- **Base ref** – a task-spawning host now branches the worker off the calling session's current (often stacked) feature branch instead of the default branch, so fixes stack against the code that actually has the bug.
- **Landing tiers reworked** – Tier 3 now splits into Case A (caller on a feature branch → local merge into the writable worktree, no staging) and Case B (caller on main → host PR/merge helper or staged command).
- **Host git/PR helper detection** – a new host-agnostic capability (matched by tool shape, no host names) is preferred over clipboard staging for push/PR/merge landing steps.
- **Completion signaling** – removed the inaccurate "you'll be notified" claim; the worker now signals completion over the coordination channel, or the caller is explicitly told to poll.
- **OpenSpec change routing** – spec-gap fixes now route their delta into an active in-flight change rather than always scaffolding a new `fix-<slug>` folder.

**Retired skills removed**

- Deleted `disk-cleanup`, `mcp-prune`, `pr-dashboard`, and `software-best-practices` from the kit and the skills catalog.

**Misc**

- Renamed `home/bin/sandbox-probe.sh` → `repo-writable-check.sh`; added `publish-target-status.sh`.
- Smaller updates to `anutron-install`, `anutron-uninstall`, `bash-style`, `debug`, `handoff`, `improve`, `kickoff`, `list-skills`, `migrate-to-openspec`, `plannotator-specs`, `upload-notion-image`, and the worktree-location rule snippet.

---

## v1.31.0 — 2026-05-30

**New skill: `bash-style`**

- A reference skill cataloguing the bash patterns that trip Claude Code's permission guardrails (`cd <repo> && git ...`, `$(...)`, backticks, heredocs, inline `-c`/`-e` interpreters, multi-line shell), the safety rules for path-based allowlisting, and the `git -C` known gap.
- `user_invocable: false` — loaded by reference from other skills. Added to the skills catalog under "Discipline and orchestration".

**Sandbox-aware `/fixit` and `/bugbash`**

- `agent-driven-development` gains a `sandbox-mode.md` reference plus a `home/bin/sandbox-probe.sh` helper, so `/fixit` and `/bugbash` detect a sandboxed environment and dispatch their worktree agents accordingly.

**Global CLAUDE.md snippet trims**

- Trimmed several global snippets (claudemd-management, plan-formatting, interaction-prefs, tech-stack, bash-command-style, worktree-location, session-topics, plannotator-spec-review, testing, spec-driven-dev, openspec-migration). The bash-command-style snippet now points at the new `bash-style` skill instead of inlining the detail.

**Docs**

- New `docs/handling-api-keys.md`; security recipe and README touch-ups.

---

## v1.30.0 — 2026-05-26

Claude Code's static analyzer flags inline `$(...)`, backticks, and heredocs in Bash as "Contains shell syntax that cannot be statically analyzed" — and that flag bypasses `settings.json` allowlists, so users see a permission prompt every invocation. `/close-worktree` was breaking on a context-line `$(git worktree list ...)` substitution. `/bugbash` had the same anti-pattern.

**Fix: extract shell context into helper scripts**

- `/close-worktree`: 7 inline `!`-prefixed context queries (including two `$(...)` substitutions) collapsed into a single call to `home/bin/close-worktree-context.sh`.
- `/bugbash`: the `for d in todo in-progress ...; do files=$(find ...)` inventory line moved into `home/bin/bugbash-inventory.sh`.
- Both helpers are symlinked from `~/.claude/bin/` by `/setup`, matching the existing convention used for `set-session-topic.sh`, `html-to-text.sh`, etc.

**docs/skills-catalog.md**
- Refreshed `trust-action` and `trust-skills` rows to match their current SKILL.md frontmatter descriptions (catalog had stale first-sentence-only versions).

---

## v1.29.0 — 2026-05-25

Closes the gap where `/execute-plan` runs all the way through `openspec archive` and then `/ralph-review` errors out because no active change exists. Ralph-review now reviews against archived deltas in place, and `/execute-plan` always tells you whether quality gates ran.

**ralph-review: archived-change mode**
- Phase 0b adds detection for recently-archived changes. When the diff between `BASE...HEAD` touches `openspec/changes/archive/<name>/`, ralph reads deltas from the archive in place — no un-archive, no git-state churn.
- Confidence tier stays at `spec` (archived deltas are the authoritative contract for what the change should have done). Base specs at `openspec/specs/<cap>/spec.md` provide post-merge context.
- `[SPEC-DRIFT]` findings surface as `[QUESTION]` in archived mode — archives are immutable history; resolution requires creating a follow-up change or editing base specs, both of which need user judgment.
- Updated failure handling and graceful-degradation tables to document the new path.

**execute-plan: always report quality-gate status**
- Reordered so Phase 5 (quality gate offer) runs before Phase 6 (summary), and the summary template includes a mandatory `Quality gates` section reporting each gate as `ran | skipped by user | not offered (auto mode) — invoke /<skill>`.
- In auto/non-interactive runs the Phase 5 offer is skipped silently as before, but the summary now explicitly tells the user neither gate ran, so they know downstream review is still their responsibility.

---

## v1.28.0 — 2026-05-25

Adds a `--pre-archive` mode to `spec-audit` that previews coverage as if a named active OpenSpec change had already been archived, and hardens 20 skills against being loaded from a non-git CWD.

**spec-audit `--pre-archive`**
- New flag passed before the subcommand: `audit.sh --pre-archive <change-name> inventory openspec`. The named change's delta specs are folded into the spec corpus and tagged `source: 'pending'` / `pending_change: '<name>'` so the downstream mapping and analysis phases see post-archive coverage instead of misleadingly flagging newly-added code as unmapped.
- Inventory output gains a top-level `pre_archive` field, a `counts.pending_spec_files` counter, and per-entry `source` / `pending_change` fields on `spec_files`.
- Validates that the change folder exists before merging. Other subcommands silently ignore the flag.

**Skill init guards against non-repo CWDs**
- 37 standalone `git` invocations across 20 SKILL.md init blocks now append `2>/dev/null || echo '(not in a git repo)'` so skills like `/handoff` load cleanly when CWD isn't a git work tree (sandboxed sessions, scratch dirs).
- Piped commands already exit 0 via the last pipe stage and were left alone.
- `write-skill` documents the pattern so new skills inherit the guard.

**Misc**
- Removes `home/bin/mysqld-orphan-check.sh` (moved to a separate sketch repo).

---

## v1.27.0 — 2026-05-25

Adds `op-secret`, a tiny shell helper for lazily loading API tokens from 1Password into the current shell session. Also catches up the skills catalog with everything added since v1.26.0 and publishes a previously-untracked diagnostic script.

**New shell helper**
- **`bin/op-secret.sh`** — sourceable zsh function (`secret VAR_NAME`) that reads from `op://claude/shell-env/<VAR>` on first request and caches the value in the shell's env for the rest of the session. Zero shell-startup cost, no secrets on disk.
- **`docs/op-secret.md`** — install + usage doc covering the 1Password layout (one item, N custom fields), service-account setup, rotation, troubleshooting, and the bash port.
- **README Extras** — new row alongside `statusline.sh` and `permissions-guide.md`.

**Skills catalog regeneration**
- Added entries for `anutron-install`, `anutron-uninstall`, `doitright`, `eli5`, `trust-action`, `trust-skills` (skills introduced since v1.26.0 but missing from the catalog).
- Removed stale entries for `tp` (now lives only as a published binary at `bin/tp/`, not a skill) and `logo` (removed from the publishable set).
- Pure spec skills (`spec-audit`, `spec-recommender`, `spec-todo`, `spec-writer`, `ralph-review`, `save-w-specs`, `plannotator-specs`) remain in `spec-driven-development.md` only, per the catalog's "this doc covers everything else" boundary.

**Misc**
- **`home/bin/mysqld-orphan-check.sh`** — diagnostic script that had landed in ai-ron but never published.

---

## v1.26.0 — 2026-05-23

Docs decomposition: the README becomes a recipe-style home page with six topic-doc cards, each illustrated. Plus accumulated skill, rule, and infrastructure updates from ai-ron.

**Docs**
- **README** rewritten from 487 lines to a recipe-style overview. Six cards linking to focused topic docs, each with a hand-drawn illustration.
- **`docs/workflow-guide.md`** rewritten as a narrative of the development cycle — the WHY of specs as source of truth, OpenSpec as the convention, and the skill cascade (kickoff/interview greenfield, brainstorm, execute-plan, ralph-review, spec-audit, bugbash, fixit) with inputs/outputs/handoffs per step. CI and prod-branch sections framed as optional conventions, not assumptions.
- **New topic docs** lifted from the old README: `spec-driven-development.md`, `skills-catalog.md`, `claude-rules.md`, `session-topics.md`, `skill-usage-tracking.md`, `quick-start.md`.
- **Six new illustrations** in `docs/images/` matching the existing recipe set's brush-pen-and-ink style. Two orphaned legacy images (`file-layout.png`, `spec-tdd-cycle.png`) removed.
- **Publish flow:** the canonical README now lives in ai-ron and is published from there. `scripts/publish.sh` carries it across, and the skills-catalog regeneration step targets `docs/skills-catalog.md` instead of inlining tables in the README.

**New skills**
- **`/doitright`** — pick the long-term-correct option from a multi-option recommendation. Used when the user types `/doitright` in response to a choice, meaning "go with the proper long-term fix unless there's a real downside beyond effort."
- **`/eli5`** — restate the prior response in plain, non-technical language and orient the user around the decision they need to make.
- **`/trust-action`** — eliminate a specific Claude Code permission prompt by adding a targeted allowlist rule to global or project scope. Refuses unfixable patterns (`$(...)`, heredocs, `cd && ...`) and bypass-prone path-based rules; proposes CLAUDE.md hardening instead. Companion to `/trust-skills`.
- **`/trust-skills`** — bulk-trust all skills defined in the current project's `.claude/skills/` directory by adding `Skill(<name>)` allowlist entries.

**New rule snippet**
- **`045-bash-command-style`** — codifies the bash patterns that trigger Claude Code's static-analysis flag (heredocs, `$(...)`, `cd && cmd`, inline interpreter invocations) and the prescribed workarounds (helper scripts, multi-`-m` commits, `git -C`).

**Removed**
- `/logo` and `/close-spec-drift` skills (consolidated or deprecated).
- Rule snippets `022-user-facing-framing`, `050-git-workflow`, `065-plannotator-cli-hygiene` (rolled into other snippets or replaced).

**Skill and infrastructure updates**
- Many in-flight updates to `anutron-install`, `setup`, `migrate-to-openspec`, `agent-driven-development`, `brainstorm`, `execute-plan`, `ralph-review`, `spec-audit`, `bugbash`, `fixit`, and others — these accumulated between v1.25.0 and this release.
- `claude-rules/` gains `lib/` (frontmatter parser used by anutron-install) and `scope-presets.json` (used by scope resolution).
- New `home/bin/` includes `set-session-topic.sh` helper script (handles PID→SESSION_ID resolution for the `/set-topic` skill).
- New `setup/install.sh` for the setup skill's wiring.

**Notes**
- Re-run `/setup` or `/anutron-install` to pick up rule and home/bin changes.
- The new home page references images at `docs/images/<topic>.png`; if you fork or steal individual docs, grab the matching illustration too.

---

## v1.25.0 — 2026-05-12

`/tp` CLI for cheap checkbox edits, ralph-review Inevitability label, execute-plan pre-archive quality gates, and a new user-facing framing rule.

**New**
- **`/tp`** — CLI for single-line checkbox flips and one-line status annotations (`✅` `❌` `🟡` `⏭`) in markdown task lists. One Bash call instead of streaming whole files through Read+Edit for tick operations in `openspec/changes/*/tasks.md`, OpenSpec base specs, and `.workflow/test-plans/*.md`. Source lives at [bin/tp/](bin/tp/) with a Makefile; a prebuilt macOS arm64 binary ships in-repo. Other platforms run `cd bin/tp && make install` to build for their architecture.
- **Rule snippet `022-user-facing-framing`** — outcome-first structure for choices and findings (Why this matters / What's happening / What could go wrong / Recommendation / Technical details). `/brainstorm` and `/ralph-review` look here for framing instructions; users can add their own version, this one, or none.

**Updated — `/ralph-review`**
- **Inevitability label** on every question finding. Classifies the underlying work as **Inevitable** (will need to happen eventually regardless — "if it's worth doing at all, it's worth doing it right the first time" applies), **Order-dependent** (genuine reason to wait), or **Avoidable** (may never be needed). Surfaces when "defer for economy" is really just postponing the inevitable, without biasing ralph's recommendation.
- **Dispatch-as-you-go** question flow. Each user answer kicks off its fix in the background while ralph immediately presents the next question. Trivial fixes apply inline; substantial fixes dispatch to a worktree agent.
- **Option 5 closes the gate** — Done now offers to archive the active OpenSpec change (merges deltas into base specs). Doesn't auto-archive — the user can keep iterating with Keep Active.

**Updated — `/execute-plan`**
- **Quality gates moved pre-archive.** Phase 4 now offers `/ralph-review` and `/spec-audit` while the change is still active and the deltas are intact. If the user picks ralph, ralph closes the gate (runs the review loop, addresses findings, archives). Previously ran post-archive where deltas had already merged.
- **Parallel-eligible stages auto-mandate worktrees.** If the dependency graph has siblings (multiple stages sharing a Depends-on with no file overlap), worktree mode is selected without asking. Fully sequential changes still ask current-branch vs worktree.
- **Test-only stages use a single combined review pass.** Stages that produce only test files run one reviewer (spec compliance + test correctness) with a one-fix-loop cap, instead of the full two-stage flow.

**Updated — other skills**
- `/brainstorm` section framing block now points at "your CLAUDE.md" for optional user-facing framing instructions, instead of citing a global rule by name.
- `/agent-driven-development` cross-references execute-plan's test-only fast-path.

**Notes**
- To pick up the new `022-user-facing-framing` rule, re-run `/setup` or recompile your CLAUDE.md from snippets. Existing skills work without it; the rule extends their default templates.
- macOS arm64 users get a working `tp` immediately after `/setup`. Other platforms must rebuild: `cd bin/tp && make install`.

---

## v1.24.0 — 2026-05-07

`/close-spec-drift` skill, `/fixit` and `/bugbash` hardening, and a plannotator CLI hygiene rule.

**New**
- **`/close-spec-drift`** — targeted workflow for "make reality match the spec" in OpenSpec projects. Surfaces full drift extent before any work, scaffolds a thin change folder (proposal + tasks, no deltas), commits with `--no-verify`. Distinct from `/brainstorm` (too heavy for cleanups), `/spec-recommender` (opposite direction), and `/fixit` (non-OpenSpec).
- **Rule snippet `065-plannotator-cli-hygiene`** — never pipe `plannotator` stdout through `tail`/`head`/`grep`. Annotations exist only on stdout and can't be recovered from disk.

**Updated — `/fixit` and `/bugbash` (workflow guards)**
- **User's Exact Ask** section in agent prompts preserves the user's literal instruction verbatim, marked as highest-priority guidance, supersedes the drift-vs-gap classification when the user prescribes a workflow.
- **Workflow-instruction guard** — when the user's wording specifies a process ("via a PR", "via OpenSpec change", "with `--no-verify`", etc.), the dispatcher defers; if the prescribed workflow doesn't fit the project, surface to the user before dispatching.
- **Pattern-cleanup pre-flight** — when the description contains keywords like "remove all" / "legacy" / "deprecated", run one comprehensive grep across the relevant scope and surface the full extent before dispatch.
- **Followup capture rule** — every "out of scope" item in the agent's report must resolve into extend-scope, `TaskCreate`, or explicit won't-fix; cannot be silently dropped.
- **Conditional merge gate** — auto-merge by default; hold for review on dispatcher-vs-user divergence, `DONE_WITH_CONCERNS`, unresolved concerns, or OpenSpec base-spec edits.
- `/bugbash` uses a new `pending-merge/` status folder + `/bugbash review` subcommand instead of a synchronous merge queue. Adds a soft cross-bug capability overlap check alongside the existing same-file hard-gate.

**Updated — other skills**
- `execute-plan` accepts legacy `## Phase N:` headings as stage boundaries with numerical-order Depends-on fallback.
- `handoff` replaces the dead `memory-query` MCP block with the auto-memory file + `MEMORY.md` index pattern.
- `spec-writer` adds the MODIFIED-vs-ADDED Requirements pitfall: MODIFIED needs the requirement to already exist verbatim in the base spec, otherwise `openspec archive` fails mid-merge.
- `migrate-to-openspec` adds audit-config translation, `--change` routing, anti-heartbeat wait pattern lockdown, and expanded test coverage.

**Updated — docs**
- `stack-spectrum.md`, `thanx-dev-system.md`, `workflow-guide.md`, and the design-to-execution / skills-and-project-organization recipes refreshed for the OpenSpec workflow.

---

## v1.23.0 — 2026-05-04

OpenSpec migration callouts in the docs and a `legacy-spec-system` rollback tag.

**New**
- Tag `legacy-spec-system` points at commit `85806d4` (= v1.21.0, the last release using the `.specs`-based workflow). Users who want the previous spec-driven system can `git checkout legacy-spec-system`.

**Updated (docs)**
- `README.md` — Spec-Driven Development section now opens with an OpenSpec callout and rollback-tag reference.
- `docs/workflow-guide.md` — top-of-file callout; lifecycle order now reads `change folder → deltas → tests → implement → archive`; opt-in mechanism is `openspec init` instead of `.specs`.
- `docs/thanx-dev-system.md` — top-of-file callout; project-tree example replaced `specs/` with `openspec/{specs,changes}/`.
- `docs/stack-spectrum.md` — inline updates across Lightweight/Personal/CLI tier checklists and the shared-conventions table; `openspec init` replaces `.specs` opt-in.
- `docs/claude-code-recipes/01-skills-and-project-organization.md` — top-of-file callout.
- `docs/claude-code-recipes/02-design-to-execution-pipeline.md` — top-of-file callout; `/brainstorm` now scaffolds an OpenSpec change folder; `/execute-plan` takes a change name; spec-update step rewrites delta specs.

**Notes**
- No skill behavior changes – this release is purely documentation alignment with v1.22.0's OpenSpec migration.

---

## v1.22.0 — 2026-05-04

Spec-driven workflow migrates from legacy `.specs` to OpenSpec.

**New**
- `skills/migrate-to-openspec/` — One-time migration tool that converts a legacy `.specs` project to OpenSpec layout with verifiable fidelity. Translator + verifier agents preserve every Given/When/Then case as an OpenSpec scenario; originals archive at `.workflow/legacy-specs/` with forwarding banners. Default cap of 20 parallel agents per wave.
- `claude-rules/snippets/global/085-openspec-migration-prompt.md` — Suggests `/migrate-to-openspec` when encountering a legacy `.specs` project.

**Updated (OpenSpec rewrites)**
- `skills/brainstorm/SKILL.md` — Now scaffolds an OpenSpec change folder (`openspec/changes/<name>/proposal.md`, `design.md`, `tasks.md`, plus delta specs at `specs/<capability>/spec.md`) instead of writing legacy `specs/foo.md`.
- `skills/execute-plan/SKILL.md` — Argument is now an OpenSpec change name, not a plan path. Loads the change via `openspec show`, parses `tasks.md` into a stage graph, dispatches per-stage agents in worktrees, and runs `openspec archive` at the end.
- `skills/save-w-specs/SKILL.md` — Gates commits on whether an active OpenSpec change's deltas describe the diff. Five-step active-change inference (single change → use it, multiple → branch match, otherwise ask).
- `skills/ralph-review/SKILL.md` — Compares implementation against the active change's deltas instead of legacy specs. Adds `openspec validate` as a pre-flight check.
- `skills/spec-audit/SKILL.md` — Inventories OpenSpec capabilities via `openspec list --specs`, excludes active-change deltas from the audit corpus.
- `skills/spec-writer/SKILL.md` — Thin orchestrator around `openspec instructions <artifact>` (proposal/design/tasks/specs).
- `skills/spec-recommender/SKILL.md` — Recommends OpenSpec capabilities + requirements; output points at `openspec instructions specs`.
- `skills/spec-todo/SKILL.md` — Reads from `.workflow/todo/` instead of `specs/todo/`. Detects via `test -d openspec`.
- `skills/fixit/SKILL.md` — Spec-aware section now uses OpenSpec: agents classify bugs as code drift (fix code, no delta needed, commit `--no-verify`) or spec gap (scaffold a fix-change folder with deltas).
- `skills/bugbash/SKILL.md` — Same OpenSpec spec-aware flow as fixit, applied per-bug.
- `claude-rules/snippets/global/080-spec-driven-dev.md` — Rewritten to describe OpenSpec spec-first order: change folder → deltas → tests → implement → archive.
- `claude-rules/snippets/global/090-plan-archiving.md` — Stubbed; superseded by OpenSpec's own archive flow.
- `claude-rules/snippets/global/040-plan-execution-handoff.md` — Updated for OpenSpec.

**Notes**
- Existing legacy `.specs` projects continue to work; the rewritten skills exit cleanly when no `openspec/` directory is present.
- `migrate-to-openspec` is a one-time-per-project op. Originals are preserved under `.workflow/legacy-specs/`.
- Pre-commit hook (`scripts/spec-check-hook.sh`) now gates on active-change deltas at `openspec/changes/<name>/specs/<capability>/spec.md` instead of `specs/*.md`.

---

## v1.21.0 — 2026-04-30

Acceptance criteria in brainstorm design phase.

**Updated**
- `skills/brainstorm/SKILL.md` — Step 9 ("Present design in sections") now pairs `it should X` acceptance criteria with each behavioral design section. Coverage rules: one criterion per distinct behavior, stop at redundancy, skip non-behavioral sections (architecture/rationale/conventions get none). Number scales naturally with design complexity — no artificial cap.
- `skills/brainstorm/SKILL.md` — Step 10 self-review adds an acceptance-criteria coverage check.
- `skills/brainstorm/SKILL.md` — Phase 2 Stage 2 ("Write failing tests") now derives tests directly from the brainstorm doc's acceptance criteria, so each `it should X` line becomes at least one failing test.

---

## v1.20.0 — 2026-04-27

Norms check and plan-mode gate in brainstorm skill.

**Updated**
- `skills/brainstorm/SKILL.md` — New Step 7 "Norms check" between pre-mortem and propose-approaches: forces Claude to name the standard professional approach for the problem space (hashing for credential comparison, env vars for secrets, parameterized queries, idempotency keys, etc.) before proposing options, so users see industry defaults even when they didn't know to ask.
- `skills/brainstorm/SKILL.md` — Phase 2 Step 3 now enters plan mode after the plan is committed; `ExitPlanMode` becomes the approval signal that hands off to execution. Prior steps remain free to write design docs.
- `hooks/remind-session-topic.sh` — Updates synced from AI-RON.

---

## v1.19.0 — 2026-04-15

Skill dependency tracking and anutron-install skills.

**Added**
- `hooks/log-skill-read.sh` — New hook that tracks Read tool accesses to skill files, logging to `~/.claude/skill-reads.tsv`. Captures dependency usage for skills loaded by reference (e.g., `agent-driven-development` loaded by `execute-plan`) that never appear in invocation logs.
- README section: "Skill usage tracking" — documents how the three logging hooks work together (invocations vs dependency reads) with setup instructions and log format reference.
- `skills/anutron-install/` — Install the anutron kit into a project (skills, hooks, compiled CLAUDE.md)
- `skills/anutron-uninstall/` — Reverse everything anutron-install did
- `skills/anutron-install-plugin/` — Lightweight plugin wrapper for per-project installs (Option B)
- Site: feed page, kit guide pages, styling updates

**Fixed**
- `hooks/check-links.sh` — Exclude `site/vendor/`, `vendor/`, and `node_modules/` from link checking to avoid false positives from vendored gem documentation

---

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
