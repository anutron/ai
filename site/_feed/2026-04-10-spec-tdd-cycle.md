---
date: 2026-04-10 16:45:00
title: "Spec → Test → Implement is non-negotiable"
image: /assets/images/airon/spec-tdd-cycle.png
---

If you write code first and the spec second, the spec is documentation, not a contract.

The order matters: spec → test → implement. The spec is the source of truth, the test enforces it, the code makes the test pass. Without that order, agents drift away from intent and you end up with code that "works" but doesn't do what you wanted.
