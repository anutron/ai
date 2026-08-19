---
tags: [formatting]
audience: [shared]
---
## Markdown formatting requirements

Consecutive lines with no blank line between them collapse into one paragraph in Plannotator (confirmed still true as of v0.19.27) – always put a blank line before/after every heading, list, code block, and paragraph, and use a bullet list for a run of related facts rather than bare sequential lines.

```markdown
<!-- Bad: collapses to one line -->
**Type:** troubleshooting
**Why:** broke prod

<!-- Good -->
- **Type:** troubleshooting
- **Why:** broke prod
```
