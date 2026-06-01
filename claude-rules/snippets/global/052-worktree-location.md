---
tags: [spec]
audience: [shared]
---
## Worktree location

**Applies to:** spec-driven projects (those with an `openspec/` directory; detect with `test -d openspec`).

Place git worktrees in `.claude/worktree/` within the project root.

**First-time setup:** if `.claude/worktree/` is missing, create it and append `.claude/worktree/` to `.gitignore`.
