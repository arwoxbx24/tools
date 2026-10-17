# TZ dcfg-pkzcf U1 — sdk-agent-test prints a final PASS line

Atom: dcfg-pkzcf · discovered from epic dcfg-aw1i7 (goal AC1: "last line is PASS").
FILE: bin/sdk-agent-test
FILE: docs/tz/2026-10-17-dcfg-pkzcf-final-pass.md
FILE: docs/tz/2026-10-17-dcfg-pkzcf-review.md (read-only review TZ, the hand does not edit it)

## Fact
`bin/sdk-agent-test` ends with `echo "ok $pass/$total"` (line 356), so its last line is `ok 40/40`, never PASS. Sibling suite `bin/goal-guard-test` ends with `PASS all`.

## Required
Add only (do not delete or change any existing line): after the existing `echo "ok $pass/$total"` line, add lines so that when `pass == total` the suite prints `PASS all` as its last line and exits 0; when not, it prints `FAIL: $pass/$total` and exits 1 (keep whatever exit behaviour the existing lines already have if they exit earlier). Nothing else.
Разведка — repowise / grep -n; edit only the FILE paths above. No secrets in output.

## Done-check (lead)
`bash bin/sdk-agent-test` → contains `PASS dead_pid_reservation_not_counted`, last line `PASS all`; `git diff origin/main --numstat -- bin/sdk-agent-test` → deleted 0.
