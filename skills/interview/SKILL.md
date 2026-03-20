---
name: interview
description: Structured interview-style review of any system, feature, or codebase. Builds an inventory, walks through items one-by-one in small chunks, tracks progress, captures decisions as artifacts. Use when the user wants to systematically review, audit, or evaluate something collaboratively.
---

# Structured Interview Review

Run a collaborative, structured review of any system, feature, or domain. You are the interviewer — you present material in small chunks, the user asks questions and makes decisions, and you capture everything into agreed-upon artifacts.

## Arguments

- `$ARGUMENTS` - What to review (e.g., "the permissions system", "our API endpoints", "the onboarding flow")

If no arguments provided, ask: "What would you like to review?"

## Context

- Working directory: !`pwd`
- Project type: !`find . -maxdepth 1 \( -name go.mod -o -name Gemfile -o -name package.json -o -name Cargo.toml -o -name pyproject.toml -o -name requirements.txt -o -name Makefile \) 2>/dev/null | head -5`
- Git branch: !`git branch --show-current 2>/dev/null | head -1`
- Date: !`date +%Y-%m-%d`

---

## Phase 0: Goal and Process Negotiation

This phase is a conversation, not a monologue. Go through these questions **one at a time**, waiting for a response before moving on.

### 0a. Confirm the goal

Restate the review goal from `$ARGUMENTS` in your own words. Ask: "Is that right, or should I adjust the scope?"

### 0b. Explore and propose an inventory

Explore the codebase or domain to build a proposed inventory of items to review. Present it as a structured list grouped into sections. Ask: "Does this cover everything? Anything to add, remove, or regroup?"

### 0c. Propose the review axes

Based on what you found, propose how each item should be evaluated. Examples:
- Edit / View / None (permission levels)
- Keep / Change / Remove (audit)
- Meets spec / Needs work / Missing (compliance)
- Custom axes the domain suggests

Ask: "How should we evaluate each item? Here is what I would suggest: [proposal]. Or tell me your framework."

### 0d. Negotiate the output format

Propose what the review should produce. Be specific about artifact types. Examples:
- SPEC documents (one per change, detailed enough for implementation without user input)
- A summary report or audit document
- A Notion page
- Jira tickets or GitHub issues
- A QA checklist per section
- A slide deck or presentation

Present 2-3 options that make sense for the goal, recommend one, and ask: "What should the output be? I would recommend [X] because [reason]."

The user may choose one, combine several, or specify something else entirely. Whatever they choose becomes the artifact format for the rest of the review.

### 0e. Set up the working directory

Once the goal, inventory, axes, and output are agreed:

1. Create a working directory: `<project-root>/<review-name>_review/` (or a location the user specifies)
2. Create `inventory.md` with the agreed inventory, all items marked pending
3. Create `log.sh` — a shell script for appending to a discussion log:

```bash
#!/bin/bash
# Usage: ./log.sh <speaker> "<message>"
LOGFILE="$(dirname "$0")/discussion.log"
echo "" >> "$LOGFILE"
echo "## $1 — $(date '+%Y-%m-%d %H:%M')" >> "$LOGFILE"
echo "" >> "$LOGFILE"
echo "$2" >> "$LOGFILE"
```

4. Make it executable
5. Initialize `discussion.log` with the agreed goal, axes, and output format
6. Create any artifact templates needed (e.g., SPEC template, QA template)

Confirm setup is complete and present the first section.

---

## Phase 1: The Interview

This is the core loop. Follow it precisely.

### Section Loop

For each section in the inventory:

1. **Present the section header** with a progress table showing all items in the section and their status (pending / reviewing / complete)
2. Move to the first pending item

### Item Loop

For each item in the current section:

1. **Present one chunk** of the item (e.g., navigation behavior, creation flow, a single API endpoint). Never present the entire item at once. If there is a natural decomposition, use it. If not, break it into 3-5 manageable chunks.

2. **Wait for the user's response.** They may:
   - Ask clarifying questions — answer them
   - Give an instruction ("add X", "change Y", "remove Z") — acknowledge it and create the agreed artifact immediately
   - Say it looks fine — note it and move on
   - Want to dive deeper — present more detail on the current chunk

3. **After the chunk is resolved**, present the next chunk of the same item. Repeat until all chunks are covered.

4. **After all chunks for an item are resolved:**
   - Log the discussion using `log.sh`
   - Update `inventory.md` to mark the item complete
   - Present the section progress table again with updated status
   - Move to the next item

### Between Sections

After completing all items in a section:
- Summarize what was decided (artifacts created, items marked clean)
- Show the full inventory with section-level completion status
- Move to the next section

### Artifact Creation

When the user gives an instruction that requires an artifact:
- Create it immediately, in the same turn
- Use the format negotiated in Phase 0
- Number artifacts sequentially (e.g., SPEC-001, SPEC-002, or FINDING-001)
- Each artifact should be self-contained — someone reading it in isolation should understand what to do
- Announce the artifact: "Created [ARTIFACT-NNN]: [title]"

---

## Phase 2: Wrap-up

After all sections are reviewed:

1. **Produce a summary document** listing:
   - Total items reviewed
   - Total artifacts produced (with titles and file paths)
   - Any cross-cutting themes or patterns noticed
   - Open questions or items deferred for later

2. **Log the final summary** to the discussion log

3. **Commit** all review artifacts to git (if in a git repo)

4. **Ask** if there is anything to revisit or if the review is complete

---

## Interaction Rules

These rules are non-negotiable. They encode the choreography that makes the interview effective.

1. **One chunk at a time.** Never present a wall of information. Break everything into discussable pieces.

2. **Wait for a response before advancing.** Do not move to the next chunk, item, or section until the user has responded to the current one.

3. **Progress is always visible.** Every time you present a chunk, the user should know where they are: which section, which item, which chunk, how many remain.

4. **Artifacts are created immediately.** When the user gives an instruction, create the artifact on the same turn. Do not batch them for later.

5. **The discussion log is append-only.** Use `log.sh` to record key decisions, instructions, and context. The log survives context resets and session changes.

6. **Ask, do not assume.** If the user's instruction is ambiguous, ask one clarifying question before creating an artifact.

7. **Be opinionated.** When presenting material, flag things that look wrong, inconsistent, or surprising. Do not just describe — analyze. Say "this feels like it might belong elsewhere" or "this overlaps with X, which could cause confusion."

8. **Adapt to the user's pace.** If the user gives rapid-fire approvals, pick up the pace. If they want to dive deep, slow down and provide more detail.

---

## Resuming a Review

If a review was started in a prior session:

1. Check for an existing `*_review/` directory with `inventory.md` and `discussion.log`
2. Read both to understand where the review left off
3. Present the inventory with current status
4. Resume from the first pending item

This works across context resets, new sessions, and different Claude instances.
