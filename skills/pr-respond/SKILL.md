---
name: pr-respond
description: Read PR review feedback, triage each comment (adopt/reject with reasoning), optionally apply changes and commit. Writes artifacts to ~/.claude/pr-responses/. Use when a PR has received review comments that need to be addressed.
---

# PR Respond

Read GitHub PR review feedback, evaluate each comment on its merits, and produce a structured response with reasoning. By default, evaluates feedback and writes artifacts without making code changes. With --apply, also makes code changes and commits locally.

## Arguments

- ARGUMENTS - Optional: PR number, PR URL, or flags (--apply, --plan-only)

## Context

- Current branch: !`git branch --show-current 2>/dev/null | head -1`
- Repo info: !`gh repo view --json owner,name --jq ".owner.login + \"/\" + .name" 2>/dev/null | head -1`
- Git status: !`git status --short 2>/dev/null | head -20`

## Instructions

### 1. Parse arguments

The raw string following the slash command is available as ARGUMENTS (e.g., "123 --apply" or "https://github.com/org/repo/pull/42 --plan-only").

- Split the argument string into tokens.
- Identify the PR reference: any token that is a bare number or a GitHub PR URL. Extract the PR number from a URL by taking the last path segment.
- Identify flags: --apply sets apply mode (evaluate feedback AND make code changes). --plan-only is the default mode (evaluate and write artifacts, but do not modify code). If neither flag is present, default to plan-only.
- Any unrecognized tokens should be ignored.

### 2. Resolve the PR

If a PR number was extracted from arguments, fetch its metadata:

```bash
gh pr view <number> --json number,title,body,state,url,headRefName
```

If no PR number was provided, detect the PR from the current branch:

```bash
gh pr list --head "$(git branch --show-current)" --state open --json number --jq ".[0].number"
```

If multiple PRs match, use the first result.

Extract owner and repo from the "Repo info" context line above (format is "owner/repo").

**Abort conditions:**
- No PR was found for the current branch and no PR number was provided. Print a message and stop.
- The PR is closed or merged AND apply mode is set. Plan-only mode is allowed on any PR state (reviewing feedback on a merged PR to learn from it is valid). Print a message explaining why apply mode is not available and stop.

### 3. Fetch review comments

Use the GitHub GraphQL API to fetch review threads with resolution status:

```bash
gh api graphql -f query='
  query {
    repository(owner:"OWNER", name:"REPO") {
      pullRequest(number:NUM) {
        reviewThreads(first:100) {
          nodes {
            isResolved
            comments(first:10) {
              nodes {
                body
                author { login }
                path
                line
              }
            }
          }
        }
      }
    }
  }
'
```

Replace OWNER, REPO, and NUM with the actual values resolved in Step 2.

**Only evaluate comments from unresolved threads.** Skip resolved threads entirely.

Also fetch top-level review bodies for any review-level comments:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews
```

Only review-submitted comments and inline PR review comments count. General PR conversation comments (issue-style comments on the PR timeline) are NOT review feedback and should be excluded.

**Abort if** no unresolved review comments exist. Print a message indicating there is nothing to address and stop.

### 4. Check for re-invocation on same state

Before performing evaluation, check whether a previous response already covers the current state.

- Look for existing response files matching the pattern:
  ```
  ~/.claude/pr-responses/<owner>-<repo>-<pr>-response-*.md
  ```
- If the most recent file exists, read its metadata lines for "HEAD at evaluation" and "Comment count".
- Compare the HEAD SHA recorded in the file against the current HEAD:
  ```bash
  git rev-parse HEAD
  ```
- If the recorded HEAD SHA matches the current HEAD AND the recorded comment count matches the current number of unresolved review comments, then skip evaluation. Print the contents of the existing response file and stop.
- Otherwise, proceed with fresh evaluation (the code has changed or new comments have arrived since the last run).

### 5. Understand the PR (Phase 1)

Build a complete picture of what this PR does and why, before evaluating any feedback.

**Fetch the full diff:**

```bash
gh pr diff <number>
```

**Read the PR description.** The title and body were already fetched in Step 2. Read them carefully to understand the author's stated intent -- what problem is being solved, what approach was chosen, and any tradeoffs the author called out.

**Read each changed file in full.** For every file that appears in the diff, use the Read tool to read the entire file (not just the diff hunks). This provides the surrounding context needed to evaluate whether reviewer suggestions make sense in the broader codebase.

**Synthesize author intent.** Write a 2-3 sentence summary of what the PR is trying to accomplish and the approach it takes. This summary will be included in the plan artifact produced later. Hold this summary in working memory for use in Step 6.

### 6. Evaluate each comment (Phase 2)

For each unresolved review comment collected in Step 3, perform the following five-point assessment:

1. **Restate the ask.** Summarize what the reviewer is requesting in one clear sentence. Strip away tone, hedging, and rhetorical questions to get to the concrete ask.

2. **Read the referenced code.** Use the Read tool to load the specific file and line range the comment targets. Read enough surrounding context (at least 20 lines above and below) to understand the code in situ.

3. **Assess alignment with author intent.** Does this feedback support or conflict with the goals identified in Step 5? Feedback that would redirect the PR toward a different goal is not automatically wrong, but it carries a higher bar for adoption.

4. **Assess technical merit.** Is the suggestion factually correct? Does it actually improve correctness, readability, performance, or maintainability? Would the change introduce new problems or unnecessary complexity?

5. **Decide: adopt or reject.** State the decision clearly, followed by one or two sentences of reasoning. Every comment must get a decision -- do not defer or mark anything as "discuss later."

**Principles for evaluation:**

- Act as a thoughtful coauthor, not a people-pleaser. Do not adopt feedback simply to be agreeable or to avoid conflict.
- Reject feedback that would compromise the PR's intent, introduce unnecessary complexity, or make the code harder to maintain, even if the reviewer is senior.
- If two reviewers give contradictory feedback on the same area of code, pick the approach that best preserves the author's intent and surface the conflict explicitly in the reasoning.
- If a reviewer comments on lines that the author did not change in this PR, default to rejecting that feedback as out of scope. Note it as something the author could choose to address in a follow-up, but do not let it block or expand the current PR.
- If no comments require code changes (all praise, questions answered inline, or discussion with no actionable items), note this fact and skip ahead to Phase 5 (Step 9).

### 7. Write Plan Artifact (Phase 3)

Create the artifact directory if it does not exist:

```bash
mkdir -p ~/.claude/pr-responses
```

Generate a timestamp once in YYYY-MM-DDThh-mm format using local time. Reuse this same timestamp for both the plan and response filenames throughout the remaining steps. Do not regenerate it.

Write the plan artifact to the following path:

```
~/.claude/pr-responses/<owner>-<repo>-<pr>-plan-<timestamp>.md
```

Use this template for the plan artifact:

```
# PR Response Plan

