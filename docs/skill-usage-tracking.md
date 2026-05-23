# Skill usage tracking

Three hooks work together to give you full visibility into which skills get used and how:

| Hook | Trigger | Logs to | What it tracks |
|------|---------|---------|----------------|
| [log-slash-command.sh](../hooks/log-slash-command.sh) | `UserPromptSubmit` | `~/.claude/skill-usage.tsv` | User-typed `/commands` |
| [log-skill-use.sh](../hooks/log-skill-use.sh) | `PostToolUse` (Skill) | `~/.claude/skill-usage.tsv` | Skill tool invocations |
| [log-skill-read.sh](../hooks/log-skill-read.sh) | `PostToolUse` (Read) | `~/.claude/skill-reads.tsv` | Read tool accesses to skill files |

The first two track direct invocations – when you type `/brainstorm` or a skill calls another skill via the Skill tool. The third tracks *dependency reads* – when a skill like `/execute-plan` reads `agent-driven-development/SKILL.md` as a reference document without formally invoking it. This is important because some skills are never invoked directly but are foundational dependencies loaded by other skills.

## Setup

```bash
# Copy hooks
cp hooks/log-skill-use.sh ~/.claude/hooks/
cp hooks/log-slash-command.sh ~/.claude/hooks/
cp hooks/log-skill-read.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/log-skill-use.sh ~/.claude/hooks/log-slash-command.sh ~/.claude/hooks/log-skill-read.sh
```

Register in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/log-slash-command.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/log-skill-use.sh" }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/log-skill-read.sh" }
        ]
      }
    ]
  }
}
```

## Log formats

**`skill-usage.tsv`** (invocations):

```
timestamp	skill	args	project
2026-04-14T18:53:45Z	brainstorm		/Users/you/my-project
```

**`skill-reads.tsv`** (dependency reads):

```
timestamp	skill	skill_path	project
2026-04-14T19:01:12Z	agent-driven-development	/Users/you/.claude/skills/agent-driven-development/SKILL.md	/Users/you/my-project
```

The `skill_path` column tells you which sub-file was read (e.g., `SKILL.md` vs `implementer-prompt.md`), so you can see whether a parent skill loaded just the description or pulled in full prompt templates.

## Analysis

After a few weeks of data, run `/skill-audit` to get a full report: frequency tables, recency, project distribution, trend analysis, and pruning recommendations. The audit cross-references both logs to distinguish skills that are "never invoked but load-bearing" from truly unused ones.
