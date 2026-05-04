## Plan execution handoff

After a plan is approved via `ExitPlanMode`, always:

1. If the project uses OpenSpec (`test -d openspec`), the plan should already live as `openspec/changes/<name>/tasks.md` — confirm the change folder is committed before handing off.
2. Show the execute command using the change NAME (not a path): `/execute-plan <name>`.
3. Use `AskUserQuestion` to ask how the user wants to proceed, with these two options:
   - **Execute in this session** — Run `/execute-plan` right here without clearing context (good for small plans or when current context is valuable).
   - **Copy to clipboard** (recommended) — Copy the `/execute-plan <name>` command to clipboard (`echo -n "/execute-plan <name>" | pbcopy`) and tell the user to run `/clear` and paste. Claude cannot execute `/clear` itself — it is a CLI command only the user can invoke.

**Plannotator-approved plans:** This same handoff fires automatically when a plan is approved via Plannotator (`/plannotator-specs` or `plannotator annotate`). The instructions are embedded in the approval message itself, configured at `{{PROJECT_DIR}}/configs/plannotator.json` (symlinked to `~/.plannotator/config.json`). Edit the JSON if the handoff steps change.
