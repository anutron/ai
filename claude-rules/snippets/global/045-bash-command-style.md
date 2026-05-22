---
tags: [quality]
audience: [shared]
---
## Bash command style

These patterns trigger Claude Code permission guardrails that **cannot be silenced by allowlist rules in `settings.json`**. They are static-analysis flags, not pattern matches. Avoid them — use the alternative forms below so commands run without prompting.

### Prefer `git -C <path>` over `cd <path> && git ...`

Claude Code flags `cd <path> && git <subcommand>` as: *"This command changes directory before running git, which can execute untrusted hooks from the target directory."* Even when `Bash(cd:*)` and `Bash(git status:*)` are both allowed, the compound form prompts.

**Bad:**

```bash
cd /path/to/repo && git status
cd ~/repos/foo && git log --oneline -5
```

**Good:**

```bash
git -C /path/to/repo status
git -C ~/repos/foo log --oneline -5
```

`Bash(git -C:*)` is auto-allowed.

### Avoid heredocs and `$(...)` in shell — use a tempfile

Claude Code flags any bash with `$(...)`, backticks, or heredocs as *"Contains shell syntax that cannot be statically analyzed"* (or *"Contains simple_expansion"* if the expansion is shorter). Prompts every time, regardless of allowlist.

**Bad** (heredoc + command substitution for a multi-line commit message):

```bash
git commit -m "$(cat <<'EOF'
Title

Body line 1
Body line 2
EOF
)"
```

**Good** (multiple `-m` flags, each becoming a paragraph):

```bash
git commit -m "Title" -m "Body line 1" -m "Body line 2"
```

This is the primary form. No tempfile, no extra Write call, no permission prompt.

**Fallback** (tempfile, only when the message contains markdown/code blocks/quoting that breaks inside `-m`):

Write to `/tmp/claude-commit-msgs/<repo>-<unix-timestamp>.txt` (collision-proof across parallel Claude sessions), then commit with `-F`:

```bash
# Use the Write tool to create /tmp/claude-commit-msgs/ai-ron-1779385427.txt
git commit -F /tmp/claude-commit-msgs/ai-ron-1779385427.txt
```

`Write(/tmp/claude-commit-msgs/**)` is globally allowlisted. The directory is OS-managed scratch (auto-cleared on reboot); flat layout means `ls` and `find -mtime +7 -delete` for cleanup. Filename = `<repo>-<unix-timestamp>.txt`; append `-<pid>` if you somehow need sub-second uniqueness.

### Avoid inline multi-line scripts in skills and ad-hoc bash

If a skill (or any task) needs shell logic with variables, conditionals, or loops, **put it in a script file** under `.claude/bin/` (project) or `~/.claude/bin/` (global) and invoke that file with a simple command form. Allowlist the script path once and it never prompts again.

**Bad** (multi-line inline script with expansions):

```bash
SESSION_ID=$(cat ~/.claude/session-topics/pid-$PPID.map 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    printf '%s' "$TOPIC" > ~/.claude/session-topics/${SESSION_ID}.txt
fi
```

**Good** (helper script invoked simply):

```bash
~/.claude/bin/set-session-topic.sh "$TOPIC"
```

Add `Bash(~/.claude/bin/set-session-topic.sh:*)` to the allowlist once.

### Never allowlist inline interpreter invocations (`python3 -c`, `node -e`, `ruby -e`, `perl -e`)

When Claude Code prompts for `python3 -c "<inline code>"`, the "don't ask again" option offers to allowlist that **exact code string**. Don't take it. The rule is brittle in two ways:

- It only matches that exact string. Any tweak — a different regex, a different slice, a different attribute name — re-prompts. Over time you accumulate dozens of near-duplicate rules that each silence one variation.
- It's path-based trust on an inline script, **but worse** — the "script" lives in `settings.json`, not in version control. No `git diff` audit trail.

**Bad** (extracting plain text from HTML inline):

```bash
jq -r '.htmlBody' thread.json | python3 -c "import sys, html, re; t=sys.stdin.read(); t=re.sub(r'<[^>]+>',' ',t); t=html.unescape(t); print(re.sub(r'\s+',' ',t))"
```

**Good** (helper script with a stable, allowlistable path):

```bash
jq -r '.htmlBody' thread.json | ~/.claude/bin/html-to-text.sh
```

Allowlist `Bash(~/.claude/bin/html-to-text.sh:*)` once. The interpreter code lives in the script file — auditable, version-controlled, and any future caller benefits.

Same rule for `node -e '<inline JS>'`, `ruby -e '<inline Ruby>'`, `perl -e '<inline Perl>'`. If the logic doesn't fit in a one-token verb, it belongs in a script file.

### Why this matters — and the tradeoff

Each unnecessary permission prompt breaks flow. The patterns above eliminate prompts that don't carry information — the same operation, just a syntactic form Claude Code can statically verify.

But the flip side is real: **trivial-prompt fatigue makes you reflexively approve non-trivial prompts.** A user worn down by 20 `ls` approvals is exactly the user who'll hit Y on `rm -rf <project>` without reading it. So these patterns are for *eliminating prompts that genuinely don't carry information* — not for finding workarounds to silence prompts you should still review.

### Safety guardrails for path-based script allowlists

The "use a helper script" pattern works **only** if the path you allowlist is in version control. `git diff` is what makes the trust auditable. Without that, allowlisting `Bash(/path/to/script.sh:*)` becomes path-based trust that doesn't bind to content — Claude can rewrite the script, the rule still passes, and you have no audit trail.

Rules of thumb when allowlisting a script path:

- **Required:** the script must be tracked by git in a repo you control.
- **Required:** the script must NOT be in a location with broad `Write` access AND no version control (e.g. `/tmp/`, `/private/tmp/`, working directories).
- **Recommended:** review the script content before allowlisting. The `/trust-action` skill enforces this — it refuses to allowlist scripts in temporary locations or untracked files, and shows script content for review before adding any path-based rule.
- **Recommended:** prefer absolute paths over `~/`. Absolute paths are unambiguous in audits.

### Always-prompt verbs

A short list of bash verbs should always prompt, regardless of allowlist — keep them in the `ask` list:

- `rm` — irreversible deletion
- `curl`, `wget` — network egress; exfiltration vector
- `chown` — ownership changes
- `dd` — block-level operations
- `sudo` — privilege escalation
- `nc`, `ncat` — arbitrary network sockets

If you find yourself wanting to silence these, the right answer is almost never "broaden the allowlist." It's either: (a) script the operation, version-control the script, and allowlist the script path (which retains the audit trail), or (b) accept the per-call prompt.

### Known gap

`Bash(git -C:*)` is broadly allowed because `git -C` is the workaround for the `cd <repo> && git ...` static-analysis flag. This means `git -C <path> push --force` and `git -C <path> reset --hard` are not caught by the `git push --force` ask rules. Live with this — if you find yourself routinely running destructive `git -C` operations through Claude, add specific patterns to `ask` at that point.
