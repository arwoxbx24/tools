# ТЗ dcfg-xrxyr — pm2-boot --only применяет env из ecosystem

Атом: dcfg-xrxyr (discovered-from dcfg-hof2v). Worktree: `/root/workspaces/tools/.worktrees/claude/dcfg-xrxyr`. Разведка — repowise; индекс: repowise/CBM проверен.

## Проблема (факты)
- `bin/pm2-boot:166` — `startOrReload "$ECO" --only "$ONLY"` без `--update-env`.
- `pm2 --help`: «-a --update-env  force an update of the environment with restart/reload».
- После `pm2-boot --only forms-gw-guard-test` тестовый сторож по-прежнему видит `TG_BOT_TOKEN`: в логе «bot StatusTrackers_bot» (`forms-gw-guard.sh:349`), хотя live `ecosystem.config.js:256` содержит `GUARD_NOTIFY: '0'`.

## U1. Правки
1. `bin/pm2-boot:166`: добавить `--update-env` в конец команды. Строки 173 и 177 не трогать.
2. `ecosystem.config.js:256` (блок `forms-gw-guard-test`, `env`): после `NPM_HOST_ID: '39'` добавить `, GUARD_NOTIFY: '0'` — та же строка, что уже стоит в живой копии tools.

## Угрозы и откат
- Затрагивает только путь `--only`; полный boot (173/177) без изменений.
- Откат: `git revert` коммита атома.

## Запреты
Не трогать другие строки и файлы, pm2 не перезапускать, секреты не читать.

## Готово, когда
1. `grep -n update-env bin/pm2-boot` → строка 166.
2. `bash -n bin/pm2-boot` rc 0; `node --check ecosystem.config.js` rc 0.
3. `git diff --stat` — только `bin/pm2-boot`, `ecosystem.config.js`, это ТЗ.
