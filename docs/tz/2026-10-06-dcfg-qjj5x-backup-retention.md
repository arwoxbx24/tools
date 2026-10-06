# ТЗ: existing disk cleanup, owner scope correction

## U2 — authoritative current scope

The owner narrowed execution to improving the existing cleanup script, with no duplicate scripts, renaming, new tests, paid runs or new executors. This section supersedes the earlier implementation steps below. The unshipped changes to `ecosystem.config.js` and `scripts/pm2/docker-backup.sh` have been reverted in this task's worktree; production was not changed.

Canonical implementation: `scripts/disk-rotate.sh`, from spec:054/spec:055. Its existing npm cache cleanup is reused unchanged. The only addition is root-owned regular `/tmp/.bcdb*.so` files older than two days, matching the previously measured SHA-256 `977a96fc9911edd8cabacb098e90229c6a2dde7384f3291e5beccaf1ee93fef5`. Require installed `lsof`, an empty diagnostic/output result and exit code 1 before passing a candidate to the existing `handle cache` path. Open files, unknown content and inspection errors are skipped. Preserve the existing backup gate, dry-run accounting, journal and deny list. No protected backup deletion or S3 change.

Acceptance for this bounded edit: `bash -n scripts/disk-rotate.sh` and `git diff --check` return 0; only this existing executable and this same TZ differ. No test file or runtime process is created. Runtime deletion, scheduled deployment, S3 restore and the original 15 GiB disk target remain unverified; these code checks do not close the atom. Rollback is restoring only this task's `disk-rotate.sh` diff from Git.

## U2 architecture and validation — 2026-10-06

The current Beads record confirms U2 as the latest authorized scope: script development only, no paid executor, cleanup run, new script, or test creation. The original disk/S3/tmux acceptance remains open; this review does not replace it. The existing spec:054/spec:055 architecture is reused rather than creating a second feature or changing the unrelated active SpecKit feature.

Requirement coverage: regular root-owned files and age are constrained by `find -P /tmp -maxdepth 1 -type f -user root -mtime +1`; content by the exact SHA-256; open files and inspection diagnostics by `lsof` exit 1 plus empty combined output. Missing lsof skips the addition. Each accepted path passes to existing `handle cache`, which checks the deny list, regular/non-symlink status and canonical path before dry-run accounting or deletion/journaling. Existing cache selection and backup gates are unchanged.

The prior review overstated the pathname-replacement risk: live `/tmp` is root-owned mode 1777, so an unrelated unprivileged user cannot replace a root-owned directory entry. Concurrent privileged writers can still modify a file or open it after inspection; lsof is a point-in-time check, not a lock. U2 does not require a new concurrency mechanism. No claim of atomic inspection/deletion or runtime safety testing is made.

Fresh validation: `bash -n scripts/disk-rotate.sh` exit 0; `git diff --check` exit 0; source diff contains 13 additions and zero removals. Only `scripts/disk-rotate.sh` and this TZ are task-owned changes. No scheduled process, runtime deletion, backup, S3 operation, or test file was created by this review.

## Superseded draft (not deployed)

Atom: dcfg-qjj5x. Owner: Codex. Worktree: this repository only.

## Goal and boundaries

Keep the existing `docker-backup` producer and `server-backup` restic→S3 consumer. The owner chose one daily local snapshot after its exact S3 copy and restore are proved. Never delete or change the S3 repository. Protected `/root/backups/docker` is read-only for this execution because the host's exact deletion approval file is absent. Keep the current deletion count and mechanism unchanged; do not trigger a backup or cleanup during implementation. Do not alter secrets, production containers, active services or other sessions.

## Owned edits

Only `ecosystem.config.js` and `scripts/pm2/docker-backup.sh`; add one small test file under `scripts/pm2/` only if necessary for the changed selection/publish logic. No other files except this ТЗ.

1. Change the existing PM2 `docker-backup` schedule from every six hours to 00:00 daily, before existing `server-backup` at 03:30. Do not add a process or scheduler.
2. In `docker-backup.sh`, write all archives into a hidden incomplete directory under the same backup root. Publish it atomically as a lexically sortable `20*` directory only when the script has zero errors. On error, leave the prior published snapshot available to `server-backup` and return the existing nonzero status. Preserve warning behavior and existing archive names. Refuse to overwrite an existing final path. Do not invoke the backup or delete any backup directory during the work.
3. Remove pre-backup rotation: it can delete a local snapshot before its exact S3 copy has been confirmed. Retain all published snapshots until exact S3 content and restore checks plus the host deletion gate are available. Do not edit `server-backup.sh`: it already takes the last sorted `20*` path; a hidden incomplete directory is invisible to that selection.

## Acceptance

`bash -n scripts/pm2/docker-backup.sh` exits 0; static check shows `cron_restart: '0 0 * * *'` for docker-backup and unchanged `30 3 * * *` for server-backup. `git diff --check` exits 0. Existing real backups and S3 unchanged. One-local-snapshot retention, real scheduled runs, S3 restore, disk ≥15 GiB, and tmux acceptance remain separate hard gates; never report them as complete from this code check.

## Review correction, required before delivery

The first executor pass created `scripts/pm2/docker-backup-publish-test`, which merely repeats the code and does not test the real script. Remove that task-owned test. It also added `rm -rf "$BACKUP_DIR"` in the protected backup root on an error. Remove that deletion and leave the hidden incomplete directory for an authorized cleanup route. Change final-path guard to reject any file, directory, or symlink. Check `mkdir` and `mv` return codes; publication failure must return nonzero and must never log success. The later owner instruction requires removing legacy pre-backup rotation until S3 restore and exact host deletion approval exist. Do not run the real backup, delete any protected directory, or touch S3.

## Rollback

Revert this task's commit to restore six-hour schedule and prior backup script behavior. Keep all existing protected snapshots intact.
