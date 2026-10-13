# Доставка через ship-post

## 1. Цель и контракт агента

`ship-post --submit` — локальная граница завершения одной задачи для Claude и Codex. Агент передаёт абсолютный linked worktree, свой атом, существующий путь ТЗ с суффиксом `#U<number>`, фактическое локальное доказательство и явный список файлов:

```text
ship-post --submit <worktree> --atom <id> --tz <path#U> --evidence <text> --files <file>...
```

`bin/ship-post:do_submit` accepts a registered linked worktree under `.worktrees/<agent>/`, a matching Claude/Codex branch and assignee, and an in-worktree TZ and file list. It rejects missing evidence, an invalid atom, an unserved repository, out-of-scope changes, invalid commit trailers, and a dirty worktree for a closed atom. On success it creates the local commit, checks for a conflict against a reachable `origin/<base>`, closes the atom with the committed SHA, writes the submission receipt, and prints `committed <atom> <sha> on <branch>`. If fetch is unavailable after commit, it warns that the conflict check is deferred, then closes and receipts the same SHA; the courier performs the later remote mergeability gate. Submit does not push.

Архитектура также читается без сети: `ship-post --status <atom>` — read-only сводка из файлов `SHIP_POST_STATE_DIR` (без `bd`, `git`, блокировок и записей), значения `none|submitted|delivering|failed|parked|<stage из receipt>`.

## 2. C4: контекст и контейнеры

```text
Claude/Codex agent
  -> ship-post --submit
  -> local commit + bd close + state/ship-post/submissions
  -> PM2 process ship-post (ecosystem.config.js, --watch)
  -> native bd events tail
  -> ship-post --watch / per-repository worker
  -> ship --handover
  -> GitHub PR, CI, merge
  -> git-sync -> live repository folders
```

`ecosystem.config.js` declares the `ship-post` process with `bin/ship-post --watch`. `bin/ship-post:do_watch` reads native Beads events and queues served repositories; it does not use file changes as events. `bin/ship-post:deliver_one` calls `ship --handover`; `bin/ship:locked_core` owns fetch, rebase, secret scan and branch push. After a proven remote merge `bin/ship-post:write_delivery_receipt` runs `git-sync` for the live repository.

## 3. Одна доставка

1. Агент submits exact files; `bin/ship-post:do_submit` validates, commits, closes the atom and records local SHA.
2. Watcher queues a repository after a closed Beads event; a close event queues only that atom (`<pending>.atoms`), the worker scans it alone; `<pending>.full` takes precedence for retries and startup (ADR-35). `bin/ship-post:do_watch` persists the cursor only after queueing.
3. A worker finds a clean closed worktree; `bin/ship-post:scan_repo` verifies trailers, owner, branch and receipt state.
5. A guarded delivery commits locally, writes `refs/dev-ready/<branch>`, prints `prod:hold guarded <reason>` and stops before fetch, push or GitHub. A plain delivery reaches `bin/ship:locked_core`, which pushes the fixed head; the remaining `ship` flow creates/uses a PR. A nonempty all-`.md` diff without pull-request CI prints `gate:auto docs-only`, checks mergeability, and merges the exact head without a CI wait. Other no-CI changes write `refs/dev-ready/<branch>`, record `wait-owner no-ci`, print `prod:wait-owner no-ci` and stop without merge, close, live sync or worktree cleanup. CI-backed plain delivery waits for CI and merges the exact head; a repository that disallows merge commits (`allow_merge_commit=false`) is merged with `--squash` (U22). `ship-post` обслуживает все репозитории `ga_roots`; после `ship` rc 0 читает вывод последнего запуска: `prod:wait-owner` создаёт квитанцию `wait-owner` с номером PR, `prod:hold` — `prod-hold`; обе стадии финальны, старая `wait-owner no-ci` один раз проходит через `ship`, коды `ship` 10/50/80 финальны для этого SHA до повторной сдачи автором (`ship-post --submit` снимает отметку, U24), 70 повторяется, а новый SHA поверх отправленного предка при неслитом PR пишет `superseded`, не code 24.
4. `bin/ship-post:scan_repo` starts `deliver_one` for all ready atoms of a repository in parallel (up to `SHIP_POST_JOBS`, default 8) without waiting for them; a per-atom lock `<repo lock>.<atom>` prevents a second concurrent delivery of the same atom (ADR-34). Push and merge stay serialized by `ga_lock` in `bin/ship` (ADR-30). `bin/ship-post:deliver_one` reconciles an existing GitHub result or calls `bin/ship:locked_core` through `ship --handover`. `bin/git-auto-lib:ga_class` marks the repository `plain`, `staged`, or `guarded`: mode `two` is staged; a skip reason in mode `one` is guarded. Before merge `bin/ship` re-fetches `origin/<base>`; if it moved since CI and the moved files overlap the PR or the delivery chain, it reopens the PR and waits for a new CI run (`bin/git-auto-lib:ga_ci_wait` with `since`), up to 5 rounds, else 70; disjoint moves merge at once (ADR-31/32).
5. `ship-promote` has two owner-quoted prod paths: `staged` (mode `two`) keeps the existing Dev-to-Prod fast-forward after Dev CI; `plain` (mode `one`) finds the atom's open PR, requires `refs/dev-ready/<head>` to equal its head SHA, then merges the atom PR with a merge commit (ADR-26) using `--match-head-commit`, so stacked branches remain descendants of `main`. It records `promote:`, runs live sync, and closes only an open or in-progress atom. `guarded` ends with `prod:hold` and never calls GitHub.
7. `bin/ship-post:write_delivery_receipt` stores remote proof, appends the Beads delivery note and runs `bin/git-sync:sync_one`.
8. `bin/git-sync:sync_one` fast-forwards the live checkout or preserves local work under rescue refs; `bin/git-state:emit` exposes delivery/sync alarms.

