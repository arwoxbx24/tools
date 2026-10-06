# spec:054 CR — safe disk cleanup and rotation (dcfg-0bj7j)

Owner goal: make the existing scheduled disk cleanup run safely, include proven disposable caches and logs, perform one accepted run, and report measured space. Owner authorized correction of `scripts/disk-rotate.sh` on 2026-10-06. Current session atom is `dcfg-spfss`, projects ledger. Previous `dcfg-0bj7j` is continuity evidence only; never claim, rename, or close it. Work only in this isolated tools worktree. Do not use the tools Beads clone or create another atom.

## Scope and architecture

- Edit `scripts/disk-rotate.sh` and the existing `scripts/tests/disk-rotate-*-selfcheck.sh` only when needed. Keep its existing schedule and backup gate. Use vendor commands for Playwright, journald, logrotate and systemd-tmpfiles. No new dependency, service, timer, wrapper or credentials.
- Protect `/root/.codex`, `/root/.claude`, `/root/workspaces/secrets`, backups, archives, snapshots, active worktrees, projects, Docker volumes and containers. A temporary name does not waive protection. Do not delete unknown `/tmp/.bcd*.so` or Codex upgrade staging until ownership and authorization are established; report them as excluded.
- Preserve the existing root backup gate for any deletion. Never use a bypass mode to obtain a green result. Dry-run must be non-destructive and must never list a protected path as a delete candidate.

## Ordered implementation

1. Fix the `set -u` defects: `handle()` uses `label=$cls` in the same `local` declaration that first assigns `cls`; `GATE_RC` is read at script exit without global initialization. Add the smallest safe initialization/assignment.
2. Make cache enumeration and live action agree. The current dry-run lists all `/tmp/*` older than two days while live uses raw `find ... -exec rm -rf`, bypassing `DENY_LIST`. Replace that raw sweep with the existing vendor `systemd-tmpfiles` cleanup and its configured age/exclusions, or an equally documented safe mechanism with per-target protection and process checks. Do not remove unknown files merely because they are old.
3. Ensure paths under protected trees are excluded from every dry-run candidate list and live deletion. Do not delete project trees nested in cache directories or follow symlinks outside an approved cache root.
4. Keep journald vacuum and existing logrotate integration. Use Playwright's native browser garbage collection on the installed browser set if safe; a dry-run should report the vendor action without downloading or deleting. A native command that cannot safely run should be reported, not replaced with raw directory removal.
5. Add one meaningful regression check for the two unbound variables and the dry/live protected-path alignment. Reuse existing selfchecks.

## Acceptance and rollback

- `bash -n scripts/disk-rotate.sh` exits 0.
- Existing disk-rotate selfchecks pass; any failed assertion is diagnosed and fixed, never suppressed.
- A guarded `GATE_MODE=enforce scripts/disk-rotate.sh --dry-run` exits 0 or a documented gate status without shell errors; captured output has zero protected delete candidates. No live run if this fails.
- For one live run, check backup gate, exact candidates and service health first; then record rc, ledger row, journal, `df -h /` before/after, timers and measured freed space. If a gate blocks deletion, report its exact reason and retain the atom open.
- Rollback: revert the task commit and restore only task-owned configuration; deleted disposable caches are rebuilt by their vendor tools.

## CR after first code-channel attempt — authoritative correction

The first provider attempt timed out after leaving a partial diff. Do **only** these code corrections and return; the coordinator runs tests. Do not start a real cleanup or rerun the long selfchecks inside the provider.

