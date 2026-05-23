# Session topics

The [set-topic](../skills/set-topic/SKILL.md) skill lets Claude (or you) set a session topic that displays in the [status line](../bin/statusline.sh). The [remind-session-topic](../hooks/remind-session-topic.sh) hook ensures Claude actually does it – it fires after every response and reminds Claude to set the topic if one isn't set yet, escalating after 5 turns.

## How it works

- Claude sets the topic via `/set-topic --initial <topic>` when it has enough context. The `--initial` flag no-ops if a topic is already set, so Claude can't overwrite it.
- The `Stop` hook checks after each response whether a topic exists. If not, it injects a reminder. After 5 turns it gets firm.
- You can override the topic anytime with `/set-topic <text>` (no `--initial` flag).

## Setup

**1. Install the hook:**

```bash
cp hooks/remind-session-topic.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/remind-session-topic.sh
```

**2. Register the hook** in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/remind-session-topic.sh"
          }
        ]
      }
    ]
  }
}
```

**3. Add the rule** to your CLAUDE.md (or use the [snippet](../claude-rules/snippets/global/055-session-topics.md)):

```markdown
## Session Topics

When you have enough context to understand what the session is about, set the topic
by invoking `/set-topic --initial <topic>`. Do this silently – don't announce it.

- Keep it concise (under ~50 chars). It renders in ALL CAPS.
- `--initial` no-ops if a topic is already set, so you cannot accidentally overwrite it.
- Do not invoke `/set-topic` more than once. Only the user can change the topic after it's set.
- If the system reminds you to set a topic, do it on your next response.
```

**4. (Optional) Install the [statusline](../bin/statusline.sh)** to actually display the topic.

## Validation

The `/set-topic` skill checks for the hook on every invocation. If the hook is missing, it prints a warning with a link to setup instructions. This surfaces the misconfiguration the first time Claude tries to set a topic.
