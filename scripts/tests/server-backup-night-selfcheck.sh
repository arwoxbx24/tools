#!/usr/bin/env bash
# Selfcheck R6 (атом dcfg-t56za.11): ночной бэкап, nice/ionice, mirror-check, окно догона.
# Запуск: timeout 120 bash scripts/tests/server-backup-night-selfcheck.sh
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$ROOT/scripts/pm2/server-backup.sh"
CATCHUP="$ROOT/scripts/pm2/backup-catchup.sh"

for f in "$SB" "$CATCHUP"; do
  [ -f "$f" ] || { echo "FATAL: нет $f"; exit 1; }
done

TMP="$(mktemp -d /tmp/dcfg-sb-selfcheck.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/mirror" "$TMP/work" "$TMP/logs"
# 3 локальных bare-репозитория — для локальной сверки mirror-check.
for n in 1 2 3; do mkdir -p "$TMP/mirror/repo$n.git"; done

: >"$TMP/s3.env"
: >"$TMP/pw.env"
: >"$TMP/notify-empty.env"
printf 'TG_BOT_TOKEN=stub\nTG_CHAT_ID=1\n' >"$TMP/notify-tok.env"

# Ссылка на снимок S3 (для проверки алерта).
export STUB_CURL="$TMP/curl.log"

write_stub() { # name body
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

# Заглушка restic: пишет argv бэкапа + собственный nice, отдаёт ls из файла.
write_stub restic '
mode="${1:-}"
if [ "$mode" = backup ]; then
  {
    printf "nice=%s\n" "$(ps -o ni= $$ | tr -d " ")"
    printf "argv:"
    for a in "$@"; do printf " <%s>" "$a"; done
    printf "\n"
  } >>"$STUB_ARGV"
  exit 0
fi
if [ "$mode" = ls ]; then cat "$STUB_LS_FILE" 2>/dev/null; exit 0; fi
if [ "$mode" = stats ]; then printf "Total Size: 100 MiB\n"; exit 0; fi
if [ "$mode" = check ]; then exit "${STUB_CHECK_RC:-0}"; fi
exit 0
'

# Воскресная ветка check требует date +%u=7, +%-d=8; форсируем только по флагу,
# прочие вызовы date (лог, +%s) делегируем системной date.
write_stub date '
if [ "${STUB_FORCE_SUNDAY:-0}" = 1 ]; then
  case "${1:-}" in
    +%u) echo 7; exit 0;;
    +%-d) echo 8; exit 0;;
  esac
fi
exec /bin/date "$@"
'

# Сетевые/тяжёлые/служебные заглушки — сервер не нагружаем, наружу не ходим.
write_stub curl '
{ printf "curl:"; for a in "$@"; do printf " <%s>" "$a"; done; printf "\n"; } >>"${STUB_CURL:-/dev/null}"
exit 0
'
write_stub pm2 '
echo "pm2:$*" >>"${STUB_PM2:-/dev/null}"
[ "${1:-}" = jlist ] && echo "[]"
exit 0
'
write_stub jq 'exit 0'
write_stub systemctl 'case "$*" in *is-active*) exit 1;; esac; exit 0'
write_stub crontab 'exit 0'
for c in dpkg apt-mark pip3 pipx uv npm snap docker redis-cli sqlite3 lsb_release; do
  write_stub "$c" 'exit 0'
done
write_stub su 'exit 1'

run_backup() { # ls_file notify_env argc_file  -> rc
  local ls_file="$1" notify="$2" argc="$3" rc
  : >"$argc"
  STUB_LS_FILE="$ls_file" \
  STUB_ARGV="$argc" \
  RESTIC="$TMP/bin/restic" \
  S3_ENV="$TMP/s3.env" \
  PW_ENV="$TMP/pw.env" \
  NOTIFY_ENV="$notify" \
  LOG="$TMP/logs/server-backup.log" \
  STAGE="$TMP/work/stage" \
  LAST_OK="$TMP/last-ok" \
  ALERT_PENDING="$TMP/alert-pending" \
  BK_MIRROR_DIR="$TMP/mirror" \
  PATH="$TMP/bin:$PATH" \
  timeout 120 bash "$SB"
  rc=$?
  return "$rc"
}

PASS=0
TOTAL=11

# --- (a)+(b): штатный ночной бэкап, mirror-check сходится (3==3).
SB_LOG="$TMP/logs/server-backup.log"
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\nrepos/repo3.git/HEAD\n' >"$TMP/ls-ok.txt"
ARGV_A="$TMP/argv-a.txt"
if ! run_backup "$TMP/ls-ok.txt" "$TMP/notify-empty.env" "$ARGV_A"; then
  echo "[a] server-backup rc!=0 на штатном прогоне (лог: $SB_LOG)"; exit 1