1. Keep the two `set -u` fixes. Remove the duplicate `scenario_1` through `scenario_11` calls accidentally inserted before `scenario_13()` in `scripts/tests/disk-rotate-gate-selfcheck.sh`. Keep exactly one call of each scenario after all definitions. Do not accept `rc=5` as proof that a regression passed.
2. In the `DR_TEST_ONLY=1` top-level branch of `scripts/disk-rotate.sh`, remove the invalid `local` declarations that cause `local: can only be used in a function`. Replace the raw test irreplacable `find` with existing `irrep_candidates`, as documented in the older spec:054 fix2, so repeat-run tests 2/8/10 no longer refix deleted paths.
3. Do **not** route `/tmp/*` to `handle`: `handle` still uses `rm -rf` and can delete unknown libraries, projects or another session. Remove this sweep entirely. The already active `systemd-tmpfiles-clean.timer` with its configured retention and tmux exclusions owns `/tmp`; comment this in the script. Do not alter its configured age or remove unknown `.bcd*.so`.
4. Add exact and descendant deny patterns for `/root/.claude`, `/root/workspaces/projects/.claude`, `/root/workspaces/system/archives`, and `/root/.codex`; preserve secrets/backups/production patterns. Also exclude protected project trees from `__pycache__` and nested cache traversal; easiest safe implementation is to omit those broad scans and leave their data to owning vendor/project mechanisms.
5. The task does not authorize Docker image/build-cache pruning. Remove `docker builder prune` and `docker image prune` from this contour's live path; do not call `cleanup_images` at hard. Keep Docker containers/volumes untouched. Keep `journalctl --vacuum-size=200M` and logrotate integration.
6. Replace the inaccurate Playwright report-only block with `playwright install chromium` in `cleanup_cache` live mode, once per run. This vendor command removed obsolete browser revisions in the observed first run while retaining browsers referenced by the installed Python package. In dry-run print a read-only action line and optionally `playwright install --list`; never use `playwright uninstall --all` or raw cache deletion. Record command rc rather than implying success after a failure.
7. No new abstractions. One short regression check is enough. Return changed files and any unresolved safety concern. Do not claim full acceptance; coordinator owns it.

## U1 — authoritative final correction, one additional executor invocation

Owner explicitly authorized exactly one additional `code-channel auto` invocation. Reuse the existing implementation: first apply `.agent-work/inherited.patch`, which contains the earlier accepted partial fix and existing test corrections. This is task-owned work offered for completion, not unrelated user edits. Do not inspect external directories or tools Beads. Do not launch executors, paid tests, cleanup, Git commits, or external messages. Coordinator owns acceptance and ship-post.

One bounded step: make the **production disposable-only cleanup path** safe and its dry/live inventory accurate. Prior observed dry-run listed 23 foreign project trash files and reported `total candidates: 0K` despite real pip cache candidates.

- Retain all earlier unbound-variable fixes and DR_TEST_ONLY backup-gate/selfcheck behavior. Keep production backup state processing intact; do not permit refixing foreign paths. Production must not delete or enumerate foreign reports, shared trash, transaction directories, Claude data, projects/worktrees, archives, Snap revisions, Docker resources, browser caches, unknown `/tmp` or session files. Remove those broad production scans/actions, including production `git worktree prune`. Old age alone is not ownership/disposability evidence. Existing temp cleanup timer owns `/tmp`.
- Production cleanup scope: regular files in existing pip/npm/nvm/package-manager disposable cache roots plus vendor apt/journald/logrotate actions already approved. Exclude symlinks and resolved protected targets. Use the same safe candidate validation in dry/live. Do not reinstall/download browsers: referenced Playwright revisions are protected; earlier native GC already ran. No new services/dependencies/configuration.
- Fix TOTAL_KB at the common call site: invoke `handle` in the current shell with process substitution instead of a pipe; list regular files once, not both their ancestor directories and children. Remove the fast `find -delete` path that bypasses candidate validation, reuse `handle` with its deletion result checked and journaled accurately. `denied` and age checks must apply before every deletion. No successful journal row for a failed removal. Add a `ponytail:` comment only for an actual bounded simplification, explaining that unknown/foreign files need explicit per-owner approval.
- Add one minimal isolated case to an existing selfcheck (not a new framework) proving nonzero, non-duplicated forecast and no foreign candidates; use the existing fixture mode/seam if meaningful. Do not weaken assertions. Run at most bash syntax and the new small case inside the provider; do not rerun the long gate suite.

Acceptance (coordinator): `bash -n scripts/disk-rotate.sh scripts/tests/disk-rotate-gate-selfcheck.sh`; existing three selfchecks once, the affected guarded dry-run with state under the coordinator scratch root; zero foreign/protected candidates and correct positive unique-file sum; only then one live run, actual deletion journal and df before/after, service-state comparison. Syntax/test PASS alone is not live acceptance. Existing return code 3 means disposable classes exhausted while disk remains above 88%; report it without manufacturing rc0. Expected gate status 5 must not be relabeled success.

