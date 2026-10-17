# TZ dcfg-bf6pk — place-files: allow main checkout → worktree of the same repository

Atom: dcfg-bf6pk. Project: worktree of /root/workspaces/tools. Discovery: repowise (index checked); facts are file:line.
Principles: KISS, YAGNI, minimal diff, fail fast. No new files, no new dependencies.

## U1

FILE: bin/place-files
FILE: bin/place-files-test

Facts:
- bin/place-files:30 destination_repo = `git -C "$ancestor" rev-parse --show-toplevel`.
- bin/place-files:47-50 source_repo = show-toplevel of the source dir; refuses `not in destination repository` when they differ.
- A linked worktree has its own toplevel, so copying /root/workspaces/tools/hooks/x.sh into /root/workspaces/tools/.worktrees/claude/<atom>/hooks fails although it is the same repository.

Change (bin/place-files):
1. Identify a repository by `git rev-parse --path-format=absolute --git-common-dir` (same object store for main checkout and its worktrees) instead of `--show-toplevel`, for both destination (line 30) and source (line 47). Keep `realpath -m` normalisation and every existing refusal and its message text unchanged.
2. Nothing else changes: root check (lines 14-17), `.git`/`secrets` refusal, symlink, `.env*`/`*.pem`/`*.key`, `destination exists`.

Test (bin/place-files-test), add cases:
- PASS: file tracked or untracked in main checkout of a temp repo → copied into a linked worktree (`git worktree add`) of that same repo under the root.
- Still refused: source from a different repo → `not in destination repository`; destination outside PLACE_FILES_ROOT → `destination outside root`; `.env` source → `forbidden filename`.
- Run: `bash bin/place-files-test` → report the PASS line.

Forbidden: editing any other file; rm/rm -rf outside the test temp dir; reading ~/.ssh, secrets, .env; network; git push.

## Source passport
- Measured 17.10: `git -C tools/.worktrees/claude/dcfg-bf6pk rev-parse --path-format=absolute --git-common-dir` → `/root/workspaces/tools/.git`; same command from `tools/hooks` → `/root/workspaces/tools/.git`.
