# Stack Spectrum

Four tiers of application blueprints. Pick the lightest tier that fits the job.

---

## Decision Criteria

| Signal | Lightweight | Personal | Distributed | Deployable |
|--------|------------|----------|-------------|------------|
| Persistent state? | No (files/env at most) | Yes (local DB) | Yes (hosted DB) | Yes (managed DB) |
| Web UI? | Yes (HTML/CSS/JS) | Yes | Yes (or native app) | Yes |
| Users besides you? | No | No | Maybe (shared data) | Yes |
| Data shared across devices? | No | No | Yes (Supabase) | Yes |
| Needs to run when laptop is closed? | No | No | No | Yes |
| Auth? | No | No | API key at most | Yes (SSO, tokens) |
| CI/CD? | No | No | No | Yes (CircleCI, Docker, Terraform) |

### Upgrade triggers

- **Lightweight to personal**: You need a database, or the UI outgrows a single HTML file.
- **Personal to distributed**: You want to share data across devices or with other people, but the app still runs locally. Swap local MySQL for Supabase.
- **Personal/distributed to deployable**: This is a rebuild. Start fresh with the deployable blueprint — the Next.js frontend carries over, but the API layer, auth, infra, and CI/CD are all new.

---

## Tier 1: Lightweight

A web app in a handful of files. HTML, CSS, JavaScript — no database, no server, no build step. Opens in a browser, works immediately.

### Example

[thanx-strategy-workbook](https://github.com/thanx-ai/thanx-strategy-workbook) — a planning tool built as a single `index.html` with inline CSS and a separate `app.jsx` loaded via CDN React.

### Project structure

```
<app-name>/
├── index.html            # Entry point — open in browser
├── app.jsx               # App logic (React via CDN, or vanilla JS)
├── styles.css            # Extracted styles (optional — can be inline)
├── assets/               # Images, icons
├── tests/
│   └── *.test.ts         # Unit tests (if logic warrants it)
├── .specs                # If spec-driven
├── specs/                # SPEC files
└── CLAUDE.md
```

For very small apps, everything lives in `index.html` — no separate files needed.

### Technology

- **HTML + CSS + JavaScript** — no build step, no bundler, no framework install
- React via CDN (`<script>` tag) when you need component structure — use JSX with Babel standalone or stick to `React.createElement`
- Tailwind via CDN Play (`<script src="https://cdn.tailwindcss.com">`) for styling, or hand-written CSS
- No package.json unless you need tests

### State

- **In-memory** — state lives in JS variables, lost on refresh
- **localStorage** — persist across sessions in the same browser
- **URL params** — shareable state encoded in the URL
- If you need a real database, upgrade to the personal tier

### Testing (optional)

Most lightweight apps don't need tests — they're small enough to verify by opening them. If the app has non-trivial logic (calculations, data transformations), extract it into a separate `.js` file and test with Vitest:

```json
{
  "scripts": { "test": "vitest run" },
  "devDependencies": { "vitest": "^3" }
}
```

### How it runs

```bash
open index.html
# or
npx serve .
```

No server required. If you need to serve it (e.g., for CORS or routing), `npx serve` is enough.

### Checklist: new lightweight app

- [ ] Create directory and `git init`
- [ ] Create `index.html` with inline styles and script (or separate files)
- [ ] Add React via CDN if you need components
- [ ] Add Tailwind via CDN Play if you want utility classes
- [ ] Write CLAUDE.md with project-specific instructions
- [ ] Add `.specs` file (if spec-driven)

---

## Tier 2: Personal

A full-stack web app that runs on your machine. Has a database, a real UI, and proper project structure — but isn't meant to be deployed or accessed by others.

### Language and runtime

- **TypeScript** across the board
- **Next.js** (App Router) as a full-stack monolith — handles both UI and API routes

### Why Next.js monolith (not separate API + frontend)

A personal app doesn't need a separate API server. Next.js API routes handle the backend, Server Components handle data fetching, and you get one process, one repo, one framework.

### Project structure

```
<app-name>/
├── src/
│   ├── app/                    # Next.js App Router
│   │   ├── layout.tsx          # Root layout
│   │   ├── page.tsx            # Home page
│   │   ├── (routes)/           # Route groups
│   │   │   └── dashboard/
│   │   │       └── page.tsx
│   │   └── api/                # API routes
│   │       └── widgets/
│   │           └── route.ts
│   ├── components/
│   │   └── ui/                 # shadcn/ui components
│   ├── lib/
│   │   ├── db.ts               # Prisma client singleton
│   │   └── utils.ts            # Shared utilities
│   └── __tests__/
│       ├── components/         # Component tests
│       └── api/                # API route tests
├── prisma/
│   ├── schema.prisma           # Database schema
│   └── migrations/             # Migration history
├── e2e/                        # Playwright E2E tests (optional)
├── public/                     # Static assets
├── package.json
├── next.config.ts
├── tsconfig.json
├── jest.config.ts
├── jest.setup.ts
├── .env.local                  # Local config (gitignored)
├── .specs                      # If spec-driven
├── specs/                      # SPEC files
└── CLAUDE.md
```

### Database: Prisma + MySQL

Local MySQL via Homebrew (or DevBox). Prisma handles schema, migrations, and typed queries.

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "mysql"
  url      = env("DATABASE_URL")
}

