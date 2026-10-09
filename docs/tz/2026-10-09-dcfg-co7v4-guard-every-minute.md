# ТЗ dcfg-co7v4 — боевой forms-gw-guard: проверка раз в минуту + свой GUARD_STATE_DIR

Исполнитель пишет код сам, code-channel не вызывает. Разведка — repowise (индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`); читать только указанные строки. Секреты, .env не читать. pm2, yc, сеть, DNS, git push не вызывать. Правка только `ecosystem.config.js` строк 233 и 236, без новой логики.

## Цель владельца 09.10
Бесшовное автопереключение боевой формы на резерв. Живой тест 15:47: сторож по cron */15 + 2 провала подряд = реакция ≥30 мин. Ложные тревоги закрыты атомом dcfg-20zl3 (forms-gw-guard.sh, PASS 33/33).

## Факты (grep -n этого хода)
- `ecosystem.config.js:233` — `cron_restart: '*/15 * * * *',` (боевой `forms-gw-guard`).
- `:236` — env боевого без `GUARD_STATE_DIR`.
- Образец — тестовый сторож: `:253` `cron_restart: '* * * * *',`; `:256` `GUARD_STATE_DIR: '/root/workspaces/projects/arwox-v3-src/forms-failover/state/gw-guard-test'`.
- `forms-gw-guard.sh:230` — `mkdir -p "$GUARD_STATE_DIR"` (каталог создаётся сам).

## U1
1. `:233` → `cron_restart: '* * * * *',`.
2. `:236` → добавить `GUARD_STATE_DIR: '/root/workspaces/projects/arwox-v3-src/forms-failover/state/gw-guard-prod'` после `...formsGwGuardEnv,`. Остальные ключи не менять.

## Критерии
1. `node -e "const c=require('./ecosystem.config.js');const a=c.apps.find(x=>x.name==='forms-gw-guard');console.log(a.cron_restart, a.env.GUARD_STATE_DIR)"` → `* * * * * /root/workspaces/projects/arwox-v3-src/forms-failover/state/gw-guard-prod`.
2. `git diff --stat` — только `ecosystem.config.js` (2 строки) и этот ТЗ.

## Откат
`git revert`; `pm2 startOrReload ecosystem.config.js --only forms-gw-guard`.

## Паспорт источников
- Факты — `grep -n` этого хода; образец — тестовый сторож `ecosystem.config.js:253,256`.
