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
DR_LOG=${DR_LOG:-/var/log/disk-rotate.log}
DR_LEDGER=${DR_LEDGER:-${LEDGER:-/var/log/disk-rotate-ledger.tsv}}
DR_STATE_FILE=${DR_STATE_FILE:-/var/lib/disk-rotate/fixed.tsv}
DR_ALERT_STATE_FILE=${DR_ALERT_STATE_FILE:-/var/log/disk-rotate-alert-state.tsv}
DR_LOCK_FILE=${DR_LOCK_FILE:-/var/run/disk-rotate.lock}
DR_LAST_OK=${DR_LAST_OK:-/root/workspaces/system/tools/scripts/data/server-backup.last-ok}
DR_JOURNAL=${DR_JOURNAL:-/var/log/disk-rotate-deletions.tsv}
DR_USAGE_PCT=${DR_USAGE_PCT:-}
DR_NOTIFY_CMD=${DR_NOTIFY_CMD:-}
DR_TEST_ONLY=${DR_TEST_ONLY:-}
DR_TEST_IRREPLACEABLE_DIR=${DR_TEST_IRREPLACEABLE_DIR:-}
DR_TEST_REPLACEABLE_DIR=${DR_TEST_REPLACEABLE_DIR:-}
NOTIFY_ENV=${NOTIFY_ENV:-/root/workspaces/secrets/services/pm2-notify.env}
ECOSYSTEM="${0%/*}/../ecosystem.config.js"
RUN_ID=$(date +%Y%m%d-%H%M%S)
GATE_MODE=${GATE_MODE:-shadow}
if [ "$GATE_MODE" = enforce ]; then
  JOURNAL_MODE=enforce
else
  JOURNAL_MODE=shadow
fi
RESTIC=${RESTIC:-/root/workspaces/tools/bin/restic}

SOFT_PCT=${SOFT_PCT:-80}
HARD_PCT=${HARD_PCT:-90}
TRASH_AGE_DAYS=${TRASH_AGE_DAYS:-14}
EXHAUSTED_PCT=88

# Коды возврата (spec:054)
RC_ALERT_FAILED=1
RC_USAGE=2
RC_EXHAUSTED=3   # классы исчерпаны, занятость после уборки выше 88%
RC_LOCKED=4
RC_GATE_CLOSED=5 # предусловие гейта не выполнено: last-ok стар, репозиторий недоступен

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
  --restore-drill)  MODE=drill ;;
  --help)
    cat <<'EOF'
Usage: disk-rotate.sh [--dry-run|--report|--check-declared|--restore-drill|--help]
  (нет аргументов)  обычный прогон из cron: уборка по классам + алерт при необходимости
  --dry-run         ничего не удаляет; печатает перечень кандидатов и прогноз
  --report          только измерение и строка в ledger; без уборки и алерта
  --check-declared  сверяет пути скриптов из crontab и ecosystem.config.js
  --restore-drill   репетиция восстановления: сверяет последний снимок predelete с живыми файлами
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
exec 9>"$DR_LOCK_FILE" || exit $RC_USAGE
if ! flock -n 9; then
  echo "LOCKED другой прогон идёт" >>"$DR_LOG"
  exit $RC_LOCKED
fi

echo "=== $(date '+%F %T') ${MODE^^} START ===" >>"$DR_LOG"
df -h / | tail -1 >>"$DR_LOG"

now=$(date +%s)
ts=$(date '+%Y-%m-%dT%H:%M:%S')
TOTAL_KB=0
ALERT_SENT=0
ALERT_FAIL=0
ALERT_RESULT=none

# Общий список незаменимых файлов прогона (копится во время классов, фиксируется
# через гейт после них). Создаётся в начале каждого прогона.
IRR_LIST=$(mktemp /tmp/disk-rotate-irr-XXXX) || exit 1

use_pct() {
  if [ -n "$DR_USAGE_PCT" ]; then
    echo "$DR_USAGE_PCT"
  else
    df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'
  fi
}
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

