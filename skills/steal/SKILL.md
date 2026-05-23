---
name: steal
description: Use when the user wants to find reusable skills, patterns, or techniques from other repos — scans tracked GitHub repos or evaluates new ones
tags: [personal]
---

# Steal

Scan tracked sources for new skills, patterns, and techniques to steal. Evaluate new repos on the fly — if you steal something, the source gets tracked for future scans.

## Arguments

- `$ARGUMENTS` - Optional: a GitHub URL to evaluate/scan, `--full` for full rescan, `--full <url>` for full rescan of one source, or a skill name to deep-dive

## Context

- Tracked sources: !`cat .claude/skills/steal/sources.yaml 2>/dev/null`
- Our skills: !`find .claude/skills -maxdepth 1 -type d 2>/dev/null | head -30`
- Our commands: !`find .claude/commands -name "*.md" 2>/dev/null | head -20`

## Instructions

### Step 0: Parse arguments

Determine the mode from `$ARGUMENTS`:

```
IF $ARGUMENTS starts with "https://" or "http://":
  URL = $ARGUMENTS (strip any trailing whitespace)
  Check if URL is already in sources.yaml
  IF found → go to "Incremental Flow"
  IF not found → go to "Evaluation Flow"

IF $ARGUMENTS is "--full":
  Go to "Full Rescan Flow" (all sources)

IF $ARGUMENTS starts with "--full " followed by a URL:
  Go to "Full Rescan Flow" (single source)

IF $ARGUMENTS is empty:
  Go to "Multi-Source Scan"

OTHERWISE:
  Treat $ARGUMENTS as a skill name → go to "Deep-Dive Flow"
```

---

### Evaluation flow (new URL)

This is the entry point for repos not yet tracked.

**Step 1: Clone the repo**

Infer the repo name from the URL (e.g., `https://github.com/drn/dots` → `dots`). If `~/Personal/<repo-name>/` already exists, use it. Otherwise:

```bash
git clone <URL> ~/Personal/<repo-name>/
```

Infer a label from the GitHub user/org (e.g., `drn` → `Darren`, `someone` → `someone`). Use the GitHub username as-is unless it maps to a known name.

**Step 2: Full sweep**

Read everything interesting in the repo. Scan for:
- Skill files (look for patterns like `skills/*/SKILL.md`, `.claude/skills/`, `agents/skills/`, or similar)
- CLAUDE.md, AGENTS.md, or equivalent instruction files
- Shell scripts (`bin/`, `scripts/`, `cmd/`)
- Shell config (`zsh/`, `bash/`, aliases, dotfiles)
- Any other patterns or techniques that could be useful

For each interesting item, assess:
1. Do we already have an equivalent? (Check our skills and commands)
2. How useful would this be for Aaron's workflow?
3. How much adaptation would it need?

**Step 3: Present steal report**

Use the steal report format (see below).

**Step 4: Offer to steal**

Ask Aaron which items to steal. For approved items, apply them (see "Stealing Items" below).

**Step 5: Update roster (or clean up)**

```
IF anything was stolen:
  Add entry to sources.yaml:
    - url: <URL>
      local: ~/Personal/<repo-name>
      last_scanned: "<current HEAD hash>"
      label: <inferred label>

IF nothing was stolen:
  rm -rf ~/Personal/<repo-name>/
  Do not add to sources.yaml
```

---

### Incremental flow (tracked source)

For a source already in `sources.yaml`.

**Step 1: Update the repo**

```bash
cd <local> && git fetch origin && git pull origin HEAD
```

Get the current HEAD hash.

**Step 2: Check for changes**

```bash
cd <local> && git diff <last_scanned>..HEAD --name-only
```

If no files changed, report "No changes since last scan for <label>" and skip to updating the scan marker.

**Step 3: Assess changes**

Read every changed file. For each, assess whether it contains something worth stealing — a new skill, an improved pattern, a useful script, a technique we should adopt.

**Step 4: Present steal report**

Use the steal report format (see below).

**Step 5: Steal approved items**

Ask Aaron which items to steal. Apply approved items (see "Stealing Items" below).

**Step 6: Update scan marker**

Update the `last_scanned` field for this source in `sources.yaml` to the current HEAD hash.

---

### Full rescan flow

Same as incremental flow, but skip the diff — read everything in the repo as if scanning for the first time. Update `last_scanned` after.

If `--full` is bare (no URL), run full rescan for every source in `sources.yaml`.

If `--full <url>`, run full rescan for just that source.

---

### Multi-source scan (bare `/steal`)

Iterate every entry in `sources.yaml`. For each, run the incremental flow.

Present a combined report with clear sections per source:

```markdown
# Steal Report

## Darren (https://github.com/drn/dots)
[steal report content or "No changes since last scan"]

## Someone (https://github.com/someone/repo)
[steal report content or "No changes since last scan"]
```

After presenting all reports, offer to steal from any source.

---

### Deep-dive flow (`/steal <skill-name>`)

Search all tracked source repos for a skill matching the name:
1. For each source in `sources.yaml`, search `<local>` for skill files matching the name
2. Read the full skill from the source repo
3. Read any equivalent skill we already have
4. Present a detailed comparison: what the source skill does, what ours does (or doesn't), and a concrete plan for adopting or adapting it

---

## Steal report format

Use this format for each source:

```markdown
## Steal Report: <label>

### Source: <url>
### Last scan: <last_scanned commit> (<date>)
### Current: <current HEAD> (<date>)
### Changes detected: <N files>

---

### New things to steal

#### Priority 1: High value
For each item:
- **What**: Name and 1-line description
- **Why**: How it helps Aaron's workflow
- **Effort**: Easy / Medium / Hard to adapt
- **Action**: Specific next step

#### Priority 2: Worth considering
Same format.

#### Priority 3: Nice to know
Interesting patterns or techniques, even if not immediately actionable.

---

### Patterns and techniques
Non-skill things worth adopting (shell aliases, git config, skill-writing patterns, etc.)
```

For evaluation flow (new repos), omit the "Last scan" line since there is no prior scan.

---

## Stealing items

When Aaron approves items to steal:

1. **For skills**: Read the full source from the source repo, adapt for your environment (file paths, tool names, project structure, workflow differences), and write to `.claude/skills/<name>/SKILL.md` in your project
2. **For patterns**: Apply to CLAUDE.md, AGENTS.md, or relevant config files
3. **For shell config**: Note it for manual adoption (do not modify shell config directly)

When adapting skills:
- Replace source-specific paths and tools
- Adjust for your project structure
- Keep the core logic and structure intact — that is what makes them good
- Add any Aaron-specific context where relevant
