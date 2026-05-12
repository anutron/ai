---
name: tp
description: ALWAYS use the `tp` CLI instead of Read+Edit for any single-line checkbox edit in markdown task lists. TRIGGER when ticking items in `openspec/changes/*/tasks.md`, `openspec/specs/**/*.md` task lists, `.workflow/test-plans/*.md`, or any markdown file with `- [ ] N.M` or `- [ ] **N.M**` checkbox lines; flipping `- [ ]` ↔ `- [x]`; appending one-line status annotations (✅ pass / ❌ fail / 🟡 partial / ⏭ skip). SKIP for multi-paragraph findings (use Edit), structural changes to a file (Write/Edit), or bulk operations across many IDs in one call (run multiple `tp` invocations instead).
---

# tp — checkbox CLI

Always reach for `tp` over Read+Edit when the operation is a single-line checkbox flip or a one-line status annotation in a markdown task list. Streaming the whole file through Edit costs ~150–200 tokens per tick; `tp` does it in one Bash call.

## TRIGGER / SKIP

- **TRIGGER** — checkbox-shaped lines: `- [ ] 1.1 Description`, `- [x] **2.4** Description`, `- [ ] **3.1a** Description – ✅ note`. Files include `openspec/changes/*/tasks.md`, `openspec/specs/**/*.md` task lists, `.workflow/test-plans/*.md`, and any other markdown with the same line shape.
- **SKIP** — anything that is not a single-line checkbox edit: multi-paragraph findings, structural changes (new sections, reordered groups), prose edits, deltas, scaffolding new files. Use Edit / Write for those.

## When to use `tp`

- Ticking items in `openspec/changes/<name>/tasks.md` as stages complete during `/execute-plan`.
- Marking rows in `.workflow/test-plans/*.md` (or any test plan with the bold-ID + emoji shape) as you work through validation passes.
- Any markdown file with `- [ ] <id> Description` or `- [ ] **<id>** Description` lines.

## When NOT to use `tp`

- **Multi-paragraph findings.** `tp` annotations are one line. If you have a finding that spans multiple sentences with rich detail, use Edit. Single-line summaries are `tp`'s job.
- **Bulk operations across many IDs.** No `tp pass 3.1 3.2 3.3` form. Run multiple invocations (in parallel via separate Bash calls if independent).
- **Scaffolding new files or sections.** `tp` only rewrites existing checkbox lines. Use Write/Edit for structural changes.
- **Anything outside the checkbox shape.** `tp` matches `^- [ ]` or `^- [x]` lines with a numeric ID (`N`, `N.M`, `N.M.M`). Free-form markdown stays on Edit.

## Command surface

Always pass `-f <file>` (required). Always pass exactly one positional `<id>`.

| Verb | Effect on `[ ]` | Effect on `[x]` | Annotation appended | Note required |
|------|-----------------|-----------------|---------------------|---------------|
| `tp pass <id> -f F -n "note"` | flips to `[x]` | rewrites | ` – ✅ note` | yes |
| `tp fail <id> -f F -n "note"` | flips to `[x]` | rewrites | ` – ❌ note` | yes |
| `tp partial <id> -f F -n "note"` | flips to `[x]` | rewrites | ` – 🟡 note` | yes |
| `tp skip <id> -f F -n "reason"` | leaves `[ ]` | leaves `[x]` | ` – ⏭ reason` | yes |
| `tp done <id> -f F` | flips to `[x]` | no-op | (none) | not allowed |
| `tp untick <id> -f F` | no-op | flips to `[ ]`, strips annotation | (none) | not allowed |

Re-running with a new note overwrites the existing annotation. Re-running `done` on a checked line (or `untick` on an unchecked line) is a no-op (exit 0, single stderr line).

## ID matching

- ID is the dotted-numeric string before the description (`2.4`, `3.1`, `0.1`).
- Match must be unique. Multiple matches → exit 1 with the line numbers listed.
- Lines inside fenced code blocks and IDs in prose are not matched.
- Bold (`**2.4**`) and plain (`2.4`) ID styles are both recognized; the original style is preserved on rewrite.

## Output

- Success: `marked <id> <verb>` to stdout, exit 0.
- No-op: `<id> already <state>` to stderr, exit 0.
- Error: single-line message to stderr, exit 1.

## Examples

Tick an OpenSpec stage's tasks:

```bash
tp done 2.1 -f openspec/changes/add-tp-cli/tasks.md
tp done 2.2 -f openspec/changes/add-tp-cli/tasks.md
tp done 2.3 -f openspec/changes/add-tp-cli/tasks.md
```

Annotate a test plan row:

```bash
tp pass 2.4 -f .workflow/test-plans/2026-05-09-validate-24h.md \
  -n "stale session worked end-to-end after fixing CSRF regression"
tp fail 5.2 -f .workflow/test-plans/2026-05-09-validate-24h.md \
  -n "actual XFO value is DENY, stricter than spec'd"
tp partial 6.1 -f .workflow/test-plans/2026-05-09-validate-24h.md \
  -n "regenerated against sibling fallback"
tp skip 4.7 -f .workflow/test-plans/2026-05-09-validate-24h.md \
  -n "depends on policy decision"
```

Reverse a tick:

```bash
tp untick 2.4 -f .workflow/test-plans/2026-05-09-validate-24h.md
```

## Notes for Claude

- `tp` must be on `$PATH`. If `command -v tp` fails: install from the source directory shipped with this kit. The kit places source at `bin/tp/` (under the published claude-skills repo) or `.claude/bin/tp/` (when developing in AI-RON). Run `make install` there (links `~/.local/bin/tp` by default; pass `PREFIX=/usr/local` for a system-wide install).
- A prebuilt macOS arm64 binary is checked in alongside the source. Other platforms must `make install` to rebuild for their architecture.
- Atomic writes mean partial files are never observable; safe to invoke without locking.
- Other workflow skills (`/execute-plan`, `/ralph-review`, `/bugbash`, `/fixit`) still call Edit directly today. A follow-on change will update them to call `tp`. Until then, reach for `tp` yourself any time the trigger matches.