mechanism_status() { # удаляющий скрипт по имени файла -> статус из встроенного списка | UNDECLARED
  local p=$1 b
  b=$(basename "$p")
  case "$b" in
    disk-rotate.sh)                          printf 'stage\n' ;;
    docker-backup.sh|backup-rotation.sh|redis-backup-daemon.sh) printf 'local-copies\n' ;;
    runtime-cache-janitor*)                  printf 'codex-zone\n' ;;
    docker-log-rotation.sh)                  printf 'container-logs\n' ;;
    server-backup.sh)                        printf 'own-drill-dir\n' ;;
    *)                                       printf 'UNDECLARED\n' ;;
  esac
}

print_mechanisms() { # -> таблица удаляющих механизмов: источник | путь | статус; undeclared: N
  local src p status undeclared=0
  for src in crontab ecosystem; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ -f "$p" ] || continue
      grep -Eq 'rm[[:space:]]+-rf|-delete|truncate' "$p" 2>/dev/null || continue
      status=$(mechanism_status "$p")
      [ "$status" = UNDECLARED ] && undeclared=$((undeclared + 1))
      printf '%s | %s | %s\n' "$src" "$p" "$status"
    done <<<"$(declared_paths "$src")"
  done
  printf 'undeclared: %s\n' "$undeclared"
}

# --- ledger (spec:054 п.3) ---
ledger_init() {
  [ -s "$DR_LEDGER" ] && return
  printf 'ts\tmode\tpct_before\tpct_after\tfreed_mb\tstate\talert\ttop5\tdeclared_missing\n' >"$DR_LEDGER"
}

ledger_top5() { # имя=вес:дельта; разделитель ';'; дельта к последней строке live
  local i n w lastw delta out="" base seg
  base=$(awk -F'\t' '$2=="live"{last=$8} END{if (last!="") print last}' "$DR_LEDGER" 2>/dev/null)
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
  local code
  if [ -n "$DR_NOTIFY_CMD" ]; then
    "$DR_NOTIFY_CMD" "$1"
    return $?
  fi
  local token="" chat=""
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -z "$token" ] || [ -z "$chat" ]; then
    echo "ALERT-FAILED no token/chat" >>"$DR_LOG"
    return 1
  fi
  code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat}" --data-urlencode "text=$1" 2>/dev/null)
  [ "$code" = "200" ]
}

alert_sent_today() { # состояние
  grep -qF "$1=$(date '+%F')" "$DR_ALERT_STATE_FILE" 2>/dev/null
}

mark_alert() { # состояние
  sed -i "/^$1=/d" "$DR_ALERT_STATE_FILE" 2>/dev/null || true
  echo "$1=$(date '+%F')" >>"$DR_ALERT_STATE_FILE"
}

