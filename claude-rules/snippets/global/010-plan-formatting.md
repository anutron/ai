---
tags: [formatting]
audience: [shared]
---
## Markdown formatting requirements

All markdown you produce MUST render correctly in Plannotator.

**CRITICAL:** Consecutive lines without blank lines between them collapse into a single paragraph.

**Rules:**

- Use **bullet lists** for related items – never bare lines in sequence
- Put a **blank line** before and after every heading, list, code block, and paragraph
- Each distinct fact gets its own bullet or paragraph – never pack multiple facts onto one line

**Bad** (separate lines but no blank lines – collapses into one paragraph):

```markdown
**Type:** troubleshooting
**Why:** The migration broke prod
**Before:** Old approach
**After:** New approach
```

**Good** (bullet list – each field renders on its own line):

```markdown
- **Type:** troubleshooting
- **Why:** The migration broke prod
- **Before:** Old approach
- **After:** New approach
```
