# Permissions guide

Claude Code asks for confirmation before running tools. This is safe but noisy — after a few sessions you'll be clicking "allow" on `Read` and `Edit` dozens of times. The `permissions` block in `~/.claude/settings.json` lets you pre-answer those questions.

This guide organizes permission rules into categories. Read the rationale, cherry-pick what fits your workflow, and merge into your settings. The `/setup` skill can walk you through this interactively.

---

## How permissions work

`~/.claude/settings.json` has a `permissions` object with three arrays:

```json
{
  "permissions": {
    "allow": [],
    "deny": [],
    "ask": []
  }
}
```

- **allow** — tool runs without asking. This is where you reduce nagging.
- **deny** — tool is blocked entirely. Claude sees the denial and adjusts.
- **ask** — tool prompts for confirmation every time. Use for dangerous-but-sometimes-needed operations.

### Pattern syntax

| Pattern | Meaning |
|---------|---------|
| `"Read"` | Allow/deny/ask for all uses of the Read tool |
| `"Read(~/.ssh/*)"` | Scoped to files matching the glob |
| `"Bash(*)"` | Allow/deny/ask for all uses of the Bash tool |
| `"Bash(git push --force:*)"` | Scoped to bash commands starting with that prefix |
| `"mcp__*"` | Wildcard — matches all MCP tool names |

The `:*` suffix on Bash patterns means "this prefix, with anything after it." Without it, the match is exact.

**Note on Bash:** Unlike other tools, bare `"Bash"` (without parentheses) does **not** grant blanket permission. Use `"Bash(*)"` to allow all Bash commands. Other tools like `"Read"`, `"Write"`, and `"Edit"` work fine in bare form.

---

## Category 1: Auto-allow core tools

**Why:** These tools are read-only or operate on local files you're actively working on. Confirming each one adds friction with no safety benefit.

```json
{
  "allow": [
    "Bash(*)",
    "Read",
    "Write",
    "Edit",
    "MultiEdit",
    "Glob",
    "Grep",
    "LS",
    "WebFetch",
    "WebSearch",
    "NotebookRead",
    "NotebookEdit",
    "TodoWrite",
    "Task",
    "Skill"
  ]
}
```

**Tradeoff:** Auto-allowing `Bash(*)` is the big one. It means Claude can run any shell command without asking. If that's too broad, remove it from `allow` — you'll confirm each command but keep everything else quiet. A middle ground is to allow `Bash(*)` but deny specific destructive commands (see category 2).

---

## Category 2: Deny destructive operations

**Why:** These commands are catastrophic and irreversible. There's no legitimate reason for Claude to run them. Deny, don't ask.

```json
{
  "deny": [
    "Bash(rm -rf /)",
    "Bash(rm -rf /:*)",
    "Bash(sudo rm -rf /)",
    "Bash(sudo rm -rf /:*)",
    "Bash(rm -rf ~)",
    "Bash(rm -rf ~:*)",
    "Bash(rm -rf ~/.claude)",
    "Bash(rm -rf ~/.claude:*)",
    "Bash(diskutil eraseDisk:*)",
    "Bash(diskutil zeroDisk:*)",
    "Bash(diskutil partitionDisk:*)",
    "Bash(diskutil apfs deleteContainer:*)",
    "Bash(diskutil apfs eraseVolume:*)",
    "Bash(dd if=/dev/zero:*)",
    "Bash(mkfs:*)",
    "Bash(gh repo delete:*)"
  ]
}
```

**Note:** The `diskutil` and `dd` rules are macOS-specific. On Linux, you'd add equivalents for `fdisk`, `parted`, etc.

---

## Category 3: Privacy boundaries

**Why:** Your home directory has folders that aren't code — personal documents, downloads, photos. Claude doesn't need access to these and shouldn't accidentally read or write them.

```json
{
  "deny": [
    "Read(~/Documents/**)",
    "Write(~/Documents/**)",
    "Edit(~/Documents/**)",
    "Bash(* ~/Documents/**)",
    "Read(~/Downloads/**)",
    "Write(~/Downloads/**)",
    "Edit(~/Downloads/**)",
    "Bash(* ~/Downloads/**)",
    "Read(~/Desktop/**)",
    "Write(~/Desktop/**)",
    "Edit(~/Desktop/**)",
    "Bash(* ~/Desktop/**)",
    "Read(~/Pictures/**)",
    "Write(~/Pictures/**)",
    "Edit(~/Pictures/**)",
    "Bash(* ~/Pictures/**)"
  ]
}
```