model Widget {
  id          Int       @id @default(autoincrement())
  name        String
  slug        String    @unique
  description String?   @db.Text
  archivedAt  DateTime? @map("archived_at")
  createdAt   DateTime  @default(now()) @map("created_at")
  updatedAt   DateTime  @updatedAt @map("updated_at")

  @@map("widgets")
}
```

```typescript
// src/lib/db.ts
import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient }

export const prisma = globalForPrisma.prisma || new PrismaClient()

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma
```

### API routes

Next.js Route Handlers in `src/app/api/`:

```typescript
// src/app/api/widgets/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/db'

export async function GET() {
  const widgets = await prisma.widget.findMany({
    where: { archivedAt: null },
    orderBy: { createdAt: 'desc' },
  })
  return NextResponse.json({ widgets })
}

export async function POST(request: NextRequest) {
  const body = await request.json()
  const widget = await prisma.widget.create({
    data: {
      name: body.name,
      slug: body.name.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
      description: body.description,
    },
  })
  return NextResponse.json(widget, { status: 201 })
}
```

```typescript
// src/app/api/widgets/[id]/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/db'

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const widget = await prisma.widget.findUnique({
    where: { id: parseInt(id) },
  })
  if (!widget) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json(widget)
}
```

### Frontend: shadcn/ui + Tailwind

Server Components for data fetching, Client Components for interactivity:

```typescript
// src/app/page.tsx
import { prisma } from '@/lib/db'
import { WidgetList } from '@/components/widget-list'

export default async function Home() {
  const widgets = await prisma.widget.findMany({
    where: { archivedAt: null },
    orderBy: { createdAt: 'desc' },
  })

  return (
    <main className="container mx-auto py-8">
      <h1 className="text-2xl font-bold mb-6">Widgets</h1>
      <WidgetList widgets={widgets} />
    </main>
  )
}
```

```typescript
// src/components/widget-list.tsx
'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface Widget {
  id: number
  name: string
  description: string | null
}

