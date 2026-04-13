![The security plugin](recipe3_security-plugin-three-helpers.png)

# Recipe 3: The security plugin

Most organizations write a security policy and distribute it as a document. People read it once (maybe) and then forget about it. When someone accidentally commits a credential or deploys to a public hosting service, the policy was technically in place – it just wasn't present in the moment when the mistake happened.

A security plugin solves this by embedding the policy into the tool itself. Instead of relying on people to remember the rules, Claude Code is made aware of the rules and actively helps enforce them. Three separable concepts, each valuable on its own:

1. **Policy context injection** – Claude reads a condensed version of your security policy at the start of every session. It becomes a knowledgeable advisor who can answer "am I allowed to do this?" with a clear yes or no, and refuses risky actions on the user's behalf even when not explicitly asked.

2. **Active guardrails** – A mechanical check that runs before Claude executes potentially dangerous commands. It catches the unambiguous bright-line violations – sensitive file names, known credential formats – using simple pattern matching. Fast and deterministic, but limited to what patterns can recognize.

3. **Compliance observability** – The plugin reports its version and presence to a central backend at the start of every session. This gives the organization visibility into who's running the plugin, who isn't, and who has an outdated version.

These three concepts require progressively more infrastructure. The first two work with nothing more than a Claude Code plugin (just files). The third requires a lightweight backend.

## The split between Concepts 1 and 2

This split is load-bearing. The two concepts cover different categories of risk and should not be confused.

**Intent-based decisions** belong in Concept 1 – the policy text Claude reads. When the user asks "how do I share this with my team?", the right response depends on what they mean: send a Slack message? Push to GitHub? Deploy to a public URL? Only the LLM understands intent, so only the LLM can route the user toward an approved channel and away from a forbidden one. A regex cannot prevent Claude from *suggesting* `vercel deploy`; only the policy in context can.

**Pattern-based decisions** belong in Concept 2 – the mechanical check. Does this string look like an AWS access key? Is the user trying to write a `.env` file? These are unambiguous, so they get caught by simple regex matching. Fast, deterministic, no LLM reasoning required.

If you push intent decisions down into regex, you'll fail to catch novel framings. If you push pattern matching up into prose, you'll trust the LLM to do work that a 5-line regex would do more reliably. Each layer does what it's good at.

## Concept 1: Policy context injection

Claude reads the security policy at the start of every session, before the user even types anything. The policy lives in Claude's context for the entire session, available for reference whenever a question of permissibility arises.

This is the cheapest, highest-leverage layer. Claude itself becomes security-aware and can reason about novel situations. A user can ask "is it okay to share this database export with a vendor?" and Claude will consult the policy and give a grounded answer. A user who asks "how do I share this with my coworkers?" gets back guidance that respects the deployment policy, not a `vercel deploy` suggestion.

### Example policy (customize to your organization)

```markdown
You are operating under [Your Org] AI Security Policy. Key rules:

NEVER (refuse and explain):
- Deploy to cloud hosting (Vercel, Netlify, Heroku, Railway, Render,
  Fly, GitHub Pages, Surge, Cloudflare Pages, Firebase Hosting,
  AWS Amplify). When the user asks how to share their work, suggest
  approved internal channels instead.
- Hardcode credentials in code files
- Include customer PII in prompts, outputs, or files

CONFIRM BEFORE (warn user, get explicit yes):
- Send emails, Slack messages, or any external communication
- Write operations to production systems
- Bulk operations affecting multiple records
- Install new plugins or MCP servers

ALWAYS SAFE:
- Read-only queries via approved data tools
- Local file creation and editing
- Git operations on feature branches (excluding sensitive files)
- Drafting content for human review

WHEN SPAWNING SUBAGENTS:
- Prepend this security context to the agent prompt so the subagent
  inherits the rules. Subagent hooks do not fire, so context is
  the only protection.

When the user asks "Am I allowed to do X?" – consult the full policy
and give a clear yes/no with the relevant rule. When unsure,
default to refusal and direct the user to a help channel.
```

This is a starting point. Your organization should write its own policy that reflects its specific risks, systems, and regulatory requirements. The example above covers common patterns, but your list of NEVER, CONFIRM, and SAFE actions will be different.

Beyond these guard rules, the policy text should include a condensed version of the full company security policy – covering topics like credential storage, data classification, approved tools, and incident reporting. This turns Claude into a resource employees can consult conversationally: "Can I use this third-party API for customer data?" "Where should I store this API key?"

## Concept 2: Active guardrails

A mechanical check that runs before Claude writes a file or executes a shell command. It looks for **bright-line violations** – the kind of thing a regex can identify reliably – and stops them. This is the last line of defense for things that should never happen, regardless of intent.

