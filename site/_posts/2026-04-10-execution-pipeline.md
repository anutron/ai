---
layout: post
title:  "From design to execution, as a pipeline"
author: aaron
categories: [ Recipes, Claude Code ]
image: assets/images/airon/recipe2_execution-pipeline-assembly.png
---

Most of the work I do with Claude Code follows the same shape: a fuzzy idea becomes a spec, the spec becomes a plan, the plan becomes code, the code gets reviewed.

That sequence is a **pipeline**, not a conversation. Treating it as a pipeline means each stage has an owner, an input, an output, and a definition of done — even when "the owner" is me and "the input" is a vague feeling I had in the shower.

## The four stages I keep coming back to

1. **Brainstorm** — get the intent on paper, fast and messy
2. **Spec** — formalize what the change IS, with enough teeth that tests can be written from it
3. **Plan** — break the spec into ordered work, with dependencies and risks called out
4. **Execute** — write the code, run the tests, commit

Each stage has a Claude Code skill behind it (`brainstorm`, `spec-writer`, plan generation in `brainstorm`, `execute-plan`), and each one hands off to the next with a written artifact in between.

The friction-removing trick: never let a stage start without its predecessor's artifact existing on disk. No spec, no plan. No plan, no code. The artifacts are the handoff protocol.
