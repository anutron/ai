---
name: migrate-to-openspec
description: Convert a legacy AI-RON spec project (`.specs` file + `specs/*.md`) to OpenSpec layout with verifiable fidelity. One-time per project. Translator + verifier agents preserve every Given/When/Then case as an OpenSpec scenario, archive originals at `.workflow/legacy-specs/`, and install the new pre-commit hook + CLAUDE.md snippets.
tags: [spec]
---

# Migrate to OpenSpec

High-fidelity migration tool. Runs five sequential phases: preflight, inventory, translate-and-verify, resolution, execution, and handoff. The translator and verifier are independent agents per source spec; both run in parallel waves up to a configurable cap (default 20).

Source specs are never deleted — they are archived at `.workflow/legacy-specs/<filename>.md` with a forwarding banner pointing to their new OpenSpec capability. The user manually deletes the archive when confident.

The tool refuses to run on a project that already has an `openspec/` directory or an `.openspec-migration.json` marker. Re-running on a migrated project exits cleanly.

## Arguments

- `--max-parallel <N>` — Cap on concurrent translator/verifier agents (default 20).
- `--auto-stash` — Auto-stash dirty working tree instead of failing preflight. Stash pop runs at the end of Phase 5.

## Phase 0: Preflight

Run `migrate.sh run [--auto-stash]` (or invoke preflight as part of the orchestrator). The CLI verifies, in order:

- `.openspec-migration.json` marker absent — if present, the tool exits 0 with the idempotent "already migrated" message.
- `openspec` CLI is on PATH (otherwise: install via `npm install -g @fission-ai/openspec`).
- The current directory is a git repository with at least one commit.
- No existing `openspec/` directory (otherwise the project looks already migrated).
- The project has legacy specs — either a `.specs` file or top-level `*.md` files inside the configured spec dir.
- The working tree is clean. If `--auto-stash` was passed, the CLI stashes uncommitted changes with message `openspec-migration auto-stash` and records the fact in `.openspec-migration-state.json` so Phase 5 can pop the stash.

Once preflight passes, the CLI tags the current HEAD as `pre-openspec-migration-<timestamp>` and creates a migration branch `openspec-migration-<timestamp>`. Both names are recorded in `.openspec-migration-state.json` (an in-progress marker; distinct from the final `.openspec-migration.json` marker written in Phase 4).

## Phase 1: Inventory

`migrate.sh inventory` (or `migrate.sh run`) walks the configured spec directory deterministically, classifying every Markdown file into one of six buckets:

- `base` — top-level `<spec-dir>/*.md` files (the translation targets).
- `plans` — anything under `<spec-dir>/plans/`.
- `docs` — anything under `<spec-dir>/docs/`.
- `audits` — anything under `<spec-dir>/audits/`.
- `todo` — anything under `<spec-dir>/todo/`.
- `other` — anything else nested under the spec dir that doesn't match the buckets above.

The CLI writes the result to `migration-inventory.json` at the project root. Arrays are sorted so the same input always produces the same output. The `run` orchestrator commits the inventory and the in-progress state file on the migration branch before handing off to later phases.

## Phase 2: Translate + verify

This phase converts every base spec into an OpenSpec capability spec and verifies fidelity. The work is split between the orchestrator (Claude reading this skill) and the deterministic CLI (`migrate.sh translate` / `migrate.sh verify`).

### Orchestrator pattern (Claude follows this)

1. Read `migration-inventory.json` from the project root. The `base` array lists every translation target.

2. **Translator wave.** For each entry in `inventory.base`, dispatch a translator agent via the `Agent` tool with `subagent_type: general-purpose`. Each translator receives a single source path. The agent's job is to:

   - Run `migrate.sh translate <source-spec-path>` (no other args needed — the CLI derives the capability name from the filename and writes to `openspec/specs/<capability>/spec.md`).
   - Capture the `translated <capability> -> <out-path>` line from stdout and report it back to the orchestrator.
   - On failure, return the error from `claude -p` so the orchestrator can decide whether to retry.

   Dispatch up to `--max-parallel` translator agents by sending **one message with N `Agent` tool calls** (default cap: 20). They run concurrently in the foreground; the message returns once all N complete – no polling needed. If the project has more than the cap, run multiple sequential waves the same way.

