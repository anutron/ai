---
name: eli5
description: Restate your prior response in plain, non-technical language and orient the user around the decision they need to make. Use when the user types /eli5 or asks to have something explained simply.
user_invocable: true
tags: [personal]
---

# ELI5

Re-explain your most recent substantive response in plain English. Strip the jargon, surface the choice, and make a recommendation.

## Instructions

1. **Identify the prior response.** Look at your last substantive assistant turn (skip trivial acknowledgements). That is the content to translate. If the prior turn was itself an ELI5 or there's nothing meaningful to restate, say so and ask the user what they'd like explained.

2. **Translate, don't summarize.** Rewrite the content so a smart non-technical reader can follow it. Replace acronyms, library names, and code references with everyday analogies or plain descriptions. Do not add new information the prior response didn't contain — if a tradeoff wasn't discussed, don't invent one.

3. **Structure the answer with these four sections, in this order.** Use the exact headings below. Keep each section tight — bullets over paragraphs.

   ### The decision

   One or two sentences naming the choice the user is being asked to make. Frame it as a question they need to answer.

   ### Your options

   A bullet list of the available options. One short sentence per option, in plain language. If the prior response only presented one path, say that explicitly and note what alternatives exist (or that no real alternative was offered).

   ### Tradeoffs

   For each option, the main upside and the main downside in plain terms. A short table is fine if it fits; otherwise nested bullets.

   ### My recommendation

   Pick one. State it directly. Give the one-line reason. If the recommendation depends on something the user knows but you don't, name that condition.

4. **Tone.** Conversational, confident, no hedging. No emojis unless the user has used them. No code blocks unless the original choice is literally about syntax. Sentence case for headings (already set above).

5. **Length.** Aim for under 250 words total. If the prior response was a one-liner, the ELI5 can be even shorter — don't pad.

## When to use

- User types `/eli5`
- User says "explain that simply," "in plain English," "ELI5," or similar
- User seems lost after a technical explanation and you want to reset the conversation around the actual decision

## When NOT to use

- The prior response was already plain-language with a clear recommendation — just answer the user's follow-up directly
- The user is asking a new question, not asking you to restate the old answer
