---
name: anutron-install
description: Install the anutron (claude-skills) toolkit into the current project via a cached clone — thin wrapper that keeps the repo up to date and delegates to the main installer.
---

# anutron-install (plugin wrapper)

This is the plugin-distributed version of `/anutron-install`. It clones the claude-skills repo to a local cache on first run, keeps it current on subsequent runs, then delegates to the real installer.

## Instructions

Run `install-wrapper.sh` from this skill's directory. It handles cloning/updating the cache and invoking the main `install.sh`. Print its output verbatim to the user.

```bash
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SKILL_DIR/install-wrapper.sh"
```

If the script exits non-zero, show the error output to the user and suggest:
- Check network connectivity (first run requires `git clone`)
- Try again (transient failures)
- Fall back to manual clone: `git clone https://github.com/anutron/claude-skills ~/.claude/anutron-cache`
