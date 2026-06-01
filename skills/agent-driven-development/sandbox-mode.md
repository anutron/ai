# Sandbox-aware dispatch

The /fixit and /bugbash skills assume two writes against the main repo root that the calling session itself performs:

1. `git worktree add MAIN_REPO/.claude/worktree[s]/<slug>` to create the worker worktree.
2. `git checkout <main-branch> && git merge <feature-branch>` to land the result.

In a sandboxed worktree (a worktree whose process cannot write outside its own directory at the OS layer), both operations fail with "Operation not permitted". This document defines a graceful degradation. The skills should auto-detect sandbox mode and switch behavior without asking the user.

Non-sandbox behavior is unchanged. Everything in this doc is opt-in based on detection.

## When this fires

Each skill's `## Context` block already runs the probe script and surfaces the result as `Sandbox mode: ok` or `Sandbox mode: sandbox`. Read it from there. If you need to re-check later in the skill, run the same script again:

```bash
~/.claude/bin/repo-writable-check.sh
```

The probe prints `ok` when MAIN_REPO/.claude/ is writable, or `sandbox` otherwise. Cache the result for the rest of the skill invocation – sandbox state does not change mid-session.

If `ok`: follow the skill's normal worktree + merge path. Stop reading this doc.

If `sandbox`: follow the sections below.

## Generic capability detection

This doc avoids naming any specific host (no argus, no hera, no plannotator). The skills detect three host capabilities at runtime by tool shape:

- **Task spawning** – a tool whose name matches `mcp__*__task_create` or `mcp__*__*_task_create`. The host can create a fresh worktree and spawn a worker in it.
- **Coordination channel** – a pair of tools whose names contain `_send`/`_message_send` and `_inbox`/`_messages`. The calling session and worker can exchange messages.
- **Clipboard helper** – `pbcopy` on PATH, or any MCP tool matching `mcp__*__*clipboard*`. The skill can stage commands for the user to run elsewhere.
- **Host git/PR helper** – a tool whose name matches `mcp__*__*_push`, `mcp__*__*_gh_pr_*`, `mcp__*__*_merge_to_*`, or a similar host-side git verb. When a landing step (push, open PR, merge to the default branch) must reach the host, calling this directly is cleaner than staging shell commands on the clipboard for the user. Prefer it over the clipboard chain whenever it is present.

When the skill needs a capability, look through the currently available MCP tools and pick the one whose shape matches. If multiple candidates exist, prefer the one whose host namespace is most active in the session (i.e. has had other recent tool calls). If none exist, fall back to the next degradation tier.

## Tier 1: delegate to a task-spawning host

If a `task_create`-shaped tool is available, use it instead of `git worktree add` + in-process `Agent`. The contract you assume:

- **Input:** a task description (same prompt content you would have given the in-process Agent), a slug, a **base ref** (see below), and any host-specific flags.
- **Output:** the host creates a worktree outside the sandbox and spawns a worker in it. The host returns the worktree path and a task identifier.

**Base ref (required — do not skip).** A `task_create`-shaped host branches the worker off the repo's default branch unless told otherwise. But the calling session is often on a stacked feature branch whose code the bug actually lives in — branching off the default branch would build the fix against code that does not contain the bug, and the fix would not stack correctly. Before calling the host, capture the calling session's current branch and pass it as the base ref:

```bash
BASE_REF=$(git branch --show-current 2>/dev/null)   # e.g. add-hera-view; empty if detached → fall back to HEAD
```

Pass `BASE_REF` as the host's `base_branch` (or equivalent) argument. That branch already exists on the host — the sandbox worktree was cut from it — so the host can branch the worker from it directly.

**Completion signaling.** A host task does NOT push its completion back to the calling session, so "fire and forget" would leave the skill hanging. Pick based on capability detection:

- **Coordination channel available:** add a final step to the worker prompt — on finish, the worker (a) sends a message to the calling session (`status: done|blocked`, branch name, one-line summary) and (b) records its result via the host's result tool (a `task_set_result`-shaped tool) before exiting. The calling session proceeds to review when that message lands.
- **No coordination channel:** there is no notification path. Tell the user plainly that completion must be polled — e.g. `Worker dispatched as task <id>. Poll its status with the host's task_get tool; it will not notify automatically.` Do not claim the caller "will be notified."

Wrap the call so the rest of the skill does not care whether the worker was started in-process or by the host. Do not merge the worker's branch into MAIN_REPO's default branch yourself in sandbox mode — but if the calling session is on a feature branch, you CAN land the fix locally. See Tier 3.

## Tier 2: staged-command fallback

If no `task_create`-shaped tool is available, fall back to staging the commands for the user to run in a shell with main-repo write access.

Build the worktree-create + agent-dispatch sequence as one bash block. Then:

1. Push it to the user's clipboard. Detect the clipboard mechanism in this order:
   - `pbcopy` if it exists.
   - Any MCP clipboard-set tool whose name contains `clipboard`.
   - Failing both: print the block to stdout under a clear "Run these commands in a shell that can write to MAIN_REPO" header.
2. Tell the user one line: `Sandbox detected – worktree commands copied to your clipboard. Paste into a shell with main-repo write access, then return here.`

Return control to the user. Do not block waiting. Later skill steps that require main-repo writes (review-driven re-dispatch, merge) stage their own commands the same way when they fire.

## Tier 3: landing the fix

The landing target is the branch the calling session was on when the skill was invoked (the original/base branch captured at dispatch), NOT automatically the repo's default branch. Detect which case applies and act accordingly — after both reviews pass.

