# Thanx Approved Dev System

A fast-launch blueprint for new Thanx applications. Based on Sketch (sketch.thanx.com) and Sherlock — the two reference implementations of the Thanx stack.

---

## Quick Start

```bash
# 1. Clone the template / create your repo
mkdir <app-name> && cd <app-name>
git init

# 2. Create the monorepo skeleton
mkdir -p api ux ops devbox.d/mysql80 devbox.d/redis

# 3. Initialize each layer
cd api && rails new . --api --database=mysql --skip-test --skip-system-test && cd ..
cd ux && npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir && cd ..

# 4. Enter devbox and install
devbox shell
devbox run setup
devbox run setup:db
```

---

## Architecture

```
<app-name>/
├── api/                    # Rails 7.1 API-only backend
│   ├── app/api/v1/         # Grape REST endpoints
│   ├── app/models/         # ActiveRecord models
│   ├── app/interactors/    # Business logic (interactor gem)
│   ├── config/             # Rails config, database.yml, initializers
│   ├── db/migrate/         # Schema migrations
│   ├── spec/               # RSpec test suite
│   │   ├── api/v1/         # Endpoint specs (*_api_spec.rb)
│   │   ├── models/         # Model specs (*_spec.rb)
│   │   ├── factories/      # FactoryBot definitions
│   │   ├── rails_helper.rb
│   │   └── spec_helper.rb
│   ├── Dockerfile          # Multi-stage production build
│   └── Gemfile
├── ux/                     # Next.js frontend (App Router)
│   ├── src/app/            # App Router pages and layouts
│   ├── src/lib/api/        # Typed API client
│   ├── src/components/     # React components
│   │   └── ui/             # shadcn/ui base components
│   ├── src/__tests__/      # Jest unit tests
│   ├── e2e/                # Playwright E2E tests
│   ├── Dockerfile          # Multi-stage production build
│   └── package.json
├── cli/                    # Go CLI (optional, for tooling)
├── ops/                    # Terraform infrastructure
├── devbox.json             # Development environment
├── devbox.d/               # Service definitions (MySQL, Redis)
│   ├── mysql80/my.cnf
│   └── redis/redis.conf
├── .circleci/config.yml    # CI/CD pipeline
├── specs/                  # SPEC files (if spec-driven)
└── CLAUDE.md               # AI assistant instructions
```

---

## Layer 1: Rails API

### Gemfile

```ruby
source 'https://rubygems.org'
ruby '>= 3.2'

gem 'rails', '~> 7.1'
gem 'grape', '~> 2.0'
gem 'grape-entity', '~> 1.0'
gem 'mysql2', '~> 0.5'
gem 'puma', '~> 6.0'
gem 'interactor-rails', '~> 2.2'
gem 'rack-cors'
gem 'omniauth-google-oauth2', '~> 1.1'
gem 'omniauth-rails_csrf_protection', '~> 1.0'

group :development, :test do
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails', '~> 6.0'
  gem 'shoulda-matchers', '~> 6.0'
  gem 'rubocop', '~> 1.0', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
end
```

### Rails Application Config

```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true

    # Grape API autoloading
    config.autoload_paths << root.join('app/api')
    config.eager_load_paths << root.join('app/api')

    config.autoloader = :zeitwerk
    initializer 'api_inflections', before: :setup_main_autoloader do
      Rails.autoloaders.main.inflector.inflect('api' => 'API')
    end

    # CORS — update origins for your app
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins 'https://your-app.thanx.com', 'http://localhost:3333'
        resource '*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options],
          credentials: true
      end
    end

    config.secret_key_base = ENV.fetch('SECRET_KEY_BASE', 'dev-secret-key-base-change-in-production')
  end
end
```

### Grape API Pattern

All endpoints live under `app/api/v1/`. A base class mounts everything:

```ruby
# app/api/v1/base.rb
module V1
  class Base < Grape::API
    version 'v1', using: :path

    helpers V1::Helpers::AuthHelpers

    mount V1::Users
    mount V1::Widgets
    # mount additional resources here
  end
end
```

Endpoint convention — RESTful resources with inline serializers:

