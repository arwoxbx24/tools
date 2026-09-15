#!/usr/bin/env bash
# Ежедневный restic-бэкап критичных данных сервера.
set -u

RESTIC=/root/workspaces/tools/bin/restic
S3_ENV=/root/workspaces/secrets/yandex-s3.env
PW_ENV=/root/workspaces/secrets/restic.env
LOG=/root/workspaces/system/tools/scripts/logs/server-backup.log
NOTIFY_ENV=/root/workspaces/projects/hh-scoring/data/notify.env
STAGE=/root/workspaces/system/tools/scripts/data/server-backup-stage

mkdir -p "$(dirname "$LOG")" "$STAGE"
log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

send_telegram() { # text
  local token="" chat=""
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    log "telegram skipped (no token/chat): $1"
    return 0
  fi
  curl -s --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" >/dev/null 2>&1 \
    || log "telegram send failed"
}

run_step() { # name command...
  local name="$1" rc
  shift
  timeout 3600 "$@" >>"$LOG" 2>&1
  rc=$?
  log "$name rc=$rc"
  return "$rc"
}

fail() { # step rc [exit]
  local step="$1" rc="$2" code="${3:-1}"
  send_telegram "🚨 server-backup: ${step} rc=${rc}, лог ${LOG}"
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
LATEST_SNAP=$(ls -1 /root/backups/docker 2>/dev/null | sort | tail -1)

timeout 3600 "$RESTIC" cat config >/dev/null 2>&1
config_rc=$?
log "config rc=$config_rc"
if [ "$config_rc" -ne 0 ]; then
  run_step init "$RESTIC" init
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
)
[ -n "$LATEST_SNAP" ] && paths+=("/root/backups/docker/$LATEST_SNAP")

backup_paths=()
for path in "${paths[@]}"; do
  [ -e "$path" ] && backup_paths+=("$path")
done

run_step backup "$RESTIC" backup --tag server --one-file-system \
  --exclude-caches --exclude node_modules --exclude .venv --exclude venv \
  --exclude __pycache__ --exclude .cache --exclude .worktrees --exclude .repowise \
  --exclude '*.pyc' --exclude /root/workspaces/system/archives --exclude /root/.pm2/logs \
  --exclude /root/.claude/file-history --exclude /root/.claude/paste-cache \
  --exclude /root/.claude/projects --exclude /root/.claude/jobs "${backup_paths[@]}"
backup_rc=$?
case "$backup_rc" in 0|3) ;; *) fail backup "$backup_rc" ;; esac

run_step forget "$RESTIC" forget --tag server --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
forget_rc=$?
case "$forget_rc" in 0|3) ;; *) fail forget "$forget_rc" ;; esac

check_rc=0
if [ "$(date +%u)" = 7 ]; then
  run_step check "$RESTIC" check --read-data-subset=5%
  check_rc=$?
  case "$check_rc" in 0|3) ;; *) fail check "$check_rc" ;; esac
else
  log "check rc=0 (не воскресенье)"
fi

stats_output=$(timeout 3600 "$RESTIC" stats --mode raw-data latest 2>&1)
stats_rc=$?
printf '%s\n' "$stats_output" >>"$LOG"
log "stats rc=$stats_rc"
stats_size=$(printf '%s\n' "$stats_output" | awk -F': ' '/^Total Size:/ {print $2; exit}')
log "SUMMARY backup_rc=$backup_rc forget_rc=$forget_rc check_rc=$check_rc stats=${stats_size:-unknown}"
case "$stats_rc" in 0|3) ;; *) fail stats "$stats_rc" ;; esac

exit 0