## 4. Состояние

Default state root is `/root/workspaces/tools/state/ship-post` (`SHIP_POST_STATE_DIR`). It contains:

INFRA-отказы (30/70/71/75/прочие) паркуются: метка `delivery-blocked`, инцидент `contour:delivery` на код (`state/ship-post/incidents/<rc>`), повтор каждым проходом, при успехе метка снимается (spec:099 v8, dcfg-c3gu3.2).

- `submissions/<repo-hash>/<worktree-hash>/<atom>/<sha>` — local submission receipt;
- `receipts/<repo-hash>/<atom>/<sha>` plus `.log`, `.failed`, `.reported`, `.ack` — delivery and diagnostic records;
- `inflight/<repo-hash>/<atom>` — one submitted SHA while delivery is unresolved;
- `locks/<repo-hash>.lock`, `watch.lock`, `pending/` — repository and watcher serialization; only the `bin/ship-post:do_watch` parent holds `watch.lock`: repository workers and the journal coproc close it, so deliveries that outlive a pm2 restart do not block the next watcher (dcfg-zd4ja);
- `cursor.json` — Beads ledger identity and last acknowledged event sequence.

`bin/ship:locked_core` writes `refs/delivered/<branch>` for a successful handover. `bin/git-sync:sync_one` keeps recoverable local work under `refs/rescue/<timestamp>/...`; `bin/git-state:emit` counts those refs.

## 5. Коды выхода

| Component | Code | Meaning in current code | Temporary |
| --- | ---: | --- | --- |
| `ship` | 10 | usage, preflight, policy or accepted-head check; `--help` exits 0; preflight names the expected worktree root | no, fix input/state |
| `ship` | 20 | gitleaks rejection | no, remove the finding |
| `ship` | 30 | commit, push, PR creation or absent CI | depends: transport/CI appearance can change; invalid PR state needs repair |
| `ship` | 40 | CI did not pass | no until CI/input changes |
| `ship` | 50 | rebase, PR conflict or merge failure | no, reconcile branch/PR |
| `ship` | 60 | post-merge close/live/reload step | depends on the failed post-step |
| `ship` | 70 | GitHub or fetch failure | yes, retry after connectivity/auth service recovery |
| `ship` | 75 | repository lock timeout | yes |
| `ship` | 80 | TЗ path not accepted | no, fix TЗ path |
| `ship-post` | 21 | no remote PR result yet; `deliver_one` proceeds to `ship` | intermediate, not a terminal result |
| `ship-post` | 22 | matching remote PR is open; `deliver_one` proceeds to `ship` | intermediate, not a terminal result |
| `ship-post` | 23 | GitHub query failed or repository is not private | query failure may be temporary; privacy denial is not |
| `ship-post` | 24 | remote result does not match the submitted SHA/state | no, reconcile before retry |

`ship-post` records 23, 70 and 75 as retryable observations in `bin/ship-post:record_failure`; after a `ship` result, 10, 50 and 80 are final for that submitted SHA, while 70 remains repeatable. Other delivery errors reopen the atom and append one note `ship-post exit <code>: <cause>; действие: <action>` to it; no separate task (ADR-28/29).

## 6. Отказы и восстановление