**Customize:** Add or remove directories based on your setup. If your code lives in `~/Documents/code/`, don't deny `~/Documents/**` — scope it more narrowly or skip this category.

---

## Category 4: Sensitive file protection

**Why:** SSH keys, cloud credentials, and GPG keys should never be read by Claude. Even in "ask" mode, a quick misclick could expose secrets. Deny outright.

```json
{
  "deny": [
    "Read(~/.aws/credentials)",
    "Read(~/.gnupg/private*)",
    "Read(~/.ssh/id_*)",
    "Write(~/.ssh/*)",
    "Edit(~/.ssh/*)"
  ]
}
```

**Extend for your stack:** If you use other credential files, add them:

```json
{
  "deny": [
    "Read(~/.config/gcloud/credentials.db)",
    "Read(~/.kube/config)",
    "Read(~/.npmrc)",
    "Read(~/.docker/config.json)",
    "Read(~/.dbt/profiles.yml)"
  ]
}
```

---

## Category 5: Guardrails (ask, don't deny)

**Why:** Force-pushing, changing repo visibility, and reading shell profiles are sometimes necessary — but they should always be a conscious decision.

```json
{
  "ask": [
    "Bash(gh repo edit --visibility public:*)",
    "Bash(git push --force:*)",
    "Bash(git push -f:*)",
    "Bash(git push origin --force:*)",
    "Bash(git push origin -f:*)",
    "Read(~/.ssh/*.pem)",
    "Write(~/.claude/settings.json)",
    "Edit(~/.claude/settings.json)"
  ]
}
```

---

## Category 6: Environment protection

**Why:** Shell profiles and environment variables can contain API keys, tokens, and paths that reveal your infrastructure. `ask` mode means Claude can read them when needed (e.g., debugging PATH issues) but you see exactly what's being accessed.

```json
{
  "ask": [
    "Read(~/.zshrc)",
    "Read(~/.zshenv)",
    "Read(~/.zprofile)",
    "Read(~/.bash_profile)",
    "Read(~/.bashrc)",
    "Read(~/.profile)",
    "Bash(env)",
    "Bash(env:*)",
    "Bash(printenv)",
    "Bash(printenv:*)"
  ]
}
```

---

## Category 7: MCP servers

MCP permissions are more personal — they depend on which servers you have installed. Two approaches:

**Blanket allow (trust all MCP servers):**
```json
{
  "allow": [
    "mcp__*"
  ]
}
```

**Per-server allow (more control):**
```json
{
  "allow": [
    "mcp__github__*",
    "mcp__slack__*",
    "mcp__notion__*"
  ]
}
```

You can also set MCP permissions in your project-level `.claude/settings.json`:
```json
{
  "mcpPermissions": {
    "server-name": {
      "allowAllTools": true
    }
  }
}
```

---

## Putting it together

Merge the categories you want into your `~/.claude/settings.json`. Here's a minimal starting point — core tool auto-allow plus the safety net:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read",
      "Write",
      "Edit",
      "MultiEdit",
      "Glob",
      "Grep",
      "LS",
      "WebFetch",
      "WebSearch",
      "NotebookRead",
      "NotebookEdit",
      "TodoWrite",
      "Task",
      "Skill"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /:*)",
      "Bash(sudo rm -rf /)",
      "Bash(sudo rm -rf /:*)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ~:*)",
      "Bash(rm -rf ~/.claude)",
      "Bash(rm -rf ~/.claude:*)",
      "Bash(gh repo delete:*)",
      "Read(~/.aws/credentials)",
      "Read(~/.gnupg/private*)",
      "Read(~/.ssh/id_*)",
      "Write(~/.ssh/*)",
      "Edit(~/.ssh/*)"
    ],
    "ask": [
      "Bash(git push --force:*)",
      "Bash(git push -f:*)",
      "Write(~/.claude/settings.json)",
      "Edit(~/.claude/settings.json)"
    ]
  }
}
```

Then layer on privacy boundaries, environment protection, and other categories as you see fit.

---

## The `/setup` approach

If you installed this toolkit via the `/setup` skill (or the plugin's `/claude-skills:setup`), it includes a permissions step that walks you through these categories interactively — presenting each one, explaining the tradeoff, and merging your choices into `settings.json`.
