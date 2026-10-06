# Tasks: Docker archives in the existing S3 backup

**Input**: spec.md, plan.md and ../../docs/tz/2026-10-06-dcfg-qjj5x-backup-retention.md#U3
**Tracking**: operational parent dcfg-qjj5x; subordinate local code-readiness atom only for courier admission.
**Checkbox meaning**: a task is checked only when its stated evidence exists. Local code checks do not check runtime tasks.

## Phase 1: Setup

- [x] T001 Bind the same tools worktree and current feature in .specify/feature.json; resolve bundled templates without creating duplicate executables.
- [x] T002 Record requirements and architecture in specs/dcfg-qjj5x-s3-docker/spec.md and plan.md, preserving the existing TZ U3.

## Phase 2: Foundational

- [ ] T003 Record and close the subordinate local code-readiness atom with syntax/review/secret-scan evidence for scripts/pm2/server-backup.sh, scripts/pm2/docker-backup.sh, ecosystem.config.js and the feature documents; submit through existing bin/ship-post and verify its receipt.

## Phase 3: US1 — One scheduler

- [x] T004 [US1] Integrate the existing producer, degraded-result handling and migration selection in scripts/pm2/server-backup.sh; evidence: 8b99dfe and two review cycles.
- [x] T005 [US1] Reject failed dumps/inventory/fatal tar/corrupt gzip and publish hidden output safely in scripts/pm2/docker-backup.sh; evidence: 8b99dfe, syntax and source review.
- [x] T006 [US1] Remove only the standalone Docker entry from the draft ecosystem.config.js; evidence: 8b99dfe.
- [ ] T007 [US1] Verify exact courier-delivered scripts/pm2/server-backup.sh and scripts/pm2/docker-backup.sh in the live tools root, then disable only the old Docker PM2 registration according to ecosystem.config.js; record zero standalone entries and one server scheduler.

## Phase 4: US2 — Recoverability

- [ ] T008 [US2] Record current local archive inventory, active services and df bytes in the existing TZ evidence section; run scripts/pm2/server-backup.sh with one-time migration enabled and record snapshot ID, producer/upload results and full-success receipt.
- [ ] T009 [US2] Extend the existing scripts/pm2/server-backup.sh drill only as necessary to retain a recovery target for verification; compare every migrated archive with its original and record N/N identical sizes/hashes, zero missing/mismatched files, plus the limits of database recovery validation.

## Phase 5: US3 — Bounded local retention

- [x] T010 [US3] Implement proof-gated bounded local retention in the existing scripts/pm2/server-backup.sh only; no second cleanup script. Preserve originals on missing receipt, recovery failure, missing snapshot or absent exact host authorization. Evidence: actual-function guard probes 8/8 and targeted review corrections; runtime deletion remains T011.
- [ ] T011 [US3] Apply only the approved exact deletion list under /root/backups/docker using the existing authorized cleanup route; record one retained complete snapshot, allocated bytes removed, df delta and unchanged active services in the existing TZ.

## Phase 6: Completion

- [ ] T012 Map FR-001–FR-010 and SC-001–SC-006 to current source/runtime receipts in specs/dcfg-qjj5x-s3-docker/spec.md and the existing TZ; close the operational parent only after all required tasks and findings are resolved.

## Dependencies

T001 → T002 → T003 → T007 → T008 → T009 → T010 → T011 → T012. T004–T006 are implemented in the current draft but require T003/T007 for activation. Do not remove local originals or disable their independent coverage before replacement source readiness is established.

## Parallel Opportunities

Independent read-only source reviews can run together; this has already occurred. Upload, restore, retention and runtime activation are sequential. No parallel marker is assigned to tasks sharing scripts or operational state.

## Implementation Strategy

MVP is US1 plus an actual integrated run. Operational acceptance includes US2 and US3; MVP readiness alone does not close dcfg-qjj5x. All added work stays within this existing owner-authorized objective.
