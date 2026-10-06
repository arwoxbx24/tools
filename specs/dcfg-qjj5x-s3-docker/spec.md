# Feature Specification: Docker archives in the existing S3 backup

**Feature Branch**: task-owned linked worktree, dcfg-qjj5x
**Created**: 2026-10-06
**Status**: Safe execution authorized without repeated permission questions; runtime acceptance pending
**Input**: Owner: «Найди скрипт, который отвечает за копирование в S3-хранилище. Добавь в него бэкапы Docker и все, а потом бэкапы Docker отключи»; «да делай строго через ТЗ спек + задачи жестко».
**Existing TZ**: ../../docs/tz/2026-10-06-dcfg-qjj5x-backup-retention.md#U3
**Beads parent**: dcfg-qjj5x

## User Scenarios & Testing

### User Story 1 - One coordinated offsite backup (Priority: P1)

The owner receives the server backup and compressed Docker data through the existing S3 automation, with no duplicate scheduler.

**Why this priority**: Stopping the producer before replacing its coverage loses Docker-volume protection.
**Independent Test**: A completed integrated run has one scheduler, a recorded offsite snapshot and the expected Docker archive inventory.
**Acceptance Scenarios**:
1. Given the existing producer and S3 job, when the integrated run succeeds, all newly produced archives are included in the server snapshot.
2. Given a producer failure, when the server run proceeds, existing server data still uploads; the overall result is degraded and the full-success marker does not advance.
3. Given concurrent invocations, only one producer and one server backup execute at a time.

### User Story 2 - Recover existing local archives (Priority: P1)

The owner can recover accumulated archives from S3 before automatic removal of authorized local copies.

**Why this priority**: Path inclusion alone does not prove that an archive exists offsite or is recoverable.
**Independent Test**: The inventoried compressed files are restored and compared with originals: N/N matching, zero missing or mismatched files.
**Acceptance Scenarios**:
1. Given a recorded local inventory, a one-time migration uploads every published archive directory.
2. Given a migration snapshot, restored compressed files match local sizes and SHA-256 values.
3. Given a missing or mismatched file, its local original is retained and acceptance fails.

### User Story 3 - Release space without backup loss (Priority: P2)

The owner retains one complete local snapshot after offsite recovery is proved and exact host authorization is present.

**Why this priority**: Repeated staging must not silently refill the disk.
**Independent Test**: Approved duplicate paths are absent, one complete snapshot remains, allocated-byte and filesystem measurements are recorded.
**Acceptance Scenarios**:
1. Given restore proof and exact deletion authorization, remove only the inventoried approved copies.
2. Given a failed upload or recovery check, retain local originals and report the failure.

### Edge Cases

- Failed dump, failed compression, fatal tar error, failed inventory or corrupt gzip: do not publish the incomplete directory.
- Active-volume tar warnings are not proof of application-consistent recovery.
- The Nginx Proxy Manager source is determined from live mount metadata; a missing legacy path does not prove the real service is uncovered.
- Migration snapshots remain subject to the existing 14-daily-snapshot S3 policy; historical copies are not promised indefinite retention.
- Capacity shortage, repeated retries and interrupted directories must be reported before an unsafe staging run.

## Requirements

### Functional Requirements

- **FR-001**: Reuse the existing S3 uploader, repository, credentials mechanism and backup schedule. Create no new executable or independent scheduler.
- **FR-002**: Preserve logical database dumps and named-volume archive coverage when disabling the independent Docker schedule.
- **FR-003**: Publish only output whose production and compressed-stream checks succeeded; exclude hidden incomplete output.
- **FR-004**: Upload all retained published archives in the same snapshot before proof-gated cleanup; after successful retention ordinary runs contain the previous and newly produced complete snapshots only.
- **FR-005**: Preserve ordinary server uploads when fresh Docker staging fails; report degradation without advancing full-success evidence.
- **FR-006**: Record snapshot identity and demonstrate exact restored compressed-file equality before local deletion.
- **FR-007**: Remove only precisely approved local copies, retain one complete local snapshot, and establish bounded future local retention after recovery proof.
- **FR-008**: Preserve active services, live data, other sessions and the existing S3 retention policy.
- **FR-009**: Block concurrent runs, bound subprocess termination, and record failures and rollback evidence.
- **FR-010**: Production application, uploads and deletions follow the owner's authorization and existing delivery route; local code readiness never closes operational acceptance.

### Key Entities

- Published snapshot: complete directory, source inventory and timestamp.
- Offsite receipt: S3 snapshot identity, captured source inventory and command result.
- Restore proof: original and restored size/hash, matched count and missing/mismatch count.
- Cleanup approval: exact paths, preserved snapshot, proof reference and measured bytes.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Exactly one scheduled server backup; zero independently scheduled Docker backup jobs.
- **SC-002**: N/N inventoried migration archives recover with identical sizes/hashes; zero missing or mismatched archives.
- **SC-003**: At least one integrated run completes successfully with a new offsite snapshot and a full-success receipt.
- **SC-004**: Approved local cleanup leaves one complete snapshot; actual allocated bytes removed and free bytes before/after are recorded. No unsupported 15-GiB guarantee.
- **SC-005**: Before/after active service inventories match; no unapproved data or session deletion.
- **SC-006**: A local readiness commit and courier delivery receipt identify the exact implementation; runtime activation and recovery evidence are recorded separately.

## Assumptions

- The current named-volume archives are necessary because the primary source list does not directly include their storage root.
- Exact compressed-byte recovery and database/application recovery are distinct claims; the latter requires independent validation.
- Recursive deletion of protected backup directories requires the exact existing host gate. No gate file is created or modified by the agent.
- Only task-owned source/configuration/documentation changes are authorized. Existing client projects and unrelated dirty files remain untouched.
