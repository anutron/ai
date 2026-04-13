![The data proxy](recipe4_data-proxy-glovebox.png)

# Recipe 4: The data proxy

## The idea

When an organization wants Claude Code to access business data – databases, APIs, dashboards, email – the simplest approach is to give Claude the credentials and let it call the APIs directly. This is also the most dangerous approach. Claude is helpful and resourceful; if it has credentials, it will use them. If those credentials grant write access to a production system, a well-intentioned request can cause real damage.

Many external services and MCP integrations lack granular permissions. They're all-or-nothing: you either have access or you don't. If a Gmail MCP includes both "draft an email" and "send an email," you can't turn off sending without losing drafting. If a database MCP allows SELECT queries, it probably also allows DELETE. The service doesn't give you the controls you need to trust Claude's actions.

A data proxy – sometimes called a cutout – sits between Claude and the systems where the blast radius exists. Claude talks to the proxy. The proxy talks to the real system. Claude never holds the keys to the real system and – critically – is prevented from finding them.

Examples of what a proxy might do:

- **Filter operations** – Pass through most of the upstream service's functionality, but remove the dangerous parts. Drafting is fine; sending is not. Reading is fine; deleting requires confirmation.
- **Scrub data** – Strip PII from query results before they reach Claude. The upstream returns a full customer record; the proxy redacts the SSN and credit card.
- **Control access by role** – Different users or departments see different tool sets.

The proxy's interface mirrors the service it wraps – the contract is identical except where it explicitly is not. A `get_user` call through the proxy returns the same shape as `get_user` on the real service, minus the PII fields. This makes the proxy transparent to Claude and the user: it feels like the real service, with guardrails.

## How it works

A data proxy can take several forms: an MCP server, a CLI tool, or a local application that exposes an API. What matters is that it sits between Claude and the real system, holds the upstream credentials, and decides what operations to expose and what data to return.

- **MCP server** – Claude discovers it like any other MCP integration. Tools appear automatically.
- **CLI** – A command-line tool (Go + Cobra is a great choice) with specific flags and well-defined input/output contracts. Claude calls it via Bash.
- **Local application server** – A lightweight HTTP API running locally. Claude calls it via curl or an MCP wrapper.

The implementation choice matters less than the principle: something sits in the middle, and Claude cannot go around it.

### The credential isolation principle

The proxy holds credentials for the upstream system (API keys, OAuth tokens, database passwords). Claude authenticates to the proxy – typically via a user-specific token – but never sees the upstream credentials.

This separation is necessary but not sufficient. You must also **actively prevent Claude from discovering the upstream credentials.** Claude is helpful; if it finds an API key in a config file, it may try to use it directly, bypassing the proxy entirely.

Protections:
- **Deny rules** in Claude Code settings – configure file paths that Claude cannot read (e.g., the directory where proxy credentials are stored)
- **Environment variables loaded outside Claude's reach** – credentials set in a shell profile that Claude's sandbox doesn't inherit
- **System keychain** – macOS Keychain, 1Password CLI, or similar – credentials that require OS-level authentication to access

The goal: two completely separate credential chains. Claude knows how to talk to the proxy. The proxy knows how to talk to the real system. Claude has no path to the real system.

Distributing these protections across an organization can be handled through a Claude Code plugin (which can include settings and deny rules that apply to every session) or through a setup/install script that configures each user's environment.

### Concrete example: email proxy

Imagine the Gmail MCP includes the ability to send emails alongside the ability to draft them, and you don't want Claude to have the power to send. You can't turn off sending without losing drafting – the service lacks the granular controls you need.

An email proxy wraps the Gmail API and exposes:
- **Search** – Find emails matching a query (pass-through)
- **Read** – Get the content of a specific thread (pass-through)
- **Draft** – Create a draft (pass-through)

Sending is not exposed. Deleting is not exposed. The proxy doesn't change the interface for the operations it does expose – search works exactly like Gmail search. It just removes the operations that carry unacceptable blast radius. Claude can find that email thread you need and draft a response, but it cannot send a message as you or delete anything from your inbox.

### Who builds the proxy

Building the proxy may require temporarily giving Claude direct API access so it can survey the upstream service's capabilities – understanding the endpoints, data shapes, and authentication patterns. This surveying phase is how the proxy gets built.