3. **Verifier wave.** After every translator in a wave returns, dispatch a verifier agent for each completed capability. Each verifier:

   - Runs `migrate.sh verify --source <source-path> --capability <name> --json`.
   - Returns the structured JSON report (already written to `.openspec-migration/verifier-reports/<capability>.json` by the CLI) to the orchestrator.

   Verifier waves use the same `--max-parallel` cap and the same one-message-with-N-Agent-calls pattern.

4. **Collect results.** Parse every verifier report. If all reports have `status == "clean"`, auto-proceed to Phase 3 (which is a no-op when there are no issues). If any report has `status == "issues"`, Phase 3 surfaces the issues for resolution.

### Wait pattern (anti-heartbeat rule)

The `Agent` tool batch above already handles concurrency. Once dispatched, the orchestrator must **not** poll for output files with throwaway Bash calls (`echo "."`, `ls`, `wait` loops, etc.).

- **Default:** send N `Agent` tool calls in a single message and let the message return naturally when all N agents complete. Foreground execution; notifications are unnecessary.
- **If async parallelism is desired** (e.g. the controller has other useful work between completions), pass `run_in_background: true` on each `Agent` call. The harness sends one completion notification per agent. Do **not** combine `run_in_background: true` with polling.
- **Never** launch `migrate.sh translate` or `claude -p` directly from a Bash subshell with `&` and poll for the output file. The `Agent` tool already provides the right primitive for both sync and async cases.
- **Escape hatch.** In the rare case a backgrounded shell process is genuinely needed, use the `Monitor` tool with a single `until [ -s <output-file> ]; do sleep 5; done` script. That fires exactly one notification when the file lands. Heartbeats are never the answer.

The reason for this rule: each heartbeat Bash call is a wasted conversation turn (~1–2 s of latency per dot, plus token cost). Past sessions have produced walls of `Bash(echo ".")` while waiting for a single slow translator – the `Agent`-tool primitive avoids the entire situation.

### What the CLI does

- `migrate.sh translate <path>` — reads `prompts/translator-prompt.md`, fills `{source_path}`, `{source_content}`, `{capability_name}`, and shells out to `claude -p`. The model returns the OpenSpec spec body followed by `<!-- META -->` and a JSON tail. The CLI writes the body to `openspec/specs/<capability>/spec.md` and the META JSON to `openspec/specs/<capability>/spec.md.meta.json`.

- `migrate.sh verify --capability <name>` — reads `prompts/verifier-prompt.md`, fills source/translation content + capability name, calls `claude -p`. Writes the structured report to `.openspec-migration/verifier-reports/<capability>.json`. Exits 0 for `clean`, 2 for `issues`.

- `migrate.sh validate-capability <name>` — wraps `openspec validate <name> --type spec --strict`. If `openspec/` hasn't been initialized yet, the CLI runs `openspec init --tools none .` first so the validator can find specs.

### Test determinism

For the bundled fixture tests (`test/run-tests.sh`), the CLI honors a `MIGRATE_FIXTURE_FAST=1` environment variable. Under that flag, `translate` copies pre-baked golden translations from `test/fixtures-golden/<capability>.md` instead of calling `claude -p`, and `verify` runs a deterministic structural diff (counts Given/When/Then bullets in the source vs `#### Scenario:` headers in the translation, plus structural checks for missing requirements/scenarios). This keeps the test suite fast and reproducible.

Real-`claude` integration is exercised by setting `MIGRATE_TEST_REAL_CLAUDE=1` before running the tests, which bypasses the fixture-fast path. Production migrations always use the real LLM — the fast path is opt-in via env and only the test runner sets it.

## Phase 3: Resolution

The orchestrator collects every verifier report under `.openspec-migration/verifier-reports/*.json` and decides per-capability what to do.

- Reports with `status: clean` are auto-accepted.
- Reports with `status: issues` are surfaced to the user with a source-vs-translation diff (`migrate.sh diff <source-path> <capability>`). The user picks one of three actions:
  - **accept** — keep the translation as-is, log the known drift, proceed.
  - **retry** — re-run the translator with verifier issues appended as a constraint. Bumps a counter at `.openspec-migration/retries/<capability>.txt`; capped at 2 retries per capability. The CLI re-runs the verifier after each retry.
  - **skip** — leave the capability un-migrated; the source spec is still archived under `.workflow/legacy-specs/` (with a "translation skipped" banner) so nothing is lost.