```ruby
# app/api/v1/widgets.rb
module V1
  class Widgets < Grape::API
    resource :widgets do
      before { authenticate_user! }

      desc 'List widgets'
      params do
        optional :status, type: String, values: %w[active archived]
      end
      get do
        widgets = Widget.where(owner: current_user)
        widgets = widgets.where(status: params[:status]) if params[:status]
        { widgets: widgets.map { |w| serialize_widget(w) } }
      end

      desc 'Create a widget'
      params do
        requires :name, type: String
        optional :description, type: String
      end
      post do
        result = Widgets::Create.call(
          user: current_user,
          name: params[:name],
          description: params[:description]
        )
        if result.success?
          serialize_widget(result.widget)
        else
          error!({ errors: result.errors }, 422)
        end
      end

      route_param :id do
        get do
          widget = Widget.find(params[:id])
          serialize_widget(widget)
        end
      end
    end

    helpers do
      def serialize_widget(widget)
        {
          id: widget.id,
          name: widget.name,
          description: widget.description,
          created_at: widget.created_at
        }
      end
    end
  end
end
```

### Auth Helpers

Three-tier authentication — session (web), bearer token (CLI/API), test header:

```ruby
# app/api/v1/helpers/auth_helpers.rb
module V1
  module Helpers
    module AuthHelpers
      def current_user
        @current_user ||= authenticate_user
      end

      def authenticate_user!
        error!({ error: 'Unauthorized' }, 401) unless current_user
      end

      private

      def authenticate_user
        # Test environment: X-Test-User-Id header
        if Rails.env.test? && env['HTTP_X_TEST_USER_ID']
          return User.find_by(id: env['HTTP_X_TEST_USER_ID'])
        end

        # Session auth (browser)
        if env['rack.session'] && env['rack.session'][:user_id]
          return User.find_by(id: env['rack.session'][:user_id])
        end

        # Bearer token (CLI / API consumers)
        auth_header = headers['Authorization'] || env['HTTP_AUTHORIZATION']
        if auth_header&.start_with?('Bearer ')
          token = auth_header.sub('Bearer ', '')
          return AccessToken.validate(token)
        end

        nil
      end
    end
  end
end
```

### Interactor Pattern

Business logic lives in interactors, not in Grape endpoints or models:

```ruby
# app/interactors/widgets/create.rb
module Widgets
  class Create
    include Interactor

    def call
      widget = Widget.new(
        name: context.name,
        description: context.description,
        owner: context.user
      )

      if widget.save
        context.widget = widget
      else
        context.fail!(errors: widget.errors.full_messages)
      end
    end
  end
end
```

**Rules:**
- One interactor per action (`Create`, `Update`, `Archive`, `Export`)
- Pass inputs via `context`
- Use `context.fail!` for errors (never raise)
- Return results on `context` (e.g., `context.widget = widget`)

### Model Conventions

```ruby
# app/models/project.rb
class Project < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  has_many :widgets, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :search, ->(query) {
    return all if query.blank?
    where('name LIKE :q OR description LIKE :q', q: "%#{query}%")
  }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  private

  def generate_slug
    base = name.to_s.downcase.gsub(/[^a-z0-9\s-]/, '').gsub(/\s+/, '-')
    candidate = base
    counter = 2
    while self.class.exists?(slug: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug = candidate
  end
end
```

**Patterns:**
- Soft deletes via `archived_at` timestamp (not gem-based)
- Auto-generated slugs with uniqueness collision handling
- Named scopes for common filters (`active`, `archived`, `search`)
- Explicit `null: false` in migrations, `validates :presence` in models

### Migration Style

```ruby
class CreateWidgets < ActiveRecord::Migration[7.1]
  def change
    create_table :widgets do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.datetime :archived_at

      t.timestamps
    end

    add_index :widgets, :slug, unique: true
  end
end
```

---

## Layer 2: Next.js Frontend

### package.json

```json
{
  "name": "ux",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "eslint",
    "typecheck": "tsc --noEmit",
    "format:check": "prettier --check .",
    "test": "jest",
    "e2e": "playwright test"
  },
  "dependencies": {
    "lucide-react": "^1.7.0",
    "next": "16.x",
    "react": "19.x",
    "react-dom": "19.x",
    "shadcn": "^4.x",
    "tw-animate-css": "^1.x"
  },
  "devDependencies": {
    "@playwright/test": "^1.x",
    "@tailwindcss/postcss": "^4",
    "@testing-library/dom": "^10.x",
    "@testing-library/jest-dom": "^6.x",
    "@testing-library/react": "^16.x",
    "@types/jest": "^30.x",
    "@types/node": "^20",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "eslint": "^9",
    "eslint-config-next": "16.x",
    "jest": "^30.x",
    "jest-environment-jsdom": "^30.x",
    "tailwindcss": "^4",
    "ts-jest": "^29.x",
    "typescript": "^5"
  }
}
```

