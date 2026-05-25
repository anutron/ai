# op-secret — lazy 1Password loader for shell env vars
#
# SOURCE this from your interactive shell rc (e.g. ~/.zshrc), don't execute it.
# Each shell session caches values in its own environment, so the second
# request for a given VAR in the same shell is 0ms.
#
# Layout in 1Password:
#   - vault:   claude
#   - item:    shell-env
#   - fields:  one custom field per env var, label = UPPER_SNAKE_CASE var name
#              (e.g. ZENDESK_API_TOKEN, GMAIL_CLIENT_ID, SLACK_BOT_TOKEN)
#
# Prereqs:
#   - 1Password CLI (`op`) installed and on PATH
#   - OP_SERVICE_ACCOUNT_TOKEN exported (we source ~/.op-service-account if present)
#
# Usage in shell:
#   secret ZENDESK_API_TOKEN                  # prints value; also exports it
#   export GMAIL_CLIENT_ID=$(secret GMAIL_CLIENT_ID)
#   tool --token "$(secret SLACK_BOT_TOKEN)"  # inline
#
# Costs:
#   - 0ms at shell startup (no eager fetch)
#   - ~1s the first time a given VAR is requested in a shell session
#   - 0ms on every subsequent request in the same session
#
# Note: this function uses zsh's indirect parameter expansion (${(P)var-});
# it is zsh-specific. A bash port would use ${!var-} instead.

# 1Password service account token (sets OP_SERVICE_ACCOUNT_TOKEN).
# Keep this file mode 0600 and outside any synced/version-controlled directory.
[ -f ~/.op-service-account ] && source ~/.op-service-account

secret() {
  local var="$1"
  [ -z "$var" ] && { echo "usage: secret VAR_NAME" >&2; return 1; }
  local val="${(P)var-}"
  if [ -n "$val" ]; then
    print -rn -- "$val"
    return 0
  fi
  command -v op >/dev/null 2>&1 || { echo "secret: op CLI not installed" >&2; return 1; }
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || { echo "secret: OP_SERVICE_ACCOUNT_TOKEN not set" >&2; return 1; }
  val="$(op read "op://claude/shell-env/$var" 2>/dev/null)"
  [ -z "$val" ] && { echo "secret: no value for $var (check 1P item: claude/shell-env)" >&2; return 1; }
  export "$var=$val"
  print -rn -- "$val"
}
