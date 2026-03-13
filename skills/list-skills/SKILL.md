---
name: list-skills
description: Quick reference of all available skills and what they do. Use when you need a reminder of your toolkit.
---

# Skill Quick Reference

Show a context-aware cheat sheet of available skills, highlighting the ones most relevant to the current work.

## Context

- Global skills: !`ls -1 ~/.claude/skills/ 2>/dev/null | head -30`
- Local skills: !`ls -1 .claude/skills/ 2>/dev/null | head -30`
- Current repo: !`git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null | head -1`
- Branch: !`git branch --show-current`
- Git status: !`git status --short 2>/dev/null | head -15`
- Recent commits: !`git log --oneline -5 2>/dev/null | head -5`
- Open PRs on this repo: !`gh pr list --limit 3 --state open 2>/dev/null | head -5`
- Has test files: !`find . -maxdepth 4 -name "*_test.*" -o -name "*.test.*" -o -name "*_spec.*" 2>/dev/null | head -3`
- Has uncommitted changes: !`git diff --stat --shortstat 2>/dev/null | tail -1`

## Instructions

### Step 1: Assess the Current Work Context

Based on the context above, determine what phase of work the user is likely in:

- **Building/implementing**: Uncommitted changes, recent commits on a feature branch, test files present
- **Reviewing/shipping**: Open PRs, branch ahead of main, clean working tree
- **Debugging**: Error messages in recent conversation, test failures, investigation branches
- **Starting fresh**: On main, no changes, beginning of session
- **Session management**: Long conversation, lots of work done, end of session feel
- **AI-RON housekeeping**: In the AI-RON repo, working on skills/config/docs

### Step 2: Print Relevant Skills First

Print a short "Relevant Now" section (3-6 skills max) based on the work context. Use your judgment. Examples:

- Uncommitted changes on a branch? Suggest: /guard, /review, /pr, /merge
- In the middle of building something? Suggest: /dev, /test, /debug
- Open PR waiting for CI? Suggest: /pr, /pr-dashboard
- Long session with lots of work? Suggest: /improve, /handoff, /changelog
- On main with no changes? Suggest: /dev, /pr-dashboard, /daily-rhythm (if in AI-RON)
- Working on skills? Suggest: /write-skill, /promote, /steal

Format:

```
RELEVANT NOW
  /skill-name     Why it is relevant right now
  /skill-name     Why it is relevant right now
```

### Step 3: Print the Full Reference

After the relevant section, print all remaining skills grouped by category. Skip the ones already shown in "Relevant Now" to avoid repetition.

```
OTHER SKILLS

  Development:  /dev  /debug  /test  /guard
  Review:       /review  /rereview  /devils-advocate
  Git & PR:     /pr  /merge  /changelog  /pr-dashboard
  Session:      /handoff  /improve  /promote  /list-skills
  Creation:     /logo  /write-skill
  AI-RON only:  /daily-rhythm  /weekly-rhythm  /monthly-rhythm  /steal  /nexonia-expenses
```

Use the compact one-line-per-category format for this section. Only show categories that have remaining skills (after removing the ones in "Relevant Now"). Omit AI-RON only if not in the AI-RON repo.
