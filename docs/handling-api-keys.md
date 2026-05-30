# Handling API keys

The single most important habit with API keys, tokens, and secrets: **they live in a vault, never in your code or config files.** A key in a `.env` you forget to gitignore, pasted into a script "just for a second," or hard-coded inline is one `git push` away from leaving your machine forever – and once a key is on the public internet, rotating it is the only fix.

This page is the best-practice summary. For the specific 1Password loader this project uses, see [op-secret.md](op-secret.md).

## The threat model: exfiltration, not exposure

It helps to be precise about what you're defending against.

- **Exposure** is a tool on your machine *reading* a key – Claude Code seeing your `.env`, your shell history holding a token. This is unavoidable and largely fine. Your local machine is transparent to the tools you run on it.
- **Exfiltration** is a key *leaving* your machine – committed to git, baked into a deployed app, pasted into a shared doc, sent to an external service. This is the crisis.

Every rule below is about the boundary: keeping keys from crossing it. Don't waste energy trying to hide keys from local tools; spend it making sure they never get committed, deployed, or shared.

## Where to put keys, ranked

- **A secret manager / vault (best).** Keys live encrypted, rotate centrally, and never sit in plaintext on disk. 1Password (recommended below), macOS Keychain, AWS Secrets Manager, and HashiCorp Vault all qualify.
- **`.env` files or shell exports (acceptable fallback).** Fine when a vault is impractical – *if* `.env` is in `.gitignore` and the file stays under `$HOME`, not in a tracked directory.
- **Hard-coded inline strings (never).** Never put a key directly in a code file, script, or committed config. Never commit a key into a teammate's repo "to help them get started."

## 1Password (recommended)

A 1Password **service account** gives a non-interactive `op` CLI read access to a vault – no biometric prompt, which is what makes it scriptable. Keys live in 1Password, get fetched on demand, and never touch disk.

This project ships a tiny lazy loader built on exactly that:

- **[op-secret.md](op-secret.md)** – the full writeup: 1Password layout, service-account setup, install, rotation, troubleshooting.
- **[op-secret.sh](../bin/op-secret.sh)** – the sourceable shell function. Call `secret OPENAI_API_KEY` and it fetches from 1Password on first use, caches in the current shell's environment, and costs nothing on every call after. Zero startup cost, no cache file, no secrets on disk.

The 1Password layout is intentionally flat: one vault (`claude`), one item (`shell-env`), one custom field per env var. Adding a key is adding a field – no code change.

## macOS Keychain (a fine alternative)

If you'd rather not run a 1Password service account, the macOS Keychain is a perfectly good local vault. It's built in, encrypted at rest, and scriptable via the `security` CLI.

Store a key:

```bash
security add-generic-password -a "$USER" -s OPENAI_API_KEY -w
```

The `-w` with no value makes it prompt for the secret interactively, so the key never lands in your shell history.

Read it back into an env var when you need it:

```bash
export OPENAI_API_KEY="$(security find-generic-password -a "$USER" -s OPENAI_API_KEY -w)"
```

Tradeoffs versus 1Password: Keychain is local-only (no sync across machines, no central rotation, no team sharing), but it has zero setup and no external dependency. For a single personal machine it's entirely sufficient.

## If a key is exposed

If a key ever lands somewhere it shouldn't – committed, pushed, deployed, or shared:

1. **Rotate it immediately.** Don't investigate first, don't wait. Generate a new key and revoke the old one. A key in git history is compromised even after you delete the file, because the history still holds it.
2. **Then** review how it got out and close the gap (missing `.gitignore` entry, a hard-coded string, a pre-commit scanner that wasn't installed).

Rotation first, investigation second. The exposure window is the whole risk, and rotation is the only thing that closes it.

## Related

- [op-secret.md](op-secret.md) – the 1Password lazy loader in detail.
- [claude-code-recipes/03-security.md](claude-code-recipes/03-security.md) – the broader AI security policy this fits inside.
