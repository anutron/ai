# op-secret: lazy 1Password loader for shell env vars

A tiny shell function that fetches API tokens from 1Password on first use and caches them in the current shell's environment for the rest of the session. Zero startup cost, no secrets on disk.

## Why

If you have a dozen API tokens (Zendesk, Gmail, Slack, OpenAI, Anthropic, etc.) and you want them available as env vars without:

- **Hard-coding them in your zshrc** — they leak into backups, dotfiles repos, and `history` greps.
- **Eagerly fetching them all at shell startup** — five to seven seconds of latency every time you open a Terminal window adds up fast.
- **Caching them to disk** — a cache file at `~/.cache/op-shell-env.sh` is faster than eager fetch, but it puts secrets back on disk, which is the thing you were trying to avoid.

`op-secret` is the smallest thing that works:

- 0ms shell startup cost (no fetch, no cache file)
- ~1s the first time a given var is requested in a shell session
- 0ms on every subsequent request in the same session
- Secrets only ever live in the current shell's environment

## Architecture

One function, `secret VAR_NAME`. On first call in a shell session it does an `op read` against a fixed 1Password path, exports the value into the shell, and prints it. On subsequent calls in the same shell it returns the already-exported value with no 1Password round-trip.

1Password layout is intentionally flat:

- **vault:** `claude`
- **item:** `shell-env`
- **fields:** one custom field per env var, label = `UPPER_SNAKE_CASE` name (e.g. `ZENDESK_API_TOKEN`, `GMAIL_CLIENT_ID`, `SLACK_BOT_TOKEN`)

One item, N fields. Adding a new token = add a new field; no code change.

## Prerequisites

- **1Password CLI** (`op`) installed. On macOS: `brew install --cask 1password-cli`.
- **A 1Password service account** with read access to the `claude` vault. Service accounts are non-interactive — they don't prompt for biometrics, which is what makes `op read` shell-friendly.
- **Zsh.** The function uses `${(P)var-}` indirect parameter expansion, which is zsh-specific. Bash users: replace with `${!var-}` and `print -rn --` with `printf '%s'`.

## Install

### 1. Create the 1Password item

In the `claude` vault, create a new item of any type (Login, Password, Secure Note — doesn't matter; we only use custom fields). Name it `shell-env`.

For each env var you want loadable, add a custom field:

- **Label:** the env var name in `UPPER_SNAKE_CASE` (e.g. `ZENDESK_API_TOKEN`)
- **Value:** the token
- **Type:** Password (so it's hidden in the UI)

### 2. Create a service account token

In 1Password's web UI: **Developer Tools → Service Accounts → Create Service Account**. Grant it **read** access to the `claude` vault. Copy the token it issues — you only see it once.

Store the token in `~/.op-service-account`:

```bash
echo 'export OP_SERVICE_ACCOUNT_TOKEN="ops_eyJ..."' > ~/.op-service-account
chmod 600 ~/.op-service-account
```

Mode 0600 means owner-only read; it does not end up in a backup or dotfiles repo as long as you keep it under `$HOME` and not in a tracked directory.

### 3. Source the function from your shell rc

Copy `op-secret.sh` somewhere stable (e.g. `~/.config/op-secret.sh`) and source it from your `~/.zshrc`:

```bash
source ~/.config/op-secret.sh
```

Or, if you already use this repo: source it directly from the checkout:

```bash
source ~/Development/Personal/ai-ron/.claude/bin/op-secret.sh
```

The function itself sources `~/.op-service-account` if it exists, so you don't need a separate line for that.

### 4. Verify

Open a new Terminal window and run:

```bash
secret ZENDESK_API_TOKEN
```

The first call should take about a second and print the value. The second call should be instant.

## Usage patterns

### Print and export in one go (most common)

```bash
secret SLACK_BOT_TOKEN
```

Prints the value to stdout *and* exports it into the current shell. After the first call, `$SLACK_BOT_TOKEN` is set for the rest of the session.

### Inline into a command

```bash
curl -H "Authorization: Bearer $(secret OPENAI_API_KEY)" https://api.openai.com/v1/models
```

The first time you do this in a shell, you pay the ~1s. Every subsequent use in the same shell is instant.

### Explicit export with rename

```bash
export ZENDESK_TOKEN=$(secret ZENDESK_API_TOKEN)
```

Useful when a tool expects a different env var name than what's in 1Password.

### Use from a script

Scripts launched from a parent shell inherit exported vars. So once `secret X` has been called in your interactive shell, any script you launch from that shell will see `$X` already set. If a script needs to be runnable from cron or a fresh shell, source `op-secret.sh` at the top and call `secret` explicitly.

## Rotation

Rotate a token: update the value in the `shell-env` item in 1Password. New shells will pick up the new value on their next `secret` call. Existing shells will keep using the cached old value until you `unset VAR` (or close the shell).

If you want the change to propagate to running shells, open a new Terminal window for the affected work — it's faster than chasing down `unset` calls.

## Troubleshooting

**`secret: op CLI not installed`**
Install the 1Password CLI (`brew install --cask 1password-cli`) and reopen the shell.

**`secret: OP_SERVICE_ACCOUNT_TOKEN not set`**
Either `~/.op-service-account` doesn't exist, or it exists but doesn't export `OP_SERVICE_ACCOUNT_TOKEN`. Check the file contents and run `source ~/.op-service-account` manually to debug.

**`secret: no value for FOO (check 1P item: claude/shell-env)`**
The field `FOO` doesn't exist in the `shell-env` item, the field is empty, or the service account doesn't have read access to the `claude` vault. The `op read` call returned nothing.

**First call is slow even on warm shells**
The function only caches *within a single shell session*. If you open a new Terminal window, the first `secret X` in that window pays the ~1s again. That's the design — the alternative is persisting secrets to disk, which we're explicitly avoiding.

**Bash instead of zsh**
Swap `${(P)var-}` for `${!var-}` and `print -rn --` for `printf '%s'`. The rest is portable.

## Why not just use the 1Password Shell Plugin?

The official 1Password Shell Plugin (`op plugin init`) is great if you're invoking a specific CLI that the plugin knows about (`gh`, `aws`, `stripe`, etc.) — it injects the token at exec time. But it doesn't help with:

- Arbitrary env vars consumed by MCP servers, scripts, or tools that read `os.environ` directly
- Cases where you want the var available in the shell, not just for one wrapped command

`op-secret` covers the env var case. Use both if you want.

## File reference

- `~/.op-service-account` — exports `OP_SERVICE_ACCOUNT_TOKEN`. Mode 0600. Not in version control.
- `~/.config/op-secret.sh` (or wherever you put it) — the sourceable function file. Safe to version-control; it contains no secrets.
- 1P item: `op://claude/shell-env/<VAR>` — read-only from the shell via the service account.
