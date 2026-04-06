#!/bin/bash
# Stop hook: reminds Claude to set a session topic if one isn't set yet.
# After 5 turns without a topic, the reminder becomes firm.

SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

TOPIC_FILE=~/.claude/session-topics/${SESSION_ID}.txt

# Topic already set — nothing to do
[ -s "$TOPIC_FILE" ] && exit 0

# Track turns
COUNTER_FILE=~/.claude/session-topics/${SESSION_ID}.turn-count
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -ge 5 ]; then
    echo "You have not set the session topic yet. Run /set-topic --initial now."
else
    echo "Reminder: set the session topic when you have enough context. Use /set-topic --initial <topic>."
fi
