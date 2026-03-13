---
name: pr-dashboard
description: Show open PRs, review requests, and recently closed PRs with age and status. Supports team members.
allowed-tools: Bash
user-invocable: true
---

# PR Dashboard

Show a PR activity dashboard for one or more GitHub users.

## User Directory

| Name | GitHub Username | Role |
|------|----------------|------|
| Aaron | anutron | manager (default) |
| Diana | DianaMelkumyan | report |
| Erin | erineastick | report |
| Bailey | bscov | report |

## Arguments

- No args: show Aaron's dashboard
- `diana`, `erin`, `bailey`: show that person's dashboard
- `team` or `all`: show dashboards for all 4 users
- Multiple names: `diana erin` shows both

Parse args case-insensitively. Match first names to the user directory above.

## Data Collection

For each target user, run these three searches **in parallel**:

```bash
# Open PRs authored by user
gh search prs --author=<username> --state=open --json number,title,repository,createdAt,url,isDraft,updatedAt --limit 30 --sort=created --order=desc

# PRs where user's review is requested
gh search prs --review-requested=<username> --state=open --json number,title,repository,createdAt,url,isDraft,updatedAt --limit 20 --sort=created --order=desc

# Recently closed/merged PRs by user
gh search prs --author=<username> --state=closed --json number,title,repository,createdAt,closedAt,url,state --sort=updated --order=desc --limit 30
```

When showing multiple users, run ALL searches in parallel (not sequentially per user).

## Enrichment (Batched GraphQL)

**Do NOT call `gh pr view` individually per PR.** Instead, batch all open PRs into one or two GraphQL queries using aliases.

### Build the query

Collect all unique (owner, repo, number) pairs from the open PR lists. For each, create a GraphQL alias:

```bash
gh api graphql -f query='
{
  pr_1: repository(owner: "thanx", name: "thanx-looker") {
    pullRequest(number: 355) {
      reviewDecision
      mergeable
      isDraft
      commits(last: 1) {
        nodes {
          commit {
            statusCheckRollup {
              state
            }
          }
        }
      }
    }
  }
  pr_2: repository(owner: "thanx", name: "thanx-dbt") {
    pullRequest(number: 808) {
      reviewDecision
      mergeable
      isDraft
      commits(last: 1) {
        nodes {
          commit {
            statusCheckRollup {
              state
            }
          }
        }
      }
    }
  }
}
'
```

### Alias naming convention

Use `pr_<index>` (e.g., `pr_1`, `pr_2`, ...). Keep a mapping of alias to (repo, number) so you can match results back.

### GraphQL node limits

GitHub GraphQL has a ~500 node limit per query. Each PR alias uses ~5 nodes. If you have more than ~80 PRs, split into multiple queries. In practice this won't happen.

### Fallback

If the GraphQL call fails (e.g., permission issues), fall back to individual `gh pr view` calls in parallel.

### Extract from results

- **reviewDecision**: `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or empty
- **CI status**: From `commits.nodes[0].commit.statusCheckRollup.state` - map to `passing` (SUCCESS), `failing` (FAILURE/ERROR), `pending` (PENDING/EXPECTED), or `none` (null/empty)
- **mergeable**: `MERGEABLE`, `CONFLICTING`, or `UNKNOWN`

## Age Calculation

Calculate age from `createdAt` to now. Display as:
- `< 1d` for less than 24 hours
- `Xd` for 1-6 days
- `Xw` for 7-29 days
- `Xmo` for 30+ days

## Output Format

Format as a clean dashboard. Use the short repo name (not `owner/repo`) to save space unless repos share a name.

### For Aaron (default, or when specified)

```
## Aaron's Open PRs (X)

| Age | Repo | PR | CI | Review | Notes |
|-----|------|----|----|--------|-------|
| 1d  | thanx-looker | #355 Add merchant integrations... | passing | review required | |
| 3w  | thanx-dbt | #791 Add UTM attribution... | passing | review required | **stale** |

## Needs Aaron's Review (X)

| Age | Repo | PR | CI | Review | Notes |
|-----|------|----|----|--------|-------|
| < 1d | thanx-nucleus | #5603 Add checkout_message... | passing | review required | |

## Aaron's Closed This Week (X)

| Closed | Repo | PR | Result |
|--------|------|----|--------|
| today  | thanx-merchant-ui | #3367 Add UTM and Location... | merged |
```

### For team members

Same format but with their name: "Diana's Open PRs", "Needs Diana's Review", etc.

### For `team`/`all`

Show each person's dashboard separated by a horizontal rule (`---`). Order: Aaron, Diana, Erin, Bailey.

## Presentation Rules

1. **Truncate PR titles** to ~50 chars with `...` if needed
2. **Link PRs** - make the `#number title` a clickable markdown link to the PR URL
3. **Highlight staleness** - if an authored PR is > 7 days old with no approval, add `**stale**` in Notes
4. **Highlight conflicts** - if mergeable is `CONFLICTING`, add `**conflict**` in Notes
5. **Highlight approved** - if reviewDecision is `APPROVED`, add `ready to merge` in Notes
6. **Sort** by age (newest first) within each section
7. **Filter closed PRs** to only those closed within the last 7 days
8. **Closed date** - show as relative ("today", "1d ago", "3d ago")
9. **Result column** for closed PRs - show `merged` or `closed` (closed = closed without merge)
10. **Skip ancient PRs** - if an authored PR is > 6 months old, group separately as "Stale (>6mo)" with just a count and note to consider closing

## After Display

End with a brief one-line summary per user, e.g.:
> **Aaron:** 5 open (2 need reviews), 3 awaiting review, 6 merged this week

If any PRs are concerning (stale, conflicting, failing CI, changes requested), call them out specifically.