fi

if grep -q -- '--limit-upload> <5120>' "$ARGV_A"; then PASS=$((PASS+1)); else
  echo "[a] backup не получил --limit-upload"; exit 1
fi
if grep -q -- '--read-concurrency> <1>' "$ARGV_A"; then PASS=$((PASS+1)); else
  echo "[a] backup не получил --read-concurrency 1"; exit 1
fi
nice_a=$(sed -n 's/^nice=\([0-9]*\)$/\1/p' "$ARGV_A" | head -1)
if [ -n "$nice_a" ] && [ "$nice_a" -ge 19 ]; then PASS=$((PASS+1)); else
  echo "[b] nice=$nice_a < 19"; exit 1
fi
if grep -q 'mirror-check s3=3 local=3' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[a] нет 'mirror-check s3=3 local=3' в логе"; exit 1
fi

# --- (c): догон вне окна (BK_HOUR=14) не запускает server-backup.
old=$(( $(date +%s) - 30 * 3600 ))
printf '%s\n' "$old" >"$TMP/catch-last-ok"
: >"$TMP/pm2.log"
env BK_HOUR=14 LAST_OK="$TMP/catch-last-ok" ALERT_PENDING="$TMP/catch-alert" \
  NOTIFY_ENV="$TMP/notify-empty.env" LOG="$TMP/logs/catchup.log" \
  PM2="$TMP/bin/pm2" STUB_PM2="$TMP/pm2.log" PATH="$TMP/bin:$PATH" bash "$CATCHUP"
if grep -q 'outside-night-window hour=14' "$TMP/logs/catchup.log"; then PASS=$((PASS+1)); else
  echo "[c] нет 'outside-night-window hour=14' в логе догона"; exit 1
fi
if [ ! -s "$TMP/pm2.log" ]; then PASS=$((PASS+1)); else
  echo "[c] pm2 запущен вне ночного окна (BK_HOUR=14)"; exit 1
fi

# --- (c): догон в окне (BK_HOUR=02) запускает server-backup.
: >"$TMP/pm2.log"
env BK_HOUR=02 LAST_OK="$TMP/catch-last-ok" ALERT_PENDING="$TMP/catch-alert" \
  NOTIFY_ENV="$TMP/notify-empty.env" LOG="$TMP/logs/catchup2.log" \
  PM2="$TMP/bin/pm2" STUB_PM2="$TMP/pm2.log" PATH="$TMP/bin:$PATH" bash "$CATCHUP"
if grep -q 'pm2:restart server-backup' "$TMP/pm2.log"; then PASS=$((PASS+1)); else
  echo "[c] pm2 restart server-backup не вызван в окне (BK_HOUR=02)"; exit 1
fi
if ! grep -q 'outside-night-window' "$TMP/logs/catchup2.log"; then PASS=$((PASS+1)); else
  echo "[c] BK_HOUR=02 ошибочно классифицирован как вне окна"; exit 1
fi

# --- (d): mirror-check расходится (s3=2, local=3) -> строка и алерт.
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\n' >"$TMP/ls-2.txt"
ARGV_D="$TMP/argv-d.txt"
: >"$TMP/curl.log"
if run_backup "$TMP/ls-2.txt" "$TMP/notify-tok.env" "$ARGV_D"; then
  echo "[d] ожидали сбой mirror-check, а бэкап завершился успешно"; exit 1
fi
if grep -q 'mirror-check s3=2 local=3' "$SB_LOG"; then PASS=$((PASS+1)); else
  echo "[d] нет 'mirror-check s3=2 local=3' в логе"; exit 1
fi
if grep -q 'mirror-check' "$TMP/curl.log"; then PASS=$((PASS+1)); else
  echo "[d] нет алерта mirror-check"; exit 1
fi

# --- (e): воскресная ветка check -> rc=1 -> тревога в ALERT_PENDING (пустой токен).
printf 'repos/repo1.git/HEAD\nrepos/repo2.git/HEAD\nrepos/repo3.git/HEAD\n' >"$TMP/ls-e.txt"
ARGV_E="$TMP/argv-e.txt"
: >"$TMP/alert-pending"
export STUB_FORCE_SUNDAY=1 STUB_CHECK_RC=1
if run_backup "$TMP/ls-e.txt" "$TMP/notify-empty.env" "$ARGV_E"; then
  echo "[e] ожидали сбой check rc=1, а бэкап завершился успешно"; exit 1
fi
unset STUB_FORCE_SUNDAY STUB_CHECK_RC
if grep -q 'check rc=1' "$TMP/alert-pending"; then PASS=$((PASS+1)); else
  echo "[e] нет 'check rc=1' в ALERT_PENDING"; exit 1
fi

echo "PASS $PASS/$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
