---
layout: post
title:  "Skills as a pegboard, not a toolbox"
author: aaron
categories: [ Recipes, Claude Code ]
image: assets/images/airon/recipe1_skill-organization-pegboard.png
featured: true
---

When I started writing skills for Claude Code, I treated them like a toolbox — throw them in, label them later. That worked for a while, then it didn't.

The shift was thinking of skills as a **pegboard**: each one has a place, you can see the whole set at a glance, and missing tools become obvious because there's an empty hook where they should be.

## What changed in practice

- **Naming is layout, not just labels.** A skill named `pr-respond` belongs near `pr` and `pr-dashboard`. Adjacency makes the set legible.
- **One job per skill.** If a skill does two things, it gets split — even if the two things are usually used together.
- **Composition over swiss-army.** Smaller skills that call each other beat one mega-skill that tries to do everything.

The illustration above is the mental model I've been using: a wall of named hooks, each holding one well-shaped tool, with empty hooks signaling where the next skill should go.

If you want the skills themselves, they're at [github.com/anutron/ai](https://github.com/anutron/ai) under `skills/`.