What it catches reliably:

- **Sensitive file names** in writes or `git add` – `.env`, `.credentials`, `*.pem`, `*.key`, `id_rsa`. Unambiguous: these files almost never legitimately belong in the working tree.
- **Curated credential formats** – a maintained dictionary of API key prefixes for the services your organization uses (`AKIA…` for AWS, `ghp_…` for GitHub PATs, `xoxb-` for Slack bot tokens, etc.). This is whack-a-mole, but it is *maintainable* whack-a-mole. Add new patterns as you discover them.

What it does not try to catch:

- **Deployment intent** – belongs in Concept 1. Regex can match `vercel deploy`, but it cannot prevent Claude from suggesting it in response to "how do I share this?" The policy in context is what stops the suggestion at the source.
- **Novel credential formats** – every quarter a new vendor ships a new key prefix. Trying to be aspirationally comprehensive is a losing game. Stay narrow and curated; let Claude's policy awareness handle the long tail.
- **Bulk operations and PII judgment** – these require understanding context. Concept 1's job.

Two response types:

- **Block** – Absolute. The check returns a block decision and Claude Code prevents execution. The user sees an explanation of what was caught and why.
- **Warn** – Educational. The check blocks execution the first time and displays a message explaining the risk. If the user re-issues the same command in the same session, it recognizes the retry and allows it through. This creates deliberate friction without being a permanent wall.

## Concept 3: Compliance observability

The plugin reports basic telemetry to a central backend at the start of every session:

- Who the user is
- What version of the plugin they're running
- Which MCP servers are enabled
- What plugins and skills are installed

This gives the organization a dashboard view of adoption: who's compliant, who isn't, who has an outdated version, and what tools people are using. It also enables supply chain auditing – if an unrecognized plugin appears in the inventory, that's worth investigating.

### Privacy boundary

This is critical to get right.

**What gets sent:** Version, timestamp, enabled MCPs, installed plugins/skills.

**What never gets sent:** Prompts, responses, file contents, commands, conversation history. Pattern *names* (e.g., "AWS access key detected") are sent for events; pattern *matches* (the actual key value) never leave the machine.

The goal is observability of adoption and risk *categories*, not surveillance of what people are doing.

### What kind of backend?

This doesn't require a complex server. A lightweight database with an API endpoint is sufficient – Supabase, Notion, or any hosted database that accepts a JSON payload, stores it, and lets you query it. The plugin makes a single API call per session.

## Optional: Gateway enforcement

If your organization has a proxy or gateway sitting between Claude and production systems (see Recipe 4: The data proxy), that gateway can check plugin compliance before serving requests.

The logic: when a user's request arrives at the gateway, check whether they've recently checked in with a current plugin version. If not, return an error with a helpful message explaining how to install the plugin.

This turns the plugin from recommended to effectively mandatory – without the plugin, you lose access to the tools you need.

Two tiers:

- **Observability only** – Track adoption, nudge non-compliant users via Slack or email. Any org can do this with the lightweight backend described above.
- **Gateway enforcement** – Block non-compliant users from accessing business data through the proxy. Requires a proxy (Recipe 4) with a compliance check in the request path.

One approach to rollout: start with observability only (monitoring mode), track adoption for a few weeks, then enable enforcement once most users are compliant. This avoids disrupting people on day one while still creating urgency to install the plugin.

---

## Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  Claude Code session                                         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ SessionStart hook                                      │  │
│  │                                                        │  │
│  │  1. Discover backend auth token (env, configs)         │  │
│  │  2. Background phone-home → backend (Concept 3)        │  │
│  │  3. stdout: policy text → injected as system-reminder  │  │
│  └─────────────────────────┬──────────────────────────────┘  │
│                            ▼                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Concept 1: Policy in context (LLM-aware)               │  │
│  │                                                        │  │
│  │ Claude reads the policy at every session start.        │  │
│  │ Handles intent and judgment:                           │  │
│  │  • "How do I share this?" → suggests internal channels │  │
│  │  • "Is X allowed?" → cites the rule                    │  │
│  │  • Bulk operations, PII, ambiguous cases               │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Concept 2: Active guardrails (deterministic)           │  │
│  │                                                        │  │
│  │ PreToolUse hook on Write/Edit/MultiEdit/Bash:          │  │
│  │  ├── Sensitive file name (.env, *.pem) → BLOCK         │  │
│  │  ├── Curated credential pattern in content → BLOCK     │  │
│  │  ├── Risky-but-occasional pattern → WARN (retry OK)    │  │
│  │  └── Normal operation → pass through                   │  │
│  │                                                        │  │
│  │ Caveat: does NOT fire for subagents.                   │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
          │                                  │
          ▼                                  ▼
