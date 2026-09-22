#!/bin/bash
# Ежедневная чистка диска. Владелец: Александр. Обновлено 22.09.2026 (spec:054).
#
# Единственная граница уборки — массив DENY_LIST ниже. Он приоритетнее любых
# правил: путь, попадающий под паттерн, не удаляется никогда.
# Docker-контейнеры и тома не удаляются никогда (ни docker rm/volume rm, ни
# docker system prune --volumes). Snap-пакеты удаляются только через `snap remove`.
#
# Классы уборки (по занятости диска):
#   cache  — при soft (>=80) и выше
#   trash  — только при hard (>=90)
#   images — только при hard (>=90)
#
# Лог: /var/log/disk-rotate.log
# Ledger: /var/log/disk-rotate-ledger.tsv
set -u
LOG=/var/log/disk-rotate.log
LEDGER=${LEDGER:-/var/log/disk-rotate-ledger.tsv}
ALERT_STATE_FILE=/var/log/disk-rotate-alert-state.tsv
LOCK=/var/run/disk-rotate.lock
NOTIFY_ENV=${NOTIFY_ENV:-/root/workspaces/secrets/services/pm2-notify.env}
ECOSYSTEM="${0%/*}/../ecosystem.config.js"

SOFT_PCT=${SOFT_PCT:-80}
HARD_PCT=${HARD_PCT:-90}
TRASH_AGE_DAYS=${TRASH_AGE_DAYS:-14}
EXHAUSTED_PCT=88

# Коды возврата (spec:054)
RC_ALERT_FAILED=1
RC_USAGE=2
RC_EXHAUSTED=3   # классы исчерпаны, занятость после уборки выше 88%
RC_LOCKED=4

# Пять каталогов для top5 и алертов (spec:054).
TOP5_DIRS=(/root/workspaces /var/lib/docker /root/backups /root/.local /tmp)
TOP5_NAMES=(workspaces docker backups local tmp)

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