The important thing: **the person wielding Claude to build the proxy should be the most experienced person on the team.** They understand the blast radius, they know which operations are dangerous, and they can make informed decisions about what the proxy exposes. The result is a safe mechanism that everyone else uses – the less experienced users never need direct API access.

## Three tiers of proxy sophistication

Choose the tier that matches your organization's technical capability and risk tolerance.

### Tier 1: Local proxy

A process that runs on the user's machine, wrapping an API with guardrails. It can be a local MCP server, a CLI tool, or a local application that exposes an API. The dangerous operations are simply absent.

- **No hosting, no internet exposure** – runs locally
- **Simplest to build** – a small MCP server, CLI, or local app that makes API calls on behalf of the user
- **Good for:** Individual contributors or small teams where each person runs their own proxy
- **Limitation:** No organizational visibility into usage

### Tier 2: Distributed proxy with shared logging

The same local proxy pattern, but it phones home to a shared database (Supabase, Notion, etc.) for audit logging. Each user runs the proxy locally; logs aggregate centrally.

- **Local execution, shared observability** – the proxy runs on the user's machine but logs queries and results to a central store
- **Moderate complexity** – requires a shared database and API keys for logging
- **Good for:** Organizations that want to see what data is being accessed across the team
- **Limitation:** No centralized enforcement – each user's proxy is independently configured

### Tier 3: Hosted proxy

> **⚠️ DO NOT BUILD THIS UNLESS YOUR ORGANIZATION HAS PROFESSIONAL SOFTWARE DEVELOPMENT AND SECURITY EXPERTISE.**

A server on the internet that all AI tool requests route through. Maximum control: centralized configuration, per-user access control, rate limiting, audit logging, compliance gating.

- **Centralized control** – one proxy serves all users, configuration changes apply immediately
- **Maximum observability** – every query is logged and attributable
- **Significant complexity and significant risk** – this is a server on the internet that holds production credentials to your business systems. A misconfigured proxy is worse than no proxy at all. A breach of the proxy is a breach of every upstream system it connects to.
- **This is not something to prototype casually or to vibe-code.** It requires proper authentication, TLS, rate limiting, security audits, and ongoing operational attention.

### Progression

Most organizations should start at Tier 1 or 2. Build a local proxy for the most common data access patterns, add shared logging when you want organizational visibility, and only graduate to Tier 3 if you have the engineering capacity to operate it safely.

---

## Diagram

```
┌────────────────────────────────────────────────────────┐
│  Tier 1: Local proxy                                   │
│                                                        │
│  Claude ──▶ Proxy (local) ──▶ Real API                 │
│             │                  │                       │
│             │ Holds API keys   │ Production system     │
│             │ Mirrors most ops │                       │
│             │ Removes dangerous│                       │
│             │ Scrubs PII       │                       │
│             └──────────────────┘                       │
│                                                        │
│  Claude cannot see the API keys.                       │
│  Claude cannot call operations the proxy doesn't       │
│  expose. The proxy is the boundary.                    │
│                                                        │
│  Proxy can be: MCP server, CLI, or local app           │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│  Tier 2: Distributed with shared logging               │
│                                                        │
│  Claude ──▶ Proxy (local) ──▶ Real API                 │
│                  │                                     │
│                  ▼                                     │
│           Shared database                              │
│           (Supabase, Notion, etc.)                     │
│           ├── Who queried what                         │
│           ├── When                                     │
│           └── Aggregated usage                         │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│  Tier 3: Hosted proxy                                  │
│  ⚠️  REQUIRES PROFESSIONAL SECURITY EXPERTISE          │
│                                                        │
│  Claude ──▶ Proxy (hosted) ──▶ Real API                │
│             │                                          │
│             ├── Centralized config                     │
│             ├── Per-user access control                │
│             ├── Compliance gating (Recipe 3)           │
│             ├── Rate limiting                          │
│             └── Full audit logging                     │
│                                                        │
│  Holds production credentials on the internet.         │
│  A breach here = breach of all upstream systems.       │
└────────────────────────────────────────────────────────┘
```

---

## Technical reference for Claude

When helping a user build a data proxy, follow these principles:

### MCP server structure