┌────────────────────────┐         ┌──────────────────────────┐
│ Concept 3: Backend     │         │ Gateway / proxy          │
│ (Supabase, Notion, …)  │         │ (if one exists)          │
│                        │         │                          │
│ Checkin events         │         │ Checks compliance        │
│ Block/warn events      │         │ before serving data      │
│ Adoption dashboard     │         │ (effectively mandatory)  │
└────────────────────────┘         └──────────────────────────┘
   (lightweight)                      (advanced, optional)
```

---

## Technical reference for Claude

When helping a user build a security plugin, follow this structure.

### Why a SessionStart hook, not a skill file

Claude Code plugins also support skills (markdown files in `commands/`), and those look like an obvious home for security policy. They are not. Skills are loaded **on demand** – when the user invokes them with a slash command, or when Claude's frontmatter heuristic decides they are relevant to the current task. They are not sitting in the context window of a fresh session.

Empirically, the only mechanisms that put text into every session's context automatically are:

- **SessionStart hook stdout** – injected as a `<system-reminder>` for both fresh sessions and resumes
- **Project CLAUDE.md** – loaded by the directory-walking memory mechanism, but only for sessions rooted in a directory that contains it (a plugin's own CLAUDE.md is not loaded in users' projects)

The hook approach is the right choice: it works regardless of where the user is working, and it fires on both fresh sessions and resumes.

### Subagent limitations

Subagents (spawned via the `Agent` tool) are a known gap in both Concepts 1 and 2.

For **Concept 1**: Subagents do not inherit the parent's SessionStart hook output, and `SubagentStart` hook stdout is not injected into the subagent's context (the hook script runs, but its stdout goes nowhere). They do inherit the parent's CLAUDE.md context, permission mode, and MCP server configuration.

For **Concept 2**: PreToolUse hooks **do not fire for subagents at all**. A subagent spawned via the `Agent` tool can write a credential to a file or run a deployment command without the hook intercepting.

Mitigations:

- Concept 1's policy text instructs the main thread to prepend security context to subagent prompts when calling `Agent`. This is not enforced – it relies on Claude following the instruction – but it raises the floor.
- Backend gating (Concept 3 with gateway enforcement) covers all agents because they share the same MCP auth.
- Track Anthropic's open issue (anthropics/claude-code#27661) for native subagent hook inheritance.

### Plugin file structure

```
your-security-plugin/
├── .claude-plugin/
│   ├── plugin.json              # Plugin metadata and version
│   └── marketplace.json         # Marketplace listing (single-plugin marketplace)
├── hooks/
│   ├── hooks.json               # Hook registration
│   ├── session-start.sh         # SessionStart hook (prints policy + checkin)
│   └── pre-tool-use.sh          # PreToolUse hook (file + credential scan)
├── lib/
│   ├── policy.sh                # The policy text printed by session-start
│   ├── credential-patterns.sh   # The curated credential dictionary
│   └── backend-client.sh        # curl wrappers for the checkin/events endpoints
├── commands/
│   └── security-status.md       # /security-status slash command (optional)
└── README.md
```

A few notes on this structure:

- **No `skills/` directory.** Skills are not auto-loaded into context, so they are the wrong place for the always-on policy. The policy lives inline in the SessionStart hook (or in a sourced `lib/policy.sh`).
- **`marketplace.json` is required** for `claude plugin install <path>` to work. A single-plugin marketplace is fine.
- **`lib/` holds shared bash functions** that both hooks source. Keeps the hooks thin. Disk I/O cost of sourcing extra files is negligible (filesystem cache after first invocation).

### hooks.json registration

The plugin's `hooks/hooks.json` registers both hooks. Note the nested `hooks` array inside each event entry – this is required by Claude Code's hook configuration schema. Use `${CLAUDE_PLUGIN_ROOT}` to reference files inside your plugin directory.

```json
{
  "description": "Security plugin hooks",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh\""
          }
        ]
      }
    ]
  }
}
```

The `matcher` field on PreToolUse limits the hook to the tools you actually want to scan. Without it, the hook would fire on every tool call (Read, Grep, Glob, etc.) and waste process startup time on operations you do not care about.

### Session start hook behavior

1. **Discover the auth token** for the backend (if your backend requires per-user auth – not all do). Common locations: an explicit env var, headers in the user's MCP config, OAuth tokens stored elsewhere by other tools.
2. **Collect telemetry**: plugin version, enabled MCPs (scan `~/.claude/settings.json`, `~/.claude/settings.local.json`, `~/.claude.json`), installed plugins, installed skills, project path.
3. **POST to backend in background** (`&`) – non-blocking, fail silently. The session must not wait on a network call.
4. **Print the policy text to stdout**. Claude Code injects this as a `<system-reminder>` in the session context. This is the always-on policy injection mechanism.

Implementation: pure bash. Dependencies: `bash`, `curl`, `jq`. Degrade gracefully if `curl` or `jq` is missing (lose telemetry, keep the policy injection).

### PreToolUse hook behavior

The hook receives the tool name and input as JSON on stdin. Parse with `jq` and dispatch by tool type. Keep the scan narrow – only catch what regex catches reliably.

- **Write / Edit / MultiEdit** – Check the file path for sensitive names (`.env`, `.credentials`, `*.pem`, `*.key`, `id_rsa`). Then scan the content being written against the curated credential dictionary. Match assignment patterns like `api_key = "..."`, `secret = "..."`, `Bearer ...` only when the value side looks like an actual credential (high-entropy or matches a known prefix), not a placeholder.

- **Bash** – Check for `git add` operations adding sensitive files. Optionally check for known deployment commands as a backstop, but do not rely on this catching deployment intent (Concept 1 handles that).

- **All other tools** – Pass through immediately. The matcher in `hooks.json` should already exclude them from invoking the hook at all.

Hook response uses exit codes and stdout, not a JSON return value. The conventions:

- **Pass:** exit 0, no output. Tool execution proceeds.
- **Block / Warn:** exit 2, write the educational message to stderr. Claude Code surfaces the stderr message and prevents execution. For warn-then-allow, write the warning hash to a session-scoped state file before exiting; on the next invocation with the same hash, exit 0 to allow.

Implementation uses a session-scoped state file (e.g., `/tmp/security-state-{session_id}.json`) to track which warnings have been shown. Probabilistic cleanup (10% chance per run, removing files older than 30 days) keeps the temp directory tidy without scheduling.

Performance per invocation: fork bash + jq + regex scan, ~10–50ms. Negligible memory footprint. No network I/O on the pass-through path; background `curl` to the events endpoint only when something is blocked or warned.

### Backend implementation

Lightweight options for the phone-home backend:

- **Supabase** – A hosted Postgres database with auto-generated REST APIs. Create a `security_checkins` table, and the plugin can write to it via a background `curl` call.
- **Notion** – A Notion database can serve as the backend if the org is already using Notion. The plugin writes rows via the Notion API.
- **Any hosted database with an API** – The requirements are: accept a JSON payload, store it, allow querying.

The phone-home call should be:
- **Background** – Must not slow down session start
- **Non-blocking** – If the backend is unreachable, fail silently
- **Graceful** – Work without `jq` or `curl` if they're missing (just lose logging)

### Compliance backend schema (Supabase example)

```sql
CREATE TABLE security_checkins (
  id BIGSERIAL PRIMARY KEY,
  user_email TEXT NOT NULL,
  plugin_version TEXT NOT NULL,
  mcps_enabled JSONB,
  plugins_installed JSONB,
  skills_installed JSONB,
  project_path TEXT,
  checked_in_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_checkins_user ON security_checkins(user_email);
CREATE INDEX idx_checkins_time ON security_checkins(checked_in_at);
```

### Security events schema (optional, for tracking blocks/warns)

```sql
CREATE TABLE security_events (
  id BIGSERIAL PRIMARY KEY,
  user_email TEXT NOT NULL,
  event_type TEXT NOT NULL,       -- 'block', 'warn', 'override'
  tool_name TEXT,                 -- 'Write', 'Edit', 'Bash'
  pattern_matched TEXT,           -- 'credential_in_file', 'cloud_deployment'
  severity TEXT NOT NULL,         -- 'block', 'warning'
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Key design principles

- **Background, non-blocking** – Phone-home and event logging must never slow down the user's session.
- **Fail silently** – If the backend is unreachable or no token is found, the plugin still works (Concepts 1 and 2 are fully local).
- **Privacy boundary** – Never send prompts, responses, file contents, or commands to the backend. Send pattern *names*, not pattern *matches*. The fact that a credential was caught is useful; the credential value itself must not leave the machine.
- **Block is absolute, warn is educational** – Blocks prevent known-bad patterns. Warns create friction but allow override on retry.
- **Pure bash** – Minimize dependencies. The plugin should work on any machine with a shell, `curl`, and `jq`.
- **Layer the right thing at the right level** – Intent and judgment in the policy text (Concept 1, LLM-aware). Bright-line patterns in the hook (Concept 2, deterministic). Do not push intent decisions down into regex; do not push pattern matching up into prose.
- **Curate, do not aspire** – The credential dictionary is maintained, not exhaustive. Add patterns as you encounter the services; accept that novel formats slip through to Concept 1.
