---
name: set-topic
description: Set the session topic displayed in the status line. Usage: /set-topic <topic text>
user_invocable: true
tags: [personal]
---

# Set Session Topic

Set the status line topic for this session.

## Instructions

0. **Preflight checks.** Verify the reminder hook and the helper script exist:

```bash
[ -x ~/.claude/hooks/remind-session-topic.sh ] || echo "MISSING: remind-session-topic.sh hook is not installed. Session topics will not be enforced."
[ -x ~/.claude/bin/set-session-topic.sh ] || echo "MISSING: ~/.claude/bin/set-session-topic.sh helper is not installed. Run /setup to install user-env tooling. Falling back to inline bash (may trigger permission prompts)."
```

Print whichever warnings fire, then continue. Do not block.

1. Parse the arguments:
   - `--initial <text>` — set only if no topic exists yet. If a topic is already set, exit silently (no output, no confirmation).
   - `<text>` (no flag) — set unconditionally. This is the user overriding the topic.
   - No text provided — infer a short topic from the conversation context, set unconditionally.

2. Keep it concise (under ~50 chars). The statusline renders it in ALL CAPS.

3. Write the topic.

**Preferred path — call the installed helper:**

```bash
~/.claude/bin/set-session-topic.sh --initial "TOPIC_TEXT_HERE"
```

```bash
~/.claude/bin/set-session-topic.sh "TOPIC_TEXT_HERE"
```

The helper handles both PID→SESSION_ID resolution and the `--initial` no-op case internally.

**Fallback path — only if the helper is missing.** Use the inline form (this triggers `Contains simple_expansion` prompts; the warning in step 0 should have told the user to run `/setup`):

For `--initial`:
```bash
SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    TOPIC_FILE=~/.claude/session-topics/${SESSION_ID}.txt
    if [ -s "$TOPIC_FILE" ]; then
        exit 0
    fi
    printf '%s' "TOPIC_TEXT_HERE" > "$TOPIC_FILE"
fi
```

For unconditional (no `--initial`):
```bash
SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    printf '%s' "TOPIC_TEXT_HERE" > ~/.claude/session-topics/${SESSION_ID}.txt
fi
```

4. For `--initial`: say nothing. For unconditional sets: confirm what was set in one line.
