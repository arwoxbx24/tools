# RECOVERY — подъём сервера из резервной копии

## Владельцу (не разработчик)

Сервер умер или нужен новый — арендуй чистый сервер **Ubuntu 24.04**, зайди в него, запусти любого агента (Claude Code, Codex) и скажи:

> Склонируй репозиторий github.com/arwoxbx24/tools (если GitHub недоступен — gitlab.com/arwox24-group/tools), прочитай RECOVERY.md и подними сервер по нему. Подтверди, что понял, и спрашивай меня, что нужно.

Агент сам спросит вход и пароли. Пароль копии (restic) есть только у тебя — без него копию не открыть.

## Агенту — порядок работы

Работай по шагам, после каждой фазы показывай владельцу итог одной строкой. Технических вопросов владельцу не задавай — только вход, ключ, пароль, оплата.

### 1. Спроси у владельца
1. Спроси вход в GitHub: `gh auth login` (репо приватные). Нет GitHub — спроси вход в GitLab.
2. Спроси пароль restic (RESTIC_PASSWORD) — хранится у владельца офлайн, восстановить его нельзя.
3. Спроси ключ S3 Yandex Cloud (AWS_ACCESS_KEY_ID и AWS_SECRET_ACCESS_KEY). Ключа нет — спроси вход в Yandex Cloud (`yc init`) и выпусти новый: `yc iam access-key create --service-account-name server-backup-sa`.
4. В конце спроси владельца сменить DNS доменов на IP нового сервера (если сервер новый).

Секреты не печатай и не коммить; держи их только в файлах `/tmp/repo.env` и `/tmp/pw.env` с правами 600.

### 2. Подготовка
```bash
apt-get update
apt-get install -y git curl bzip2 gh
cd /tmp
curl -fsSLO https://github.com/restic/restic/releases/download/v0.19.1/restic_0.19.1_linux_amd64.bz2
curl -fsSLO https://github.com/restic/restic/releases/download/v0.19.1/SHA256SUMS
grep restic_0.19.1_linux_amd64.bz2 SHA256SUMS | sha256sum -c -     # должно быть OK, иначе стоп
bunzip2 restic_0.19.1_linux_amd64.bz2
install -m 755 restic_0.19.1_linux_amd64 /usr/local/bin/restic
restic version
gh auth login            # вход владельца (шаг 1.1)
gh auth setup-git        # без этого git clone приватного репо спросит пароль
git clone https://github.com/arwoxbx24/tools /tmp/tools
```
GitHub недоступен — тот же код в GitLab: `git clone https://gitlab.com/arwox24-group/tools.git /tmp/tools` (логин и токен GitLab — спроси у владельца).
Файлы окружения (значения — от владельца):
```bash
# /tmp/repo.env (chmod 600)
AWS_ACCESS_KEY_ID=<от владельца>
AWS_SECRET_ACCESS_KEY=<от владельца>
RESTIC_REPOSITORY=s3:https://storage.yandexcloud.net/arwox-server-backup
# /tmp/pw.env (chmod 600)
RESTIC_PASSWORD=<от владельца>
```

### 3. Проверка копии
```bash
set -a; . /tmp/repo.env; . /tmp/pw.env; set +a
restic snapshots --tag server --latest 3
```
Ожидание: есть снимки с тегом `server` за последние дни. Ошибка пароля — снова спроси пароль у владельца. Ошибка доступа — спроси ключ S3 (шаг 1.3).

### 4. Восстановление — по одной фазе
Каждая фаза отдельно, следующая — только после успешной. Скрипт и restic берутся из /tmp: фаза 2 перезаписывает /root/workspaces/tools из снимка.
```bash
cp /tmp/tools/restore.sh /tmp/restore.sh
export RESTIC=/usr/local/bin/restic
bash /tmp/restore.sh --phase 0 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # сухой прогон: что будет сделано
bash /tmp/restore.sh --phase 2 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # файлы из снимка server в / (workspaces, /etc, конфиги /root, /var/www)
bash /tmp/restore.sh --phase 1 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # пакеты apt/pip/npm/snap по спискам из копии
bash /tmp/restore.sh --phase 3 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # базы на хосте: PostgreSQL, Redis, Grafana
bash /tmp/restore.sh --phase 4 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # docker compose и тома
bash /tmp/restore.sh --phase 5 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # pm2 resurrect — запуск сервисов и ботов
bash /tmp/restore.sh --phase 6 --repo-env /tmp/repo.env --pw-env /tmp/pw.env   # crontab root
```
- Порядок 2 → 1 → 3 → 4 → 5 → 6 тот же, что у `--phase all`. 2 раньше 1: списки пакетов лежат в копии.
- Фаза 2 не трогает сеть и диски нового сервера: `/etc/fstab`, `/etc/netplan`, `/etc/hostname`, `/etc/hosts`, `/etc/machine-id`, `/etc/ssh`, `/etc/cloud`, `/etc/resolv.conf` остаются свои.
- Фаза 1 сама ставит node v20.19.4 с nodejs.org в `/root/.nvm/versions/node/` (по этому пути его ждут сервисы) и в конце печатает `ok=N failed=M`.
- `/usr/local` в копии нет. Между фазами 1 и 5 поставь pm2 той же версии и верни пути, которые ждёт обёртка `/root/bin/pm2`:
  ```bash
  export PATH=/root/.nvm/versions/node/v20.19.4/bin:$PATH
  npm install -g pm2@6.0.14
  ln -sf /root/.nvm/versions/node/v20.19.4/bin/node /usr/local/bin/node
  ln -sf /root/.nvm/versions/node/v20.19.4/bin/pm2 /usr/local/bin/pm2
  ``` Пакеты из строк `FAIL:` поставь по официальной документации продукта (docker — docs.docker.com/engine/install/ubuntu). Без docker не начинай фазу 4, без pm2 — фазу 5.
- Нужен не последний снимок — добавь `--snapshot <id>` из шага 3.

### 5. Проверка после
```bash
pm2 list                 # сервисы online
docker ps                # контейнеры Up
crontab -l               # задания на месте
pm2 describe server-backup
```
Ночной бэкап (03:30) должен снова писать в тот же репозиторий: после первой ночи — `tail /root/workspaces/system/tools/scripts/logs/server-backup.log`, строка `SUMMARY backup_rc=0`.

### 6. Чего в копии нет — делается заново
- `~/.ssh` — ключи SSH: владелец добавляет свой ключ заново при аренде сервера.
- `~/.local` — CLI агентов (claude, opencode, pnpm, uv, pipx): переустановить штатными установщиками.
- `/usr/local/bin` — свои команды сервера (`bd`, `cl`, `agent-*`, `arwox-mail`, `teamlead` и др.): после подъёма сверь с `ls /root/workspaces/tools/bin` и поставь недостающие по их README.
- DNS доменов — владелец меняет IP у регистратора (шаг 1.4).
- GitHub Actions runner — может потребовать новую регистрацию токеном из настроек репо.

После успеха удали `/tmp/repo.env` и `/tmp/pw.env`.

Подробности устройства копии — runbook `docs/solutions/2026-09-15-server-backup-restic-yandex.md` в репо github.com/arwoxbx24/agent-contour.
