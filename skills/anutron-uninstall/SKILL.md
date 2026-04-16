---
name: anutron-uninstall
description: Uninstall the anutron (claude-skills) kit from the current project — reverses everything /anutron-install did.
---

# anutron-uninstall

Run the uninstaller script from this skill's directory. It reads the breadcrumb and reverses every install operation.

```bash
bash "$(dirname "$SKILL_PATH")/uninstall.sh"
```

Print the script's output directly to the user. The script produces a clear summary of what was removed.

If the script exits non-zero, show the error output. Common case: breadcrumb missing means anutron isn't installed (or was already uninstalled).
