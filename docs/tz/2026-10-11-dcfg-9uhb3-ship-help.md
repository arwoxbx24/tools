TZ dcfg-9uhb3 U1 — ship: --help exits 0, preflight refusal names the expected worktree root

Source: /root/workspaces/projects/docs/tz/2026-10-11-ship-post-submit-defects.md (ADR-S1, ADR-S4, Atoms B); bd dcfg-9uhb3, dcfg-z73k1.3.
Files allowed: bin/ship, bin/ship-test.d/u23-help.sh (new), docs/ship-post-ARCHITECTURE.md (one line in section 5 only). Nothing else.
Scratch only in /tmp. No git add/commit/push, no bd writes, no pm2, no network, no secrets. At most ~40 changed lines. Keep the existing style.

## Changes in bin/ship
1. `-h|--help` anywhere in the argument loop (before `-*) usage`, line ~39): print the same usage text to STDOUT and exit 0 immediately,
   before any log write, git or gh call. `usage` for real errors stays stderr + exit 10.
2. Preflight refusal at line ~48 (`[[ $wtr == "$root"/* ]] || leave 10 preflight`): before leaving, print to stderr
   `ship: worktree <wtr> outside <root>; use <root>/<agent>/<atom> or set GA_WT_ROOT` (exact variable names as in the file).
   Exit code stays 10.

## Test bin/ship-test.d/u23-help.sh
Same style as bin/ship-test.d/u2-policy.sh (sourced by bin/ship-test; helpers p, f, ship, mkrepo, mkwt available).
- u23-1: `out=$(ship --help 2>/dev/null); rc=$?` -> rc 0 and out contains `usage`.
- u23-2: a worktree path outside the worktree root (e.g. a plain `git worktree add` under $d/outside) -> rc 10 and stderr contains `GA_WT_ROOT`.

## docs/ship-post-ARCHITECTURE.md
In section 5 table row `ship | 10`, append to the meaning: `; --help exits 0; preflight names the expected worktree root`.

## Done-check (paste last lines)
SHIP_TEST_ONLY=u23 bash bin/ship-test   -> both u23-1 and u23-2 PASS, no FAIL
bash bin/ship-doc-check                  -> rc 0 (if it needs a base, run as CI does; report the command used)
