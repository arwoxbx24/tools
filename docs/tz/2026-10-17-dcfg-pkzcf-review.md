# TZ dcfg-pkzcf U2 — independent review of merged PR #324 #325 #326 (read-only)

Atom: dcfg-pkzcf. Review only; write nothing.
Scope: the changes between git commits d76a0a4 and e8f8fd9 in this repository, files `bin/sdk-agent`, `bin/sdk-agent-test`, `bin/goal-guard`, `bin/goal-guard-test`, `hooks/statusline-segment.sh`, `hooks/statusline-segment-test.sh`. The working tree is at e8f8fd9 (after the changes). Intent: TZ files `docs/tz/2026-10-17-dcfg-tlnxh-dead-reservations.md`, `docs/tz/2026-10-17-dcfg-aw1i7.2-guard-statusline.md`, `docs/tz/2026-10-17-dcfg-aw1i7.3-cap7.md`.

## Check
1. Correctness vs each TZ: dead-reservation fold (exactly once, under the lock, cost from .out or budget as upper bound), orphan engine keeps its reservation, `cap --json` writes nothing, `check_daily_cap` math, DAILY_CAP 7.00 in the non-test path.
2. Money safety: any path where a real spend is not counted, or a live run's reservation is dropped.
3. Concurrency: races between two wrappers folding the same entry; lock fd inheritance; files left behind on error/kill.
4. goal-guard: blocks with open atom when background_tasks is []; passes when field is absent or non-empty.
5. statusline: seg_sdk prints nothing on cap error; `ctx ↻ compacted` only when current_usage is null.
6. Tests: any weakened or deleted assertion.

## Output
A list, one line per finding: `<file>:<line> <CRITICAL|HIGH|MEDIUM|LOW> <problem> — <evidence>`; then a last line `findings: N (critical C, high H)`. No findings → `findings: 0`. Do not guess: cite the line.
