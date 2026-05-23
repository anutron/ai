# Quick start

Four ways to adopt the toolkit, depending on how much commitment you want.

| If you want... | Use |
|----------------|-----|
| The full toolkit globally, auto-updating | Option A: full plugin |
| To try it in one folder without commitment | Option B: per-project plugin |
| Full control / fork / customize | Option C: clone + promote |
| To cherry-pick individual pieces | Option D: steal |

## Option A: Install as a plugin (recommended)

```
/plugin install claude-skills@anutron/claude-skills
```

Then run the setup wizard:

```
/claude-skills:setup
```

Setup walks you through interactively – rules, hooks, statusline. Pick what you want, skip what you don't. Skills are available immediately as `/claude-skills:<name>`.

**Updates:** Plugin updates happen automatically. When rules, hooks, or the statusline change, a session-start check nudges you to re-run `/claude-skills:setup` to refresh the installed copies.

## Option B: Try in a sandbox project (no global install)

Want to test-drive the toolkit without touching your global Claude Code config?

```
/plugin install anutron-install@anutron/claude-skills
```

Then, in any folder you want to try the kit:

```
/anutron-install
```

This installs everything – skills, hooks, compiled CLAUDE.md – **scoped to that folder only**. Your global `~/.claude/` is untouched. Run `/anutron-uninstall` when done to leave the folder exactly as it was.

Best for: trying things out in a throwaway project, per-project customization, or showing the toolkit to a teammate without changing your own setup.

## Option C: Clone and promote (manual)

For more control, or if you want skills without the `claude-skills:` namespace prefix:

**1. Clone the repo:**

```bash
git clone https://github.com/anutron/claude-skills.git ~/claude-skills
cd ~/claude-skills
```

**2. Install the rules** (compiles snippets into your `~/.claude/CLAUDE.md`):

```bash
./claude-rules/compile.sh link     # set up CLAUDE.md targets
./claude-rules/compile.sh compile  # builds from snippets
```

If you already have a `~/.claude/CLAUDE.md`, `link` asks how to handle it:

- **Replace** – backs up your file, symlinks to compiled output
- **Inject** – keeps your file, appends a managed section between begin/end markers that updates on recompile

See [claude-rules/README.md](../claude-rules/README.md) for details.

**3. Promote skills globally** – open Claude Code in this repo and run:

```
/promote
```

This compares the skills in `skills/` against `~/.claude/skills/`, classifies each one, and symlinks the ones you choose. After promotion, skills are available in every project. Updates are a `git pull` away.

**4. (Optional, terminal only) Install hooks and the status line.** See [session-topics.md](session-topics.md) and [skill-usage-tracking.md](skill-usage-tracking.md) for the setup snippets.

Steps 1–3 work in the terminal CLI, VS Code, JetBrains, and the desktop app. Step 4 is terminal-only – hooks and the status line rely on shell execution that IDE extensions don't support.

## Option D: Just steal what you like

Don't want the full toolkit? Grab `/steal` and use it to cherry-pick:

```
I want to use https://github.com/anutron/claude-skills/blob/main/skills/steal/SKILL.md – can you add this skill?
```

Then point it at this repo:

```
/steal https://github.com/anutron/claude-skills
```

This scans the repo and presents a report of what's worth stealing. You choose what to adopt – individual skills, patterns, or just ideas.