### Next.js Config — API Rewrites

Next.js proxies API calls to the Rails backend. This is the glue between layers:

```typescript
// next.config.ts
import type { NextConfig } from "next";

const RAILS_API = process.env.RAILS_API_URL || "http://localhost:3334";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      // Resource-specific rewrites (customize per app)
      {
        source: "/api/widgets/:path*",
        destination: `${RAILS_API}/api/v1/widgets/:path*`,
      },
      {
        source: "/api/widgets",
        destination: `${RAILS_API}/api/v1/widgets`,
      },
      // Catch-all for versioned API
      {
        source: "/api/v1/:path*",
        destination: `${RAILS_API}/api/v1/:path*`,
      },
      // Generic fallback
      {
        source: "/api/:path*",
        destination: `${RAILS_API}/api/:path*`,
      },
    ];
  },
};

export default nextConfig;
```

### Auth Middleware

Session-based auth with Google SSO and local dev bypass:

```typescript
// src/middleware.ts
import { NextRequest, NextResponse } from 'next/server';

const PUBLIC_PATHS = ['/auth', '/health', '/_next', '/favicon.ico', '/api'];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (PUBLIC_PATHS.some((path) => pathname.startsWith(path))) {
    return NextResponse.next();
  }

  const sessionCookie = request.cookies.get('_yourapp_session');
  if (!sessionCookie) {
    const apiUrl = process.env.API_URL || 'http://localhost:3334';
    const isLocal = !apiUrl.includes('yourapp.thanx.com');
    if (isLocal) {
      const returnTo = encodeURIComponent(request.nextUrl.origin);
      return NextResponse.redirect(`${apiUrl}/auth/dev_login?return_to=${returnTo}`);
    }
    return NextResponse.redirect(`${apiUrl}/auth/google_oauth2`);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
```

### Typed API Client

Single module, one function per endpoint, typed responses:

```typescript
// src/lib/api/client.ts
export class ApiClientError extends Error {
  status: number;
  body: unknown;
  constructor(message: string, status: number, body?: unknown) {
    super(message);
    this.name = 'ApiClientError';
    this.status = status;
    this.body = body;
  }
}

export async function apiClient<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const url = path.startsWith('/') ? path : `/${path}`;
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
    credentials: 'include',
  });

  if (!res.ok) {
    let body: unknown;
    try { body = await res.json(); } catch { body = null; }
    throw new ApiClientError(
      `API error ${res.status}: ${res.statusText}`,
      res.status,
      body
    );
  }

  if (res.status === 204) return undefined as T;

  const contentType = res.headers.get('content-type') || '';
  if (contentType.includes('application/json')) return res.json();
  return res.text() as T;
}

// --- Typed endpoints ---

export interface Widget {
  id: number;
  name: string;
  slug: string;
  description: string | null;
  created_at: string;
}

export async function getWidgets(): Promise<Widget[]> {
  const data = await apiClient<{ widgets: Widget[] }>('/api/widgets');
  return data.widgets;
}

export async function createWidget(params: {
  name: string;
  description?: string;
}): Promise<Widget> {
  return apiClient<Widget>('/api/widgets', {
    method: 'POST',
    body: JSON.stringify(params),
  });
}

export async function getCurrentUser(): Promise<User> {
  return apiClient<User>('/api/v1/me');
}
```

**Key conventions:**
- `credentials: 'include'` for session cookies
- Generic `apiClient<T>()` handles all fetch + error logic
- Each endpoint gets its own typed function
- No state management library needed for most apps (React hooks + fetch)

### Component Library

Use **shadcn/ui** for platform UI. Install components as needed:

```bash
cd ux && npx shadcn@latest add button card dialog tabs
```

Components land in `src/components/ui/` and are fully customizable.

### Jest Config

