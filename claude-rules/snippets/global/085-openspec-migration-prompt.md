---
tags: [spec]
audience: [aaron]
---
## OpenSpec migration prompt

If a project has legacy AI-RON specs (`.specs` file or top-level `specs/*.md`) but no `openspec/` directory, suggest `/migrate-to-openspec` when the user asks for spec work. Migration is one-time, 1-5 minutes, preserves originals at `.workflow/legacy-specs/`.

Skip if the user opted out via the `legacy-spec-system` tag.
