---
tags: [spec]
audience: [shared]
---
## Spec-driven development (OpenSpec)

**Opt-in per project via the `openspec/` directory.** Projects with an `openspec/` directory at their root use spec-driven development. Projects without one do not.

**Detection:** `test -d openspec` – zero-cost, no file snooping.

**Recommendation:** If the user creates a new application or asks to create/modify code in a project that lacks an `openspec/` directory, recommend running `openspec init` (or `/migrate-to-openspec` if a legacy `.specs` system is present).

### The process (spec-first, non-negotiable)

OpenSpec organises work as **changes**. Each change is a folder under `openspec/changes/<name>/` containing a proposal, design notes, tasks (the implementation plan), and delta specs that describe how base capabilities change.

1. **Create the change first** – `openspec new change <name>`. Write `proposal.md`, `design.md`, `tasks.md`, and the relevant delta specs at `openspec/changes/<name>/specs/<capability>/spec.md` before any code is written.
2. **Show the change to the user** for approval on new features (MUST WAIT for approval).
3. **Write tests** from the deltas (when testable).
4. **Implement** – Write code to pass the tests, working through `tasks.md`.
5. **Show results and commit** – Deltas, tests, and code travel together in the commit.
6. **Archive when done** – `openspec archive <name>` merges the deltas into the base specs at `openspec/specs/<capability>/spec.md` and cleans up the change folder.

**NEVER derive specs from code.** If you wrote code first and deltas second, the spec is documentation, not a contract. The order matters: change folder -> deltas -> tests -> implement -> archive.

**On every behavioral change the user requests: update the active change's deltas on the same turn.**

- The base specs at `openspec/specs/<capability>/spec.md` are the source of truth – if specs and code drift, the code needs updating.
- In-flight deltas at `openspec/changes/<name>/specs/<capability>/spec.md` describe the change's future state. Update them as requirements arrive; don't batch.

### Spec reporting

After committing, always report spec status:

- `Specs: Updated (openspec/changes/<name>/specs/<cap>/spec.md)` – delta changes included
- `Specs: No behavioral changes` – config/docs/cosmetic only
- `Specs: Skipped (no openspec/ dir)` – project doesn't use OpenSpec
- `Specs: Missing` – behavioral changes without delta updates

### Writing OpenSpec artifacts

Always use `/spec-writer` to produce OpenSpec text. It wraps `openspec instructions <artifact>` (proposal/design/tasks/specs) and returns enriched templates with project context. Do not write artifact sections by hand – invoke the skill.

### Key principles

- The base specs are the source of truth – if it's not in the specs, it doesn't exist.
- Tests validate spec compliance.
- Specs evolve with the code – always keep them updated.
- `openspec validate --all --strict` should pass at every commit boundary.
