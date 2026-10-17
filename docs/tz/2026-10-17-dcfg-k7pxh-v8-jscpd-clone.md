# TZ dcfg-k7pxh v8 — CI red: jscpd new clone inside agent-errors-baseline

Base TZs v1–v7 apply. Do not edit bin/agent-errors-baseline-test.

FILE: bin/agent-errors-baseline

Check: bin/agent-errors-baseline-test

## Defect (FACT, CI run 39055861558 on 980fff5, PR #318)
```
Clone found (bash) [NEW]
 - agent-errors-baseline [59:9 - 64:4] (6 lines, 59 tokens)
   agent-errors-baseline [126:7 - 131:7]
ERROR: jscpd found 1 new clones not in the baseline (allowed: 0)
```
CI step: `npx --yes jscpd@5.4.1 --baseline-from-ref origin/main --fail-on-new-clones=0 bin scripts`. Lines 126–131 existed on main (weekly path); lines 59–64 are the new anomaly code repeating them.

## U1 — fix (DRY)
Remove the duplication: define the repeated fragment once (e.g. a shell variable holding the shared jq text, or a jq `def` shared by both programs) and use it in both the anomaly program and the weekly program, so no run of 6+ identical lines with 50+ tokens remains between 59–64 and 126–131. Behavior of both modes must not change: weekly output identical, anomaly rows identical. Least code; no other edits.
