# TZ dcfg-j7b9m — csb-check: evals schema per spec:095 FR-17

## U1 — relax `valid_evals`, keep R4–R8 checks
Worktree: /root/workspaces/tools/.worktrees/claude/dcfg-j7b9m (branch claude/dcfg-j7b9m-csb-check-real). Recon — repowise; index: repowise/CBM checked, missing → `tools/bin/code-memory-enable`.

Defect (fact): `bin/csb-check:22-26` requires `.evals | length == 4` and every eval's assertions to be exactly R4–R8.
The live csb `evals.json` (projects `.claude/skills/csb/evals/evals.json`) has 9 evals: T-A, T-B, T-C, T-G with R4–R8 and
c92fe941, 707d9523, 220f6db3, a87b856f, 887fb01a with P1–P10 + R8. Result: `csb-check T-A <transcript> --evals <that file>` → exit 64.

Change (only `bin/csb-check` and `bin/csb-check-test`):
1. Schema: `.evals` is an array with length >= 1; every eval keeps the current polygon/sandbox checks; `.assertions` length >= 1 and every `.id` matches `^[RP][0-9]+$`.
2. Assertions of the selected eval that this checker does not implement (anything other than R4–R8) print one line `<id>: INCOMPLETE (нет проверки)` and make the verdict at best INCOMPLETE (rc 2). Implemented R4–R8 logic stays unchanged.
3. Malformed evals file (not an object, empty evals, bad id) still exits 64.
4. Add cases to `bin/csb-check-test`: (a) 9-eval file like the live one → T-A no longer exits 64; (b) eval with P1 → line `P1: INCOMPLETE (нет проверки)`; (c) empty `.evals` → 64.

Principles: KISS, YAGNI, fail fast; minimal diff; no new files, no dependencies.
Forbidden: rm -rf, git commit/push, editing outside the worktree, secrets, `~/.ssh`, `/etc`.

Acceptance:
1) `bin/csb-check-test` exits 0.
2) `bin/csb-check T-A /root/.claude/projects/-root-workspaces-projects/ac1916fd-bac4-4df2-80ec-d7fde3d20d90.jsonl --evals /root/workspaces/projects/.worktrees/claude/dcfg-y1m04.3/.claude/skills/csb/evals/evals.json --no-journal` exits with a code other than 64.

Sources: spec:095 FR-17 (bd dcfg-yxfd9 note copied in dcfg-j7b9m): «схема evals — длина >=1; у выбранного eval assertions >=1 с id ^[RP][0-9]+$; assertion без проверки → '<id>: INCOMPLETE (нет проверки)'».
