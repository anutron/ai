---
name: anutron-uninstall
description: Uninstall the anutron (claude-skills) kit from the current project — reverses everything /anutron-install did.
tags: [personal]
---

# anutron-uninstall

Reverses everything `/anutron-install` wrote into the current working directory. Reads `.anutron-install.json` (the breadcrumb) to know exactly what to undo. Mode-aware: behaviour differs based on how the original install was done.

## How to invoke

```bash
bash "$(dirname "$SKILL_PATH")/uninstall.sh"
```

Print the script's output directly to the user. If the script exits non-zero, show the error. The most common cause is a missing breadcrumb — anutron is not installed, or was already uninstalled.

## What it undoes

- **Skills** — removed according to the install mode recorded in the breadcrumb:
  - `mode=symlink` — each `.claude/skills/<name>` symlink is `rm`'d; source files are untouched.
  - `mode=copy` — each `.claude/skills/<name>` directory is `rm -rf`'d.
  - Legacy breadcrumb (no `mode` field) — falls back to the safest combined behaviour: `rm -f` for symlinks and regular files; directories are skipped to avoid data loss.
- **Hook scripts** — same mode-aware logic applied to `.claude/hooks/` files.
- **`CLAUDE.md`** — the `BEGIN ANUTRON-INSTALL` … `END ANUTRON-INSTALL` block is stripped; everything outside that block is preserved. If the file is empty (or contained only the anutron block), it is deleted.
- **`.claude/settings.json`** — the `anutronInstalled` key is removed, and only the hook command entries that the breadcrumb recorded as anutron-owned are stripped from the `hooks` object. All other user keys are preserved.
- **Breadcrumb** — `.anutron-install.json` is deleted as the final step.

## Idempotent

Running a second time after a clean uninstall exits cleanly with a "not installed" message (breadcrumb not found). No partial state is left behind.
