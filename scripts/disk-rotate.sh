#!/bin/bash
# Ежедневная чистка диска. Владелец: Александр. Обновлено 22.09.2026.
#
# Единственная граница уборки — массив DENY_LIST ниже (см. spec:054). Он
# приоритетнее любых правил: путь, попадающий под паттерн, не удаляется никогда.
# Docker-контейнеры и тома не удаляются никогда (ни docker rm/volume rm, ни
# docker system prune --volumes).
#
# Лог: /var/log/disk-rotate.log
set -u
LOG=/var/log/disk-rotate.log
DISK_ALERT_PCT=85
LOCK=/var/run/disk-rotate.lock
NOTIFY_ENV=${NOTIFY_ENV:-/root/workspaces/secrets/services/pm2-notify.env}
ECOSYSTEM="${0%/*}/../ecosystem.config.js"

# Коды возврата (spec:054 п.4)
RC_ALERT_FAILED=1
RC_USAGE=2
RC_RESERVED=3   # зарезервирован: «классы исчерпаны, занятость выше 88%» (следующий атом)
RC_LOCKED=4

# Запретный список — единственное место, где задана граница уборки.
DENY_LIST=(
  '/root/backups/**'
  '/root/workspaces/secrets/**'
  '/root/.codex/**'
  '**/hh-scoring*/**'
  '/root/.local/share/uv/**'
  '/home/gitmirror/**'
)

denied() { # path -> 0 если путь в запретном списке
  local p=$1 pat
  for pat in "${DENY_LIST[@]}"; do
    [[ "$p" == $pat ]] && return 0
  done
  return 1
}

MODE=run
case "${1:-}" in
  '')               MODE=run ;;
  --dry-run)        MODE=dry-run ;;
  --report)         MODE=report ;;
  --check-declared) MODE=check ;;
  --help)
    cat <<'EOF'
Usage: disk-rotate.sh [--dry-run|--report|--check-declared|--help]
  (нет аргументов)  обычный прогон из cron: уборка + алерт при необходимости
  --dry-run         ничего не удаляет; печатает перечень кандидатов и прогноз
  --report          только измерение и строка в лог; без уборки и алерта
  --check-declared  сверяет пути скриптов из crontab и ecosystem.config.js
  --help            этот перечень
EOF
    exit 0
    ;;
  *)
    echo "unknown flag: $1" >&2
    exit $RC_USAGE
    ;;
esac

# Взаимное исключение прогонов: неблокирующий flock во всех режимах, кроме help.
exec 9>"$LOCK" || exit $RC_USAGE
if ! flock -n 9; then
  echo "LOCKED другой прогон идёт" >>"$LOG"
  exit $RC_LOCKED
fi

echo "=== $(date '+%F %T') ${MODE^^} START ===" >>"$LOG"
df -h / | tail -1 >>"$LOG"

now=$(date +%s)
TOTAL_KB=0

declared_paths() {
  {
    crontab -l 2>/dev/null | grep -oE '/[^[:space:]]+' | grep -E '(scripts?/|\.sh$|\.py$|\.js$)' | sed -E 's/:[0-9]+$//'
    grep -oE "script: *'[^']+'" "$ECOSYSTEM" 2>/dev/null | sed -E "s/script: *'([^']+)'/\1/"
  } | grep '^/' | sort -u
}

# --report: только измерение и строка в лог; без уборки и алерта.
if [ "$MODE" = report ]; then
  echo "report: $(df -P / | awk 'NR==2 {print $5}') use" >>"$LOG"
  echo "=== $(date '+%F %T') END ===" >>"$LOG"
  exit 0
fi

# --check-declared: сверка объявленных путей с файловой системой; без уборки.
if [ "$MODE" = check ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -e "$p" ]; then
      echo "MISSING $p" | tee -a "$LOG"
    fi
  done <<<"$(declared_paths)"
  echo "=== $(date '+%F %T') END ===" >>"$LOG"
  exit 0
fi

