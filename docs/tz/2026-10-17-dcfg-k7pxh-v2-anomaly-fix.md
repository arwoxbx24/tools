# TZ dcfg-k7pxh v2 — anomaly mode fails acceptance (fix)

Base TZ: docs/tz/2026-10-17-dcfg-k7pxh-anomaly-log.md (unchanged, all its rules apply). The v1 edit is present in the worktree; fix it.

FILE: bin/agent-errors-baseline
FILE: bin/agent-errors-baseline-test

## U1 — acceptance failures (FACT, lead runs 17.10)
1. Self-test: `bin/agent-errors-baseline-test` →
   `FAIL: expected [^s1	3	S1	Stop hook feedback: second$]` and `anomalies=0 S1=0 S2=0 R1=0 D1=0 F1=0 skipped_lines=0`.
   S1 is not detected on its own fixture. Find why the Stop hook feedback record (`.type=="user"`, string `.message.content` starting with `Stop hook feedback:`) is not matched and fix it; same check for S2, R1, D1, F1 fixtures.
2. Real corpus: `bin/agent-errors-baseline --anomalies --session a8fd1d9d` (with and without `--corpus /root/.claude/projects`) → `no transcript for a8fd1d9d`.
   The real file is `/root/.claude/projects/-root-workspaces-projects/a8fd1d9d-bf27-4ca4-92c1-edb1bb959809.jsonl`: transcripts sit one directory level below the corpus root. Session selection must find files at any depth under the corpus whose basename starts with ID, using the same file list the weekly path already builds (reuse, no second scanner).

## Done when (lead checks)
- self-test passes;
- `--anomalies --session a8fd1d9d` prints ≥1 S1 row (that session has consecutive "Stop hook feedback:" records);
- the weekly path output is unchanged.

Forbidden: same list as the base TZ.
