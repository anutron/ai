---
name: kickoff
description: "Use when starting a brand new project from scratch -- runs discovery, picks a tech stack tier, then hands off to brainstorm and build. Guides non-technical and technical users alike."
user-invocable: true
---

# Kickoff: New Project from Zero

Take a user from "I have an idea" to a running first version. Three phases: discover the problem, pick the right stack, then hand off to `/brainstorm` for design, planning, and build.

## Arguments

- `$ARGUMENTS` - Optional: short description of the project idea

## Context

- Stack spectrum: !`head -30 docs/stack-spectrum.md 2>/dev/null | head -30`
- Date: !`date +%Y-%m-%d`

---

## Phase 1: Discovery

A focused conversation to understand the problem space, the user, and the constraints. This is not a full `/interview` -- it is 5-8 questions, asked one at a time, tailored to a new project.

### Step 1: Seed the conversation

If `$ARGUMENTS` is provided, acknowledge it but do not treat it as a solution. The user often leads with what they want to build. Your job is to pull back to WHY before letting them describe WHAT.

If `$ARGUMENTS` describes a solution ("I want to build an app that..."):

> "Got it -- before we get into the shape of the thing, I want to understand the problem it solves. Tell me: what is not working today? What is the pain, the gap, the thing that is not getting done?"

If `$ARGUMENTS` describes a problem ("I need a way to..."):

> "Good, that gives me a starting point. Let me dig into this a bit before we start designing anything."

If no arguments:

> "Tell me about the problem you are trying to solve. Not the solution yet -- just the pain point, the gap, or the thing that is not working today."

### Step 2: Context extraction

The goal of this phase is to build deep understanding of the problem BEFORE solutions enter the conversation. Ask these one at a time. Skip any the user already covered.

**Keep pushing away from solutions.** If the user jumps to "so I want an app that does X," redirect: "Hold that thought -- I want to make sure I fully understand the problem before we start solutioning. A few more questions."

1. **What is the pain?** -- "What is not working today? What happens when this problem goes unsolved?"
2. **Who feels the pain?** -- "Who runs into this problem? Just you, a team, customers?" (This is the single biggest stack decision driver.)
3. **What does success look like?** -- "If this were solved perfectly, what would be different? What would you be able to do that you cannot do now?"
4. **What have you tried?** -- "Have you tried solving this with existing tools, spreadsheets, manual processes? What worked and what did not?"
5. **How do they work today?** -- "Walk me through the current workflow. Where does it break down?" (Skip if already covered.)

### Step 3: Technical experience

Assess the user's comfort level. Ask directly but without condescension:

> "Quick question so I calibrate the right approach: how much experience do you have building software? Pick the closest:"
>
> 1. **None** -- I have ideas but I have never written code
> 2. **Some** -- I can read code and make small changes, or I have built simple things before
> 3. **Comfortable** -- I build software regularly but I am not an expert in all areas
> 4. **Expert** -- I know exactly what I want technically, just help me execute

Store this internally. It affects stack recommendation and the level of detail in explanations.

### Step 4: Constraints

Ask about anything not yet covered, one at a time:

- **Data**: "Does this need to store data? If so, does the data need to be accessible from multiple devices or shared with others?"
- **Timeline**: "Is there a deadline or is this open-ended?"
- **Existing systems**: "Does this need to talk to any existing tools or services?"

Skip questions that are already answered. Do not ask more than 2-3 constraint questions total.

### Step 5: Summarize understanding

Present a concise summary:

> "Here is what I understand:
> - **Goal:** [what they want to build]
> - **Users:** [who uses it]
> - **Data:** [persistence needs]
> - **Experience:** [their level]
> - **Constraints:** [timeline, integrations, etc.]
>
> Sound right?"

Wait for confirmation before proceeding.

---

## Phase 2: Stack Selection

Read the full stack spectrum document at `docs/stack-spectrum.md`. Use it to make a recommendation.

### The bias ladder

Default to the simplest tier that works. The user must push you upward, not the other way around.

**Lightweight** -- for prototypes, proofs of concept, and getting ideas into a visual form quickly. Good for validating whether something is worth building for real. Ask: "Is the goal to explore an idea or to build something you will use regularly?" If exploring, lightweight. If using, personal.

