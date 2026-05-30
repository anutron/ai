---
tags: [spec]
audience: [shared]
---
## Plan execution handoff

After a plan is approved via `ExitPlanMode`:

1. If OpenSpec (`test -d openspec`), confirm `openspec/changes/<name>/tasks.md` is committed.
2. Show: `/execute-plan <name>` (use the change NAME, not a path).
3. `AskUserQuestion` with two options:
   - **Execute in this session** – run `/execute-plan` here without clearing context.
   - **Copy to clipboard** (recommended) – `echo -n "/execute-plan <name>" | pbcopy`, then tell the user to run `/clear` and paste. Claude cannot execute `/clear` itself – only the user can.

**Plannotator-approved plans:** same handoff fires automatically, configured at `{{PROJECT_DIR}}/configs/plannotator.json` (symlinked to `~/.plannotator/config.json`).
