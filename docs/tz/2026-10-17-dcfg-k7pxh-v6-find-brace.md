# TZ dcfg-k7pxh v6 — root cause: find -exec replaces {} inside the jq program

Base TZs v1–v5 apply. Do not edit bin/agent-errors-baseline-test.

FILE: bin/agent-errors-baseline

Check: bin/agent-errors-baseline-test

## Root cause (FACT, v5 Check output)
`find ... -exec jq -R -r -n --arg f {} "$ANOMPROG" {} \;` — find replaces EVERY `{}` in every argument, including the empty-object literals inside ANOMPROG:
```
( {s: $s, rows: [], sk: 0, fbn: 0, hp: false, zt: 0, tu: 0, lt: null, ids: /tmp/aeb-anom-XRaE0H/d1.jsonl, rc: /tmp/aeb-anom-XRaE0H/d1.jsonl, dc: /tmp/aeb-anom-XRaE0H/d1.jsonl};
jq: 5 compile errors
```

## U1 — fix
Do not pass the jq program through `find -exec`. Collect the file list with find (`-print0`), then loop `while IFS= read -r -d '' f; do jq -R -r -n --arg f "$f" "$ANOMPROG" "$f"; done` (or xargs -0 with the program in a variable not touched by substitution). Keep stderr visible, keep script rc 0, keep `--session` without `-mtime`. Also fix the jq error at program line 36 (`unexpected ')'`) if it remains after the brace fix. Weekly path unchanged.
