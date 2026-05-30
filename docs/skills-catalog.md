# Skills catalog

The skills in this toolkit, grouped by purpose. Spec-driven development has its own catalog in [spec-driven-development.md](spec-driven-development.md); this doc covers everything else.

## Development

| Skill | Description |
|-------|-------------|
| [brainstorm](../skills/brainstorm/SKILL.md) | You MUST use this before any creative work -- creating features, building components, adding functionality, or modifying behavior. Explores intent, designs the solution, scaffolds an OpenSpec change folder (proposal + design + delta specs + tasks), and hands off to execution. |
| [bugbash](../skills/bugbash/SKILL.md) | Use when the user wants to do a QA session or report multiple bugs — interactive session where bugs are reported conversationally and agents fix them in parallel |
| [close-worktree](../skills/close-worktree/SKILL.md) | Use when done working in a git worktree and ready to merge it back to the main branch — asks whether to merge or squash |
| [debug](../skills/debug/SKILL.md) | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes — multi-agent competing hypotheses debugging |
| [execute-plan](../skills/execute-plan/SKILL.md) | Use when an OpenSpec change is approved and ready to implement — executes the change's tasks.md with agent-driven development, worktree isolation, TDD discipline, two-stage review, native Task dependencies for parallel execution, and `openspec archive` at the end. |
| [fixit](../skills/fixit/SKILL.md) | Use when the user reports a bug or issue that can be fixed without blocking their current work — backgrounds an agent in a worktree to fix and merge back without breaking stride |
| [guard](../skills/guard/SKILL.md) | Use before any git commit to check for secrets, security antipatterns, and test breakage |
| [kickoff](../skills/kickoff/SKILL.md) | Use when starting a brand new project from scratch -- runs discovery, picks a tech stack tier, then hands off to brainstorm and build. Guides non-technical and technical users alike. |
| [rereview](../skills/rereview/SKILL.md) | Use when a previous review missed something or the user wants a thorough second pass — re-review with fresh eyes, zero regressions, go slow and analyze everything |
| [review](../skills/review/SKILL.md) | Use when the user asks to review code, review current changes, or review a PR number |
| [test](../skills/test/SKILL.md) | Use after writing or modifying code to run targeted tests and identify coverage gaps, before claiming code works |
| [unstaged](../skills/unstaged/SKILL.md) | Use when the user wants to see what's changed or plan commits — shows uncommitted/unstaged changes grouped by logical commit themes |

## Discipline and orchestration

These skills describe how agents should think and work. They're loaded by reference when other skills need them – not typically invoked directly.

| Skill | Description |
|-------|-------------|
| [agent-driven-development](../skills/agent-driven-development/SKILL.md) | Use when executing implementation plans with independent tasks — orchestration pattern for worktree isolation, TDD discipline, and two-stage review. Referenced by execute-plan, fixit, and bugbash. |
| [bash-style](../skills/bash-style/SKILL.md) | Reference for bash patterns that trigger Claude Code permission guardrails (static-analysis flags that allowlist rules cannot silence). Load when about to run bash with `cd <repo> && git ...`, `$(...)`, backticks, heredocs, inline `python3 -c` / `node -e` / `ruby -e` / `perl -e`, multi-line shell logic with variables/conditionals, or before allowlisting a new script path. Also covers always-prompt verbs and the `git -C` known gap. |
| [test-driven-development](../skills/test-driven-development/SKILL.md) | Use when implementing any feature or bugfix, before writing implementation code |
| [verification-before-completion](../skills/verification-before-completion/SKILL.md) | Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always |

## Git and PR

| Skill | Description |
|-------|-------------|
| [changelog](../skills/changelog/SKILL.md) | Use when the user asks for a changelog, release notes, or summary of recent changes |
| [merge](../skills/merge/SKILL.md) | Use when the user wants to merge the current branch to master — merges via GitHub PR |
| [pr](../skills/pr/SKILL.md) | Use when code is ready to ship — opens a PR, waits for CI to pass, fixes failures, addresses review comments, and loops until fully green |
| [pr-dashboard](../skills/pr-dashboard/SKILL.md) | Use when the user asks about PR status, open PRs, review requests, or wants a PR overview — shows open PRs, review requests, and recently closed PRs with age and status |
| [pr-respond](../skills/pr-respond/SKILL.md) | Read PR review feedback, triage each comment (adopt/reject with reasoning), optionally apply changes and commit. Writes artifacts to ~/.claude/pr-responses/. Use when a PR has received review comments that need to be addressed. |

## General

