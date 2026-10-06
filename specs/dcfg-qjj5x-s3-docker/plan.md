# Implementation Plan: Docker archives in the existing S3 backup

**Date**: 2026-10-06 | **Spec**: spec.md | **TZ**: ../../docs/tz/2026-10-06-dcfg-qjj5x-backup-retention.md#U3

## Summary

Keep server-backup.sh as the only scheduled S3 orchestration. It invokes the existing docker-backup.sh producer before capturing archives. Remove only the separate Docker ecosystem entry. Preserve current S3 source paths, credential loading, repository and retention. Capture retained directories before cleanup: initial history migration, then the prior plus new snapshot after successful retention. Pin the full offsite snapshot ID and restore/compare all compressed files before any deletion; reserve target capacity and preserve the exact host authorization gate.

## Technical Context

**Language**: Bash; existing JavaScript PM2 configuration.
**Dependencies**: existing Docker, restic, gzip, GNU coreutils, flock, PM2, Beads and ship-post.
**Storage**: existing /root/backups/docker staging and existing S3 repository.
**Validation**: nonmutating shell/JavaScript syntax checks, independent two-cycle review, actual authorized upload and recovery. No new test scripts.
**Platform**: existing Linux host.
**Constraints**: no new executable, paid executor, credential inspection, client editing, unapproved deletion, direct push or direct ship.
**Scale**: measured baseline 5 published local directories, approximately 5.94 GB allocated; refreshed inventory defines migration N.

## Constitution Check

Same tools Git root and linked worktree; shared Beads remains in projects. Existing uploader and producer are reused. Local code readiness is a subordinate delivery atom, not operational closure. Parent operational work remains open until SC-001–SC-006 are measured. Protected-path host gates remain authoritative.

## Project Structure

### Documentation (this feature)

specs/dcfg-qjj5x-s3-docker/{spec.md,plan.md,tasks.md}
docs/tz/2026-10-06-dcfg-qjj5x-backup-retention.md
.specify/feature.json

### Source Code (repository root)

scripts/pm2/server-backup.sh — existing orchestration, migration selection and success evidence.
scripts/pm2/docker-backup.sh — existing compressed staging, failure propagation and publication.
ecosystem.config.js — existing schedules; remove only the standalone Docker entry.

## Execution and Rollback

1. Complete local readiness and submit its closed code atom through the existing courier; never close the operational parent from syntax alone.
2. Verify courier merge and exact live source identity before applying PM2 transition.
3. Record inventory and space; migrate historical archives once; record snapshot ID.
4. Restore archives, compare inventory/sizes/hashes and validate recovery claims.
5. Apply only the exact authorized local cleanup and future retention policy; measure space and unchanged services.

Rollback restores only the owned source/configuration changes through normal delivery. Existing S3 snapshots and local archives are preserved. Do not restore the unsafe pre-upload deletion step. If new staging fails, ordinary server uploads continue; overall completion remains degraded.

## Current Evidence and Gaps

Local implementation baseline: 8b99dfe; syntax checks passed; three real independent reviewers covered six roles in two cycles. MinIO restore rc0, 550M. Actual proxy-manager bind mounts are under /root/workspaces/system/services/proxy-manager, within the primary workspace input. Proof-gated local retention is implemented in the existing uploader; actual archive recovery, live schedule transition and space release still need runtime evidence. No deletion is attempted without the unchanged host gate.
