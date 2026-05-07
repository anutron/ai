## Plannotator CLI hygiene

When invoking `plannotator annotate` (or any plannotator command), **always redirect stdout to a file with `>`**. Never pipe through `tail`, `head`, `grep`, or any other truncating filter.

Plannotator emits submitted annotations to **stdout only**. There is no on-disk log of submitted feedback — drafts at `~/.plannotator/drafts/<hash>.json` are in-progress buffers that get cleared on submit, and session metadata at `~/.plannotator/sessions/<pid>.json` only contains port/mode/label, not annotations.

If stdout is truncated or lost, the user's submitted annotations are unrecoverable — they can't be retrieved from disk and would have to be re-typed from scratch.

**Required pattern for background invocation:**

```bash
OUT=/path/to/.annotations.txt
rm -f "$OUT"
plannotator annotate <file-or-folder> > "$OUT" 2>&1
```

Then `Read` the full file when the user submits. Never `| tail -N` even for "preview" — there's no preview use case that justifies the risk of dropping real submissions.

**Other plannotator notes:**

- Plannotator can run multiple sessions concurrently on different ports (e.g., `plannotator review <pr-url>` and `plannotator annotate <folder>` are separate sessions with similar UIs but different content). Confirm port + content before assuming a session is the right one.
- `plannotator sessions` lists active sessions. `plannotator last` opens the most recent.
- The `--json` flag emits a structured decision object (`{ decision, feedback }`) — useful for hook integration; pairs with `--gate` for the three-button UX.
