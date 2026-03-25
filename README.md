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
| [fixit](skills/fixit/SKILL.md) | Fire-and-forget bug fix — backgrounds an agent in a worktree to fix and merge back |
| [guard](skills/guard/SKILL.md) | Pre-commit safety check for secrets, security antipatterns, and test breakage |
| [handoff](skills/handoff/SKILL.md) | Generate a handoff prompt to pass context to another agent thread |
| [interview](skills/interview/SKILL.md) | Structured interview-style review of any system, feature, or codebase — walks through items one-by-one in small chunks, tracks progress, captures decisions as artifacts |
| [improve](skills/improve/SKILL.md) | End-of-session retrospective — upgrade skills, fix codebase gaps, capture durable knowledge |
| [list-skills](skills/list-skills/SKILL.md) | Quick reference of all available skills |
| [mcp-prune](skills/mcp-prune/SKILL.md) | Analyze active MCP servers and disable irrelevant ones for the current project |
| [merge](skills/merge/SKILL.md) | Merge current branch to master via GitHub PR merge |
| [plannotator-specs](skills/plannotator-specs/SKILL.md) | Interactive spec review via Plannotator — review with inline annotations before committing |
| [pr](skills/pr/SKILL.md) | Open a PR, wait for CI, fix failures, address review comments, loop until green |
| [pr-dashboard](skills/pr-dashboard/SKILL.md) | Show open PRs, review requests, and recently closed PRs with age and status |
| [pr-respond](skills/pr-respond/SKILL.md) | Read PR review feedback, triage each comment (adopt/reject with reasoning), optionally apply changes and commit |
| [promote](skills/promote/SKILL.md) | Audit project skills and recommend which to promote to global |
| [rereview](skills/rereview/SKILL.md) | Re-review with fresh eyes — zero regressions, slow and thorough |
| [review](skills/review/SKILL.md) | Quick code review shorthand for current changes or a PR number |
| [save-w-specs](skills/save-w-specs/SKILL.md) | Save progress — spec-aware commit that verifies specs were updated alongside behavioral changes |
| [set-topic](skills/set-topic/SKILL.md) | Set the session topic displayed in the status line — pairs with [statusline.sh](bin/statusline.sh) |
| [skill-audit](skills/skill-audit/SKILL.md) | Analyze skill usage logs and recommend which to keep, prune, or consolidate |
| [test](skills/test/SKILL.md) | Intelligent test runner that targets changed code and identifies coverage gaps |
| [unstaged](skills/unstaged/SKILL.md) | Show uncommitted changes grouped by logical commit themes |
| [upload-notion-image](skills/upload-notion-image/SKILL.md) | Upload local images to Notion pages natively via the Notion API file upload flow |
| [worktree](skills/worktree/SKILL.md) | Close a git worktree and merge it back to the main branch |
| [write-skill](skills/write-skill/SKILL.md) | Create or improve a Claude Code skill with best practices |

## Extras

| File | Description |
|------|-------------|
| [statusline.sh](bin/statusline.sh) | Custom Claude Code status line — context bar, git status, session topic, and terminal title |

The status line displays a **session topic** that Claude sets via the [set-topic](skills/set-topic/SKILL.md) skill. The statusline writes a PID-to-session mapping on each render; `/set-topic` writes the topic text to the same directory (`~/.claude/session-topics/`). Both pieces are needed for session topics to work.

To use the status line, point your Claude Code settings at it:
```json
{
  "statusLine": ".claude/bin/statusline.sh"
}
```

## Hooks

Shell scripts that run as [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) to log skill usage for analysis.

| Hook | Trigger | Description |
|------|---------|-------------|
| [log-skill-use.sh](hooks/log-skill-use.sh) | `PostToolUse` (matcher: `Skill`) | Logs every Skill tool invocation to `~/.claude/skill-usage.tsv` |
| [log-slash-command.sh](hooks/log-slash-command.sh) | `UserPromptSubmit` | Logs user-typed `/commands` to the same TSV (deduplicates with the above) |

### Setup

1. Copy the hooks somewhere persistent (e.g., `~/.claude/hooks/`):
   ```bash
   mkdir -p ~/.claude/hooks
   cp hooks/log-skill-use.sh hooks/log-slash-command.sh ~/.claude/hooks/
   chmod +x ~/.claude/hooks/log-skill-use.sh ~/.claude/hooks/log-slash-command.sh
   ```

2. Register them in `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "~/.claude/hooks/log-slash-command.sh"
             }
           ]
         }
       ],
       "PostToolUse": [
         {
           "matcher": "Skill",
           "hooks": [
             {
               "type": "command",
               "command": "~/.claude/hooks/log-skill-use.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. Use the [skill-audit](skills/skill-audit/SKILL.md) skill to analyze the collected data after a few weeks.

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
