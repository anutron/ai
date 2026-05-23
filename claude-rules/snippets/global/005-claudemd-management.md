---
tags: [personal]
audience: [aaron]
---
## CLAUDE.md Management

Both `~/.claude/CLAUDE.md` (global) and the project CLAUDE.md are **compiled from snippets** — never edit the CLAUDE.md files directly.

**Source of truth:** the `snippets/` directory in `claude-rules/`
- `snippets/global/*.md` → compiled into `~/.claude/CLAUDE.md`
- `snippets/project/*.md` → compiled into the project's CLAUDE.md

**Workflow:**
1. Edit or create a snippet in the appropriate `snippets/{global,project}/` directory
2. Run `compile.sh` (in `claude-rules/`) to regenerate the dist files
3. The CLAUDE.md files are symlinks to the compiled output — changes appear immediately

**Commands:**
- `compile.sh compile` — Rebuild both CLAUDE.md files from snippets
- `compile.sh promote <name>.md` — Move a snippet from project to global scope
- `compile.sh demote <name>.md` — Move a snippet from global to project scope
- `compile.sh list` — Show all snippets and their scope
- `compile.sh status` — Check if dist files were modified outside the snippet system

**Naming convention:** Snippets are numbered for ordering (e.g., `010-plan-formatting.md`, `040-tech-stack.md`). Use gaps to allow inserting new snippets without renumbering.

**Template Variables:**
Snippets can use `{{VAR}}`-style placeholders (double curly braces around an uppercase name) that compile.sh resolves during compilation.

Built-in variables — refer to these names when writing placeholders in snippets:
- `CLAUDE_RULES_DIR` — absolute path to the claude-rules directory
- `PROJECT_DIR` — absolute path to the project root (parent of claude-rules/)
- `PERSONAL_DIR` — absolute path to the personal-projects root (parent of PROJECT_DIR)
- `GLOBAL_TARGET` — absolute path to `~/.claude/CLAUDE.md`

Custom variables: define in `variables.env` (next to `compile.sh`), one per line (`KEY=value`). Values can reference other variables using the same placeholder syntax.

When editing or creating snippets, **always use template variables for paths** — never hardcode absolute paths. This keeps snippets portable and publishable.
