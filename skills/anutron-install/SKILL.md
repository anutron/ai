---
name: anutron-install
description: Install the anutron (claude-skills) kit into the current project — symlinks skills, registers hooks, compiles CLAUDE.md from snippets.
---

# anutron-install

Run the installer script from this skill's directory. It handles everything end-to-end.

```bash
bash "$(dirname "$SKILL_PATH")/install.sh"
```

Print the script's output directly to the user. The script produces a clear summary distinguishing first-install from update.

If the script exits non-zero, show the error output and suggest fixes based on the error message.
