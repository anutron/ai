## User-facing framing for choices and findings

When asking the user to **contemplate something** – review a design section, weigh a code-review question, pick among debugging hypotheses, evaluate a proposed change – the user is usually approving your output, not co-authoring it. Lead with intent and impact. Keep technical detail as a spot-check, not the headline.

### Structure

Skip parts that don't apply; keep parts that do:

- **Why this matters** – situate the question. What does this touch (a user flow, a security boundary, a performance hotpath, an external contract)? What downstream behavior or decisions depend on the answer? Help them understand why they're being pulled in.
- **What's happening / Outcome** – plain-language summary of the current state or what the choice unlocks. No jargon, no line numbers in the narrative.
- **What could go wrong** (for findings) or **Tradeoffs** (for design choices) – consequences in system or user behavior, not code mechanics. Every existing behavior has a reason; surface it before recommending change.
- **Recommendation** – take a position. Defend it with the tradeoffs. Don't hedge between options – if the user disagrees, their response is where they redirect.
- **Technical details** – a brief 1-3 line summary of the concrete artifacts (file, type or function, key fields, the relevant delta or spec line). Users often skim this, but sometimes catch a real issue at this layer.

### Examples

| Good (outcome-first) | Bad (mechanism-first) |
|---|---|
| "the UI freezes briefly during resume" | "`functionA()` calls `time.Sleep()` on the main thread" |
| "users could see stale data" | "the backing array could be shared" |
| "removing the delay makes resume snappier but risks the previous session not stopping before the new one starts" | "remove the `tea.Cmd` dispatch and call directly" |

### When it applies

- Presenting design sections during brainstorming or planning
- Listing findings or questions in a code review
- Surfacing hypotheses during debugging
- Recommending changes during a retrospective or audit
- Any `AskUserQuestion` that asks the user to weigh tradeoffs

### When it doesn't apply

- Status updates and completion reports (just say what changed)
- Strictly procedural prompts ("which file?")
- Output the user reads but doesn't have to decide on (changelogs, summaries)
