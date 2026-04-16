---
title: "Install the plugin"
order: 1
icon: "fa-download"
cta_label: "How"
cta_link: "/kit/01-install/"
summary: "One command to drop the whole A-stack into Claude Code."
image: "/assets/images/airon/file-layout.png"
---

The fastest way to start using everything in the A-stack is the plugin:

```
/plugin install ai@anutron/ai
```

This installs all the skills, hooks, and CLAUDE.md snippets — namespaced under `ai:` so they don't collide with anything else you have. Updates auto-apply when the repo changes.

## What you get

- 40+ skills (workflow, review, debugging, planning)
- Pre-commit hooks (link checks, spec checks)
- A compile-time CLAUDE.md system that lets you mix-and-match rules per project

After install, run:

```
/ai:setup
```

to walk through the optional bits (statusline, hooks, project rules).
