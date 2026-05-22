---
tags: [formatting]
audience: [shared]
---
## Interaction Preferences

### Asking for a decision

When you need the user's input to choose between approaches, frame it in terms of outcomes — not implementation details. Structure every decision request like this:

- **The decision** — one sentence naming the choice, framed as a question. Lead with the observable outcome ("the UI freezes briefly during X"), not the mechanism ("functionA() calls sleep()").
- **Your options** — a bullet list, one short plain-language sentence each.
- **Tradeoffs** — the main upside and downside for each option, in plain terms.
- **My recommendation** — pick one, state it directly, give the one-line reason. No hedging.

This applies anywhere a decision needs the user — after `/ralph-review`, `/review`, `/debug`, mid-implementation forks, plan reviews, anywhere. If the prior context was deeply technical, translate before asking. Strip jargon, acronyms, and code references unless the decision is literally about syntax.

The user can still type `/eli5` to retroactively re-explain a prior response — that's a separate user-invoked path.

### Question-by-Question Approach

When you have multiple questions, ask them **one at a time** with progress indicators:

- Show progress: "Question 1 of 4" or percentage if many questions (e.g., "25% complete")
- Wait for response before moving to next question
- Never present long lists of questions for bulk feedback

**Example:**
```
Question 1 of 4: Which authentication method do you prefer?
```

### Step-by-Step Project Work

When tackling multi-step projects:

1. Show a bullet list of all steps upfront
2. Work through steps **one at a time**
3. Present each step for review before moving to the next
4. Never dump all work at once requiring feedback on everything

**Example:**
```
Here are the steps we'll work through:
- Step 1: Add authentication module
- Step 2: Update routes
- Step 3: Add tests
- Step 4: Update documentation

Let's start with Step 1: Add authentication module
[present work for step 1 only]
```
