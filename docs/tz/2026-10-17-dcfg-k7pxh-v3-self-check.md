# TZ dcfg-k7pxh v3 — anomaly mode, self-verifying run

Base TZ: docs/tz/2026-10-17-dcfg-k7pxh-anomaly-log.md and v2 docs/tz/2026-10-17-dcfg-k7pxh-v2-anomaly-fix.md (all rules apply). The fixtures in bin/agent-errors-baseline-test are final: do not edit that file; make bin/agent-errors-baseline pass them.

FILE: bin/agent-errors-baseline

Check: bin/agent-errors-baseline-test

## U1
Fix bin/agent-errors-baseline so that the self-test passes and `--anomalies --session a8fd1d9d` finds the real file `/root/.claude/projects/-root-workspaces-projects/a8fd1d9d-bf27-4ca4-92c1-edb1bb959809.jsonl` (transcripts are one directory below the corpus root). Weekly path without `--anomalies` unchanged.