### Case A: calling session is on a feature branch (not main/master)

Merging the worker's branch into the *current* branch is a write to the calling session's own worktree, which IS writable in sandbox mode — no staging required:

```bash
git fetch origin <feature-branch>     # worker pushed here; reading the remote is allowed in sandbox mode
git merge FETCH_HEAD --no-edit        # lands into the current (writable) branch
```

Then get the updated branch back to the host. Prefer a host git/PR helper (a `*_push`-shaped tool, per capability detection) over staging a clipboard command. Only if no host helper exists, stage `git push` for the user via the Tier 2 clipboard chain.

### Case B: calling session is on main/master

The calling session cannot write MAIN_REPO's default branch in sandbox mode. Land via the cleanest available path:

1. **Host git/PR helper present (preferred):** call it directly — open a PR (`*_gh_pr_create`-shaped) or merge to the default branch (`*_merge_to_*`-shaped) — instead of staging to the clipboard.
2. **No host helper:** build the merge command set and stage it via the Tier 2 clipboard chain:
   - `git -C MAIN_REPO checkout <main-branch>`
   - `git -C MAIN_REPO merge <feature-branch> --no-edit`
   - Cleanup if appropriate: `git -C MAIN_REPO worktree remove <path> --force` and `git -C MAIN_REPO branch -D <slug>`

### Report

Report to the user with the skill's normal format, calling out how the fix landed:

```
Fixit ready: <short title>
  Branch: <feature-branch> (pushed; worktree at <path>)
  Landed: <merged into <branch> locally | PR #<n> opened | merge staged to clipboard — run in a shell with main-repo write access>
  📋 Specs: <status>
```

## Async verify-then-archive (OpenSpec projects in sandbox mode only)

Standard OpenSpec lifecycle has the calling session run `openspec archive <name>` once the change lands on main. In sandbox mode the calling session cannot touch MAIN_REPO, so the worker has to archive from its own worktree. This requires the worker to park between "fix pushed" and "archive run" and the calling session to signal verification.

This pattern only fires when **all three** are true:

- `openspec/` exists at the project root.
- The probe returned `sandbox`.
- A coordination channel is available (per Generic capability detection above).

If any of the three is false, skip this pattern. The skill instead either takes the normal openspec-archive path (non-sandbox) or stages a manual archive command for the user (sandbox without coordination channel) – see "Fallback when no coordination channel" below.

### Worker contract changes

When this pattern fires, the worker prompt gains two requirements:

1. After implementing + committing + pushing the feature branch, the worker does **not** call task_complete (or its host equivalent). Instead it sends a message to the calling session via the coordination channel:

   ```
   status: pending-verification
   branch: <feature-branch>
   change: <openspec-change-name>
   ```

2. The worker then parks – polls its inbox on a slow interval (e.g. every 5 minutes) until it receives a message containing `verified: true` or `verified: false`:

   - On `verified: true`: the worker runs `openspec archive <change>` in its own worktree, commits the archive movement, pushes, sends a final `status: archived` message, then calls task_complete and exits.
   - On `verified: false`: the worker reads the included feedback, addresses it on the same branch, pushes again, sends a fresh `status: pending-verification`, and re-parks.
   - If no message arrives within a sensible timeout (default 24h): the worker sends `status: parked-timeout` and exits without archiving. The user will need to archive manually.

### Calling session changes

When the worker reports `pending-verification`:

1. Run the standard two-stage review (spec compliance, then code quality) against the worker's pushed branch. The calling session can read from the remote even when it cannot write to MAIN_REPO.
2. If both reviews pass: send `verified: true` to the worker via the coordination channel. Then land the fix per Tier 3 (local merge if the calling session is on a feature branch; otherwise a host PR/merge helper or a staged merge).
3. If issues are found: send `verified: false` with the feedback bundled. Wait for the worker's next `pending-verification`.

The worker's final `status: archived` is the signal the calling session can fully report success to the user.

### Fallback when no coordination channel

If the probe returns `sandbox`, OpenSpec is in use, but no coordination channel is detected, the worker cannot park. In that case:

1. The worker implements, commits, pushes, and exits normally (does not archive).
2. The calling session, after reviews pass, stages BOTH the merge command and the archive command for the user:

```
git -C MAIN_REPO checkout <main-branch>
git -C MAIN_REPO merge <feature-branch> --no-edit
git -C MAIN_REPO -c core.editor=true openspec archive <change>
git -C MAIN_REPO push
```

This is strictly worse than the parked-worker path (user has more to do, archive runs against MAIN_REPO main rather than the feature branch) but it is the correct behavior when the host provides no IPC.

## What not to do

- Do not hardcode any host name (argus, hera, plannotator, etc.) in detection logic. Tool-shape matching is the contract.
- Do not auto-merge into MAIN_REPO's default branch from sandbox mode — stage it, or use a host PR/merge helper. Merging the worker's branch into the calling session's *own* feature branch is fine: that write lands in the writable worktree, not MAIN_REPO.
- Do not branch the worker off the default branch when the calling session is on a stacked feature branch — pass the current branch as the base ref (Tier 1).
- Do not tell the user the caller "will be notified" of completion when no coordination channel exists — say it must be polled (Tier 1).
- Do not change non-sandbox behavior. When the probe returns `ok`, every code path in this doc is dead.
- Do not probe more than once per skill invocation. Cache the result.
- Do not require the user to choose between modes. Detection auto-selects.