```
your-proxy-mcp/
├── src/
│   └── index.ts          # MCP server definition, tool handlers
├── package.json          # Dependencies (MCP SDK)
├── tsconfig.json
└── README.md
```

Use the MCP SDK (Node.js/TypeScript is the most mature). Each tool the proxy exposes maps to one operation on the upstream API.

### CLI proxy structure

```
your-proxy-cli/
├── cmd/
│   ├── root.go           # Cobra root command
│   ├── search.go         # search subcommand
│   ├── read.go           # read subcommand
│   └── draft.go          # draft subcommand
├── internal/
│   └── client/
│       └── upstream.go   # Upstream API client (holds credentials)
├── go.mod
├── go.sum
└── README.md
```

Go + Cobra is well-suited for proxy CLIs: single binary, explicit flags, well-defined input/output contracts. Each subcommand maps to one upstream operation.

### Interface design

The proxy's interface mirrors the upstream service it wraps. The contract is identical except where it explicitly differs:

- **Pass-through operations** return the same shape as the upstream. `proxy search "invoices Q4"` returns the same result format as searching the real service.
- **Scrubbed operations** return the same shape with sensitive fields redacted or omitted. `proxy get_customer 123` returns the customer record minus PII.
- **Removed operations** simply don't exist. There is no `proxy send_email` command. Claude cannot call what doesn't exist.

The goal is transparency: the proxy feels like the real service, with guardrails. Users and Claude don't need to learn a new interface – they just can't do the dangerous things.

### Building the proxy

The person building the proxy may need to give Claude temporary direct API access to survey the upstream service – understanding endpoints, data shapes, and auth patterns. This is a bootstrapping step done by the most experienced person on the team. Once the proxy is built, everyone else uses the proxy; they never need direct access.

Things to be thoughtful about when designing the proxy:

- **Which operations carry blast radius?** Anything that modifies state in the upstream system (writes, deletes, sends) deserves careful consideration.
- **What data is sensitive?** PII, financial data, credentials, internal identifiers – consider scrubbing or redacting before data reaches Claude.
- **What's the right balance between leverage and safety?** The whole point of the proxy is finding this balance. Too restrictive and it's not useful; too permissive and it's not safe.

### Credential isolation implementation

1. **Store upstream credentials outside Claude's reach:**
   ```json
   // In Claude settings – deny read access to credential storage
   {
     "permissions": {
       "deny": [
         "Read: ~/.config/your-proxy/credentials.json",
         "Read: ~/.your-proxy/.env"
       ]
     }
   }
   ```

2. **Load credentials in the proxy process, not via Claude:**
   ```typescript
   // MCP server example – reads its own credentials at startup
   const apiKey = process.env.UPSTREAM_API_KEY;
   ```
   ```go
   // CLI example – reads credentials from keychain or config
   apiKey := os.Getenv("UPSTREAM_API_KEY")
   ```

3. **Distribute deny rules across the org** via one of:
   - **Claude Code plugin** – Include a settings file with deny rules. Every user who installs the plugin gets the protection automatically.
   - **Setup/install script** – A script that configures each user's Claude Code settings to include the deny rules.
   - **CLAUDE.md instruction** – A rule in the project's CLAUDE.md explicitly telling Claude not to access certain paths or use certain credentials directly.

### Logging schema (for Tier 2)

```sql
CREATE TABLE proxy_queries (
  id BIGSERIAL PRIMARY KEY,
  user_email TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  query_params JSONB,
  result_summary TEXT,          -- e.g., "returned 15 rows" (not the actual data)
  queried_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Log the query metadata, not the full results. The goal is observability (who's querying what, how often) not surveillance.

### Security considerations for Tier 3 (hosted)

If the user wants to build a hosted proxy, flag these concerns:

- The proxy will be accessible on the internet – it needs proper authentication (not just API keys)
- It holds production credentials – a breach of the proxy is a breach of the upstream systems
- Rate limiting is essential – an AI tool can generate thousands of requests per session
- TLS is mandatory – credentials flow over the wire
- Regular security audits – the proxy is a high-value target
- Recommend OAuth2 with short-lived tokens rather than long-lived API keys
- Consider IP allowlisting if the proxy only needs to serve known office/VPN ranges

**If the user does not have staff with security and infrastructure expertise, strongly recommend Tier 1 or Tier 2 instead.**
