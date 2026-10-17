# TZ dcfg-l3ztf U1 — F1 noise: test first

Goal: anomaly class F1 ("claim without evidence") must not fire on honest "NOT DONE" reports or on text that quotes a `/goal` line. FACT (17.10, --days 7 on the real corpus): 74 of 135 F1 rows contained "NOT DONE" or "/goal". Rule today: bin/agent-errors-baseline:71 `(.lt.t | contains("DONE"))`.

FILE: bin/agent-errors-baseline-test

## U1 — add failing fixtures (test-first; do not edit anything else)
In bin/agent-errors-baseline-test, next to the `f1.jsonl` fixture (lines 80–84) and before the `padf` loop (line 90), add two fixtures in the same style:
- `f1n.jsonl`: line 1 `{"type":"user","message":{"content":"go"}}`, line 2 an assistant text record with text `NOT DONE: AC2 failed`.
- `f1g.jsonl`: line 1 the same user "go", line 2 an assistant text record with text `/goal AC1 ... followed by ✅ DONE`.
After the existing `--session n` check (lines 103–104), add in the same style:
- `out=$("$bin" --anomalies --session f1n --corpus "$adir")` and `chk '^anomalies=0 S1=0 S2=0 R1=0 D1=0 F1=0 skipped_lines=0$'`
- the same for `--session f1g`.
Keep line 99 (`all DONE` → F1 row) and line 100 (corpus total `F1=1`) exactly as they are: after the code fix the two new fixtures add no rows, so the total stays 7.
Expected now (before the code fix): the test FAILS. Do not change bin/agent-errors-baseline.
Rules: least code; no other edits; no comments beyond the existing style.
