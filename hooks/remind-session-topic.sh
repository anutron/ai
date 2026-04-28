#!/bin/bash
# UserPromptSubmit hook: injects a system-reminder prompting Claude to call
# /set-topic --initial once the session has enough context, if no topic is
# set yet. stdout from UserPromptSubmit hooks is added to Claude's context
# for the current turn, so this is effective enforcement (not just a toast).
#
# Sub-agents are excluded automatically: the pid-$PPID.map file is only
# written by statusline.sh, which doesn't render for sub-agents. If the
# map doesn't exist, this script exits silently.

SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

TOPIC_FILE=~/.claude/session-topics/${SESSION_ID}.txt

# Topic already set — nothing to do.
[ -s "$TOPIC_FILE" ] && exit 0

# Track turns in this session.
COUNTER_FILE=~/.claude/session-topics/${SESSION_ID}.turn-count
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$COUNTER_FILE"

# Inject a system-reminder starting on turn 3 — by then there's usually
# enough context to infer a topic. Before that, stay silent so short
# throwaway sessions aren't nagged.
if [ "$COUNT" -ge 3 ]; then
    cat <<'EOF'
<system-reminder>
The session topic has not been set. Before responding, call /set-topic --initial <topic> with a concise topic (under ~50 chars) inferred from the conversation so far. This is a standing instruction from the user — do not skip or announce it; just set the topic and continue with the user's request.
</system-reminder>
EOF
fi

exit 0
