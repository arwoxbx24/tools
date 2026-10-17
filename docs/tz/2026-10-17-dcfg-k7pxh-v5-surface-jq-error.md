# TZ dcfg-k7pxh v5 — surface the hidden jq error, then fix it

Base TZs v1–v4 apply. Diagnosis v4 (sdk-agent read, 17.10): the anomaly jq program fails and its error is hidden by `2>/dev/null || true` at bin/agent-errors-baseline:113; fixture and filter logic traced as correct.

FILE: bin/agent-errors-baseline

Check: bin/agent-errors-baseline-test

## U1
1. At bin/agent-errors-baseline:113 stop discarding jq stderr: let it reach stderr (keep rc 0 of the script, e.g. keep `|| true` but drop `2>/dev/null`).
2. Read the ANOMPROG jq program (bin/agent-errors-baseline:59-111) against jq 1.x semantics and fix the defect that makes it fail (common causes: a `def` after use, `$__loc__`, `input`/`inputs` with `-n` and `-R` together, `limit`/`reduce` syntax, string slicing on null, `tostring` on objects). The self-test (Check) must pass.
3. For `--session`, do not apply the `-mtime` filter (session lookup must work for older files); weekly path unchanged.
Do not edit bin/agent-errors-baseline-test.
