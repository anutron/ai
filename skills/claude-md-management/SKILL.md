---
name: claude-md-management
description: Reference for editing CLAUDE.md content – snippet locations, naming convention, template variables, and compile.sh commands (compile/promote/demote/list/status). Load when the user wants to add, edit, or reorganize CLAUDE.md rules, or move a rule between global and project scope.
user_invocable: false
tags: [personal]
---

# CLAUDE.md management

Both `~/.claude/CLAUDE.md` (global) and the project CLAUDE.md are compiled from snippets in `claude-rules/snippets/` – never edit the CLAUDE.md files directly.

- `snippets/global/*.md` → `~/.claude/CLAUDE.md`
- `snippets/project/*.md` → project's CLAUDE.md

Edit a snippet, then run `compile.sh`. CLAUDE.md files are symlinks to the compiled output.

## Commands

- `compile.sh compile` – rebuild both CLAUDE.md files
- `compile.sh promote <name>.md` – move snippet from project to global
- `compile.sh demote <name>.md` – move snippet from global to project
- `compile.sh list` – show all snippets and their scope
- `compile.sh status` – check for out-of-band edits to dist files

## Naming

Numbered for ordering (`010-...`, `040-...`); leave gaps.

## Template variables

`{{VAR}}` placeholders resolved at compile time. Always use these for paths – never hardcode.

Built-in:

- `CLAUDE_RULES_DIR` – absolute path to the claude-rules directory
- `PROJECT_DIR` – absolute path to the project root (parent of claude-rules/)
- `PERSONAL_DIR` – absolute path to the personal-projects root (parent of PROJECT_DIR)
- `GLOBAL_TARGET` – absolute path to `~/.claude/CLAUDE.md`

Custom: define in `variables.env` next to `compile.sh` as `KEY=value`, one per line. Values may reference other variables.