# Кандидаты ходят сюда: в dry-run печатаются, иначе удаляются. Все проверены по DENY_LIST.
handle() { # class; читает пути из stdin (NUL)
  local cls=$1 p kb age
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    denied "$p" && continue
    if [ "$MODE" = dry-run ]; then
      kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      age=$(( (now - $(stat -c %Y "$p" 2>/dev/null)) / 86400 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t%sd\t%s\n' "$p" "$kb" "$age" "$cls"
    else
      rm -rf -- "$p" 2>/dev/null
    fi
  done
}

# find-правки на каталогах-кэшах: в run — fast -delete, в dry-run — список кандидатов.
clean_dir() { # base mtime class [extra find args...]
  local base=$1 mtime=$2 cls=$3; shift 3
  denied "$base" && return
  if [ "$MODE" = dry-run ]; then
    find "$base" -mindepth 1 -mtime "+$mtime" "$@" -print0 2>/dev/null | handle "$cls"
  else
    find "$base" -mindepth 1 -mtime "+$mtime" "$@" -delete 2>/dev/null
  fi
}

# --- кэши пакетных менеджеров (безопасно, скачается заново) ---
clean_dir /root/.cache/pip     1 pip-cache
clean_dir /root/.npm/_npx      1 npm-npx
clean_dir /root/.npm/_cacache  1 npm-cacache
clean_dir /root/.nvm/.cache    1 nvm-cache
clean_dir /var/lib/snapd/cache 1 snapd-cache

if [ "$MODE" != dry-run ]; then
  apt-get clean >>"$LOG" 2>&1

  # --- мусор docker: только сборочный кэш и висячие слои; образы/контейнеры/тома НЕ трогаем ---
  docker builder prune -a -f >>"$LOG" 2>&1
  docker image prune -f      >>"$LOG" 2>&1   # без -a: используемые образы остаются
fi

# --- диагностические логи CI-раннеров ---
clean_dir /opt/actions-runner/_diag    1 runner-diag -type f
clean_dir /root/actions-runner-2/_diag 1 runner-diag -type f

# --- архивы сессий Claude ---
clean_dir /root/.claude/projects     2 claude-sessions -name '*.jsonl'
clean_dir /root/.claude/jobs         2 claude-jobs -type f
clean_dir /root/.claude/paste-cache  2 claude-paste -type f
clean_dir /root/.claude/file-history 3 claude-filehistory -type f

# --- логи ---
if [ "$MODE" != dry-run ]; then
  journalctl --vacuum-size=200M >>"$LOG" 2>&1
fi
if [ "$MODE" = dry-run ]; then
  find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' \) -mtime +1 -print0 2>/dev/null | handle old-logs
else
  find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' \) -mtime +1 -delete 2>/dev/null
fi

# --- временные файлы ---
if [ "$MODE" = dry-run ]; then
  find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -print0 2>/dev/null | handle tmp-old
else
  find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -exec rm -rf {} + 2>/dev/null
fi

# --- отработавшие worktree агентов (только незанятые); в dry-run не удаляем ---
if [ "$MODE" = run ]; then
  for d in /root/workspaces/projects/.claude/worktrees/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    denied "$d" && continue
    ls -l /proc/*/cwd 2>/dev/null | grep -q "$n" && continue   # занят — пропускаем
    git -C /root/workspaces/projects worktree remove --force "$d" >>"$LOG" 2>&1
  done
  git -C /root/workspaces/projects worktree prune >>"$LOG" 2>&1

  # --- старые бинарники Claude Code ---
  ls -1 /root/.local/share/claude/versions 2>/dev/null | sort -V | head -n -2 | while IFS= read -r v; do
    p="/root/.local/share/claude/versions/$v"
    denied "$p" || rm -f "$p"
  done

  # --- размер томов Docker ---
  du -sh /var/lib/docker/volumes 2>/dev/null >>"$LOG"
fi

# --- алерт о заполнении диска (только обычный прогон) ---
ALERT_FAILED=0
send_alert() { # text
  local token="" chat="" code
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    echo "ALERT-FAILED no token/chat" >>"$LOG"
    ALERT_FAILED=1
    return 1
  fi
  code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" 2>/dev/null)
  if [ "$code" != "200" ]; then
    echo "ALERT-FAILED code $code" >>"$LOG"
    ALERT_FAILED=1
    return 1
  fi
  return 0
}

if [ "$MODE" = run ]; then
  pct=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
  if [ "$pct" -ge "$DISK_ALERT_PCT" ]; then
    top=$(du -xsh /root/workspaces /var/lib/docker /root/backups /root/.local /tmp 2>/dev/null | sort -rh | head -5)
    send_alert "🚨 Диск ${pct}% после disk-rotate. Top: $top"
  fi

  F=/root/workspaces/system/tools/scripts/data/server-backup.last-ok
  now2=$(date +%s)
  last_ok=0
  [ -f "$F" ] && last_ok=$(cat "$F")
  if [ ! -f "$F" ] || [ $((now2 - last_ok)) -gt 129600 ]; then
    echo "server-backup dead-man: последний успешный прогон старше 36 ч (или не было)" >>"$LOG"
    send_alert "🚨 server-backup: последний успешный прогон старше 36 ч (или не было) — проверить pm2 server-backup"
  fi
fi

df -h / | tail -1 >>"$LOG"

# Итог dry-run: суммарный объём и прогноз занятости (диск при этом не меняется).
if [ "$MODE" = dry-run ]; then
  total_kb=$(df -P / | awk 'NR==2 {print $2}')
  freed_pct=$(awk -v k="$TOTAL_KB" -v t="$total_kb" 'BEGIN{ if (t>0) printf "%.2f", (k/t)*100; else printf "0" }')
  pct_now=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
  forecast=$(awk -v p="$pct_now" -v f="$freed_pct" 'BEGIN{ printf "%.1f", p-f }')
  echo "total candidates: ${TOTAL_KB}K"
  echo "use now: ${pct_now}% ; forecast after cleanup: ${forecast}% (dry-run, disk unchanged)"
fi

echo "=== $(date '+%F %T') END ===" >>"$LOG"

if [ "$MODE" = run ] && [ "$ALERT_FAILED" -eq 1 ]; then
  exit $RC_ALERT_FAILED
fi
exit 0
