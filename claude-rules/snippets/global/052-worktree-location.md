---
tags: [spec]
audience: [shared]
---
## Worktree Location

**Applies to:** Any project with a `.specs` file (spec-driven projects).

When creating git worktrees (via `/close-worktree`, the Agent tool with `isolation: "worktree"`, or any other mechanism), place them in `.claude/worktree/` within the project root.

**First-time setup:** If `.claude/worktree/` does not exist in the project:
1. Inform the user: "This project doesn't have a `.claude/worktree/` directory yet -- creating it and adding to `.gitignore`."
2. Create the directory
3. Add `.claude/worktree/` to the project's `.gitignore` (append if not already present)

This keeps worktrees co-located with the project instead of scattered in `/tmp` or other locations.