maybe_alert() { # состояние текст
  local st=$1 txt=$2
  if alert_sent_today "$st"; then
    echo "ALERT-SKIP $st уже сегодня" >>"$DR_LOG"
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
  print_mechanisms
  echo "=== $(date '+%F %T') END ===" >>"$DR_LOG"
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
if [ "$MODE" = run ] && [ "$DR_TEST_ONLY" != 1 ]; then
  check_declared
  if [ "$DECLARED_MISSING" -gt 0 ]; then
    echo "DECLARED-MISSING $DECLARED_MISSING" >>"$DR_LOG"
    maybe_alert declared "disk-rotate: $DECLARED_MISSING объявленных скриптов отсутствуют (см. ledger)"
  fi
fi

# Кандидаты ходят сюда: в dry-run печатаются, иначе удаляются. Все проверены по DENY_LIST.
journal_row() { # class action path size snapshot restore reason -> 10-колоночная строка в $DR_JOURNAL
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" "$RUN_ID" "$JOURNAL_MODE" "$@" >>"$DR_JOURNAL"
}

restic_env() { # задать RESTIC_REPOSITORY/RESTIC_PASSWORD_FILE из DR_RESTIC_REPO или env-файлов
  RESTIC=${RESTIC:-/root/workspaces/tools/bin/restic}
  if [ -n "${DR_RESTIC_REPO:-}" ]; then
    export RESTIC_REPOSITORY="$DR_RESTIC_REPO" RESTIC_PASSWORD_FILE="$DR_RESTIC_PASSWORD_FILE"
  else
    set -a
    # shellcheck disable=SC1090
    source "/root/workspaces/secrets/yandex-s3.env"
    # shellcheck disable=SC1090
    source "/root/workspaces/secrets/restic.env"
    set +a
  fi
}

gate_open() { # -> 0 если предусловие гейта выполнено; иначе печатает причину в GATE_REASON и 1
  GATE_REASON=
  local last_ok now_s
  if [ ! -f "$DR_LAST_OK" ]; then
    GATE_REASON=no-last-ok
    return 1
  fi
  last_ok=$(cat "$DR_LAST_OK" 2>/dev/null)
  now_s=$(date +%s)
  if [ $(( now_s - last_ok )) -gt 129600 ]; then
    GATE_REASON=last-ok-stale
    return 1
  fi
  if ! "$RESTIC" cat config >/dev/null 2>&1; then
    GATE_REASON=restic-unreachable
    return 1
  fi
  return 0
}

irrep_candidates() { # -> незаменимые кандидаты (не в state, не в DENY_LIST) на stdout
  if [ -n "$DR_TEST_IRREPLACEABLE_DIR" ] && [ -d "$DR_TEST_IRREPLACEABLE_DIR" ]; then
    while IFS= read -r -d '' p; do
      denied "$p" && continue
      grep -qxF "$p" <(awk -F'\t' '{print $1}' "$DR_STATE_FILE" 2>/dev/null) && continue
      printf '%s\n' "$p"
    done < <(find "$DR_TEST_IRREPLACEABLE_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
  fi
  for p in "${REFIX_PATHS[@]:-}"; do
    printf '%s\n' "$p"
  done
}

# --restore-drill (spec:055): репетиция восстановления; без уборки и без ledger.
if [ "$MODE" = drill ]; then
  restic_env
  drill_id=$("$RESTIC" snapshots --tag predelete --latest 1 --json 2>/dev/null \
    | jq -r '.[0].short_id' 2>/dev/null)
  if [ -z "$drill_id" ] || [ "$drill_id" = null ]; then
    echo "drill: 0 files"
    exit 1
  fi
  drill_d=$(mktemp -d /tmp/restore-drill-XXXX) || exit 1
  "$RESTIC" restore "$drill_id" --target "$drill_d" >/dev/null 2>&1
  drill_n=0; drill_m=0; drill_k=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    real="${f#"$drill_d"}"
    [ -f "$real" ] || continue
    drill_n=$((drill_n + 1))
    if cmp -s -- "$f" "$real"; then
      drill_m=$((drill_m + 1))
    else
      drill_k=$((drill_k + 1))
    fi
  done < <(find "$drill_d" -type f 2>/dev/null)
  rm -rf -- "$drill_d"
  echo "drill: $drill_n files, $drill_m match, $drill_k mismatch"
  if [ "$drill_k" -eq 0 ] && [ "$drill_n" -gt 0 ]; then
    exit 0
  fi
  exit 1
fi

fix_candidates() { # class listfile -> 0/1; фиксирует незаменимые в restic predelete и пишет state/journal
  local class=$1 listfile=$2
  local -a paths=() fix_paths=()
  local -A sha1_map=()
  local p sha1 sha2 size mtime snapshot_id dump rc total quota
  local quota=${DR_FIX_QUOTA_BYTES:-10737418240}
  total=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    paths+=("$p")
    sha1_map["$p"]=$(sha256sum < "$p" | cut -c1-64)
  done <"$listfile"
  # Квота (spec:055): при превышении бюджета оставшиеся пути не фиксируем, а откладываем.
  for p in "${paths[@]}"; do
    size=$(stat -c %s "$p" 2>/dev/null || echo 0)
    if [ "$total" -gt 0 ] && [ $((total + size)) -gt "$quota" ]; then
      journal_row "$class" deferred "$p" "$size" - - quota
      continue
    fi
    fix_paths+=("$p")
    total=$((total + size))
  done
  if [ "${#fix_paths[@]}" -eq 0 ]; then
    return 1
  fi
  fix_list=$(mktemp)
  printf '%s\n' "${fix_paths[@]}" >"$fix_list"
  dump=$("$RESTIC" backup --files-from-verbatim "$fix_list" --tag predelete --host "$(hostname)" --json)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    for p in "${fix_paths[@]}"; do
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      journal_row "$class" deferred "$p" "$size" - - restic-backup-failed
    done
    rm -f -- "$fix_list"
    return 1
  fi
  snapshot_id=$(printf '%s' "$dump" | jq -r 'select(.message_type=="summary") | .snapshot_id')
  for p in "${fix_paths[@]}"; do
    sha2=$(sha256sum < "$p" | cut -c1-64)
    if [ "${sha1_map["$p"]}" = "$sha2" ]; then
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      mtime=$(stat -c %Y "$p" 2>/dev/null || echo -)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$p" "$size" "$mtime" "$sha2" "$snapshot_id" "$(date +%s)" >>"$DR_STATE_FILE"
      journal_row "$class" fixed "$p" "$size" "$snapshot_id" - -
    else
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      journal_row "$class" deferred "$p" "$size" - - changed-during-snapshot
    fi
  done
  rm -f -- "$fix_list"
}

verify_and_delete() { # class -> удаление по гейту: проверка копии в restic; заполняет REFIX_PATHS
  local class=$1
  [ -f "$DR_STATE_FILE" ] || return 0
  local tmp now_s path size mtime sha256 snapshot_id fixed_ts sid_path
  local -a rec
  local -A snap_path=() snap_done=()
  local p s m ms meta snap_size snap_mtime
  tmp=$(mktemp)
  now_s=$(date +%s)
  while IFS=$'\t' read -ra rec; do
    [ "${#rec[@]}" -eq 6 ] || continue   # мусор (напр. строки тревог) пропускаем
    path="${rec[0]}"; size="${rec[1]}"; mtime="${rec[2]}"
    sha256="${rec[3]}"; snapshot_id="${rec[4]}"; fixed_ts="${rec[5]}"
    [ -n "$path" ] || continue
    if [ ! -e "$path" ]; then
      journal_row "$class" vanished "$path" "$size" "$snapshot_id" - -
      continue
    fi
    if [ $((now_s - fixed_ts)) -gt 86400 ]; then
      journal_row "$class" snapshot-stale "$path" "$size" "$snapshot_id" - -
      REFIX_PATHS+=("$path")
      continue
    fi
    if [ -z "${snap_done[$snapshot_id]:-}" ]; then
      snap_done[$snapshot_id]=1
      while IFS=$'\t' read -r p s m; do
        [ -n "$p" ] || continue
        ms=$(date -d "$m" +%s 2>/dev/null || echo 0)
        snap_path["$snapshot_id"$'\x1f'"$p"]="$s"$'\t'"$ms"
      done < <("$RESTIC" ls --json "$snapshot_id" 2>/dev/null \
        | jq -r 'select(.struct_type=="node" and .type=="file") | [.path, (.size|tostring), .mtime] | @tsv')
    fi
    sid_path="$snapshot_id"$'\x1f'"$path"
    if [ -z "${snap_path[$sid_path]+set}" ]; then
      journal_row "$class" changed-after-snapshot "$path" "$size" "$snapshot_id" - -
      REFIX_PATHS+=("$path")
      continue
    fi
    meta="${snap_path[$sid_path]}"
    snap_size="${meta%%$'\t'*}"; snap_mtime="${meta#*$'\t'}"
    if [ "$snap_size" = "$(stat -c %s "$path" 2>/dev/null)" ] \
       && [ "$snap_mtime" = "$(stat -c %Y "$path" 2>/dev/null)" ] \
       && [ "$(sha256sum < "$path" | cut -c1-64)" = "$sha256" ]; then
    if [ "$GATE_MODE" = enforce ]; then
      rm -f -- "$path"
      journal_row "$class" deleted "$path" "$size" "$snapshot_id" \
          "$RESTIC restore $snapshot_id --repo '$RESTIC_REPOSITORY' --target /var/lib/disk-rotate/restore/$RUN_ID --include '$path'" -
    else
      journal_row "$class" would-delete "$path" "$size" "$snapshot_id" - -
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$path" "$size" "$mtime" "$sha256" "$snapshot_id" "$fixed_ts" >>"$tmp"
      fi
      continue
    fi
    journal_row "$class" changed-after-snapshot "$path" "$size" "$snapshot_id" - -
    REFIX_PATHS+=("$path")
  done <"$DR_STATE_FILE"
  mv -f "$tmp" "$DR_STATE_FILE"
}

gate_process() { # class listfile -> 0, либо RC_GATE_CLOSED при закрытом гейте
  local class=$1 listfile=$2
  local p path size rec
  local -A known=()
  restic_env
  GATE_REASON=
  if ! gate_open; then
    # незаменимые не фиксируем и не удаляем — только журнал с причиной закрытия
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      journal_row "$class" deferred "$p" "$size" - - "gate-closed:$GATE_REASON"
    done <"$listfile"
    return $RC_GATE_CLOSED
  fi
  verify_and_delete "$class"
  # Уже зафиксированные (в state) при повторной фиксации пропускаем; к оставшимся
  # добавляем пути из списка повторной фиксации (stale/changed в verify_and_delete).
  local tmp
  tmp=$(mktemp)
  while IFS=$'\t' read -ra rec; do
    [ "${#rec[@]}" -eq 6 ] || continue
    path="${rec[0]}"
    [ -n "$path" ] || continue
    known["$path"]=1
  done <"$DR_STATE_FILE"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -n "${known[$p]:-}" ] && continue
    printf '%s\n' "$p"
  done <"$listfile" >"$tmp"
  for p in "${REFIX_PATHS[@]:-}"; do
    [ -n "$p" ] || continue
    printf '%s\n' "$p"
  done >>"$tmp"
  if [ -s "$tmp" ]; then
    fix_candidates "$class" "$tmp"
  fi
  rm -f "$tmp"
  # срок хранения снимков predelete: 31 день (spec:055); неудача не блокирует прогон
  if ! "$RESTIC" forget --tag predelete --group-by host,tags --keep-within 31d >>"$DR_LOG" 2>&1; then
    journal_row gate forget-skipped - 0 - - forget-locked
  fi
  # при занятости >=95% свежие снимки проходят правило 24 ч сразу
  if [ "$(use_pct)" -ge 95 ]; then
    verify_and_delete "$class"
  fi
  return 0
}

handle() { # class [irr]; пути из stdin (NUL). irr — незаменимые: не удалять, копить в IRR_LIST
  local cls=$1 irr=${2:-} p kb age size label=$cls
  [ "$irr" = irr ] && label=irreplaceable
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    denied "$p" && continue
    if [ "$MODE" = dry-run ]; then
      kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      age=$(( (now - $(stat -c %Y "$p" 2>/dev/null)) / 86400 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t%sd\t%s\n' "$p" "$kb" "$age" "$label"
    elif [ "$irr" = irr ]; then
      printf '%s\n' "$p" >>"$IRR_LIST"
    else
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      rm -rf -- "$p" 2>/dev/null
      journal_row "$cls" deleted "$p" "$size" replaceable - -
    fi
  done
}

# find-правки на каталогах-кэшах: в run — fast -delete, в dry-run — список кандидатов.
clean_dir() { # base mtime class [irr|--] [extra find args...]; irr — собрать файлы в IRR_LIST
  local base=$1 mtime=$2 cls=$3; shift 3
  local irr=0
  [ "${1:-}" = irr ] && { irr=1; shift; }
  denied "$base" && return
  if [ "$MODE" = run ] && [ "$irr" = 1 ]; then
    find "$base" -mindepth 1 -mtime "+$mtime" -type f "$@" -print0 2>/dev/null | handle "$cls" irr
    return
  fi
  if [ "$MODE" = dry-run ]; then
    if [ "$irr" = 1 ]; then
      find "$base" -mindepth 1 -mtime "+$mtime" -type f "$@" -print0 2>/dev/null | handle "$cls" irr
    else
      find "$base" -mindepth 1 -mtime "+$mtime" "$@" -print0 2>/dev/null | handle "$cls"
    fi
  else
    find "$base" -mindepth 1 -mtime "+$mtime" "$@" -delete 2>/dev/null
    journal_row "$cls" deleted - - replaceable - "clean_dir $base"
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
  clean_dir /root/.claude/projects     3 cache irr -name '*.jsonl'
  clean_dir /root/.claude/jobs         3 cache irr -type f
  clean_dir /root/.claude/paste-cache  3 cache irr -type f
  clean_dir /root/.claude/file-history 3 cache irr -type f

  # --- __pycache__ старше суток в рабочих каталогах (запретный список сильнее класса) ---
  while IFS= read -r -d '' p; do
    denied "$p" && continue
    if [ "$MODE" = dry-run ]; then
      kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); kb="${kb:-0}"
      age=$(( (now - $(stat -c %Y "$p" 2>/dev/null)) / 86400 ))
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%sk\t%sd\t%s\n' "$p" "$kb" "$age" cache
    else
      size=$(stat -c %s "$p" 2>/dev/null || echo -)
      rm -rf -- "$p"
      journal_row cache deleted "$p" "$size" replaceable - -
    fi
  done < <(find /root/workspaces /root/.local /opt /usr/local -type d -name __pycache__ -mtime +1 -print0 2>/dev/null)

  # --- /tmp/* старше 2 суток ---
  if [ "$MODE" = dry-run ]; then
    find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -print0 2>/dev/null | handle cache
  else
    find /tmp -mindepth 1 -maxdepth 1 -mtime +2 -exec rm -rf {} + 2>/dev/null
    journal_row cache deleted - - replaceable - "find /tmp"
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
    # осиротевшая копия: файлы считаем незаменимыми (удаление — через гейт)
    find "$d" -type f -print0 2>/dev/null | handle cache irr
  done

  # --- системные очистки кэша (только боевой режим) ---
  if [ "$MODE" = run ]; then
    apt-get clean >>"$DR_LOG" 2>&1
    journal_row gate deleted - - replaceable - "apt-get clean"
    docker builder prune -a -f >>"$DR_LOG" 2>&1
    journal_row gate deleted - - replaceable - "docker builder prune"
    docker image prune -f >>"$DR_LOG" 2>&1
    journal_row gate deleted - - replaceable - "docker image prune"
    journalctl --vacuum-size=200M >>"$DR_LOG" 2>&1
    journal_row gate deleted - - replaceable - "journalctl --vacuum-size"
  fi
}

cleanup_trash() { # работает только при hard
  # --- незаменимые: файлы копим в IRR_LIST (удаление — через гейт после классов) ---
  find /root/workspaces/projects/.agent-work -maxdepth 1 -type d -name 'trash-*' \
    -mtime "+$TRASH_AGE_DAYS" -print0 2>/dev/null | while IFS= read -r -d '' d; do
      [ -n "$d" ] || continue
      denied "$d" && continue
      find "$d" -type f -print0 2>/dev/null | handle trash irr
    done
  find /root/workspaces/system/archives -maxdepth 2 -type f -name '*.tar.gz' \
    -mtime "+$TRASH_AGE_DAYS" -print0 2>/dev/null | handle trash irr

  # --- snap: только `snap remove <имя>`; файлы .snap и каталоги snapd не трогаем ---
  while read -r name; do
    [ -n "$name" ] || continue
    if [ "$MODE" = dry-run ]; then
      printf '%s\t-\t-\ttrash\n' "$name"
    else
      snap remove "$name" >>"$DR_LOG" 2>&1
      journal_row trash deleted - - replaceable - "snap remove $name"
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
      docker rmi "$img" >>"$DR_LOG" 2>&1
    fi
  done < <(docker images --no-trunc -q 2>/dev/null | awk -v refs="$(printf '%s' "$refs")" '
    BEGIN { n=split(refs, a, "\n"); for (i=1; i<=n; i++) used[a[i]]=1 }
    !($0 in used) { print }')
}

# Уровень always (spec:055): кандидаты незаменимые, собираются в IRR_LIST вне
# зависимости от занятости, ДО классов по порогам. Ничего не удаляется напрямую.
cleanup_always() { # вызывается в каждом run/dry-run; логи и кандидаты -> IRR_LIST
  local lr=/root/workspaces/tools/etc/disk-rotate-logrotate.conf
  if [ -f "$lr" ]; then
    if [ "$MODE" = dry-run ]; then
      logrotate -d -s /var/lib/disk-rotate/logrotate.state "$lr" >>"$DR_LOG" 2>&1
    else
      logrotate -s /var/lib/disk-rotate/logrotate.state "$lr" >>"$DR_LOG" 2>&1
    fi
  else
    echo "logrotate: нет $lr (пропускаю)" >>"$DR_LOG"
  fi

  # reports: старые отчёты и сжатые логи
  find -P /root/workspaces/system/tools/scripts/context       -type f -mtime +7  -print0 2>/dev/null | handle reports irr
  find -P /root/workspaces/system/tools/scripts/agent-reports -type f -mtime +14 -print0 2>/dev/null | handle reports irr
  find -P /root/workspaces/system/tools/scripts/logs -maxdepth 1 -type f -name '*.gz' -mtime +14 -print0 2>/dev/null | handle reports irr

  # txdirs: рабочие каталоги проектов старше 2 суток, кроме помеченных promoted
  while IFS= read -r -d '' d; do
    [ -n "$d" ] || continue
    denied "$d" && continue
    grep -q '"promoted"[[:space:]]*:[[:space:]]*true' "$d/.tx-meta.json" 2>/dev/null && continue
    find -P "$d" -type f -print0 2>/dev/null | handle txdirs irr
  done < <(find -P /root/workspaces/projects -maxdepth 1 -type d -name '.t-*' -mtime +2 -print0 2>/dev/null)

  # profile: история и бэкапы Claude старше 14 суток
  find -P /root/.claude/file-history -type f -mtime +14 -print0 2>/dev/null | handle profile irr
  find -P /root/.claude/backups      -type f -mtime +14 -print0 2>/dev/null | handle profile irr
}

# Тестовый режим (DR_TEST_ONLY=1): только тестовые классы, реальная уборка не выполняется.
if [ "$DR_TEST_ONLY" = 1 ]; then
  REFIX_PATHS=()
  # незаменимые: собрать обычные файлы тестового каталога и отдать гейту
  irrep_tmp=$(mktemp)
  if [ -n "$DR_TEST_IRREPLACEABLE_DIR" ] && [ -d "$DR_TEST_IRREPLACEABLE_DIR" ]; then
    find "$DR_TEST_IRREPLACEABLE_DIR" -maxdepth 1 -type f -print 2>/dev/null >>"$irrep_tmp"
  fi
  gate_process test-irreplaceable "$irrep_tmp"
  rm -f -- "$irrep_tmp"
  # заменимые: просто удаляются
  if [ -n "$DR_TEST_REPLACEABLE_DIR" ] && [ -d "$DR_TEST_REPLACEABLE_DIR" ]; then
    find "$DR_TEST_REPLACEABLE_DIR" -maxdepth 1 -type f -delete 2>/dev/null
  fi
elif [ "$MODE" != report ]; then
  cleanup_always
  if [ "$state" = soft ] || [ "$state" = hard ]; then
    cleanup_cache
  fi
  if [ "$state" = hard ]; then
    cleanup_trash
    cleanup_images
  fi
fi

# После классов по порогам — фиксация незаменимых и системная чистка (только run).
if [ "$MODE" = run ] && [ "$DR_TEST_ONLY" != 1 ]; then
  [ -s "$IRR_LIST" ] && gate_process irreplaceable "$IRR_LIST"
  for r in /root/workspaces/projects/.agent-work /root/workspaces/system/archives /root/workspaces/projects/.claude/worktrees /root/.claude/projects /root/.claude/jobs /root/.claude/paste-cache /root/.claude/file-history \
           /root/workspaces/projects/.t-* /root/workspaces/system/tools/scripts/context /root/workspaces/system/tools/scripts/agent-reports /root/workspaces/system/tools/scripts/logs; do
    [ -d "$r" ] && find "$r" -mindepth 1 -type d -empty -delete 2>/dev/null
  done
  git -C /root/workspaces/projects worktree prune >>"$DR_LOG" 2>&1
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
  F=$DR_LAST_OK
  last_ok=0
  [ -f "$F" ] && last_ok=$(cat "$F")
  if [ ! -f "$F" ] || [ $((now - last_ok)) -gt 129600 ]; then
    echo "server-backup dead-man: последний успешный прогон старше 36 ч (или не было)" >>"$DR_LOG"
    maybe_alert backup "server-backup: последний успешный прогон старше 36 ч (или не было) — проверить pm2 server-backup"
  fi
fi

[ "$ALERT_SENT" -gt 0 ] && ALERT_RESULT=sent
[ "$ALERT_FAIL" -gt 0 ] && ALERT_RESULT=failed

df -h / | tail -1 >>"$DR_LOG"

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
  "$state_ledger" "$ALERT_RESULT" "$top5" "$DECLARED_MISSING" >>"$DR_LEDGER"

echo "=== $(date '+%F %T') END ===" >>"$DR_LOG"

if [ "$state_ledger" = exhausted ]; then
  exit $RC_EXHAUSTED
fi
if [ "$MODE" = run ] && [ "$ALERT_FAIL" -gt 0 ]; then
  exit $RC_ALERT_FAILED
fi
exit 0