**Personal** (default for most projects) -- if the app needs a database and a real UI, but only one person uses it. This is the most likely starting point for anything that delivers real, ongoing value.

**Distributed** -- if data needs to be shared across devices or with a small group. Same as personal but with Supabase instead of local MySQL.

**Deployable** -- the highest bar. Only recommend this if ALL of these are true:
- Other people will use it over the internet
- The user has **comfortable** or **expert** technical experience AND the support infrastructure to maintain a public service (or explicit organizational backing)
- The app genuinely requires auth, CI/CD, and production infrastructure

Putting something on the internet is dangerous. Proactively surface the risks:

> "Before we go here, I want to be direct about what deploying to the internet means:
>
> - **Security liability** -- public apps are attack surfaces. SQL injection, XSS, auth bypass, data leaks. You are responsible for patching vulnerabilities promptly.
> - **Uptime responsibility** -- if people depend on it, downtime is your problem. Monitoring, alerting, incident response.
> - **Data protection** -- user data means legal obligations (privacy laws, breach notification).
> - **Ongoing maintenance** -- dependencies rot, APIs change, certificates expire. A deployed app is never done.
>
> Do you have the expertise and support to handle all of that? If not, a personal or distributed app gives you 90% of the value with none of the risk."

If the user has **none** or **some** technical experience, push back firmly:

> "I would strongly recommend starting with [personal/distributed] instead. You will get a working version faster and avoid taking on security and maintenance obligations you are not ready for. If you outgrow it, the jump to deployable is a rebuild -- but by then you will have the experience to do it right."

If they insist after two pushbacks, respect the choice -- but note in the discovery summary that the user was advised of the risks and chose to proceed.

### Present the recommendation

> "Based on what you've told me, I recommend the **[tier name]** stack:
>
> [2-3 sentences about what that means practically -- what technologies, how it runs, what the experience will be like]
>
> [If relevant: why NOT the tier above -- what they would gain vs. what complexity it adds]
>
> Want to go with this, or do you have a reason to go bigger/smaller?"

Wait for agreement. If the user wants a different tier, discuss it -- but maintain the bias toward simplicity.

---

## Phase 3: Brainstorm Handoff

Once the problem and stack are agreed, hand off to `/brainstorm`. Write a handoff summary first.

### Step 1: Write discovery summary

Save to `specs/docs/<date>-<topic>/discovery.md`:

```markdown
# Discovery: <Project Name>

**Date:** <today>
**Stack tier:** <chosen tier> (from docs/stack-spectrum.md)

## Problem
<What the user wants to build and why>

## Users
<Who uses it, how they access it>

## Data
<What gets stored, where, sharing requirements>

## Constraints
<Timeline, integrations, technical experience level>

## Stack Decision
<Why this tier was chosen, any pushback or discussion>
```

Commit immediately.

### Step 2: Invoke brainstorm

Invoke `/brainstorm` with a reference to the discovery doc. The brainstorm will:
1. Read the discovery doc for context (it checks for interview artifacts)
2. Design the solution within the chosen stack tier
3. Write a spec doc
4. Create an implementation plan
5. Offer to execute

When invoking brainstorm, include the project idea and a note about the stack:

> `/brainstorm <project description> -- discovery doc at specs/docs/<date>-<topic>/discovery.md, stack tier is <tier>`

---

## Interaction Rules

1. **One question at a time.** Never present a wall of questions.
2. **Skip what you already know.** If the user's initial description answers a question, do not re-ask it.
3. **Be warm but direct.** This is often a user's first interaction building something. Make it feel collaborative, not like a form.
4. **Bias toward action.** The discovery phase should be 5-10 minutes of conversation, not an hour. Get enough to make good decisions, then move.
5. **Respect expertise.** If the user is an expert, do not over-explain. If they are new, explain more and check understanding.
6. **Protect non-technical users.** The deployable tier is genuinely dangerous for someone who cannot maintain it. Lightweight and personal apps are safe, useful, and do not expose anyone to security risk.

---

## Resuming a Kickoff

If a discovery doc exists at `specs/docs/**/discovery.md` but no brainstorm doc exists alongside it:

1. Read the discovery doc
2. Present a summary of where things left off
3. Ask if they want to continue to brainstorm or revisit the discovery
