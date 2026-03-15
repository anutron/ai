# Claude Code Skills

My collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills. Steal what's useful.

## Usage

Copy any `SKILL.md` file into your project's `.claude/skills/<name>/SKILL.md` or your global `~/.claude/skills/<name>/SKILL.md`.

## Skills

| Skill | Description |
|-------|-------------|
| [bugbash](skills/bugbash/SKILL.md) | Interactive QA — report bugs conversationally, agents fix them in parallel using worktrees |
| [changelog](skills/changelog/SKILL.md) | Generate an intelligent changelog from recent commits |
| [debug](skills/debug/SKILL.md) | Multi-agent competing hypotheses debugging |
| [dev](skills/dev/SKILL.md) | Multi-agent iterative development with parallel testing and code review |
| [devils-advocate](skills/devils-advocate/SKILL.md) | Challenge your own plans — structured counter-arguments before committing to an approach |
| [disk-cleanup](skills/disk-cleanup/SKILL.md) | Scan local disk for large storage consumers and identify cleanup opportunities |
| [execute-plan](skills/execute-plan/SKILL.md) | Execute a plan with a team of agents, delegating to spare tokens in the main thread |
| [guard](skills/guard/SKILL.md) | Pre-commit safety check for secrets, security antipatterns, and test breakage |
| [handoff](skills/handoff/SKILL.md) | Generate a handoff prompt to pass context to another agent thread |
| [improve](skills/improve/SKILL.md) | End-of-session retrospective — upgrade skills, fix codebase gaps, capture durable knowledge |
| [list-skills](skills/list-skills/SKILL.md) | Quick reference of all available skills |
| [mcp-prune](skills/mcp-prune/SKILL.md) | Analyze active MCP servers and disable irrelevant ones for the current project |
| [merge](skills/merge/SKILL.md) | Merge current branch to master via GitHub PR merge |
| [nexonia-expenses](skills/nexonia-expenses/SKILL.md) | Browser automation for expense reports — reads receipts, builds line items, automates form entry |
| [pr](skills/pr/SKILL.md) | Open a PR, wait for CI, fix failures, address review comments, loop until green |
| [pr-dashboard](skills/pr-dashboard/SKILL.md) | Show open PRs, review requests, and recently closed PRs with age and status |
| [promote](skills/promote/SKILL.md) | Audit project skills and recommend which to promote to global |
| [rereview](skills/rereview/SKILL.md) | Re-review with fresh eyes — zero regressions, slow and thorough |
| [review](skills/review/SKILL.md) | Quick code review shorthand for current changes or a PR number |
| [save-w-specs](skills/save-w-specs/SKILL.md) | Save progress — update SPECs for behavioral changes, then commit |
| [skill-audit](skills/skill-audit/SKILL.md) | Analyze skill usage logs and recommend which to keep, prune, or consolidate |
| [test](skills/test/SKILL.md) | Intelligent test runner that targets changed code and identifies coverage gaps |
| [unstaged](skills/unstaged/SKILL.md) | Show uncommitted changes grouped by logical commit themes |
| [worktree](skills/worktree/SKILL.md) | Close a git worktree and merge it back to the main branch |
| [write-skill](skills/write-skill/SKILL.md) | Create or improve a Claude Code skill with best practices |

## Plugins I Use

These are the [Claude Code plugins](https://docs.anthropic.com/en/docs/claude-code/plugins) I have enabled. Most are from the official marketplace.

| Plugin | Source | What it does |
|--------|--------|-------------|
| **superpowers** | `claude-plugins-official` | Skill routing, brainstorming, TDD, plan writing/execution, systematic debugging, code review workflows |
| **feature-dev** | `claude-plugins-official` | Guided feature development with codebase understanding and architecture focus |
| **pr-review-toolkit** | `claude-plugins-official` | Comprehensive PR review using specialized agents (code review, type analysis, test coverage, silent failures) |
| **frontend-design** | `claude-plugins-official` | Distinctive, production-grade frontend interfaces — avoids generic AI aesthetics |
| **playground** | `claude-plugins-official` | Creates interactive single-file HTML playgrounds with live preview and controls |
| **commit-commands** | `claude-plugins-official` | Git workflow shortcuts — commit, push, PR creation, branch cleanup |
| **ralph-loop** | `claude-plugins-official` | Iterative development loop — run tests and fix until green |
| **github** | `claude-plugins-official` | GitHub MCP integration — issues, PRs, code search |
| **code-review** | `claude-code-plugins` | Code review for pull requests |
| **security-guidance** | `claude-code-plugins` | Security-focused code analysis |
