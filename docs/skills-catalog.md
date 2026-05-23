# Skills catalog

The skills in this toolkit, grouped by purpose. Spec-driven development has its own catalog in [spec-driven-development.md](spec-driven-development.md); this doc covers everything else.

## Development

| Skill | Description |
|-------|-------------|
| [kickoff](../skills/kickoff/SKILL.md) | Use when starting a brand new project from scratch – runs discovery, picks a tech stack tier, then hands off to brainstorm and build |
| [brainstorm](../skills/brainstorm/SKILL.md) | You MUST use this before any creative work – creating features, building components, adding functionality, or modifying behavior |
| [execute-plan](../skills/execute-plan/SKILL.md) | Use when you have an approved plan ready to implement – agent-driven development, worktree isolation, TDD, two-stage review |
| [fixit](../skills/fixit/SKILL.md) | Use when the user reports a bug that can be fixed without blocking their current work – backgrounds an agent in a worktree |
| [test](../skills/test/SKILL.md) | Use after writing or modifying code to run targeted tests and identify coverage gaps, before claiming code works |
| [debug](../skills/debug/SKILL.md) | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes – multi-agent competing hypotheses |
| [bugbash](../skills/bugbash/SKILL.md) | Use when the user wants to do a QA session or report multiple bugs – agents fix them in parallel |
| [guard](../skills/guard/SKILL.md) | Use before any git commit to check for secrets, security antipatterns, and test breakage |
| [unstaged](../skills/unstaged/SKILL.md) | Use when the user wants to see what's changed or plan commits – groups by logical commit themes |
| [close-worktree](../skills/close-worktree/SKILL.md) | Use when done working in a git worktree and ready to merge it back to the main branch |
| [review](../skills/review/SKILL.md) | Use when the user asks to review code, review current changes, or review a PR number |
| [rereview](../skills/rereview/SKILL.md) | Use when a previous review missed something or the user wants a thorough second pass – zero regressions |

## Discipline and orchestration

These skills describe how agents should think and work. They're loaded by reference when other skills need them – not typically invoked directly.

| Skill | Description |
|-------|-------------|
| [agent-driven-development](../skills/agent-driven-development/SKILL.md) | Use when executing implementation plans with independent tasks – worktree isolation, TDD discipline, two-stage review |
| [test-driven-development](../skills/test-driven-development/SKILL.md) | Use when implementing any feature or bugfix, before writing implementation code |
| [verification-before-completion](../skills/verification-before-completion/SKILL.md) | Use when about to claim work is complete, before committing or creating PRs – evidence before assertions always |
| [tp](../skills/tp/SKILL.md) | CLI for checkbox flips and one-line status annotations in markdown task lists (`tasks.md`, test plans) – much cheaper than Read+Edit per tick. Ships source + prebuilt macOS arm64 binary at [bin/tp/](../bin/tp/) |

## Git and PR

| Skill | Description |
|-------|-------------|
| [pr](../skills/pr/SKILL.md) | Use when code is ready to ship – opens a PR, waits for CI, fixes failures, addresses review comments, loops until green |
| [pr-respond](../skills/pr-respond/SKILL.md) | Use when a PR has received review comments – triages each comment (adopt/reject with reasoning) |
| [pr-dashboard](../skills/pr-dashboard/SKILL.md) | Use when the user asks about PR status, open PRs, or review requests |
| [merge](../skills/merge/SKILL.md) | Use when the user wants to merge the current branch to master – merges via GitHub PR |
| [changelog](../skills/changelog/SKILL.md) | Use when the user asks for a changelog, release notes, or summary of recent changes |

## General

| Skill | Description |
|-------|-------------|
| [interview](../skills/interview/SKILL.md) | Use when the user wants to systematically review, audit, or evaluate something – builds an inventory, walks through items one-by-one |
| [devils-advocate](../skills/devils-advocate/SKILL.md) | Use when the user wants to stress-test an idea, plan, or approach – challenges assumptions and finds weaknesses |
| [improve](../skills/improve/SKILL.md) | Use at the end of a session to run a retrospective – upgrades skills, fixes codebase gaps, captures knowledge |
| [handoff](../skills/handoff/SKILL.md) | Use when switching repos, handing off work, or sharing context between agents |
| [write-skill](../skills/write-skill/SKILL.md) | Use when creating a new skill or improving an existing one – applies best practices for structure, dynamic context, and safety |
| [skill-audit](../skills/skill-audit/SKILL.md) | Use after collecting usage data for a few weeks to identify dead weight – recommends which skills to keep, prune, or consolidate |
| [promote](../skills/promote/SKILL.md) | Use when checking which project skills should be available globally |
| [disk-cleanup](../skills/disk-cleanup/SKILL.md) | Use when the user asks about disk space or storage – scans for large consumers, never deletes without approval |
| [logo](../skills/logo/SKILL.md) | Use when the user wants to create or generate a logo – produces 6 SVG alternatives with a side-by-side comparison page |
| [mcp-prune](../skills/mcp-prune/SKILL.md) | Use when starting work in a project with many global MCP servers that waste context tokens |
| [upload-notion-image](../skills/upload-notion-image/SKILL.md) | Use when embedding images in Notion pages – uploads natively via the Notion API file upload flow |
| [set-topic](../skills/set-topic/SKILL.md) | Set the session topic displayed in the [status line](../bin/statusline.sh) |
| [setup](../skills/setup/SKILL.md) | Interactive onboarding wizard – installs rules, hooks, and statusline for the claude-skills toolkit |
| [software-best-practices](../skills/software-best-practices/SKILL.md) | Use after completing implementation to validate code quality – checks tests, linting, run scripts, error handling, executes code and iterates until success |
| [steal](../skills/steal/SKILL.md) | Use when the user wants to find reusable skills, patterns, or techniques from other repos – scans tracked GitHub repos or evaluates new ones |
| [list-skills](../skills/list-skills/SKILL.md) | Use when you need a reminder of your toolkit – quick reference of all available skills |
| [migrate-to-openspec](../skills/migrate-to-openspec/SKILL.md) | Convert a legacy `.specs` project to OpenSpec layout with verifiable fidelity – one-time per project |
