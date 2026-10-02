#!/usr/bin/env bash
# Ежедневный restic-бэкап критичных данных сервера.
set -u

RESTIC=${RESTIC:-/root/workspaces/tools/bin/restic}
S3_ENV=${S3_ENV:-/root/workspaces/secrets/yandex-s3.env}
PW_ENV=${PW_ENV:-/root/workspaces/secrets/restic.env}
LOG=${LOG:-/root/workspaces/system/tools/scripts/logs/server-backup.log}
NOTIFY_ENV=${NOTIFY_ENV:-/root/workspaces/secrets/services/pm2-notify.env}
STAGE=${STAGE:-/root/workspaces/system/tools/scripts/data/server-backup-stage}
LAST_OK=${LAST_OK:-/root/workspaces/system/tools/scripts/data/server-backup.last-ok}
ALERT_PENDING=${ALERT_PENDING:-/root/workspaces/system/tools/scripts/data/server-backup.alert-pending}
BK_MIRROR_DIR=${BK_MIRROR_DIR:-/home/gitmirror/repos}

# Ночной бэкап — максимально низкий приоритет (nice 19 + ionice idle).
NICE_PREFIX=(nice -n 19)
if command -v ionice >/dev/null 2>&1; then
  NICE_PREFIX=(nice -n 19 ionice -c3)
fi
renice --priority 19 -p $$ >/dev/null 2>&1 || true
printf '[%s] nice=%s\n' "$(date '+%F %T')" "$(ps -o ni= -p $$ | tr -d '[:space:]')" >>"$LOG"

if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt $((5 * 1024 * 1024)) ]; then
  mv -f "$LOG" "$LOG.1"
fi
mkdir -p "$(dirname "$LOG")" "$STAGE"
log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

send_telegram() { # text
  local token="" chat="" rc
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    log "telegram skipped (no token/chat): $1"
    return 1
  fi
  curl -s --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || log "telegram send failed"
  return "$rc"
}

run_step() { # name command...
  local name="$1" rc
  shift
  timeout 3600 "$@" >>"$LOG" 2>&1
  rc=$?
  log "$name rc=$rc"
  return "$rc"
}

