# Sandbox-aware dispatch

The /fixit and /bugbash skills assume two writes against the main repo root that the calling session itself performs:

1. `git worktree add MAIN_REPO/.claude/worktree[s]/<slug>` to create the worker worktree.
2. `git checkout <main-branch> && git merge <feature-branch>` to land the result.

In a sandboxed worktree (a worktree whose process cannot write outside its own directory at the OS layer), both operations fail with "Operation not permitted". This document defines a graceful degradation. The skills should auto-detect sandbox mode and switch behavior without asking the user.

Non-sandbox behavior is unchanged. Everything in this doc is opt-in based on detection.

## When this fires

Each skill's `## Context` block already runs the probe script and surfaces the result as `Sandbox mode: ok` or `Sandbox mode: sandbox`. Read it from there. If you need to re-check later in the skill, run the same script again:

```bash
~/.claude/bin/sandbox-probe.sh
```

The probe prints `ok` when MAIN_REPO/.claude/ is writable, or `sandbox` otherwise. Cache the result for the rest of the skill invocation – sandbox state does not change mid-session.

If `ok`: follow the skill's normal worktree + merge path. Stop reading this doc.

If `sandbox`: follow the sections below.

## Generic capability detection

This doc avoids naming any specific host (no argus, no hera, no plannotator). The skills detect three host capabilities at runtime by tool shape:

- **Task spawning** – a tool whose name matches `mcp__*__task_create` or `mcp__*__*_task_create`. The host can create a fresh worktree and spawn a worker in it.
- **Coordination channel** – a pair of tools whose names contain `_send`/`_message_send` and `_inbox`/`_messages`. The calling session and worker can exchange messages.
- **Clipboard helper** – `pbcopy` on PATH, or any MCP tool matching `mcp__*__*clipboard*`. The skill can stage commands for the user to run elsewhere.

When the skill needs a capability, look through the currently available MCP tools and pick the one whose shape matches. If multiple candidates exist, prefer the one whose host namespace is most active in the session (i.e. has had other recent tool calls). If none exist, fall back to the next degradation tier.

## Tier 1: delegate to a task-spawning host

If a `task_create`-shaped tool is available, use it instead of `git worktree add` + in-process `Agent`. The contract you assume:

- Input: a task description (same prompt content you would have given the in-process Agent), a slug, and any host-specific flags.
- Output: the host creates a worktree outside the sandbox and spawns a worker in it. The host returns the worktree path and a task identifier the calling session can later use to receive worker status.

Wrap the call so the rest of the skill does not care whether the worker was started in-process or by the host – both paths converge to "a worker is running, we will be notified when it reports back".

Do not try to merge the worker's branch yourself in sandbox mode. See Tier 3.

## Tier 2: staged-command fallback

If no `task_create`-shaped tool is available, fall back to staging the commands for the user to run in a shell with main-repo write access.

Build the worktree-create + agent-dispatch sequence as one bash block. Then:

1. Push it to the user's clipboard. Detect the clipboard mechanism in this order:
   - `pbcopy` if it exists.
   - Any MCP clipboard-set tool whose name contains `clipboard`.
   - Failing both: print the block to stdout under a clear "Run these commands in a shell that can write to MAIN_REPO" header.
2. Tell the user one line: `Sandbox detected – worktree commands copied to your clipboard. Paste into a shell with main-repo write access, then return here.`

Return control to the user. Do not block waiting. Later skill steps that require main-repo writes (review-driven re-dispatch, merge) stage their own commands the same way when they fire.

## Tier 3: post-implementation merge (always staged in sandbox mode)

The calling session cannot run `git merge` against MAIN_REPO in sandbox mode regardless of whether dispatch was tier 1 or tier 2. After both reviews pass:

1. Build the merge command set:
   - `git -C MAIN_REPO checkout <original-branch>`
   - `git -C MAIN_REPO merge <feature-branch> --no-edit`
   - Cleanup if appropriate: `git -C MAIN_REPO worktree remove <path> --force` and `git -C MAIN_REPO branch -D <slug>`
2. Stage the block to the user's clipboard via the Tier 2 clipboard chain.
3. Report to the user with the same format the skill normally uses, but call out that the merge is staged:

```
Fixit ready to merge: <short title>
  Branch: <feature-branch> (pushed; worktree at <path>)
  📋 Specs: <status>
  Sandbox detected – merge command copied to clipboard. Run it in a shell with main-repo write access.
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
2. If both reviews pass: send `verified: true` to the worker via the coordination channel. Then stage the merge command for the user (Tier 3).
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
- Do not try to auto-merge from sandbox mode. Staging the merge command for the user is correct.
- Do not change non-sandbox behavior. When the probe returns `ok`, every code path in this doc is dead.
- Do not probe more than once per skill invocation. Cache the result.
- Do not require the user to choose between modes. Detection auto-selects.
