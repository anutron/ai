---
name: set-topic
description: Set the session topic displayed in the status line. Usage: /set-topic <topic text>
user_invocable: true
---

# Set Session Topic

Set the status line topic for this session.

## Instructions

1. Determine the topic text:
   - If the user provided text after `/set-topic`, use that exactly
   - If no text was provided, infer a short topic from the conversation context

2. The topic will be displayed in ALL CAPS in the status line. Write it in whatever case — the statusline uppercases it.

3. Keep it concise — the statusline allows up to ~60% of its width (~50 chars). Shorter is better. If too long, truncate intelligently (don't cut mid-word).

4. Set it by running this bash command:

```bash
SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    echo "<TOPIC_TEXT>" > ~/.claude/session-topics/${SESSION_ID}.txt
fi
```

5. Confirm to the user what was set. Keep it brief — one line.
