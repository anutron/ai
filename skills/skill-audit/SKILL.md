---
name: skill-audit
description: Analyze skill usage logs and recommend which skills to keep, prune, or consolidate. Use after collecting usage data for a few weeks to identify dead weight.
---

## Context

- Usage log: !{cat ~/.claude/skill-usage.tsv 2>/dev/null | head -500}
- Log line count: !{wc -l ~/.claude/skill-usage.tsv 2>/dev/null | head -1}
- Installed local skills: !{ls ~/.claude/skills/ 2>/dev/null | head -30}
- Installed plugins: !{claude plugins list 2>&1 | grep -E "^  " | head -30}
- Date range: !{head -2 ~/.claude/skill-usage.tsv 2>/dev/null | tail -1 | cut -f1}
- Latest entry: !{tail -1 ~/.claude/skill-usage.tsv 2>/dev/null | cut -f1}

## Instructions

Analyze skill usage data and make pruning recommendations.

### Step 1: Check Data Sufficiency

If the usage log has fewer than 20 entries or spans less than 7 days, tell the user there is not enough data yet and stop. Show current entry count and date range.

### Step 2: Build Usage Report

From the TSV log, compute:

1. **Frequency table** - skill name, total invocations, sorted descending
2. **Recency** - last used date for each skill
3. **Project distribution** - which skills are used in which projects
4. **Time pattern** - any skills that were used early but stopped (abandoned)

Present as a single markdown table with columns: Skill, Uses, Last Used, Projects, Trend (active/declining/abandoned).

### Step 3: Cross-Reference Installed Skills

Compare the usage data against all installed skills (local + plugins). Categorize each installed skill:

- **ACTIVE** - Used 3+ times in the last 30 days
- **OCCASIONAL** - Used 1-2 times in the last 30 days
- **DORMANT** - Not used in last 30 days but used before
- **NEVER USED** - Installed but zero log entries

Present as a categorized list.

### Step 4: Recommendations

For each category, recommend:

- **ACTIVE** - Keep. No action.
- **OCCASIONAL** - Keep. Note which projects use them.
- **DORMANT** - Candidate for disabling. Ask if the user still needs it.
- **NEVER USED** - Strong candidate for removal. Flag these clearly.

Also look for:
- **Duplicates** - Skills that seem to do the same thing (e.g., multiple review skills)
- **Plugin bloat** - Plugins with many sub-skills where only 1-2 are used

### Step 5: Present Action Plan

Show a concrete list of recommended actions:

```
REMOVE (never used):
  - skill-name-1
  - skill-name-2

DISABLE (dormant, re-enable if needed):
  - skill-name-3

KEEP (active/occasional):
  - everything else
```

Wait for user approval before taking any action.

### Step 6: Execute Approved Removals

For approved removals:
- Local skills: remove the symlink from ~/.claude/skills/ (keep the source in AI-RON)
- Plugins: run claude plugins disable plugin-name

Do NOT delete source files. Only remove symlinks and disable plugins so everything is reversible.

### Abort Conditions

- No usage log file exists: tell the user to use skills for a while first and stop.
- Fewer than 20 entries: not enough data, stop.
- Less than 7 days of data: too early to draw conclusions, stop.