Delivery: only `ship-post --submit` under GIT-LOCAL, own atom `dcfg-spfss`, TZ this file `#U1`, explicit owned files. Do not invoke ship or remote CI. Rollback: only this task's eventual commit; disposable caches rebuild with their owning tools. Return changed files and exact unresolved limits.

### U1 execution authorization and safe ceiling

After the single authorized additional executor returned without a source fix, the owner explicitly answered "да делай" to inline correction by the current Codex, without new executors or sessions. This overrides the code-channel-only route for this bounded correction only.

Production no longer processes foreign backup-state paths or unknown irreplaceable files. Existing backup state-machine behavior remains covered in isolated fixture mode. Before any production deletion, the existing last-ok/restic gate must open. Only stale regular files in canonical pip/npm content-addressed/nvm/snap download caches are candidates; a cache containing project/source markers is excluded as a whole. npx installed code, browser revisions and unknown files remain protected. Vendor apt/journald/logrotate outcomes are checked; vendor cleanup volume is measured live, not invented in dry-run. Notifications are suppressed in coordinator acceptance by a failing notify command and are reported separately from cleanup.

### U1 measured local acceptance — 2026-10-06

| Criterion | Command and observed result | Status |
|---|---|---|
| Shell syntax and patch integrity | `bash -n scripts/disk-rotate.sh scripts/tests/disk-rotate-gate-selfcheck.sh`; `git diff --check`: rc0 | PROVEN |
| Existing deterministic checks | Read-only bwrap, no network: disk-rotate-selfcheck ALL PASS rc0; gate-selfcheck PASS16/16 rc0; zones PASS4/4 rc0 | PROVEN |
| Accounting regression | RED rc1: total0, expected12, count2. GREEN production fixture rc0: unique12K; symlink and project-marked npm cache excluded | PROVEN |
| Real safe dry-run | Read-only bwrap, native actual cache roots, task-owned state, enforce: rc0; stale files0, foreign/protected candidates0. Cache marker scan empty and `find -mtime +1` confirms there are no stale files now | PROVEN |
| Actual cleanup | Own worktree script, native global flock, actual disk usage, enforce, fresh native backup/restic gate: open; journal confirms apt cache clean and journald vacuum success | PROVEN |
| Freed garbage | Vendor output: freed79.2M archived journals; journal directory282912→201740 KiB. Current caches unchanged because no stale candidates | PROVEN |
| Overall disk measurement | df available4236960→4432940 KiB, usage96%→96%. Whole-host delta195980 KiB includes concurrent activity; do not attribute it all to this script. Script's own ledger net193MB is also a whole-host measurement | PROVEN |
| Return code | Live rc3: documented disposable classes exhausted above88%, no cleanup failure and backup gate open. Not relabeled rc0 | PROVEN |
| Operational health | `systemctl show` before/after: logrotate and tmpfiles timer/service ActiveState, SubState, Result, ExecMainStatus identical | PROVEN |
| Existing recurrence | `crontab -l`: `0 4 * * * GATE_MODE=enforce /root/workspaces/tools/scripts/disk-rotate.sh`; timer configuration unchanged | PROVEN configured; scheduled execution of this new revision UNVERIFIED |
| External notifications | Acceptance deliberately uses failing notify command; none sent, alert result failed. Delivery of alerts is not claimed | PROVEN suppressed |

CE simplification: reuse, quality, efficiency lenses performed inline under the owner's explicit no-new-executor exception. Common handler reused, vendor mechanisms preserved; no further simplification edits. Source and requirements review performed against AGENTS and this U1. Independent peer review not run: the paid/executor ceiling and owner exception prohibit a new session; no independent-review PASS claimed. No retained source defect in the bounded read; remote CI/deployment not assessed.

Evidence receipts are retained under the current Codex runtime scratchpad `/root/.codex/.tmp/dcfg-spfss-tests/`: three selfcheck outputs, red-output, green-fixture, accepted-dry output/rc, accepted-live output/rc/log/journal/ledger, df/cache/service before/after. This document records outcomes; the receipts are the underlying evidence.

Local delivery is GIT-LOCAL ship-post submit of this TZ and the two owned scripts. Remote push/PR/CI/merge and scheduled deployment belong to the courier; no claim they have run.
