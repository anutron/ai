---
name: bash-style
description: Reference for bash patterns that trigger Claude Code permission guardrails (static-analysis flags that allowlist rules cannot silence). Load when about to run bash with `cd <repo> && git ...`, `$(...)`, backticks, heredocs, inline `python3 -c` / `node -e` / `ruby -e` / `perl -e`, multi-line shell logic with variables/conditionals, or before allowlisting a new script path. Also covers always-prompt verbs and the `git -C` known gap.
user_invocable: false
tags: [quality]
---

# Bash command style

Some bash patterns trigger Claude Code permission guardrails that **cannot be silenced by allowlist rules**. They are static-analysis flags, not pattern matches. Use the alternative forms below so commands run without prompting.

## Prefer `git -C <path>` over `cd <path> && git ...`

`cd <path> && git <subcommand>` is flagged: *"changes directory before running git, which can execute untrusted hooks."* Even with both subcommands allowed, the compound form prompts.

```bash
# Bad
cd /path/to/repo && git status

# Good
git -C /path/to/repo status
```

`Bash(git -C:*)` is auto-allowed.

## Avoid heredocs and `$(...)` in shell — use multiple `-m` or a tempfile

Any bash with `$(...)`, backticks, or heredocs is flagged *"shell syntax that cannot be statically analyzed."* Prompts every time, regardless of allowlist.

```bash
# Bad — heredoc + command substitution
git commit -m "$(cat <<'EOF'
Title

Body
EOF
)"

# Good — multiple -m flags, each becomes a paragraph
git commit -m "Title" -m "Body line 1" -m "Body line 2"
```

**Fallback** (tempfile, only when the message has markdown/code blocks/quoting that breaks inside `-m`):

Write to `/tmp/claude-commit-msgs/<repo>-<unix-timestamp>.txt` (collision-proof across parallel sessions), then `git commit -F <path>`. `Write(/tmp/claude-commit-msgs/**)` is globally allowlisted. Append `-<pid>` if you need sub-second uniqueness. The directory is OS-managed scratch; `find -mtime +7 -delete` for cleanup.

## Avoid inline multi-line scripts — put logic in a script file

If a task needs shell logic with variables, conditionals, or loops, **put it in a script file** under `.claude/bin/` (project) or `~/.claude/bin/` (global) and invoke that file with a simple command form. Allowlist the script path once and it never prompts again.

```bash
# Bad — inline multi-line with expansions
SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    printf '%s' "$TOPIC" > ~/.claude/session-topics/${SESSION_ID}.txt
fi

# Good — helper script
~/.claude/bin/set-session-topic.sh "$TOPIC"
```

## Never allowlist inline interpreter invocations

When Claude Code prompts for `python3 -c "<inline code>"`, the "don't ask again" option offers to allowlist that **exact code string**. Don't take it:

- Only matches that exact string. Any tweak re-prompts. You accumulate dozens of near-duplicate rules.
- Path-based trust on inline code with no `git diff` audit trail — the "script" lives in `settings.json`.

```bash
# Bad
jq -r '.htmlBody' thread.json | python3 -c "import sys, html, re; t=sys.stdin.read(); ..."

# Good — helper script with stable allowlistable path
jq -r '.htmlBody' thread.json | ~/.claude/bin/html-to-text.sh
```

Same rule for `node -e`, `ruby -e`, `perl -e`. If the logic doesn't fit in a one-token verb, it belongs in a script file.

## Safety guardrails for path-based script allowlists

The "use a helper script" pattern works **only** if the path is in version control. `git diff` is what makes the trust auditable. Otherwise the rule passes regardless of script content — Claude can rewrite the script and the trust still binds.

- **Required:** script must be tracked by git in a repo the user controls.
- **Required:** script must NOT be in a writable, untracked location (`/tmp/`, working dirs).
- **Recommended:** review script content before allowlisting (the `/trust-action` skill enforces this).
- **Recommended:** prefer absolute paths over `~/` for audit clarity.

## Always-prompt verbs

These verbs should always prompt — keep them in `ask`, never silence them:

- `rm` — irreversible deletion
- `curl`, `wget` — network egress; exfiltration vector
- `chown` — ownership changes
- `dd` — block-level operations
- `sudo` — privilege escalation
- `nc`, `ncat` — arbitrary network sockets

If you want to silence one: either script the operation, version-control it, and allowlist the script path; or accept the per-call prompt.

## Known gap: `git -C` is broadly allowed

`Bash(git -C:*)` is broadly allowed because it's the workaround for the `cd <repo> && git ...` flag. So `git -C <path> push --force` and `git -C <path> reset --hard` are not caught by the `git push --force` ask rules. Live with this — if you routinely run destructive `git -C` operations, add specific patterns to `ask`.

## Why this matters — the tradeoff

Each unnecessary permission prompt breaks flow. These patterns eliminate prompts that don't carry information.

But: **trivial-prompt fatigue makes you reflexively approve non-trivial prompts.** A user worn down by 20 `ls` approvals hits Y on `rm -rf <project>` without reading it. These patterns are for *eliminating prompts that genuinely don't carry information* — not workarounds to silence prompts you should still review.
