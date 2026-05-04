## OpenSpec migration prompt

If you encounter a project with the legacy AI-RON spec system (a `.specs` file or top-level `specs/*.md` files **without** an `openspec/` directory) and the user asks for spec-related work, suggest running `/migrate-to-openspec` first. The migration is one-time, parallelized, typically 1-5 minutes, and preserves originals at `.workflow/legacy-specs/`.

Don't nag if the user has explicitly opted to keep the legacy system on a particular project – the global tag `legacy-spec-system` exists for that case.
