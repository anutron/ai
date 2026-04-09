# claude-rules: Snippet-Based CLAUDE.md Management

A compilation system for managing Claude Code's `CLAUDE.md` instruction files using modular, numbered snippets instead of monolithic markdown files.

## Why

`CLAUDE.md` files grow fast. Once you have 20+ rules covering formatting, git workflow, testing, spec-driven development, and project-specific conventions, a single file becomes hard to maintain. You lose track of what's in there, edits break neighboring sections, and sharing rules across projects means copy-pasting.

**claude-rules solves this** by splitting instructions into small, numbered snippet files that get compiled into your `CLAUDE.md` files automatically. Each snippet is a self-contained rule you can add, remove, reorder, or share independently.

## How It Works

```
claude-rules/
├── compile.sh              # The compiler
├── variables.env           # Custom template variables
├── snippets/
│   ├── global/             # → compiled into ~/.claude/CLAUDE.md
│   │   ├── 010-claudemd-management.md
│   │   ├── 020-plan-formatting.md
│   │   ├── 030-interaction-prefs.md
│   │   └── ...
│   └── project/            # → compiled into <project>/CLAUDE.md
│       ├── 010-communication-style.md
│       ├── 020-documentation.md
│       └── ...
└── dist/                   # Generated output (gitignored)
    ├── global.md
    └── project.md
```

- **Global snippets** become `~/.claude/CLAUDE.md` — instructions that apply to every project
- **Project snippets** become `<your-project>/CLAUDE.md` — instructions specific to one repo

The compiled files are symlinked to their target locations, so changes appear immediately after recompiling.

## Setup

1. **Copy `claude-rules/` into your project root** (or clone this repo and symlink it)

2. **Link the compiled output to where Claude Code reads it:**
   ```bash
   ./claude-rules/compile.sh link
   ```

   If you already have a `~/.claude/CLAUDE.md`, the script asks how you want to handle it:

   - **Replace** — backs up your file (`.bak.YYYYMMDD`), then symlinks to the compiled output. Your existing content is replaced entirely.
   - **Inject** — keeps your file intact and appends a managed section between `<!-- BEGIN/END claude-rules -->` markers. Only the managed section updates on recompile. Your own rules stay untouched.

   If no existing file is found, it symlinks directly (nothing to preserve).

3. **Compile:**
   ```bash
   ./claude-rules/compile.sh compile
   ```

   In inject mode, `compile` automatically updates the managed section in your CLAUDE.md files.

## Usage

### Adding a snippet

Create a new `.md` file in `snippets/global/` or `snippets/project/`:

```bash
# Add a new global rule
cat > claude-rules/snippets/global/045-code-style.md << 'EOF'
## Code Style

- Use 2-space indentation
- Prefer `const` over `let`
- No semicolons in TypeScript
EOF

# Recompile
./claude-rules/compile.sh compile
```

### Numbering convention

Snippets are sorted alphabetically, so the numeric prefix controls order:
- Use gaps (010, 020, 030...) so you can insert new snippets without renumbering
- Example: to add something between 020 and 030, name it 025

### Commands

| Command | Description |
|---------|-------------|
| `compile.sh compile` | Rebuild both CLAUDE.md files from snippets |
| `compile.sh compile --force` | Rebuild even if external modifications are detected |
| `compile.sh link` | Create symlinks from target locations to dist files |
| `compile.sh status` | Check if dist files were modified outside the snippet system |
| `compile.sh promote <name>.md` | Move a snippet from project to global scope |
| `compile.sh demote <name>.md` | Move a snippet from global to project scope |
| `compile.sh list` | Show all snippets and their scope |

### Promote / Demote

Start a rule as project-specific, then promote it to global when you realize it applies everywhere:

```bash
# This project rule is useful everywhere — promote it
./claude-rules/compile.sh promote 025-error-handling.md

# This global rule only makes sense here — demote it
./claude-rules/compile.sh demote 045-code-style.md
```

### Drift detection

If someone (or Claude) edits the compiled `CLAUDE.md` directly, `compile.sh` detects it:

```bash
./claude-rules/compile.sh status
# WARNING: global (~/.claude/CLAUDE.md) was modified since last compile.
# Changes made outside the snippet system:
# [diff output]
```

Running `compile` will refuse to overwrite until you incorporate the changes into snippets (or use `--force`).

## Template Variables

Snippets can use `{{VARIABLE}}` placeholders that get resolved during compilation.

### Built-in variables

| Variable | Value |
|----------|-------|
| `{{CLAUDE_RULES_DIR}}` | Absolute path to the `claude-rules/` directory |
| `{{PROJECT_DIR}}` | Absolute path to the project root (parent of `claude-rules/`) |
| `{{GLOBAL_TARGET}}` | `~/.claude/CLAUDE.md` |

### Custom variables

Define additional variables in `variables.env`:

```bash
# variables.env
SETUP_GUIDE={{PROJECT_DIR}}/SETUP.md
SKILLS_DIR={{PROJECT_DIR}}/.claude/skills
```

Values can reference built-in variables or previously defined custom variables. Use `{{VARIABLE_NAME}}` in your snippets and they'll be replaced with the resolved value at compile time.

## Included Snippets

### Global (apply to all projects)

| Snippet | Purpose |
|---------|---------|
| `010-claudemd-management` | Self-referential: tells Claude how the snippet system works |
| `020-plan-formatting` | Markdown formatting rules for plans, reports, specs |
| `030-interaction-prefs` | Question-by-question and step-by-step interaction style |
| `040-plan-execution-handoff` | How to hand off approved plans for execution |
| `050-git-workflow` | Commit-per-turn workflow and spec pre-commit hook |
| `060-plannotator-spec-review` | Review loop for specs using Plannotator |
| `070-testing` | TDD approach and framework recommendations |
| `080-spec-driven-dev` | Full SPEC-first development methodology |
| `090-plan-archiving` | Archive approved plans in `specs/plans/` |

### Project (apply to one repo)

| Snippet | Purpose |
|---------|---------|
| `010-communication-style` | Opinionated, decisive recommendations |
| `020-documentation` | Documentation requirements for apps |
| `030-working-directory` | Ephemeral scratch file conventions |
| `040-skill-naming` | Skill prefix conventions for publishability |

## How It Pairs with Skills and Specs

The claude-skills repo provides three complementary systems:

- **Rules** (this system) — *How* Claude should work: formatting, git workflow, interaction style, development methodology
- **Skills** (`skills/`) — *What* Claude can do: reusable slash commands for development, testing, deployment
- **Specs** (via the spec-driven-dev snippet) — *What to build*: the contract that drives implementation

Rules are always active (compiled into CLAUDE.md). Skills are invoked on demand. Specs are the source of truth for each feature.