```typescript
// jest.config.ts
import type { Config } from "jest";
import nextJest from "next/jest.js";

const createJestConfig = nextJest({ dir: "./" });

const config: Config = {
  setupFilesAfterSetup: ["<rootDir>/jest.setup.ts"],
  testEnvironment: "jsdom",
  moduleNameMapper: { "^@/(.*)$": "<rootDir>/src/$1" },
  testPathIgnorePatterns: ["/node_modules/", "/e2e/"],
};

export default createJestConfig(config);
```

```typescript
// jest.setup.ts
import "@testing-library/jest-dom";
```

---

## Layer 3: DevBox Environment

### devbox.json

```json
{
  "packages": {
    "ruby": "3.4.2",
    "bundler": "2.6.2",
    "nodejs": "24.2.0",
    "yarn": "1.22.22",
    "mysql80": "8.0.41",
    "redis": "7.2.7",
    "go": "1.24.3",
    "terraform": "1.14.4"
  },
  "shell": {
    "init_hook": [
      "echo '<app-name> devbox ready. Run `devbox run setup` to install dependencies.'"
    ],
    "scripts": {
      "setup": ["cd api && bundle install && cd ../ux && yarn install"],
      "setup:db": ["cd api && bundle exec rake db:create db:migrate"],
      "api:server": ["cd api && bundle exec rails server -p 3334"],
      "api:console": ["cd api && bundle exec rails console"],
      "api:test": ["cd api && bundle exec rspec"],
      "api:lint": ["cd api && bundle exec rubocop"],
      "ux:dev": ["cd ux && yarn dev -p 3333"],
      "ux:build": ["cd ux && yarn build"],
      "ux:test": ["cd ux && yarn test"],
      "ux:lint": ["cd ux && yarn lint"],
      "services:up": ["devbox services up"],
      "services:down": ["devbox services stop"]
    }
  },
  "env": {
    "MYSQL_UNIX_PORT": "$MYSQL_UNIX_PORT",
    "BUNDLE_BUILD__PSYCH": "--with-libyaml-dir=/opt/homebrew/opt/libyaml"
  }
}
```

### Ports

| Service    | Local Port | Production Port |
|------------|-----------|-----------------|
| Rails API  | 3334      | 3000            |
| Next.js UX | 3333      | 3000            |
| MySQL      | 3306      | 3306            |
| Redis      | 6379      | 6379            |

### Running Locally

```bash
devbox shell                # Enter environment
devbox run services:up      # Start MySQL + Redis
devbox run setup            # Install deps (first time)
devbox run setup:db         # Create + migrate DB (first time)
devbox run api:server       # Terminal 1: Rails on :3334
devbox run ux:dev           # Terminal 2: Next.js on :3333
```

---

## Layer 4: Testing

### Rails API — RSpec + FactoryBot

**rails_helper.rb** (standard setup):

```ruby
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rspec/rails'
require 'shoulda/matchers'

Shoulda::Matchers.configure do |c|
  c.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.fixture_paths = [Rails.root.join('spec/fixtures')]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
```

**Factory pattern:**

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@thanx.com" }
    sequence(:google_uid) { |n| "google_uid_#{n}" }
    name { 'Test User' }
  end
end
```

**API spec pattern:**

```ruby
# spec/api/v1/widgets_api_spec.rb
require 'rails_helper'

RSpec.describe V1::Widgets, type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { 'X-Test-User-Id' => user.id.to_s } }

  describe 'GET /api/v1/widgets' do
    it 'returns the user widgets' do
      create_list(:widget, 3, owner: user)

      get '/api/v1/widgets', headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['widgets'].length).to eq(3)
    end

    it 'returns 401 without auth' do
      get '/api/v1/widgets'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

**Model spec pattern:**

```ruby
# spec/models/widget_spec.rb
require 'rails_helper'

RSpec.describe Widget, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to belong_to(:owner).class_name('User') }
  end

  describe 'slug generation' do
    it 'generates a kebab-case slug from name' do
      widget = create(:widget, name: 'My Cool Widget')
      expect(widget.slug).to eq('my-cool-widget')
    end
  end
end
```

### Frontend — Jest + Playwright

**API client tests** (mock global fetch):

