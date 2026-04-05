## Spec Review via Plannotator

**When `/brainstorm` is NOT driving** (e.g., standalone spec edits or spec files written outside the brainstorming flow), use Plannotator for spec review:

1. Write the spec file (do NOT commit yet)
2. Invoke `/plannotator-specs` — this opens Plannotator in the browser for inline annotation
3. Address annotations: if the user leaves a **question**, immediately rewrite the relevant section to answer it and re-open in Plannotator — don't discuss in the terminal unless the annotation explicitly says "discuss w/ me before rewriting the plan"
4. Re-open in Plannotator for verification
5. Loop until the user approves (submits with no annotations)
6. Only then proceed to the next step (commit, implementation planning, etc.)

**Why Plannotator:** It provides inline annotation — the user can leave targeted comments directly on sections, which is faster and more precise than reviewing a raw markdown file in the terminal.

**This applies to (when not using `/brainstorm`):**
- Brainstorming spec documents
- SPEC files in `.specs`-enabled projects (`specs/`)
- Any design document that needs user approval before proceeding
