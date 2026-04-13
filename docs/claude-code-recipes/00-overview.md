# Claude Code adoption recipes

These recipes describe strategies that may help organizations scale Claude Code adoption – fast, and in a safe way. They're not a single system, and not the only way to do this. They're patterns worth considering, drawn from practical experience.

The patterns aim to be:

- **Shareable** – Conventions, rules, and tools live in version control, not in someone's head
- **Easily adopted** – Others in your org can pull what they need without coordination overhead
- **Durable** – Decisions are captured in documents that survive employee turnover and context loss
- **Easily iterable** – Every piece is modular and independently changeable
- **Safe** – Security policy is embedded in the tooling, not just written in a doc nobody reads
- **Approachable** – Useful for non-developers and developers alike

The recipes are ordered from foundational to advanced. The first two require nothing beyond Claude Code itself. The latter two introduce infrastructure that multiplies the value but requires more investment.

## The recipes

### 1. Skills and project organization

![Skills and project organization](recipe1_skill-organization-pegboard.png)

How to structure a personal Claude Code workshop so that your skills, rules, and customizations are portable and version-controlled – and how to share them with others in your organization in ways that don't disrupt your own iteration speed. Covers the `.claude/` directory, the skill system, the snippet-compiled CLAUDE.md pattern, permission configuration, and three different mechanisms for letting others adopt your skills.

**Prerequisites:** Claude Code installed. A git repository.

### 2. The design-to-execution pipeline

![The design-to-execution pipeline](recipe2_execution-pipeline-assembly.png)

A document-driven workflow for building things with AI that produces predictable outcomes and minimizes LLM drift. Designed to be approachable for non-developers and developers alike – the discipline is in the documents, not the technology. Captures intent before code gets written, keeps a living specification of what should be true, and uses version control to maintain a clear history of how the system evolved.

**Prerequisites:** Recipe 1 (project organization). A willingness to plan before building.

### 3. The security plugin

![The security plugin](recipe3_security-plugin-three-helpers.png)

A Claude Code plugin that embeds your organization's security policy into every session. Three separable concepts: policy context injection (Claude becomes security-aware), active guardrails (hooks that catch dangerous patterns), and compliance observability (tracking who's running the plugin). No infrastructure required for the first two; a lightweight backend enables the third.

**Prerequisites:** A security policy (even a draft). Claude Code's plugin system.

### 4. The data proxy

![The data proxy](recipe4_data-proxy-glovebox.png)

When AI tools need access to business data, a proxy in the middle is safer than giving the AI direct credentials. The proxy handles authentication, decides which operations to expose, and ensures Claude never holds the keys to the real system. Three tiers of sophistication depending on the org's technical capability.

**Prerequisites:** An API or data source you want Claude to access safely.
