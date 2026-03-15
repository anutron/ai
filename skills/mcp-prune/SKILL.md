---
name: mcp-prune
description: Analyze active MCP servers and disable irrelevant ones for the current project. Use when starting work in a project with many global MCP servers that waste context tokens. Saves config to project settings.
---

## Context

- Working directory: !{pwd}
- Project indicators: !{ls -1 CLAUDE.md package.json Gemfile go.mod Cargo.toml pyproject.toml requirements.txt tsconfig.json Makefile 2>/dev/null | head -10}
- CLAUDE.md summary: !{head -30 CLAUDE.md 2>/dev/null | head -30}
- Project MCP config: !{cat .claude/mcp.json 2>/dev/null | head -20}
- Current disabled servers: !{python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [print(s) for p in d.get('projects',{}).values() for s in p.get('disabledMcpServers',[])]" ~/.claude.json 2>/dev/null | sort -u | head -20}

## Instructions

Analyze the current project and recommend which MCP servers to disable to save context tokens.

### Step 1: Inventory Active MCP Servers

List every MCP server currently loaded in this session. For each one, note:
- Server name (e.g., claude_ai_Slack, zendesk-knowledge-base, memory, things)
- Approximate tool count (count the mcp__servername__* tools available)
- What it provides (Slack messaging, Zendesk KB, calendar, etc.)

Present this as a table sorted by tool count (highest first).

### Step 2: Analyze Project Relevance

Based on the project context above (CLAUDE.md, package files, project MCP config), determine what this project actually needs. Consider:
- What languages and frameworks are used
- What integrations the project references
- What workflows are described in CLAUDE.md
- Project-specific MCP servers (these are always relevant)

### Step 3: Recommend Disable List

Categorize each MCP server as:
- **KEEP** - Directly relevant to this project
- **DISABLE** - Not relevant, wastes context tokens
- **MAYBE** - Edge case, ask the user

Present the recommendation as a clear table with server name, verdict, and one-line reason.

### Step 4: Wait for Approval

Show the user the proposed disable list and ask for confirmation. Let them override any choices before proceeding.

### Step 5: Apply Configuration

After approval, write the `disabledMcpServers` array to `.claude/settings.local.json` (create it if needed, merge with existing content). This file is gitignored and project-local.

The format is:

```json
{
  "disabledMcpServers": ["server-name-1", "server-name-2"]
}
```

Use the exact server names as they appear in the MCP tool prefixes (e.g., "claude_ai_Slack" from mcp__claude_ai_Slack__*, "zendesk-knowledge-base" from mcp__zendesk-knowledge-base__*).

Tell the user to restart Claude Code for the changes to take effect.

### Abort Conditions

- If fewer than 3 MCP servers are active, tell the user pruning is not needed and stop.
- If all servers appear relevant, tell the user and stop without writing config.
