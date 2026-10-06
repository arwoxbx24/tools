# spec:099 U3 — recover shared delivery after interrupted services

## Source and scope
Continuation of spec:099 U2, not a new specification. Parent requirements: projects/specs/099-ship-dev-prod/cr-2026-10-06-git-authority.md D01-D08; implementation baseline tools origin/main 6e6d57d. Owner R081-R083 approved the two-pass audit findings and direct inline correction. Own atom dcfg-m6vui, projects ledger, tools Git root, own linked worktree. Allowed files: bin/ship-post, bin/ship, bin/ship-post-test, this TZ. No client files, secrets, host hooks, other services, external models or new executables. Runtime deployment requires owner confirmation; final local submission and existing courier delivery remain authorized.

## U3 — requirements and architecture
R1 Preserve pending work on transient errors. Retry safe reads at bounded intervals, without model calls. Startup still reconstructs pending work. Do not clear uncertain state or repeat mutations blindly.
R2 Reconcile remote results before treating legacy .failed/inflight markers as final. Retry transient API/fetch/lock errors automatically. Product/security failures remain explicit, recoverable blockers; their partial Beads registration must complete idempotently. Never invent remote success.
R3 Persist delivery receipt separately from Beads acknowledgement. Repair missing notes using the receipt, without another push. Persist actor, repository, atom, submitted/remote SHA, time and stage in receipts/logs.
R4 Accept only repositories and worktree layouts the courier serves. Delivery of an accepted SHA never stages or commits additional files. In accepted mode keep HEAD fixed (no automatic rebase); GitHub exact-head merge and CI decide admissibility. Conflicts require corrected, locally accepted work. Legacy direct ship retains its existing behavior.
R5 Observe worker death; exit watcher so the existing PM2 restart policy can recover. Graceful shutdown stops readers/workers; startup repairs interrupted operations. No new process names or daemons.
R6 Event test must start with open atom, finish startup scan, then close it. Prove event-driven delivery separately from startup recovery.

## Ordered tasks / acceptance
T1 Add deterministic regressions for transient API recovery, pending retry after Beads outage, failure registration retry, receipt-note repair, actor data, actual close event, worker death, allowed roots and accepted-head rejection.
T2 Repair shared helpers/scan/watch; extend existing ship with optional --expected-head. Normal hooks, gitleaks, private destination and exact-head merge remain required.
T3 Run `bash -n bin/ship-post bin/ship bin/ship-post-test`; `env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 timeout 90 bash bin/ship-post-test`. Expected failures=0, no real GitHub/Beads mutations from tests. Owner R076 forbids sandbox launch: tests use only temporary local repos and PATH-injected bd/gh/ship mocks, no bwrap or live-service outage. Real ship accepted-head checks tested before external calls with native temp Git and mocked library.
T4 One implementation review, repair demonstrated findings, rerun only affected checks. `git diff --check` expected empty. Submit once through existing ship-post with explicit file manifest and acceptance evidence. Distinguish local closure, remote receipt and runtime deployment.

## Failure classification and limits
Temporary read/transport/lock errors retain closed readiness and pending retry. CI, secret, conflict and scope denials do not become automatic approval. Recovered services alone cannot repair wrong code or merge conflicts. Receipts/commits survive process restart, but this is not a disk-loss backup guarantee. No claims of power-loss fsync durability or distributed exactly-once delivery.

## Rollback
Revert only this owned patch through normal Git delivery, preserving local commits, pending markers, receipts and Beads history. Do not delete state to regain a green result. No production restart during offline acceptance.

## Planning consistency check
R1-R6 map to T1-T4 and existing D01-D08; accepted-head mode strengthens exact-SHA and owned-files requirements. No new repository scope, production authority, service name or package dependency. Earlier mock acceptance does not establish these new failure scenarios. Deployment approval is separate from code acceptance.

## Review and verified intermediate results
The single implementation review found dry-run mutation, incomplete repeated-failure registration, legacy marker reconciliation and timeout-truncated journal lines. Corrections preserve dry-run as read-only, reconcile remote results even for old failures, reopen on renewed product failure, and retain partial JSON until the complete line arrives. CI API outage/pending checks are distinct from confirmed red checks. Accepted delivery pins secret scanning, push, CI, merge and delivered ref to the accepted SHA.
Initial regression: 4 checks, 4 failures. First full run: 68 checks, 0 failures. Affected recovery run after review fixes: 17 checks, 0 failures. Final exact-tree run recorded separately before submission. No real service outage, reboot or power-loss claim.
Owner R084-R087: further source reads use refreshed indexes only. RepoWise index-only update covers this worktree; Codebase Memory fast-mode coverage excludes bin, so it is not source evidence for these scripts. No models used for indexing. Existing legacy product blockers still require genuine repair and normal closure; this change does not erase tracker dependencies or fabricate an acceptance result.

Final full-run follow-up: 75 checks exposed one additional crash-reconciliation defect (receipt parent directory missing when recovery starts before first delivery). Added directory creation to the shared receipt writer; no acceptance weakened. Final rerun follows that exact correction.

## Final local acceptance
After the shared receipt-directory correction, the specified full test command completed with exit 0 and `checks=75 failures=0`. Fresh `bash -n bin/ship-post bin/ship bin/ship-post-test` and `git diff --check` both completed with exit 0 and empty output. RepoWise index-only refresh returned `ok: true`, `outcome: noop`, `cost_usd: 0.0`. This proves local deterministic acceptance only; remote delivery and application to the running courier require their own receipts. No runtime restart or deployment was performed in this acceptance.
