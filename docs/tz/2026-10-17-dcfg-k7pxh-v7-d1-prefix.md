# TZ dcfg-k7pxh v7 — D1 must use the same denial definition as weekly mode

Base TZs v1–v6 apply. Do not edit bin/agent-errors-baseline-test.

FILE: bin/agent-errors-baseline

Check: bin/agent-errors-baseline-test

## Defect (review 17.10, verified by reading)
bin/agent-errors-baseline:104 — anomaly class D1 counts any error tool_result whose content contains `has been denied`. Weekly mode (:161) counts a denial only when the content matches `^\s*Permission to use ` (and `has been denied`). Failing input: `is_error:true` tool_result with content `sandbox policy: write to /etc has been denied` → counted as D1, not a permission denial.

## U1 — fix
In the ANOMPROG D1 branch (around :104), require the same prefix test as weekly mode: content matches `^\s*Permission to use ` AND contains `has been denied`. Change nothing else; weekly path unchanged.
