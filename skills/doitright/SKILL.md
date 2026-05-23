---
name: doitright
description: Pick the long-term-correct option from the choices you just presented. Use when the user types /doitright in response to a multi-option recommendation, meaning "go with the proper long-term fix unless there's a real downside beyond effort."
user_invocable: true
tags: [personal]
---

# Do it right

The user invoked this in response to a list of options you presented (typically shortcut / defer / proper long-term variants). They're invoking the principle: **"If it's worth doing at all, it's worth doing right."**

Translation: pick the long-term-correct option unless there's a real downside beyond effort.

## Instructions

1. **Identify the options you just presented.** Look at your most recent set of options. The "long-term-correct" option is the one that solves the underlying problem properly, not just the immediate symptom. It is usually – but not always – the option labeled "proper," "long-term," or the highest-effort one.

2. **Stress-test before committing.** Before announcing the pick, scan for downsides beyond effort:

   - Does the long-term option risk breaking something else (regressions, blast radius)?
   - Is there a deadline or external constraint that makes "now" matter more than "right"?
   - Does it require knowledge, access, or context the user doesn't have right now?
   - Is it overengineering for a problem that may not actually exist (YAGNI)?
   - Does it depend on an unproven assumption that a shortcut would let us validate cheaply?

   If any of these apply, **surface it before proceeding.** Say something like: "You said /doitright, but I want to flag X first – it's a downside beyond effort. Still want the long-term option, or does that change your read?"

3. **If no real downside, just go.** State the pick in one line, then proceed with the work. No re-litigating the tradeoffs you already presented – the user made the call.

4. **If you presented only one option, or the options are not a defer/shortcut/long-term shape**, say so and ask what they want you to do. Don't invent a "long-term" option that wasn't on the table.

## Tone

Confident, no hedging. The user invoked a shortcut precisely so they wouldn't have to re-explain. Confirm in one line and move.

## Example

You presented:

- Option 1 (Recommended): Defer – add a TODO, wait for a real user to hit it
- Option 2: Quick fix – 10-minute timeout, ~5 min change
- Option 3: Proper fix – streaming upload with progress and configurable deadline, ~30 min + tests

User types: `/doitright`

You respond:

> Going with option 3 – streaming upload with progress and configurable deadline. No downsides beyond the ~30 min of effort and the test surface, both of which you've already signed up for. Starting now.

Then proceed.

## When NOT to use

- The user didn't actually invoke `/doitright` – don't reinterpret other phrases as this skill
- You didn't just present a multi-option list – if there's nothing to "pick," ask what they're referring to
- The long-term option in your list has a real downside beyond effort – flag it instead of silently overriding
