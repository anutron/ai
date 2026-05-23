# Claude rules

Version-controlled CLAUDE.md snippets with a compilation system. Rules are persistent behavioral instructions – they tell Claude how you want it to work in every conversation.

Instead of one monolithic CLAUDE.md file, rules live as small focused markdown snippets compiled into the final CLAUDE.md by a build script. This keeps each concern composable, portable, reviewable, and templatable.

- **Snippets** live in `claude-rules/snippets/global/` and `claude-rules/snippets/project/`
- **Global snippets** compile into `~/.claude/CLAUDE.md` (applies to all projects)
- **Project snippets** compile into the project's `CLAUDE.md` (applies to this project only)
- **Template variables** (`{{PROJECT_DIR}}`, `{{RULES_DIR}}`, etc.) replace hardcoded paths, making snippets portable and publishable
- **Numbered filenames** (e.g., `010-git-workflow.md`, `040-testing.md`) control ordering with gaps for easy insertion

The compiled CLAUDE.md is a symlink to the build output, so you never edit it directly. If someone does, a checksum-based tamper detection catches the drift.

One meta-move: include a snippet that teaches Claude about the snippet system itself. This way Claude knows to edit snippets rather than the compiled output when rules need to change.

See [claude-rules/README.md](../claude-rules/README.md) for setup.

## The snippets

| Snippet | Description |
|---------|-------------|
| `005-claudemd-management` | How CLAUDE.md files are compiled from snippets |
| `010-plan-formatting` | Markdown formatting requirements for structured output |
| `020-interaction-prefs` | Question-by-question and step-by-step interaction patterns |
| `022-user-facing-framing` | Structure for choices and findings – outcome-first, recommendation takes a position. Referenced by `/brainstorm` and `/ralph-review` |
| `040-plan-execution-handoff` | What to do after plan approval |
| `040-tech-stack` | Tech stack spectrum – four tiers from lightweight to deployable (references [stack-spectrum.md](stack-spectrum.md)) |
| `050-git-workflow` | Commit conventions and pre-commit hooks |
| `052-worktree-location` | Place git worktrees in `.claude/worktree/` within spec-driven projects |
| `055-session-topics` | Set status line topics for session identification |
| `060-plannotator-spec-review` | Interactive spec review via Plannotator |
| `070-testing` | Test-driven development defaults |
| `080-spec-driven-dev` | OpenSpec spec-first process – change folder, deltas, tests, archive |
| `085-openspec-migration-prompt` | Suggests `/migrate-to-openspec` for legacy `.specs` projects |
| `090-plan-archiving` | Stub – superseded by OpenSpec; legacy plans live at `.workflow/plans/` |
