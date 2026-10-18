# ТЗ dcfg-demsy.23.2 — ротация журнала уборки /var/log/disk-rotate.log
FILE: etc/disk-rotate-logrotate.conf
Проверка: `logrotate -d -s "$(mktemp)" etc/disk-rotate-logrotate.conf` → rc 0, в выводе есть `/var/log/disk-rotate.log` и нет `error`.

## Зачем (замер 18.10)
`/var/log/disk-rotate.log` — 1.49 ГБ без ротации; диск 99%, свободно ~1.4 ГиБ. `scripts/disk-rotate.sh` уже вызывает logrotate с этим конфигом (`cleanup_always`: `logrotate -s "$DR_LOGROTATE_STATE" etc/disk-rotate-logrotate.conf`, в dry-run с `-d`), но правила для его собственного журнала нет.

## Правка
Добавить второй блок для `/var/log/disk-rotate.log` по образцу существующего блока (тот же стиль комментария спеки), с отличием: **без `copytruncate`, с `create`** (ADR-3 dcfg-demsy.23: copytruncate сначала копирует файл — 1.5 ГБ при ~1.4 ГиБ свободных = ENOSPC; переименование места не требует). Параметры: `size 5M`, `rotate 9999`, `dateext`, `dateformat -%Y%m%d-%s`, `compress` (без `delaycompress`), `create`, `missingok`, `notifempty`, `nomail`, `su root root` (`/var/log` — 775 root:syslog). Одна строка комментария — почему без copytruncate. Существующий блок не менять.

## Проверить и доложить (не править)
Пишет ли `scripts/disk-rotate.sh` в `$DR_LOG` только перенаправлениями `>>"$DR_LOG"` на каждую команду или держит открытый дескриптор (`exec …>>"$DR_LOG"`, перенаправление в cron). Ответ — строка `файл:строка`.

## Запреты
Только этот файл. Без запуска logrotate без `-d`, без правки `/var/log` и `/etc`, без коммита, push, PR.

## Готово, когда
Проверка выше rc 0; `grep -c copytruncate etc/disk-rotate-logrotate.conf` = 1 (только старый блок); в выводе `-d` для `/var/log/disk-rotate.log` нет `copying` / `truncating`.
