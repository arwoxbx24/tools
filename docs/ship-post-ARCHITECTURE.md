# Доставка через ship-post

## 1. Цель и контракт агента

`ship-post --submit` — локальная граница завершения одной задачи для Claude и Codex. Агент передаёт абсолютный linked worktree, свой атом, существующий путь ТЗ с суффиксом `#U<number>`, фактическое локальное доказательство и явный список файлов:

```text
ship-post --submit <worktree> --atom <id> --tz <path#U> --evidence <text> --files <file>...
```

`bin/ship-post:do_submit` принимает только зарегистрированный linked worktree в `.worktrees/<agent>/`, ветку и assignee, согласованные с Claude/Codex, путь ТЗ и файлы внутри worktree. Он отклоняет пустое доказательство, неверный атом, неразрешённый репозиторий, чужие/неперечисленные изменения, неверные trailers и закрытый атом с грязной рабочей копией. При успехе создаёт локальный коммит, закрывает атом и пишет submission receipt; сеть не является частью `--submit`.

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
2. Watcher queues a repository after a closed Beads event; `bin/ship-post:do_watch` persists the cursor only after queueing.
3. A worker finds a clean closed worktree; `bin/ship-post:scan_repo` verifies trailers, owner, branch and receipt state.
4. `bin/ship-post:deliver_one` reconciles an existing GitHub result or calls `bin/ship:locked_core` through `ship --handover`.
5. `bin/ship:locked_core` pushes the fixed head; the remaining `ship` flow creates/uses a PR, waits for CI and merges the exact head.
6. `bin/ship-post:write_delivery_receipt` stores remote proof, appends the Beads delivery note and runs `bin/git-sync:sync_one`.
7. `bin/git-sync:sync_one` fast-forwards the live checkout or preserves local work under rescue refs; `bin/git-state:emit` exposes delivery/sync alarms.

## 4. Состояние

Default state root is `/root/workspaces/tools/state/ship-post` (`SHIP_POST_STATE_DIR`). It contains:

- `submissions/<repo-hash>/<worktree-hash>/<atom>/<sha>` — local submission receipt;
- `receipts/<repo-hash>/<atom>/<sha>` plus `.log`, `.failed`, `.reported`, `.ack` — delivery and diagnostic records;
- `inflight/<repo-hash>/<atom>` — one submitted SHA while delivery is unresolved;
- `locks/<repo-hash>.lock`, `watch.lock`, `pending/` — repository and watcher serialization;
- `cursor.json` — Beads ledger identity and last acknowledged event sequence.

`bin/ship:locked_core` writes `refs/delivered/<branch>` for a successful handover. `bin/git-sync:sync_one` keeps recoverable local work under `refs/rescue/<timestamp>/...`; `bin/git-state:emit` counts those refs.

## 5. Коды выхода

| Component | Code | Meaning in current code | Temporary |
| --- | ---: | --- | --- |
| `ship` | 10 | usage, preflight, policy or accepted-head check | no, fix input/state |
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

`ship-post` records 23, 70 and 75 as retryable observations in `bin/ship-post:record_failure`; other delivery errors reopen the atom and create/reuse a diagnostic task.

## 6. Отказы и восстановление

- Conflict (50): `ship` reports a conflicting PR or failed rebase/merge. Rebase or otherwise reconcile the agent branch, then submit/deliver the corrected head.
- SHA change: an `inflight` record with another SHA becomes code 24 in `bin/ship-post:deliver_one`; inspect remote state before any retry.
- No CI: a repository without a pull-request workflow receives `wait-owner no-ci` receipt in `bin/ship-post:write_wait_owner_no_ci_receipt`; production requires the owner’s word recorded by that path.
- Repository skip: `bin/git-auto-lib:ga_skip_reason` returns `allowlist` or `hh-scoring`; `ship-post` excludes it from served roots and `git-sync` emits `skip:<reason>`.

## 7. Наблюдаемость

PM2 declares `/root/.pm2/logs/ship-post-out.log` and `/root/.pm2/logs/ship-post-error.log`. Per-delivery command output is `receipts/.../<sha>.log`; receipt JSON carries local and remote SHA/URL. `bin/ship-post:ack_delivery` adds a delivery marker to Beads notes. `bin/git-state:emit` reports branch, behind/ahead, dirty state, PR count, rescue-ref count and alarm; `bin/git-sync:emit` appends sync results to `${GA_LOG_DIR:-/root/workspaces/tools/logs}/git-sync.log`.

## 8. Перенос: environment и пути

`ship-post` reads `SHIP_POST_STATE_DIR`, `SHIP_POST_BEADS_ROOT`, `SHIP_POST_SINCE`, `SHIP_POST_RETRY_SECONDS`, `SHIP_POST_REPOS` and `BEADS_ACTOR`. `git-auto-lib` defaults include `GA_PROJECTS=/root/workspaces/projects`, `GA_TOOLS=/root/workspaces/tools`, `GA_CONTOUR_GITDIR=/root/workspaces/system/contour-config.git` and `GA_CONTOUR_WT=/root`; `git-sync` and `git-state` use `GA_LOG_DIR` when set. `ship` defaults `BEADS_DIR` to `/root/workspaces/projects/.beads` and discovers worktrees under `/root/workspaces/projects/.worktrees` unless `GA_WT_ROOT` is set. PM2 hard-codes `/root/workspaces/tools/bin/ship-post` in `ecosystem.config.js`.

## 9. Тесты и CI

`bin/ship-post-test` is the isolated behavioural suite for submit, courier, receipts, watcher and actor parity. `bin/ship-test` exercises the lower `ship` delivery flow. `bin/ship-doc-check` fails a chain-script diff without this document and checks every backticked anchor in the `file:function` form. `bin/ship-doc-check-test` covers its four required temporary-repository cases.

`tools-smoke` has no `paths:` filter, so pull requests always create a run for `ga_ci_wait`. On pull requests it runs the doc gate and only runs `ship-test` when the delivery chain or `bin/ship-test` changed; pushes to `main` run `ship-test` unconditionally.

## 10. Ссылки

- [spec 099 ship dev/prod](/root/workspaces/projects/specs/099-ship-dev-prod/)
- [LAWS-PROCEDURES.md, «Ветки агентов»](/root/workspaces/projects/docs/LAWS-PROCEDURES.md)
