---
name: spec-writer
description: "Use whenever writing or updating spec text — single source of truth for the SPEC format. Takes approved intent and a target file, produces spec text."
---

# Spec Writer

Pure spec text production. Takes approved intent and a target, writes properly formatted spec text. No judgment, no inference, no questions asked. Think of this as a formatter — you tell it what to write, it writes it in the right format and the right place.

**This skill is the single source of truth for the SPEC format.** All spec writing should go through this skill for consistency.

## Arguments

- `$ARGUMENTS` - Natural language description of what to write and where

Examples:
```
/spec-writer "Create a new spec for user authentication at specs/auth.md"
/spec-writer "Add rate limiting section to specs/auth.md"
/spec-writer "Insert error handling behavior after §Interface in specs/api.md"
```

Or invoked programmatically by `/spec-recommender` or `/ralph-review` with structured intent.

## Context

- Spec-aware project: !`test -f .specs && cat .specs || echo "no .specs file"`
- Spec directory contents: !`ls specs/*.md 2>/dev/null | head -10`

---

## The SPEC Format

When creating a new spec file, use this template:

```markdown
# SPEC: {Feature Name}

## Purpose
Why this exists, what problem it solves.

## Interface
- **Inputs**: What goes in
- **Outputs**: What comes out
- **Dependencies**: What it needs

## Behavior
Step-by-step: given X, system does Y, resulting in Z.
Describe each distinct behavior as its own subsection or numbered item.

## Test Cases
- Happy path scenarios
- Error cases and how they're handled
- Edge cases and boundary conditions

## Examples
Concrete usage examples with real data.
```

**When appending to an existing spec, do NOT force this template.** Read the existing file first and match its style and structure. If the spec organizes by tool (like a tool-by-tool description), follow that. If it uses different heading levels, match those. The template is for new files only.

---

## Abstraction Boundary Rule

**Specs must describe interface-level behavior, not internal implementation details.** Reference method signatures and public contracts, not private struct fields or internal data structures.

**Why:** Agents read specs to build a mental model of the system. If a spec mentions internal field names, agents will write code that references those fields directly — even when those fields are private or belong to a different layer. This causes repeated hallucination failures.

**Bad** (leaks implementation):
```
- `canLaunch()` checks `len(activeItems) < maxConcurrent`
- Excess items are pushed to `itemQueue`
- Remove from `activeItems` map
```

**Good** (describes the interface):
```
- Concurrency is managed by `scheduler` (`Scheduler` interface)
- `scheduler.Submit(req)` returns `(queued bool, cmd Cmd)` — handles concurrency internally
- `scheduler.ActiveItem(id)` returns the item handle or nil
- The component does NOT have `activeItems` or `itemQueue` fields — those are internal to the scheduler implementation
```

When writing or updating specs, always ask: "Could an agent read this and correctly write code against the described API?" If the spec references fields that aren't accessible from the layer being documented, rewrite to use the interface methods instead.

---

## Instructions

```
1. Parse the intent from $ARGUMENTS or programmatic input

2. Determine the target:
   IF a file path is mentioned → use it
   IF intent says "create" or "new" → create a new file
     Default location: specs/ directory (from .specs file, or specs/ if no .specs)
   IF intent says "append" or "add to" → append to existing file
   IF intent says "insert after <section>" → insert after that section
   IF ambiguous → default to append if file exists, create if it doesn't

3. IF target file exists:
   - Read it fully
   - Analyze its structure (heading levels, section patterns, style)
   - You MUST match that style — do not impose the template on existing files

4. IF creating a new file:
   - Use the full SPEC template above
   - Fill in every section from the provided intent
   - Leave no section empty — if the intent doesn't cover a section,
     write a reasonable placeholder based on the intent
     (e.g., "## Test Cases\n- Verify {primary behavior} works as described")

5. IF appending:
   - Add a new section at the end of the file
   - Match the existing heading level and formatting style
   - Add a blank line before the new section

6. IF inserting after a named section:
   - Find the section heading
   - Insert new content after that section's content (before the next heading)
   - Match the existing formatting

7. Write the text to the file using the Write or Edit tool

8. Print what was written and where:
   "Spec text written to {file path}. {N} lines added. Not committed."

9. Do NOT commit — the caller handles that
```

---

## What This Skill Does NOT Do

- **No inference** — It does not figure out what the intent should be. The caller (user, spec-recommender, or ralph-review) provides the intent.
- **No contradiction detection** — It does not check if the new text contradicts existing spec text. Ralph-review's review sub-agent catches those.
- **No clarifying questions** — If the intent is unclear, the caller should have resolved that before invoking this skill.
- **No committing** — The caller decides when and how to commit.