```typescript
const mockFetch = jest.fn();
global.fetch = mockFetch;

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    headers: new Headers({ 'content-type': 'application/json' }),
    json: () => Promise.resolve(body),
    text: () => Promise.resolve(JSON.stringify(body)),
  };
}

describe('getWidgets', () => {
  it('fetches widgets with credentials', async () => {
    mockFetch.mockResolvedValue(jsonResponse({ widgets: [] }));
    const result = await getWidgets();
    expect(result).toEqual([]);
    expect(mockFetch).toHaveBeenCalledWith(
      '/api/widgets',
      expect.objectContaining({ credentials: 'include' })
    );
  });
});
```

**Playwright E2E** — saved auth state, browser-level integration tests.

### Running Tests

```bash
cd api && bundle exec rspec         # Rails specs
cd ux && yarn test                  # Jest unit tests
cd ux && yarn e2e                   # Playwright E2E
```

---

## Layer 5: Docker

### Rails API Dockerfile

Multi-stage build, jemalloc, non-root user:

```dockerfile
ARG RUBY_VERSION=3.4.2
FROM ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl default-mysql-client libjemalloc2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="libjemalloc.so.2"

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential default-libmysqlclient-dev git pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .
RUN cp config/database.build.yml config/database.yml && \
    bundle exec bootsnap precompile --gemfile app/ lib/

FROM base
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log tmp
USER 1000:1000

ENTRYPOINT ["./bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
```

### Next.js Dockerfile

Multi-stage build, Alpine, standalone output:

```dockerfile
FROM node:24.2.0-alpine AS base

FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json yarn.lock* package-lock.json* ./
RUN if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
    elif [ -f package-lock.json ]; then npm ci; \
    else npm install; fi

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
RUN mkdir .next && chown nextjs:nodejs .next
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000 HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

---

## Layer 6: CI/CD (CircleCI)

### Pipeline Structure

```yaml
version: 2.1

orbs:
  aws-ecr: circleci/aws-ecr@6.5.0
  ruby: circleci/ruby@2.0.1
  thanx-services: thanx/thanx-services@0.35.1

executors:
  ruby:
    docker:
      - image: cimg/ruby:3.4.2
        environment:
          BUNDLE_JOBS: "3"
          BUNDLE_RETRY: "3"
          BUNDLE_PATH: vendor/bundle

  ruby_app:
    docker:
      - image: cimg/ruby:3.4.2
        environment:
          BUNDLE_JOBS: "3"
          BUNDLE_RETRY: "3"
          BUNDLE_PATH: vendor/bundle
      - image: cimg/mysql:8.0
        environment:
          MYSQL_ALLOW_EMPTY_PASSWORD: "true"
          MYSQL_ROOT_HOST: "%"
        command: --sql_mode=IGNORE_SPACE,STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION

  node:
    docker:
      - image: cimg/node:24.2.0

  aws:
    docker:
      - image: cimg/python:3.9.2
```

### Jobs

**API jobs:**
- `api-lint` — `bundle exec rubocop`
- `api-security` — `bundle exec brakeman --no-pager`
- `api-test` — RSpec with parallelism=2, JUnit output, test splitting by timings

**UX jobs:**
- `ux-lint` — `npm run lint`
- `ux-typecheck` — `tsc --noEmit`
- `ux-format` — `prettier --check .`
- `ux-test` — Jest with JUnit output

### Workflows

```yaml
workflows:
  build-test:
    jobs:
      - api-lint
      - api-security
      - api-test
      - ux-lint
      - ux-typecheck
      - ux-format
      - ux-test
    # All run in parallel on non-production branches

  deploy-production:
    jobs:
      - build-api        # Docker build + push to ECR
      - build-ux         # Docker build + push to ECR
      - migrate:         # Run DB migrations on ECS
          requires: [build-api]
      - update-api:      # Update ECS service
          requires: [migrate]
      - update-ux:       # Update ECS service
          requires: [build-ux]
    # Only runs on `production` branch
```

### Deployment

- Push to `production` branch triggers deploy
- Docker images tagged with `${CIRCLE_SHA1}`, pushed to ECR
- Migrations run as a separate ECS task before service update
- ECS services updated sequentially (API after migration, UX after build)
- Terraform for infrastructure changes (separate `ops` workflow)

---

## Layer 7: Authentication

### Google SSO (OmniAuth)

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV.fetch('GOOGLE_CLIENT_ID'),
    ENV.fetch('GOOGLE_CLIENT_SECRET'),
    {
      scope: 'email,profile',
      prompt: 'select_account',
      hd: 'thanx.com'  # Restrict to Thanx domain
    }
end
```

