---
name: anutron-install
description: Install the anutron (claude-skills) kit into the current project — symlinks or copies skills, registers hooks, compiles CLAUDE.md from snippets.
tags: [personal]
---

# anutron-install

Installs the anutron (claude-skills) kit into the current working directory: skills land in `.claude/skills/`, hook scripts in `.claude/hooks/`, and compiled snippets are injected into `CLAUDE.md` between `BEGIN ANUTRON-INSTALL` / `END ANUTRON-INSTALL` markers. A breadcrumb at `.anutron-install.json` records everything the uninstaller needs to reverse the operation.

## How to invoke

```bash
bash "$(dirname "$SKILL_PATH")/install.sh"
```

Pass any combination of flags after `install.sh`. Print the script's output directly to the user. If the script exits non-zero, show the error and suggest a fix based on the message.

## Non-interactive defaults (no flags, no manifest)

When run with no flags and no `.anutron-install.config.json` in the target:

- **Symlink mode** is the default when the resolved source is a writable local clone.
- **Copy mode** is the default when the source is `~/.claude/anutron-cache` (the read-only plugin cache).
- **Full scope** is always the default — installs every publishable skill.
- On a TTY with no flags and no manifest, the script prompts interactively before writing anything.

## Flags

- `--mode=symlink|copy` — install mode. `symlink` keeps live edits flowing from the source (skills are symlinks). `copy` produces self-contained files so the install works without the source repo present.
- `--scope=full|spec-discipline|dev-tools|custom` — which preset of skills and snippets to install (default: `full`).
- `--interactive` — force the mode/scope prompts even when other flags would suppress them.
- `--for-contributors` — shortcut for `--mode=copy --scope=spec-discipline`; post-install summary includes a commit reminder.
- `--help` / `-h` — print usage and exit.

## Scope presets

Preset definitions live in `claude-rules/scope-presets.json` in the source repo — that file is the authoritative source.

- **full** — everything not matched by the source's hardcoded exclude list. Aaron's default for his own dev loop. Installs all skills (`*`) and all snippets (`*`), excluding personal/non-publishable entries.
- **spec-discipline** — spec-first + TDD + quality gates. Installs skills tagged `spec` or `quality`, and snippets tagged `spec`, `quality`, or `formatting` with `audience: shared`. Recommended for contributor-facing repos.
- **dev-tools** — extends `spec-discipline` and adds skills tagged `workflow` or `pr` (parallel execution, PR shipping).
- **custom** — reads `includeSkills`, `excludeSkills`, `includeSnippets`, `excludeSnippets` from `.anutron-install.config.json` in the target. Exits non-zero if the manifest is missing.

## Per-project manifest

Create `.anutron-install.config.json` at the target root to set non-interactive defaults:

```json
{
  "mode": "symlink",
  "scope": "spec-discipline",
  "includeSkills": ["my-extra-skill"],
  "excludeSkills": ["bugbash"],
  "includeSnippets": ["extra-snippet.md"],
  "excludeSnippets": ["010-git-workflow.md"]
}
```

- `mode` and `scope` — defaults used when no flag is passed.
- `includeSkills` / `excludeSkills` — add or drop skills from the resolved scope. `includeSkills` is the required input when `scope=custom`.
- `includeSnippets` / `excludeSnippets` — add or drop snippet files from the resolved set. `includeSnippets` is the required input when `scope=custom`.
- Unknown top-level keys trigger a warning but do not fail the install.
- Command-line flags always win over manifest values.

## Sharing with contributors

Use this flow to commit working skills into a repo so contributors get them on `git clone`, no source repo required.

1. In the target repo, run `/anutron-install --for-contributors`. This installs copy mode + spec-discipline scope.

2. Inspect the result before committing:
   - `.claude/skills/` — skill directories (regular files, not symlinks).
   - `.claude/hooks/` — hook scripts (regular files).
   - `.claude/settings.json` — verify `anutronInstalled` metadata and hook registrations look correct.
   - `CLAUDE.md` — verify the `BEGIN ANUTRON-INSTALL` … `END ANUTRON-INSTALL` block contains the expected spec/quality snippets.

3. Commit the entire produced tree so contributors get skills on clone:
   ```bash
   git add .claude/skills .claude/hooks .claude/settings.json CLAUDE.md
   git commit -m "Add anutron skills for spec-driven contribution workflow"
   ```
   Do **not** add `.claude/skills/` to `.gitignore` — committing is the whole point of copy mode.

4. (Optional) Add a `CONTRIBUTING.md` pointing contributors at `/brainstorm`, `/execute-plan`, and `/save-w-specs` as the intended workflow entry points.

5. To update later, re-run `/anutron-install --for-contributors` in the repo and commit any diffs. The post-install summary lists which skills changed since the last install (based on source commit tracking).

## Idempotent re-runs

Re-running with the same flags is safe at any time:

- **Copy mode** skips skills whose content hasn't changed. Each copied `SKILL.md` contains an `<!-- anutron-installed-from: <src>@<commit> -->` comment; if the commit matches, the copy is skipped.
- **Symlink mode** is a no-op for any skill whose symlink already points to the correct source path.
- `CLAUDE.md` always contains exactly one `BEGIN ANUTRON-INSTALL` block after a re-run.
- `.claude/settings.json` never contains duplicate hook command entries.

On a copy-mode re-run against a source that has advanced, the summary lists skills updated since the previous install.

## Uninstall

Run `/anutron-uninstall` to reverse everything the installer did.

## Locating the source repo

The installer resolves its source in priority order:

1. `ANUTRON_SOURCE` environment variable, if set.
2. `~/.claude/anutron-cache`, if it exists (plugin cache path).
3. Self-location: follows the symlink from the installed `install.sh` back to its real path, then walks up until a directory containing both `skills/` and `claude-rules/snippets/global/` is found.

If no source resolves, the installer exits non-zero and names all three options in the error message.
