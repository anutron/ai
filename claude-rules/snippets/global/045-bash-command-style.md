---
tags: [quality]
audience: [shared]
---
## Bash command style

Some bash patterns trigger Claude Code permission guardrails that allowlist rules cannot silence. Core rules to keep commands running without prompts:

- Use `git -C <path>` instead of `cd <path> && git ...`
- No `$(...)`, backticks, or heredocs — prefer `git commit -m "Title" -m "Body"`, or write to `/tmp/claude-commit-msgs/<repo>-<unix-ts>.txt` and `git commit -F`
- No inline multi-line shell — put logic in `.claude/bin/` or `~/.claude/bin/` scripts and allowlist the path
- Never allowlist `python3 -c '...'`, `node -e '...'`, `ruby -e '...'`, `perl -e '...'` — script it instead
- Always-prompt verbs (`rm`, `curl`, `wget`, `chown`, `dd`, `sudo`, `nc`) stay in `ask`

Load the `bash-style` skill for examples, the safety guardrails on path-based allowlisting, and the `git -C` known gap.
