## Tech Stack Spectrum

New applications follow the **stack spectrum** defined in `{{PROJECT_DIR}}/docs/stack-spectrum.md`. Four tiers, pick the lightest that fits:

| Tier | When to use | Stack |
|------|-------------|-------|
| **Lightweight** | No database, simple web UI | HTML + CSS + JS (no build step) |
| **Personal** | Local app with DB and real UI | Next.js + Prisma + MySQL + shadcn/ui |
| **Distributed** | Local app, shared/hosted data | Personal tier + Supabase (Postgres) |
| **Deployable** | Production app for other users | Rails + Next.js monorepo (see `docs/thanx-dev-system.md`) |

### Quick decision guide

- **Need a database?** No → Lightweight. Yes → Personal or higher.
- **Need shared data across devices?** → Distributed.
- **Other people will use it?** → Deployable.
- **Going from personal/distributed to deployable?** That's a rebuild, not an upgrade. Start fresh with the deployable blueprint.

### Legacy applications

Existing apps (`fitbit-cli`, `gmail-mcp`, `things-mcp`) use their existing stacks. When modifying legacy apps, follow existing patterns — do not migrate them.

### MCP servers

Node.js/TypeScript (MCP SDK is Node-native). These don't fit neatly into the web app spectrum — they're their own thing.