denied_top() { # dir -> 0 если сам каталог напрямую входит в запретный список
  local p=$1 pat base
  for pat in "${DENY_LIST[@]}"; do
    base="${pat%/\*\*}"
    [ "$p" = "$base" ] && return 0
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
  (нет аргументов)  обычный прогон из cron: уборка по классам + алерт при необходимости
  --dry-run         ничего не удаляет; печатает перечень кандидатов и прогноз
  --report          только измерение и строка в ledger; без уборки и алерта
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
ts=$(date '+%Y-%m-%dT%H:%M:%S')
TOTAL_KB=0
ALERT_SENT=0
ALERT_FAIL=0
ALERT_RESULT=none

use_pct() { df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'; }
used_kb() { df -P / | awk 'NR==2 {print $3}'; }

# --- счётчик «объявленное существует» (spec:054 п.4) ---
declared_paths() { # источник: crontab | ecosystem
  local src=$1
  if [ "$src" = crontab ]; then
    crontab -l 2>/dev/null | grep -oE '/[^[:space:]]+' \
      | grep -E '(scripts?/|\.sh$|\.py$|\.js$)' | sed -E 's/:[0-9]+$//' | grep '^/' | sort -u
  else
    grep -oE "script: *'[^']+'" "$ECOSYSTEM" 2>/dev/null | sed -E "s/script: *'([^']+)'/\1/" | grep '^/' | sort -u
  fi
}

check_declared() { # -> stdout: строки «источник | путь»; global DECLARED_MISSING
  local src p missing=0
  for src in crontab ecosystem; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ ! -e "$p" ]; then
        printf '%s | %s\n' "$src" "$p"
        missing=$((missing + 1))
      fi
    done <<<"$(declared_paths "$src")"
  done
  DECLARED_MISSING=$missing
}

# --- ledger (spec:054 п.3) ---
ledger_init() {
  [ -s "$LEDGER" ] && return
  printf 'ts\tmode\tpct_before\tpct_after\tfreed_mb\tstate\talert\ttop5\tdeclared_missing\n' >"$LEDGER"
}

ledger_top5() { # имя=вес:дельта; разделитель ';'; дельта к последней строке live
  local i n w lastw delta out="" base seg
  base=$(awk -F'\t' '$2=="live"{last=$8} END{if (last!="") print last}' "$LEDGER" 2>/dev/null)
  for i in "${!TOP5_DIRS[@]}"; do
    n="${TOP5_NAMES[$i]}"
    w=$(du -sm "${TOP5_DIRS[$i]}" 2>/dev/null | awk '{print $1}'); w="${w:-0}"
    lastw=""
    if [ -n "$base" ]; then
      for seg in ${base//;/ }; do
        [[ "$seg" == "$n="* ]] && { lastw="${seg#*=}"; lastw="${lastw%%:*}"; break; }
      done
    fi
    if [ -n "$lastw" ] && [[ "$lastw" =~ ^[0-9]+$ ]]; then
      delta=$((w - lastw))
    else
      delta=0
    fi
    out+="$n=$w:${delta};"
  done
  echo "${out%;}"
}

# --- алерт (не больше одного на состояние в сутки) ---
send_alert() { # text -> 0/1
  local token="" chat="" code
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    echo "ALERT-FAILED no token/chat" >>"$LOG"
    return 1
  fi
  code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" 2>/dev/null)
  [ "$code" = "200" ]
}

alert_sent_today() { # состояние
  grep -qF "$1=$(date '+%F')" "$ALERT_STATE_FILE" 2>/dev/null
}

mark_alert() { # состояние
  sed -i "/^$1=/d" "$ALERT_STATE_FILE" 2>/dev/null || true
  echo "$1=$(date '+%F')" >>"$ALERT_STATE_FILE"
}

maybe_alert() { # состояние текст
  local st=$1 txt=$2
  if alert_sent_today "$st"; then
    echo "ALERT-SKIP $st уже сегодня" >>"$LOG"
    return 0
  fi
  if send_alert "$txt"; then
    ALERT_SENT=$((ALERT_SENT + 1))
    mark_alert "$st"
  else
    ALERT_FAIL=$((ALERT_FAIL + 1))
  fi
}

# --check-declared: сверка объявленных путей; без уборки и без строки в ledger.
if [ "$MODE" = check ]; then
  check_declared
  if [ "$DECLARED_MISSING" -gt 0 ]; then
    maybe_alert declared "disk-rotate: $DECLARED_MISSING объявленных скриптов отсутствуют (нужно проверить crontab/ecosystem)"
  fi
  echo "=== $(date '+%F %T') END ===" >>"$LOG"
  exit 0
fi

# Измерение до уборки и состояние.
pct_before=$(use_pct)
used_before=$(used_kb)
if [ "$pct_before" -ge "$HARD_PCT" ]; then
  state=hard
elif [ "$pct_before" -ge "$SOFT_PCT" ]; then
  state=soft
else
  state=below
fi
state_ledger=$state
mode_ledger=live
[ "$MODE" = dry-run ] && mode_ledger=dry
[ "$MODE" = report ] && mode_ledger=report

# «Объявленное существует» — при обычном прогоне (spec:054 п.4).
DECLARED_MISSING=0
if [ "$MODE" = run ]; then
  check_declared
  if [ "$DECLARED_MISSING" -gt 0 ]; then
    echo "DECLARED-MISSING $DECLARED_MISSING" >>"$LOG"
    maybe_alert declared "disk-rotate: $DECLARED_MISSING объявленных скриптов отсутствуют (см. ledger)"
  fi
fi

# Кандидаты ходят сюда: в dry-run печатаются, иначе удаляются. Все проверены по DENY_LIST.
handle() { # class; пути из stdin (NUL)
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

cleanup_cache() { # работает при soft и выше
  # --- кэши пакетных менеджеров (безопасно, скачается заново) ---
  clean_dir /root/.cache/pip     1 cache
  clean_dir /root/.npm/_npx      1 cache
  clean_dir /root/.npm/_cacache  1 cache
  clean_dir /root/.nvm/.cache    1 cache
  clean_dir /var/lib/snapd/cache 1 cache

  # --- артефакты сессий агента старше 3 суток ---
  clean_dir /root/.claude/projects     3 cache -name '*.jsonl'
  clean_dir /root/.claude/jobs         3 cache -type f
  clean_dir /root/.claude/paste-cache  3 cache -type f
  clean_dir /root/.claude/file-history 3 cache -type f

  # --- __pycache__ старше суток в рабочих каталогах (запретный список сильнее класса) ---
  while IFS= read -r -d '' p; do
    denied "$p" && continue
    if [ "$MODE" = dry-run ]; then
      kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      age=$(( (now - $(stat -c %Y "$p" 2>/dev/null)) / 86400 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t%sd\t%s\n' "$p" "$kb" "$age" cache
    else
      rm -rf -- "$p"
    fi
  done < <(find /root/workspaces /root/.local /opt /usr/local -type d -name __pycache__ -mtime +1 -print0 2>/dev/null)

  # --- /tmp/* старше 2 суток ---
  if [ "$MODE" = dry-run ]; then
    find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -print0 2>/dev/null | handle cache
  else
    find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -exec rm -rf {} + 2>/dev/null
  fi

  # --- осиротевшие рабочие копии git: (а) не занята процессом И (б) не менялась >48ч ---
  for d in /root/workspaces/projects/.claude/worktrees/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    denied "$d" && continue
    ls -l /proc/*/cwd 2>/dev/null | grep -q "$n" && continue   # (а) занята процессом
    m=$(stat -c %Y "$d" 2>/dev/null)
    [ -n "$m" ] || continue
    [ $(( now - m )) -lt 172800 ] && continue                 # (б) менялась <48ч
    if [ "$MODE" = dry-run ]; then
      kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      age=$(( (now - m) / 86400 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t%sd\t%s\n' "$d" "$kb" "$age" cache
    else
      git -C /root/workspaces/projects worktree remove --force "$d" >>"$LOG" 2>&1
    fi
  done
  git -C /root/workspaces/projects worktree prune >>"$LOG" 2>&1

  # --- системные очистки кэша (только боевой режим) ---
  if [ "$MODE" = run ]; then
    apt-get clean >>"$LOG" 2>&1
    docker builder prune -a -f >>"$LOG" 2>&1
    docker image prune -f >>"$LOG" 2>&1
    journalctl --vacuum-size=200M >>"$LOG" 2>&1
  fi
}

cleanup_trash() { # работает только при hard
  find /root/workspaces/projects/.agent-work -maxdepth 1 -type d -name 'trash-*' \
    -mtime "+$TRASH_AGE_DAYS" -print0 2>/dev/null | handle trash
  find /root/workspaces/system/archives -maxdepth 2 -type f -name '*.tar.gz' \
    -mtime "+$TRASH_AGE_DAYS" -print0 2>/dev/null | handle trash

  # --- snap: только `snap remove <имя>`; файлы .snap и каталоги snapd не трогаем ---
  while read -r name; do
    [ -n "$name" ] || continue
    if [ "$MODE" = dry-run ]; then
      printf '%s\t-\t-\ttrash\n' "$name"
    else
      snap remove "$name" >>"$LOG" 2>&1
    fi
  done < <(snap list --all 2>/dev/null | awk '
    NR>1 { n=$1; notes=$NF; if (notes ~ /disabled/) d[n]=1; else a[n]=1 }
    END { for (n in d) if (!(n in a)) print n }')
}

cleanup_images() { # работает только при hard
  local refs img
  refs=$(docker ps -aq 2>/dev/null | xargs -r docker inspect -f '{{.Image}}' 2>/dev/null | sort -u)
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    if [ "$MODE" = dry-run ]; then
      bytes=$(docker image inspect -f '{{.Size}}' "$img" 2>/dev/null); bytes="${bytes:-0}"
      kb=$(( bytes / 1024 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t-\timages\n' "$img" "$kb"
    else
      docker rmi "$img" >>"$LOG" 2>&1
    fi
  done < <(docker images --no-trunc -q 2>/dev/null | awk -v refs="$(printf '%s' "$refs")" '
    BEGIN { n=split(refs, a, "\n"); for (i=1; i<=n; i++) used[a[i]]=1 }
    !($0 in used) { print }')
}

# Классы по состоянию диска.
if [ "$MODE" != report ]; then
  if [ "$state" = soft ] || [ "$state" = hard ]; then
    cleanup_cache
  fi
  if [ "$state" = hard ]; then
    cleanup_trash
    cleanup_images
  fi
fi

pct_after=$(use_pct)
used_after=$(used_kb)
case "$MODE" in
  dry-run) freed_mb=$(( TOTAL_KB / 1024 )) ;;
  report)  freed_mb=0 ;;
  *)       freed_mb=$(( (used_before - used_after) / 1024 )) ;;
esac

# Состояние exhausted: классы отработали, а занятость после уборки выше 88% (код 3).
if [ "$MODE" = run ] && [ "$pct_after" -gt "$EXHAUSTED_PCT" ]; then
  state_ledger=exhausted
  owner_list=""
  for i in "${!TOP5_DIRS[@]}"; do
    d="${TOP5_DIRS[$i]}"
    if denied_top "$d"; then
      sz=$(du -sm "$d" 2>/dev/null | awk '{print $1}'); sz="${sz:-0}"
      owner_list+=" ${d}=${sz}M"
    fi
  done
  maybe_alert exhausted "disk-rotate: занятость ${pct_after}% после уборки — требуют решения владельца:${owner_list:- (нет в запретном списке)}"
fi

# Алерты о заполнении диска (soft/hard) — только обычный прогон.
if [ "$MODE" = run ]; then
  if [ "$state" = soft ] || [ "$state" = hard ]; then
    top=$(du -xsh "${TOP5_DIRS[@]}" 2>/dev/null | sort -rh | head -5)
    maybe_alert "$state" "Диск ${pct_after}% после disk-rotate. Top: $top"
  fi

  # dead-man server-backup: последний успешный прогон старше 36 ч (или не было)
  F=/root/workspaces/system/tools/scripts/data/server-backup.last-ok
  last_ok=0
  [ -f "$F" ] && last_ok=$(cat "$F")
  if [ ! -f "$F" ] || [ $((now - last_ok)) -gt 129600 ]; then
    echo "server-backup dead-man: последний успешный прогон старше 36 ч (или не было)" >>"$LOG"
    maybe_alert backup "server-backup: последний успешный прогон старше 36 ч (или не было) — проверить pm2 server-backup"
  fi
fi

[ "$ALERT_SENT" -gt 0 ] && ALERT_RESULT=sent
[ "$ALERT_FAIL" -gt 0 ] && ALERT_RESULT=failed

df -h / | tail -1 >>"$LOG"

# Итог dry-run: суммарный объём и прогноз занятости (диск при этом не меняется).
if [ "$MODE" = dry-run ]; then
  total_kb=$(df -P / | awk 'NR==2 {print $2}')
  freed_pct=$(awk -v k="$TOTAL_KB" -v t="$total_kb" 'BEGIN{ if (t>0) printf "%.2f", (k/t)*100; else printf "0" }')
  pct_now=$(use_pct)
  forecast=$(awk -v p="$pct_now" -v f="$freed_pct" 'BEGIN{ printf "%.1f", p-f }')
  echo "total candidates: ${TOTAL_KB}K"
  echo "use now: ${pct_now}% ; forecast after cleanup: ${forecast}% (dry-run, disk unchanged)"
fi

top5=$(ledger_top5)
ledger_init
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$ts" "$mode_ledger" "$pct_before" "$pct_after" "$freed_mb" \
  "$state_ledger" "$ALERT_RESULT" "$top5" "$DECLARED_MISSING" >>"$LEDGER"

echo "=== $(date '+%F %T') END ===" >>"$LOG"

if [ "$state_ledger" = exhausted ]; then
  exit $RC_EXHAUSTED
fi
if [ "$MODE" = run ] && [ "$ALERT_FAIL" -gt 0 ]; then
  exit $RC_ALERT_FAILED
fi
exit 0
