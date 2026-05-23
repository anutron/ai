---
tags: [formatting]
audience: [shared]
---
## Markdown Formatting Requirements

All markdown you produce — plans, reports, codebase gap summaries, agent outputs, specs, any structured text — MUST use proper markdown to ensure correct rendering in Plannotator.

### Line Breaks

**CRITICAL:** Consecutive lines in markdown without blank lines between them get collapsed into a single paragraph. This applies everywhere, not just plans.

**Rules:**
- Use **bullet lists** for related items — never bare lines in sequence
- Put a **blank line** before and after every heading, list, code block, and paragraph
- Each distinct piece of information gets its own bullet or paragraph — never pack multiple facts onto one line separated only by spaces

**Bad** (all on one line — collapses into one paragraph):
```markdown
**File:** impl.go **Friction:** Race condition **Status:** Fixed
```

**Also bad** (separate lines but no blank lines — ALSO collapses into one paragraph):
```markdown
**Type:** troubleshooting
**Why:** The migration broke prod
**Before:** Old approach
**After:** New approach
```

**Good** (bullet list — each field renders on its own line):
```markdown
- **File:** `impl.go`
- **Friction:** Race condition
- **Status:** Fixed
```

Use bullet lists for related items:

```markdown
## Executive Summary

- **Timeline:** This week
- **Target Users:** Data analysts/non-developers
- **Strategy:** Feature flags to hide unstable features
- **Primary UI:** Flask templates (stable)
- **Hidden Features:** React SPA + Investigator AI (developer mode only)
```

### General Plan Structure Best Practices

1. **Use descriptive headings** — `## Section Name` for major sections
2. **Use lists for related items** — Bullet points (`-`) or numbered lists (`1.`)
3. **Use code blocks for code** — Triple backticks with language identifier
4. **Use tables for structured data** — Markdown tables for comparisons or structured info
5. **Use checkboxes for tasks** — `- [ ]` for unchecked, `- [x]` for checked

### Example Well-Formatted Plan

```markdown
# Project Implementation Plan

## Overview

This plan outlines the implementation strategy for adding feature flags to the dashboard.

## Key Details

- **Timeline:** This week
- **Estimated effort:** 9 hours
- **Risk level:** Low
- **Dependencies:** None

## Implementation Steps

### 1. Add Feature Flag Configuration

Create a new settings module:

` ``python
# settings.py
class Settings:
    enable_react_spa: bool = False
    enable_investigator_ai: bool = False
` ``

### 2. Update Routes

Modify the following routes:

- [ ] Update root route redirect logic
- [ ] Add feature flag checks to `/app/*` routes
- [ ] Protect investigator routes with flag check

## Success Criteria

The implementation will be considered successful when:

1. All tests pass
2. Feature flags correctly hide/show features
3. Production mode defaults to stable UI
```