Every decision is recorded in `.openspec-migration/resolution.json` (`{ <capability>: "accept" | "skip" }`) so Phase 4 knows which translations to install.

### Auto-accept mode

When `migrate.sh run --auto-accept` is invoked, Phase 3 auto-accepts every clean report and skips any with issues. Auto-accept never retries — the semantics are "trust whatever's clean, defer the rest". The skipped capabilities show up in the Phase 5 summary so the user can revisit them later.

### CLI helpers

- `migrate.sh diff <source-path> <capability>` — unified diff between the source and translation (uses `diff -u`).
- `migrate.sh retry <source-path> <capability>` — re-translate with verifier issues as constraint, then re-verify.
- `migrate.sh resolve <capability> --action accept|retry|skip` — record the orchestrator's decision before invoking `migrate.sh execute`.

## Phase 4: Execution

After resolution, `migrate.sh execute` (or the tail of `migrate.sh run`) writes the new layout, validates it, and commits everything as one migration commit. The implementation is in `_execute()` in `migrate.sh`; the steps are:

1. **Initialize OpenSpec.** If `openspec/` doesn't exist, run `openspec init --tools none .`.
2. **Confirm accepted translations.** Each accepted capability already has a translated spec at `openspec/specs/<capability>/spec.md` from Phase 2; the executor just confirms presence.
3. **Archive every source spec** at `.workflow/legacy-specs/<filename>.md` with a forwarding banner. The banner reads `# [Legacy] <title>` followed by `> Migrated to OpenSpec on <YYYY-MM-DD>.` and a list of new locations. Skipped capabilities get a "translation skipped" banner instead so the source is never silently dropped.
4. **Move sibling artifacts:** `<spec-dir>/plans/` → `.workflow/plans/`, `<spec-dir>/docs/` → `.workflow/docs/`, `<spec-dir>/audits/` → `.workflow/audits/`, `<spec-dir>/todo/` → `.workflow/todo/`. Subdirectories are preserved.
5. **Preserve `.specs`** as `.workflow/legacy-specs/.specs`, then delete the original `.specs` and the (now-empty) spec dir.
6. **Validate.** Run `openspec validate --all --strict`. On failure, the executor rolls back via `git reset --hard <pre-migration-tag>` + `git clean -fdq` and aborts.
7. **Install templates** from `templates/` into the project: three CLAUDE.md snippets at `claude-rules/snippets/global/` and the new pre-commit hook at `scripts/spec-check-hook.sh`. If a template is missing (Stage 6 hasn't filled it in), the executor writes a one-line stub so the install step still succeeds — Stage 6 replaces the stubs with real content.
8. **Recompile snippets.** If `claude-rules/compile.sh` exists, run `./claude-rules/compile.sh compile`. This is a no-op for projects without the snippet pipeline.
9. **Write the marker** `.openspec-migration.json` at the project root with structured metadata (timestamp, branch, tag, capabilities, skipped, tool version).
10. **Commit** everything on the migration branch with message `Migrate to OpenSpec layout` and a body listing capability and artifact counts. The commit uses `--no-verify` so the (newly-installed) hook doesn't block the migration commit itself.

### Transactional rollback

Phase 4 is transactional: the pre-migration tag created in Phase 0 is the rollback target. If `openspec validate --all --strict` fails, the executor calls `git reset --hard <tag>` followed by `git clean -fdq` and returns non-zero. The user lands on the migration branch with the working tree restored to its pre-migration state and a clear error message.

## Phase 5: Handoff

`migrate.sh handoff` (called automatically at the end of `migrate.sh run`) prints a structured summary, restores any auto-stashed WIP, and finalizes state:

- Prints branch name, pre-migration tag, capability count, archive count, and `.workflow/` artifact counts.
- Shows the user how to review (`git diff main..<branch>`, `openspec validate --all --strict`), merge (`git checkout main && git merge --no-ff <branch>`), and roll back (`git reset --hard <tag>`).
- If `--auto-stash` was used in Phase 0, runs `git stash pop` so the user's pre-migration WIP comes back.
- Writes a structured report to `.openspec-migration/report.json` for downstream tooling.
- Removes the in-progress marker `.openspec-migration-state.json`. The durable signal that the project is migrated is the final `.openspec-migration.json` written in Phase 4.
