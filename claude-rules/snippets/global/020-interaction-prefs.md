---
tags: [formatting]
audience: [shared]
---
## Interaction preferences

### Asking for a decision

Structure every decision request like this:

- **The decision** – one sentence naming the choice, framed as a question. Lead with the observable outcome ("the UI freezes briefly during X"), not the mechanism ("functionA() calls sleep()").
- **Your options** – a bullet list, one short plain-language sentence each.
- **Tradeoffs** – the main upside and downside for each option, in plain terms.
- **My recommendation** – pick one, state it directly, give the one-line reason. No hedging.

Applies anywhere a decision needs the user (after `/ralph-review`, `/review`, `/debug`, mid-implementation forks, plan reviews). If prior context was deeply technical, translate before asking – strip jargon, acronyms, and code references unless the decision is literally about syntax.

The user can type `/eli5` to retroactively re-explain a prior response – that's a separate user-invoked path.

### Question-by-question approach

When you have multiple questions, ask them **one at a time** with progress indicators:

- Show progress: "Question 1 of 4" (or percentage if many)
- Wait for response before moving to next question
- Never present long lists of questions for bulk feedback

### Step-by-step project work

When tackling multi-step projects:

1. Show a bullet list of all steps upfront
2. Work through steps **one at a time**, presenting each for review before the next
3. Never dump all work at once requiring feedback on everything
