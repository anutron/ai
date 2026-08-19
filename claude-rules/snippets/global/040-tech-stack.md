---
tags: [personal]
audience: [aaron]
---
## Tech stack spectrum

New apps follow the spectrum at `{{PROJECT_DIR}}/docs/stack-spectrum.md`. Pick the lightest tier that fits:

| Tier | When to use | Stack |
|------|-------------|-------|
| **Lightweight** | No database, simple web UI | HTML + CSS + JS (no build step) |
| **Personal** | Local app with DB and real UI | Next.js + Prisma + MySQL + shadcn/ui |
| **Distributed** | Local app, shared/hosted data | Personal tier + Supabase (Postgres) |
| **Deployable** | Production app for other users | Rails + Next.js monorepo |
| **CLI** | Terminal-first tool | Go + Cobra (+ Bubbletea for TUI) |

Going from personal/distributed to deployable is a rebuild, not an upgrade – start fresh with the deployable blueprint.

MCP servers: Node.js/TypeScript (SDK is Node-native); outside the web spectrum.