### Session Config

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: '_yourapp_session',
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax
```

### Auth Flow

1. **User visits app** → Next.js middleware checks for session cookie
2. **No cookie** → Redirect to Rails `/auth/google_oauth2` (prod) or `/auth/dev_login` (local)
3. **Google OAuth** → Callback creates/updates User, sets session cookie
4. **Subsequent requests** → Session cookie validated by Grape auth helper
5. **API/CLI access** → Bearer token via device authorization flow (optional)

### Dev Login Bypass

For local development without Google credentials:

```ruby
# config/routes.rb (development only)
if Rails.env.development?
  get '/auth/dev_login', to: 'sessions#dev_login'
end
```

This auto-creates a test user and sets the session cookie. No Google credentials needed locally.

---

## Environment Variables

### Required in Production

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY_BASE` | Rails session encryption |
| `GOOGLE_CLIENT_ID` | Google OAuth app ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth secret |
| `RAILS_API_URL` | Next.js → Rails proxy target |
| `APP_URL` | Public URL for links/redirects |

### Optional / Defaults

| Variable | Default | Purpose |
|----------|---------|---------|
| `RAILS_API_URL` | `http://localhost:3334` | API backend URL |
| `MYSQL_UNIX_PORT` | `$MYSQL_UNIX_PORT` | DevBox MySQL socket |

---

## Checklist: New App Launch

### Day 1 — Skeleton

- [ ] Create repo with monorepo structure (`api/`, `ux/`, `ops/`)
- [ ] Copy `devbox.json` and `devbox.d/` service configs
- [ ] Initialize Rails API (`rails new . --api --database=mysql`)
- [ ] Initialize Next.js (`npx create-next-app@latest . --typescript --tailwind --app --src-dir`)
- [ ] Add Grape, interactors, OmniAuth to Gemfile
- [ ] Add shadcn, testing deps to package.json
- [ ] Set up `next.config.ts` with API rewrites
- [ ] Set up auth middleware in Next.js

### Day 1 — Foundation

- [ ] Create User model + migration
- [ ] Set up OmniAuth Google callback + session store
- [ ] Create auth helpers (session + bearer + test header)
- [ ] Create dev login bypass for local development
- [ ] Set up RSpec + FactoryBot + Shoulda Matchers
- [ ] Set up Jest + Testing Library
- [ ] Write first factory (`:user`)
- [ ] Write first API spec (auth endpoint)
- [ ] Set up API client (`src/lib/api/client.ts`)

### Day 2 — CI/CD

- [ ] Create `.circleci/config.yml` with lint/test/build jobs
- [ ] Create Dockerfiles for API and UX
- [ ] Set up ECR repos
- [ ] Set up ECS cluster + services
- [ ] Configure Terraform in `ops/`
- [ ] Test full deploy pipeline

### Day 2 — Ship

- [ ] Build first feature (Grape endpoint + interactor + model + Next.js page)
- [ ] Write specs for the feature
- [ ] Deploy to production
- [ ] Verify Google SSO works with `hd: 'thanx.com'`

---

## Conventions Summary

| Area | Convention |
|------|-----------|
| API framework | Grape, versioned under `/api/v1/` |
| Business logic | Interactors (one per action) |
| Serialization | Inline in Grape helpers (not separate classes) |
| Authentication | Session (web) + Bearer (API) + Test header |
| Models | Soft deletes via `archived_at`, auto-slug generation |
| Frontend | Next.js App Router, TypeScript strict |
| Components | shadcn/ui for platform chrome |
| API calls | Typed `apiClient<T>()` wrapper with `credentials: 'include'` |
| Testing (API) | RSpec + FactoryBot + Shoulda Matchers |
| Testing (UX) | Jest + Testing Library + Playwright E2E |
| Linting | RuboCop (API) + ESLint + Prettier (UX) |
| Docker | Multi-stage builds, non-root users |
| CI/CD | CircleCI, parallel jobs, deploy on `production` branch |
| Infra | ECS + ECR + Terraform |
| Local dev | DevBox with MySQL + Redis services |
| Ports | API :3334, UX :3333 (local), both :3000 (prod) |