stage_manifests() {
  mkdir -p "$STAGE/manifests"
  dpkg --get-selections >"$STAGE/manifests/dpkg-selections.txt" 2>/dev/null || :
  apt-mark showmanual >"$STAGE/manifests/apt-manual.txt" 2>/dev/null || :
  pip3 freeze >"$STAGE/manifests/pip-freeze.txt" 2>/dev/null || :
  pipx list --json >"$STAGE/manifests/pipx.json" 2>/dev/null || :
  uv tool list >"$STAGE/manifests/uv-tools.txt" 2>/dev/null || :
  NPM=$(ls -d /root/.nvm/versions/node/*/bin/npm 2>/dev/null | sort -V | tail -1)
  "$NPM" ls -g --depth=0 >"$STAGE/manifests/npm-global.txt" 2>/dev/null || :
  snap list >"$STAGE/manifests/snap.txt" 2>/dev/null || :
  docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' >"$STAGE/manifests/docker-images.txt" 2>/dev/null || :
  ls -la /usr/local/bin >"$STAGE/manifests/usr-local-bin.txt" 2>/dev/null || :
  systemctl list-unit-files --state=enabled >"$STAGE/manifests/systemd-enabled.txt" 2>/dev/null || :
  { uname -a; lsb_release -a; } >"$STAGE/manifests/os.txt" 2>/dev/null || :
  log "manifests: $(ls "$STAGE/manifests" | wc -l) файлов"
}

stage_host_dumps() {
  local pg=skip redis=skip grafana=skip integrity
  mkdir -p "$STAGE/host-db"

  if systemctl is-active --quiet 'postgresql@16-main'; then
    su - postgres -c pg_dumpall 2>>"$LOG" | gzip >"$STAGE/host-db/pg_dumpall.sql.gz"
    [ -f "$STAGE/host-db/pg_dumpall.sql.gz" ] && [ "$(stat -c%s "$STAGE/host-db/pg_dumpall.sql.gz")" -ge 100 ] && pg=ok
  else
    log "WARNING: postgresql@16-main не запущен"
  fi
  [ -f "$STAGE/host-db/pg_dumpall.sql.gz" ] && [ "$(stat -c%s "$STAGE/host-db/pg_dumpall.sql.gz")" -ge 100 ] || log "WARNING: host-db pg_dumpall.sql.gz пустой"

  if systemctl is-active --quiet redis-server; then
    redis-cli --rdb "$STAGE/host-db/redis-dump.rdb" >>"$LOG" 2>&1 || cp /var/lib/redis/dump.rdb "$STAGE/host-db/redis-dump.rdb"
    [ -f "$STAGE/host-db/redis-dump.rdb" ] && [ "$(stat -c%s "$STAGE/host-db/redis-dump.rdb")" -ge 100 ] && redis=ok
  else
    log "WARNING: redis-server не запущен"
  fi
  [ -f "$STAGE/host-db/redis-dump.rdb" ] && [ "$(stat -c%s "$STAGE/host-db/redis-dump.rdb")" -ge 100 ] || log "WARNING: host-db redis-dump.rdb пустой"

  if [ -f /var/lib/grafana/grafana.db ]; then
    sqlite3 /var/lib/grafana/grafana.db ".backup '$STAGE/host-db/grafana.db'" >>"$LOG" 2>&1
    integrity=$(sqlite3 "$STAGE/host-db/grafana.db" "PRAGMA integrity_check" 2>>"$LOG")
    if [ "$integrity" = ok ]; then
      [ -f "$STAGE/host-db/grafana.db" ] && [ "$(stat -c%s "$STAGE/host-db/grafana.db")" -ge 100 ] && grafana=ok
    else
      log "WARNING: grafana.db integrity_check=$integrity"
    fi
  else
    log "WARNING: grafana.db отсутствует"
  fi
  [ -f "$STAGE/host-db/grafana.db" ] && [ "$(stat -c%s "$STAGE/host-db/grafana.db")" -ge 100 ] || log "WARNING: host-db grafana.db пустой"
  log "host-db: pg=$pg redis=$redis grafana=$grafana"
}

fail() { # step rc [exit]
  local step="$1" rc="$2" code="${3:-1}"
  local alert="🚨 server-backup: ${step} rc=${rc}, лог ${LOG}"
  if ! send_telegram "$alert"; then
    printf '%s\n' "$alert" >"$ALERT_PENDING"
    log "alert queued"
  fi
  exit "$code"
}

set -a
# shellcheck disable=SC1090
source "$S3_ENV"
set +a

if [ ! -f "$PW_ENV" ]; then
  (umask 077; printf 'RESTIC_PASSWORD=%s\n' "$(openssl rand -hex 32)" >"$PW_ENV")
  chmod 600 "$PW_ENV"
  log "restic.env создан — скопировать пароль в менеджер паролей владельца"
fi
set -a
# shellcheck disable=SC1090
source "$PW_ENV"
set +a

# Снимок cron и свежий docker-бэкап.
crontab -l >"$STAGE/crontab-root.txt" 2>>"$LOG" || :
stage_manifests
stage_host_dumps
LATEST_SNAP=$(ls -1 /root/backups/docker 2>/dev/null | sort | tail -1)

curl -s --max-time 10 -o /dev/null https://storage.yandexcloud.net
preflight_rc=$?
if [ "$preflight_rc" -ne 0 ]; then
  log "preflight: S3 недоступен rc=$preflight_rc"
  fail preflight "$preflight_rc" 3
fi

timeout 3600 "${NICE_PREFIX[@]}" "$RESTIC" cat config --retry-lock 30m >/dev/null 2>&1
config_rc=$?
log "config rc=$config_rc"
if [ "$config_rc" -ne 0 ]; then
  run_step init "${NICE_PREFIX[@]}" "$RESTIC" init --retry-lock 30m
  init_rc=$?
  if [ "$init_rc" -ne 0 ]; then
    fail init "$init_rc" 2
  fi
else
  config_rc=0
fi

paths=(
  /root/workspaces/projects /root/workspaces/tools /root/workspaces/system
  /root/workspaces/secrets /root/workspaces/sandbox /root/.claude /root/.config
  /root/.pm2 /root/.codex/config.toml /root/.codex/AGENTS.md /root/.codex/hooks.json
  /root/CLAUDE.md /root/AGENTS.md /root/GEMINI.md /etc /data/minio
  /root/nginx-proxy-manager "$STAGE"
  /root/.claude.json /root/.bashrc /root/.profile /root/.gitconfig /root/.gitignore_global
  /root/.mc /root/.docker /root/.gnupg /root/.beads /root/.dolt /root/.opencode
  /root/.agents /root/ecosystem.config.js /var/www /opt/actions-runner/.runner
  /root/actions-runner-2/.runner /home/claude /home/gitmirror/repos /home/gitmirror/archived-repos
)
paths+=(/root/.tmux*)
[ -n "$LATEST_SNAP" ] && paths+=("/root/backups/docker/$LATEST_SNAP")

backup_paths=()
for path in "${paths[@]}"; do
  [ -e "$path" ] && backup_paths+=("$path")
done

run_step unlock "${NICE_PREFIX[@]}" "$RESTIC" unlock --retry-lock 30m

run_step backup "${NICE_PREFIX[@]}" "$RESTIC" backup --tag server --group-by host,tags --one-file-system \
  --exclude-caches --exclude node_modules --exclude .venv --exclude venv \
  --exclude __pycache__ --exclude .cache --exclude .repowise \
  --exclude '*.pyc' --exclude /root/workspaces/system/archives --exclude /root/.pm2/logs \
  --exclude /root/.claude/file-history --exclude /root/.claude/paste-cache \
  --exclude /root/.claude/projects --exclude /root/.claude/jobs \
  --read-concurrency 1 --limit-upload "${BK_LIMIT_UPLOAD:-5120}" --retry-lock 30m \
  "${backup_paths[@]}"
backup_rc=$?
case "$backup_rc" in 0|3) ;; *) fail backup "$backup_rc" ;; esac
date +%s >"$LAST_OK"

# Сверка числа bare-репозиториев зеркала в S3 с локальным каталогом.
mirror_local=$(ls -d "$BK_MIRROR_DIR"/*.git 2>/dev/null | wc -l)
mirror_s3=$(timeout 3600 "${NICE_PREFIX[@]}" "$RESTIC" ls latest "$BK_MIRROR_DIR" 2>>"$LOG" \
  | grep -Ec '(\.git)?/HEAD$')
log "mirror-check s3=$mirror_s3 local=$mirror_local"
if [ "$mirror_s3" -lt "$mirror_local" ]; then
  fail mirror-check "$((mirror_local - mirror_s3))"
fi

run_step forget "${NICE_PREFIX[@]}" "$RESTIC" forget --tag server --group-by host,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune --retry-lock 30m
forget_rc=$?
case "$forget_rc" in 0|3) ;; *) fail forget "$forget_rc" ;; esac

check_rc=0
if [ "$(date +%u)" = 7 ]; then
  run_step check "${NICE_PREFIX[@]}" "$RESTIC" check --read-data-subset="$(( ($(date +%-d) - 1) / 7 % 4 + 1 ))/4" --retry-lock 30m
  check_rc=$?
  case "$check_rc" in 0|3) ;; *) fail check "$check_rc" ;; esac

  DRILL=/tmp/restic-drill
  rm -rf "$DRILL"
  run_step restore "${NICE_PREFIX[@]}" "$RESTIC" restore latest --target "$DRILL" \
    --include /root/CLAUDE.md --include /root/workspaces/tools/ecosystem.config.js --retry-lock 30m
  restore_rc=$?
  if [ "$restore_rc" -ne 0 ]; then
    rm -rf "$DRILL"
    fail restore "$restore_rc"
  fi
  if ! cmp -s "$DRILL/root/CLAUDE.md" /root/CLAUDE.md \
    || ! cmp -s "$DRILL/root/workspaces/tools/ecosystem.config.js" /root/workspaces/tools/ecosystem.config.js; then
    rm -rf "$DRILL"
    fail restore 1
  fi
  log "restore-drill ok (2 files)"
  rm -rf "$DRILL"
else
  log "check rc=0 (не воскресенье)"
fi

stats_output=$(timeout 3600 "${NICE_PREFIX[@]}" "$RESTIC" stats --mode raw-data latest --retry-lock 30m 2>&1)
stats_rc=$?
printf '%s\n' "$stats_output" >>"$LOG"
log "stats rc=$stats_rc"
stats_size=$(printf '%s\n' "$stats_output" | awk -F': ' '/Total Size:/ {print $2; exit}')
case "$stats_rc" in 0|3) ;; *) fail stats "$stats_rc" ;; esac
log "SUMMARY backup_rc=$backup_rc forget_rc=$forget_rc check_rc=$check_rc stats=${stats_size:-unknown}"
if [ "$(date +%u)" = 7 ]; then
  send_telegram "✅ server-backup: неделя ок, snapshot latest, size ${stats_size:-unknown}, drill ok"
fi

exit 0