## PR Context
- **PR:** #<number> — <title>
- **URL:** <pr url>
- **Branch:** <branch name>
- **Author Intent:** <2-3 sentence summary from Step 5>

## Adopted Feedback

### <short description of comment>
- **Reviewer:** @<username>
- **Their input:** <quote or paraphrase of what they asked for>
- **Location:** <file:line>
- **Assessment:** <why this feedback has merit>
- **Planned change:** <specific description of the code change to make>

(repeat for each adopted comment)

## Rejected Feedback

### <short description of comment>
- **Reviewer:** @<username>
- **Their input:** <quote or paraphrase>
- **Location:** <file:line>
- **Assessment:** <why this should not be adopted>
- **Tradeoffs:** <what the reviewer gains/loses from this rejection>

(repeat for each rejected comment)
```

### 8. Execute Changes (Phase 4 — only with --apply)

If apply mode was not set in Step 1, skip this step entirely and proceed to Step 9.

For each adopted comment from the plan:
- Read the target file using the Read tool.
- Make the edit using the Edit tool.

After all changes are made, check if a test runner is already available and runnable without any setup. Look for common patterns:

```
npx jest
npx vitest
pytest
rspec
go test
cargo test
make test
```

Only run tests if the command works immediately — never install dependencies or set up test environments. If the environment is not ready, skip tests and note "Tests skipped — environment not ready" for the summary.

Stage only the files that were changed by adopted feedback. Create a single commit with the following message:

```
Address PR review feedback (#<pr-number>)
```

Do NOT push. Do NOT amend existing commits.

### 9. Write Response Summary (Phase 5 — runs unconditionally)

This step runs regardless of whether --apply was passed.

Write the response summary to the following path, using the SAME timestamp generated in Step 7:

```
~/.claude/pr-responses/<owner>-<repo>-<pr>-response-<timestamp>.md
```

Use this template for the response summary:

```
# PR Response: <owner>/<repo> #<number>

- **PR:** [<title>](<url>)
- **Branch:** <branch>
- **Commit:** <SHA of the commit from Step 8, or "N/A — plan only" if --apply was not used>
- **HEAD at evaluation:** <current HEAD SHA, always recorded>
- **Comment count:** <total unresolved review comments evaluated>
- **Date:** <YYYY-MM-DD>
- **Plan:** ~/.claude/pr-responses/<owner>-<repo>-<pr>-plan-<timestamp>.md

## Adopted Feedback

### <short description>
- **Reviewer:** @<username>
- **Their input:** <what they asked for>
- **Change made:** <what was done, or "Planned but not applied" if --apply was not used>
- **Tradeoffs:**
  - Good: <how this improves the PR>
  - Bad: <any cost — added complexity, divergence from original intent, etc.>
- **Impact on author intent:** <neutral / minor shift / significant shift>

(repeat for each adopted comment)

## Rejected Feedback

### <short description>
- **Reviewer:** @<username>
- **Their input:** <what they asked for>
- **Why not adopted:** <technical reasoning>
- **Tradeoffs:**
  - Good: <what is preserved by rejecting>
  - Bad: <what the reviewer loses>
- **Options:**
  - A) <alternative approach if one exists>
  - B) Adopt as-is if author disagrees with this rejection
  - C) Discuss further with reviewer

(repeat for each rejected comment)

## Test Results
<pass/fail/skipped — brief note>

## Next Steps
- Review this summary
- To apply changes: /pr-respond --apply
- Push when ready: git push
- Reply to reviewer on GitHub if desired
```

### 10. Present Summary (Phase 6)

Print the full response summary content to the terminal so the user can see the complete summary inline.

Print both artifact file paths:

```
Plan: ~/.claude/pr-responses/<owner>-<repo>-<pr>-plan-<timestamp>.md
Response: ~/.claude/pr-responses/<owner>-<repo>-<pr>-response-<timestamp>.md
```

If in plan-only mode, remind the user they can run /pr-respond --apply to execute the planned changes.

Wait for user instruction. Do not take further action.
