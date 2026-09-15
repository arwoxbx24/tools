#!/bin/bash
# Ежедневная чистка диска. Владелец: Александр. Обновлено 23.08.2026.
#
# ЗАПРЕЩЕНО ТРОГАТЬ (проверено аварией 23.08):
#   /root/workspaces        — рабочие проекты, прямой запрет владельца
#   /root/.local/share/uv   — НЕ кэш! там живут repowise, semgrep и др.
#                             их удаление ломает индексацию во всех сессиях
#   /home/gitmirror         — зеркала репозиториев, резервные копии
#   docker образы/тома      — используются живыми контейнерами
#
# Лог: /var/log/disk-rotate.log
set -u
LOG=/var/log/disk-rotate.log
DISK_ALERT_PCT=85
NOTIFY_ENV=/root/workspaces/projects/hh-scoring/data/notify.env
echo "=== $(date '+%F %T') START ===" >>"$LOG"
df -h / | tail -1 >>"$LOG"

# --- кэши пакетных менеджеров (безопасно, скачается заново) ---
find /root/.cache/pip     -mindepth 1 -mtime +1 -delete 2>/dev/null
find /root/.npm/_npx      -mindepth 1 -mtime +1 -delete 2>/dev/null
find /root/.npm/_cacache  -mindepth 1 -mtime +1 -delete 2>/dev/null
find /root/.nvm/.cache    -mindepth 1 -mtime +1 -delete 2>/dev/null
find /var/lib/snapd/cache -mindepth 1 -mtime +1 -delete 2>/dev/null
apt-get clean >>"$LOG" 2>&1

# --- мусор docker: только сборочный кэш и висячие слои, образы НЕ трогаем ---
docker builder prune -a -f >>"$LOG" 2>&1
docker image prune -f      >>"$LOG" 2>&1   # без -a: используемые образы остаются

# --- диагностические логи CI-раннеров ---
find /opt/actions-runner/_diag     -type f -mtime +1 -delete 2>/dev/null
find /root/actions-runner-2/_diag  -type f -mtime +1 -delete 2>/dev/null

# --- архивы сессий Claude ---
find /root/.claude/projects     -name '*.jsonl' -mtime +2 -delete 2>/dev/null
find /root/.claude/jobs         -type f -mtime +2 -delete 2>/dev/null
find /root/.claude/paste-cache  -type f -mtime +2 -delete 2>/dev/null
find /root/.claude/file-history -type f -mtime +3 -delete 2>/dev/null

# --- логи ---
journalctl --vacuum-size=200M >>"$LOG" 2>&1
find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' \) -mtime +1 -delete 2>/dev/null

# --- временные файлы ---
find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -exec rm -rf {} + 2>/dev/null

# --- отработавшие worktree агентов (только незанятые) ---
for d in /root/workspaces/projects/.claude/worktrees/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  ls -l /proc/*/cwd 2>/dev/null | grep -q "$n" && continue   # занят — пропускаем
  git -C /root/workspaces/projects worktree remove --force "$d" >>"$LOG" 2>&1
done
git -C /root/workspaces/projects worktree prune >>"$LOG" 2>&1

# --- старые бинарники Claude Code ---
ls -1 /root/.local/share/claude/versions 2>/dev/null | sort -V | head -n -2 | while IFS= read -r v; do
  rm -f "/root/.local/share/claude/versions/$v"
done

# --- размер томов Docker ---
du -sh /var/lib/docker/volumes 2>/dev/null >>"$LOG"

# --- алерт о заполнении диска ---
send_telegram() { # text
  local token="" chat=""
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    echo "telegram skipped (no token/chat): $1" >>"$LOG"
    return 0
  fi
  curl -s --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" >/dev/null 2>&1 \
    || echo "telegram send failed" >>"$LOG"
}

pct=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
if [ "$pct" -ge "$DISK_ALERT_PCT" ]; then
  top=$(du -xsh /root/workspaces /var/lib/docker /root/backups /root/.local /tmp 2>/dev/null | sort -rh | head -5)
  send_telegram "🚨 Диск ${pct}% после disk-rotate. Top: $top"
fi

df -h / | tail -1 >>"$LOG"
echo "=== $(date '+%F %T') END ===" >>"$LOG"
