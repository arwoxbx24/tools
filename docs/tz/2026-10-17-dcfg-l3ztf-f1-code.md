# TZ dcfg-l3ztf U2 — F1 rule fix + registry row

Base: docs/tz/2026-10-17-dcfg-l3ztf-f1-noise.md (the test already has the failing fixtures f1n and f1g). Do not edit bin/agent-errors-baseline-test.

FILE: bin/agent-errors-baseline
FILE: TOOLS-REGISTRY.md

Check: bin/agent-errors-baseline-test

## U2a — F1 rule (bin/agent-errors-baseline:71, inside ANOMPROG)
Today: `if .tu == 0 and .lt != null and (.lt.t | contains("DONE")) then ... F1 ...`.
New: F1 fires only when the last text contains `DONE` AND does not contain `NOT DONE` AND does not contain `/goal`. Change only that condition; nothing else in the script.

## U2b — TOOLS-REGISTRY.md line 21 (row `agent-errors-baseline`)
In the "how to call" cell, after the existing `bin/agent-errors-baseline --days N --corpus DIR` text, add: `; аномалии: bin/agent-errors-baseline --anomalies [--session ID] [--days N] — строка на поломку (S1 S2 R1 D1 F1) + итог`. Keep the rest of the row and the table format unchanged.

Rules: least code; no refactors; weekly mode unchanged.