export function WidgetList({ widgets }: { widgets: Widget[] }) {
  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
      {widgets.map((widget) => (
        <Card key={widget.id}>
          <CardHeader>
            <CardTitle>{widget.name}</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-muted-foreground">
              {widget.description || 'No description'}
            </p>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
```

### package.json

```json
{
  "name": "<app-name>",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev --turbopack",
    "build": "next build",
    "start": "next start",
    "lint": "eslint src/",
    "typecheck": "tsc --noEmit",
    "test": "jest",
    "test:watch": "jest --watch",
    "e2e": "playwright test",
    "db:migrate": "prisma migrate dev",
    "db:push": "prisma db push",
    "db:studio": "prisma studio",
    "db:seed": "tsx prisma/seed.ts"
  },
  "dependencies": {
    "@prisma/client": "^6",
    "lucide-react": "^1.7",
    "next": "16.x",
    "react": "19.x",
    "react-dom": "19.x",
    "shadcn": "^4.x",
    "tw-animate-css": "^1.x"
  },
  "devDependencies": {
    "@playwright/test": "^1",
    "@tailwindcss/postcss": "^4",
    "@testing-library/dom": "^10",
    "@testing-library/jest-dom": "^6",
    "@testing-library/react": "^16",
    "@types/jest": "^30",
    "@types/node": "^22",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "eslint": "^9",
    "eslint-config-next": "16.x",
    "jest": "^30",
    "jest-environment-jsdom": "^30",
    "prisma": "^6",
    "tailwindcss": "^4",
    "ts-jest": "^29",
    "tsx": "^4",
    "typescript": "^5"
  }
}
```

### next.config.ts

```typescript
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // No API rewrites needed — API routes live in the same app
}

export default nextConfig
```

### Jest config

```typescript
// jest.config.ts
import type { Config } from 'jest'
import nextJest from 'next/jest.js'

const createJestConfig = nextJest({ dir: './' })

const config: Config = {
  setupFilesAfterSetup: ['<rootDir>/jest.setup.ts'],
  testEnvironment: 'jsdom',
  moduleNameMapper: { '^@/(.*)$': '<rootDir>/src/$1' },
  testPathIgnorePatterns: ['/node_modules/', '/e2e/'],
}

export default createJestConfig(config)
```

```typescript
// jest.setup.ts
import '@testing-library/jest-dom'
```

### Testing

**Unit/component tests** with Jest + React Testing Library:

```typescript
// src/__tests__/components/widget-list.test.tsx
import { render, screen } from '@testing-library/react'
import { WidgetList } from '@/components/widget-list'

describe('WidgetList', () => {
  it('renders widget names', () => {
    const widgets = [
      { id: 1, name: 'Alpha', description: 'First widget' },
      { id: 2, name: 'Beta', description: null },
    ]
    render(<WidgetList widgets={widgets} />)
    expect(screen.getByText('Alpha')).toBeInTheDocument()
    expect(screen.getByText('Beta')).toBeInTheDocument()
  })

  it('shows placeholder for missing description', () => {
    render(<WidgetList widgets={[{ id: 1, name: 'Test', description: null }]} />)
    expect(screen.getByText('No description')).toBeInTheDocument()
  })
})
```

**API route tests** with Jest (mock Prisma):

```typescript
// src/__tests__/api/widgets.test.ts
import { GET } from '@/app/api/widgets/route'
import { prisma } from '@/lib/db'

jest.mock('@/lib/db', () => ({
  prisma: {
    widget: {
      findMany: jest.fn(),
    },
  },
}))

describe('GET /api/widgets', () => {
  it('returns widgets', async () => {
    const mockWidgets = [{ id: 1, name: 'Test', slug: 'test' }]
    ;(prisma.widget.findMany as jest.Mock).mockResolvedValue(mockWidgets)

    const response = await GET()
    const body = await response.json()

    expect(body.widgets).toEqual(mockWidgets)
    expect(response.status).toBe(200)
  })
})
```

### Auth

No. It's your machine.

### Dev environment

No DevBox required. Just MySQL running locally (Homebrew or DevBox, your choice):

```bash
# .env.local
DATABASE_URL="mysql://root@localhost:3306/<app-name>_dev"
```

### Ports

| Service | Port |
|---------|------|
| Next.js | 3000 (default) |
| MySQL | 3306 |
| Prisma Studio | 5555 |

### Checklist: new personal app

- [ ] `npx create-next-app@latest <app-name> --typescript --tailwind --eslint --app --src-dir`
- [ ] `cd <app-name> && npm install @prisma/client && npm install -D prisma tsx`
- [ ] `npx prisma init --datasource-provider mysql`
- [ ] `npx shadcn@latest init`
- [ ] Add commonly used shadcn components: `npx shadcn@latest add button card dialog input`
- [ ] Create `src/lib/db.ts` (Prisma singleton)
- [ ] Define initial schema in `prisma/schema.prisma`
- [ ] `npx prisma migrate dev --name init`
- [ ] Set up Jest: `jest.config.ts` + `jest.setup.ts`
- [ ] Create `src/__tests__/` directory structure
- [ ] Add `.specs` file (if spec-driven)
- [ ] Write CLAUDE.md with project-specific instructions
- [ ] Install pre-commit hook: `cp scripts/spec-check-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`

---

## Tier 3: Distributed

Identical to the personal tier, but the database is hosted in Supabase instead of running locally. The app still runs on your machine (or as a native/Electron app), but the data is shared — accessible from multiple devices or by other people.

### Example

[Sherlock](https://github.com/thanx-ai/sherlock) — a data investigation tool. Python/Flask dashboard runs locally, data lives in Supabase.

### What changes from personal

| Concern | Personal | Distributed |
|---------|----------|-------------|
| Database | Local MySQL | Supabase (Postgres) |
| Prisma provider | `mysql` | `postgresql` |
| Connection | `localhost:3306` | Supabase connection string |
| Auth | None | Supabase API key (service role or anon) |
| Data access | Single machine | Any device with the key |
| Migrations | `prisma migrate dev` (local) | `prisma migrate deploy` (remote) |

### Setup diff from personal

1. **Change Prisma provider** in `schema.prisma`:

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
```

2. **Set connection string** in `.env.local`:

```bash
DATABASE_URL="postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres"
```

3. **Optionally add Supabase client** for realtime, auth, or storage:

```bash
npm install @supabase/supabase-js
```

```typescript
// src/lib/supabase.ts
import { createClient } from '@supabase/supabase-js'

export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)
```

### When to use Supabase client vs Prisma

- **Prisma** — for all standard CRUD and queries. It's your ORM; Supabase is just the Postgres host.
- **Supabase client** — only when you need Supabase-specific features: realtime subscriptions, auth, file storage, edge functions.

Most distributed apps just use Prisma and treat Supabase as a hosted Postgres. The Supabase client is optional.

### Native/Electron variant

The distributed tier also covers apps that aren't web apps at all — Mac apps, Electron apps, CLIs — where the app is a local binary but the data lives in Supabase. In that case:

- Skip the Next.js frontend
- Use `@supabase/supabase-js` directly from your app (or any Postgres client)
- The Supabase API key is the only credential needed

### Checklist: converting personal to distributed

- [ ] Create a Supabase project at [supabase.com](https://supabase.com)
- [ ] Change Prisma provider from `mysql` to `postgresql`
- [ ] Update `DATABASE_URL` in `.env.local` to Supabase connection string
- [ ] Run `npx prisma migrate dev` to recreate migrations for Postgres
- [ ] Add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` to `.env.local` (if using Supabase client)
- [ ] Test locally — the app still runs on your machine, just talks to a remote DB

---

## Tier 4: Deployable

The full Thanx stack. See **[docs/thanx-dev-system.md](thanx-dev-system.md)** for the complete blueprint.

### Summary

- **Backend**: Rails 7.1 API-only + Grape + Interactors + MySQL + Redis/Sidekiq
- **Frontend**: Next.js (App Router) + TypeScript + shadcn/ui
- **Dev environment**: DevBox with MySQL + Redis services
- **Testing**: RSpec + FactoryBot (API), Jest + RTL + Playwright (UX)
- **Auth**: Google SSO via OmniAuth, session + bearer + test header
- **CI/CD**: CircleCI with parallel lint/test/build jobs
- **Deployment**: Docker multi-stage builds, ECS + ECR, Terraform
- **Ports**: API :3334, UX :3333 (local), both :3000 (prod)

### What makes it different from personal/distributed

| Concern | Personal/Distributed | Deployable |
|---------|---------------------|------------|
| API layer | Next.js API routes | Rails + Grape (separate process) |
| Database ORM | Prisma | ActiveRecord |
| Business logic | Inline in API routes | Interactors |
| Auth | None / API key | Google SSO + bearer tokens |
| Dev environment | npm scripts + local or remote DB | DevBox with managed services |
| Testing (API) | Jest with mocked Prisma | RSpec + FactoryBot + real DB |
| CI/CD | None | CircleCI pipeline |
| Docker | None | Multi-stage builds |
| Infrastructure | None | Terraform + ECS + ECR |

### Why it's a rebuild

Going from personal/distributed to deployable means replacing the entire API layer (Next.js route handlers to Rails + Grape), swapping the ORM (Prisma to ActiveRecord), adding auth, CI/CD, Docker, and Terraform. The Next.js frontend carries over to the `ux/` directory with minimal changes, but everything else is new. Start with the deployable blueprint from day one if you know the app needs to be production-grade.

---

## Conventions shared across all tiers

| Convention | All tiers |
|------------|-----------|
| Formatting | Prettier (tiers 2-4) |
| Linting | ESLint (tiers 2-4) |
| Package manager | npm (when applicable) |
| Git | Commit every logical unit of work |
| Specs | `.specs` file opts in to spec-driven development |
| CLAUDE.md | Every project gets one |
