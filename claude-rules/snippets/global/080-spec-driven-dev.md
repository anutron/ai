---
tags: [spec]
audience: [shared]
---
## Spec-driven development (OpenSpec)

**Opt-in per project via the `openspec/` directory.**

**Detection:** `test -d openspec` – zero-cost.

**Recommendation:** If the user creates a new application or asks to create/modify code in a project lacking `openspec/`, recommend `openspec init` (or `/migrate-to-openspec` if a legacy `.specs` system is present).

### The process (spec-first, non-negotiable)

Work is organised as **changes** under `openspec/changes/<name>/` (proposal, design, tasks, delta specs).

1. **Create the change first** – `openspec new change <name>`. Write `proposal.md`, `design.md`, `tasks.md`, and deltas at `openspec/changes/<name>/specs/<capability>/spec.md` before any code.
2. **Get user approval** on new features (MUST WAIT).
3. **Write tests** from the deltas (when testable).
4. **Implement** – Code to pass tests, working through `tasks.md`.
5. **Commit** – Deltas, tests, and code travel together.
6. **Archive** – `openspec archive <name>` merges deltas into base specs at `openspec/specs/<capability>/spec.md`.

**NEVER derive specs from code.** Order matters: change folder -> deltas -> tests -> implement -> archive.

**On every behavioral change the user requests: update the active change's deltas on the same turn.**

- Base specs (`openspec/specs/<capability>/spec.md`) are the source of truth – if specs and code drift, fix the code.
- In-flight deltas (`openspec/changes/<name>/specs/<capability>/spec.md`) describe the change's future state. Update as requirements arrive; don't batch.

### Spec reporting

After committing, report status:

- `Specs: Updated (openspec/changes/<name>/specs/<cap>/spec.md)` – deltas included
- `Specs: No behavioral changes` – config/docs/cosmetic
- `Specs: Skipped (no openspec/ dir)`
- `Specs: Missing` – behavioral changes without delta updates

### Writing OpenSpec artifacts

Always use `/spec-writer` (wraps `openspec instructions <artifact>`). Do not write artifact sections by hand.

### Commit boundary

`openspec validate --all --strict` should pass at every commit.