| Skill | Description |
|-------|-------------|
| [anutron-install](../skills/anutron-install/SKILL.md) | Install the anutron (claude-skills) kit into the current project — symlinks or copies skills, registers hooks, compiles CLAUDE.md from snippets. |
| [anutron-uninstall](../skills/anutron-uninstall/SKILL.md) | Uninstall the anutron (claude-skills) kit from the current project — reverses everything /anutron-install did. |
| [devils-advocate](../skills/devils-advocate/SKILL.md) | Use when the user wants to stress-test an idea, plan, or approach — challenges assumptions and finds weaknesses before committing |
| [disk-cleanup](../skills/disk-cleanup/SKILL.md) | Use when the user asks about disk space or storage — scans for large storage consumers and identifies cleanup opportunities. Read-only, never deletes without approval |
| [doitright](../skills/doitright/SKILL.md) | Pick the long-term-correct option from the choices you just presented. Use when the user types /doitright in response to a multi-option recommendation, meaning "go with the proper long-term fix unless there's a real downside beyond effort." |
| [eli5](../skills/eli5/SKILL.md) | Restate your prior response in plain, non-technical language and orient the user around the decision they need to make. Use when the user types /eli5 or asks to have something explained simply. |
| [handoff](../skills/handoff/SKILL.md) | Generate a handoff prompt to pass context to another agent thread. Use when switching repos, handing off work, or sharing context between agents. |
| [improve](../skills/improve/SKILL.md) | Use at the end of a session to run a retrospective — upgrades skills, fixes codebase gaps, and captures durable knowledge |
| [interview](../skills/interview/SKILL.md) | Structured interview-style review of any system, feature, or codebase. Builds an inventory, walks through items one-by-one in small chunks, tracks progress, captures decisions as artifacts. Use when the user wants to systematically review, audit, or evaluate something collaboratively. |
| [list-skills](../skills/list-skills/SKILL.md) | Quick reference of all available skills and what they do. Use when you need a reminder of your toolkit. |
| [mcp-prune](../skills/mcp-prune/SKILL.md) | Analyze active MCP servers and disable irrelevant ones for the current project. Use when starting work in a project with many global MCP servers that waste context tokens. Saves config to project settings. |
| [migrate-to-openspec](../skills/migrate-to-openspec/SKILL.md) | Convert a legacy AI-RON spec project (`.specs` file + `specs/*.md`) to OpenSpec layout with verifiable fidelity. One-time per project. Translator + verifier agents preserve every Given/When/Then case as an OpenSpec scenario, archive originals at `.workflow/legacy-specs/`, and install the new pre-commit hook + CLAUDE.md snippets. |
| [promote](../skills/promote/SKILL.md) | Use when checking which project skills should be available globally — finds skills not yet promoted and recommends which to symlink to ~/.claude/skills/ |
| [set-topic](../skills/set-topic/SKILL.md) | Set the session topic displayed in the status line. Usage: /set-topic <topic text> |
| [setup](../skills/setup/SKILL.md) | Install user-env tooling — symlinks helper scripts from the claude-skills source into ~/.claude/bin/, registers allowlist entries, and reports status. Use when the user runs /setup, when /set-topic warns the helper is missing, or when first wiring up a new machine. Idempotent. |
| [skill-audit](../skills/skill-audit/SKILL.md) | Analyze skill usage logs and recommend which skills to keep, prune, or consolidate. Use after collecting usage data for a few weeks to identify dead weight. |
| [software-best-practices](../skills/software-best-practices/SKILL.md) | Use after completing implementation to validate code quality — checks tests, linting, run scripts, error handling, executes code and iterates until success |
| [steal](../skills/steal/SKILL.md) | Use when the user wants to find reusable skills, patterns, or techniques from other repos — scans tracked GitHub repos or evaluates new ones |
| [trust-action](../skills/trust-action/SKILL.md) | Eliminate a specific Claude Code permission prompt by adding a targeted allowlist rule to global (~/.claude/settings.json) or project (.claude/settings.json) scope. Use when the user pastes a single permission prompt (text containing "Do you want to proceed?" or "don't ask again") and wants future occurrences of that exact action silenced. Always asks the user to choose global vs project scope before writing. Refuses unfixable patterns (`$(...)`, heredocs, `cd && ...`) and bypass-prone path-based rules (scripts in /tmp/, untracked files) and proposes CLAUDE.md hardening instead. Companion skill `/trust-skills` handles bulk-trust of project-local skills. |
| [trust-skills](../skills/trust-skills/SKILL.md) | Bulk-trust all skills defined in the current project's `.claude/skills/` directory. Discovers local skills, shows them to the user, asks where to write the rules (project settings.json vs settings.local.json), then adds `Skill(<name>)` allowlist entries. Use when working in a project that has its own skills and you keep getting per-skill permission prompts. |
| [upload-notion-image](../skills/upload-notion-image/SKILL.md) | Upload local images to Notion pages natively via the Notion API file upload flow. No external hosting needed — images live inside Notion. Use when embedding images in Notion pages. |
| [write-skill](../skills/write-skill/SKILL.md) | Use when creating a new skill or improving an existing one — applies best practices for structure, dynamic context, and safety |
