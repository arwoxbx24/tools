# TZ dcfg-k7pxh v4 — read-only diagnosis (5 Whys)

FILE: bin/agent-errors-baseline
FILE: bin/agent-errors-baseline-test

Three code runs failed the same check. Do not edit anything. Read both files and answer.

Failing output of `bin/agent-errors-baseline-test` (FACT):
```
FAIL: expected [^s1	3	S1	Stop hook feedback: second$]
anomalies=0 S1=0 S2=0 R1=0 D1=0 F1=0 skipped_lines=0
```
Also `bin/agent-errors-baseline --anomalies --session a8fd1d9d` prints `no transcript for a8fd1d9d`; the real file is `/root/.claude/projects/-root-workspaces-projects/a8fd1d9d-bf27-4ca4-92c1-edb1bb959809.jsonl`.

Answer, short:
1. 5 Whys for "S1=0 on the s1 fixture": trace the fixture lines through the code (file selection, jq filter, awk state) and name the exact line(s) where the record is lost, with file:line.
2. Is the fixture itself valid against the TZ record shapes (`.type=="user"`, string `.message.content` starting `Stop hook feedback:`)? Quote it.
3. Why the session file is not found: file:line of the selection and what it does.
4. The minimal exact fix (old → new text) for each cause.