- Conflict (50): `ship` reports a conflicting PR or failed rebase/merge. Rebase or otherwise reconcile the agent branch, then submit/deliver the corrected head.
- Conflict at submit (50, ADR-27 and CR-ADR-27): `bin/ship-post:do_submit` fetches `origin/<base>` and runs `git merge-tree --write-tree --name-only origin/<base> HEAD` after committing the listed files and before `bd close`; rc 1 rejects a reachable conflict with code 50, the conflicting files and the fix command, and leaves courier state empty. A fetch failure defers this check while closing and receipting the committed SHA. The courier checks remote mergeability before merge. `bin/git-auto-lib:ga_base` in `local` mode selects the base, including for a nested repository (`<repo>/sub`, dcfg-8yqv4.36).
- SHA change: an `inflight` record with another SHA becomes code 24 in `bin/ship-post:deliver_one`, except when the old SHA is an ancestor of the new SHA and its PR is not merged: the courier records `superseded <old> -> <new>` and continues with the new head.
- No CI: a nonempty all-`.md` diff prints `gate:auto docs-only` and merges after the mergeability check; other changes return `prod:wait-owner no-ci` after branch push and PR creation, and production requires the owner’s word through `ship-promote`.
- Guarded repository: `bin/git-auto-lib:ga_skip_reason` returns `allowlist` or `hh-scoring`; `ship` returns `prod:hold guarded <reason>` after local commit and dev-ready ref, before any remote action. `ship-post` serves these roots and stores a final `prod-hold` receipt; `git-sync` emits `skip:<reason>`.
- Nested `.git` without a work tree (`<repo>/.git/.git`): `bin/git-auto-lib:ga_roots` skips it silently — `--show-toplevel` is empty and `realpath` stderr is discarded, so `ship` output carries no `realpath: ''` line (dcfg-rtbvl, test T10 in `bin/git-auto-lib-test`).
- Closed atom skipped (ADR-29): `bin/ship-post:report_closed_skip` turns any skip of a closed atom on branch `claude|codex/<atom>-*` (no assignee, branch/agent mismatch, dirty worktree, TЗ outside worktree), and a differently named `claude|codex/*` branch whose SHA is not in `origin/<base>`, into `record_failure` code 10 with action `сдай через ship-post --submit`, once per atom+SHA.
- `bin/git-auto-lib` начинается с `#!/usr/bin/env bash`, чтобы repowise индексировал функции `ga_*`.

## 7. Наблюдаемость

PM2 declares `/root/.pm2/logs/ship-post-out.log` and `/root/.pm2/logs/ship-post-error.log`. Per-delivery command output is `receipts/.../<sha>.log`; receipt JSON carries local and remote SHA/URL. `bin/ship-post:ack_delivery` adds a delivery marker to Beads notes. `bin/git-state:emit` reports branch, behind/ahead, dirty state, PR count, rescue-ref count and alarm; `bin/git-sync:emit` appends sync results to `${GA_LOG_DIR:-/root/workspaces/tools/logs}/git-sync.log`.

## 8. Перенос: environment и пути

`ship-post` reads `SHIP_POST_STATE_DIR`, `SHIP_POST_JOBS`, `SHIP_POST_BEADS_ROOT`, `SHIP_POST_SINCE`, `SHIP_POST_RETRY_SECONDS`, `SHIP_POST_REPOS` and `BEADS_ACTOR`. `git-auto-lib` defaults include `GA_PROJECTS=/root/workspaces/projects`, `GA_TOOLS=/root/workspaces/tools`, `GA_CONTOUR_GITDIR=/root/workspaces/system/contour-config.git` and `GA_CONTOUR_WT=/root`; `git-sync` and `git-state` use `GA_LOG_DIR` when set. `ship` defaults `BEADS_DIR` to `/root/workspaces/projects/.beads` and discovers worktrees under `/root/workspaces/projects/.worktrees` unless `GA_WT_ROOT` is set. PM2 hard-codes `/root/workspaces/tools/bin/ship-post` in `ecosystem.config.js`.

pm2 restarts `ship-post` when `bin/ship-post` or `bin/git-auto-lib` changes (`watch` in `ecosystem.config.js`); an interrupted delivery is reconciled from GitHub on startup.

## 9. Тесты и CI

`bin/ship-post-test` is the isolated behavioural suite for submit, courier, receipts, watcher and actor parity. `bin/ship-test` exercises the lower `ship` delivery flow. `bin/ship-doc-check` fails a chain-script diff without this document and checks every backticked anchor in the `file:function` form. `bin/ship-doc-check-test` covers its four required temporary-repository cases.

`tools-smoke` has no `paths:` filter, so pull requests always create a run for `ga_ci_wait`. On pull requests it runs the doc gate and only runs `ship-test` when the delivery chain or `bin/ship-test` changed; pushes to `main` run `ship-test` unconditionally.

## 10. Ссылки

- [spec 099 ship dev/prod](/root/workspaces/projects/specs/099-ship-dev-prod/)
- [LAWS-PROCEDURES.md, «Ветки агентов»](/root/workspaces/projects/docs/LAWS-PROCEDURES.md)
