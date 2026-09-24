#!/bin/bash
# disk-rotate-notify-test: проверка политики уведомлений U2 (dcfg-tui43).
# AE3: гейт open + pct < HARD_PCT => DR_NOTIFY_CMD не вызвана;
#      гейт закрыт          => вызвана.
# AE4: тексты в заглушке без /root/, {, .json, .env.
# Запуск: bash scripts/disk-rotate-notify-test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd -P)/disk-rotate.sh"
RESTIC=/root/workspaces/tools/bin/restic

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

I= R= STATE= JOURNAL= LASTOK= LOCK= LEDGER= TLOG= ALERTS= NOTIFY= S=
NOTIFY_STUB= REPO= PASSFILE=
RUN_ENV=()

fixture() {
  local name=$1
  local d="$TMP/$name"
  S="$d"; I="$d/irreplaceable"; R="$d/replaceable"
  mkdir -p "$I" "$R"
  STATE="$d/state.tsv"; JOURNAL="$d/journal.tsv"
  LASTOK="$d/lastok"; LOCK="$d/lock"
  LEDGER="$d/ledger.tsv"; TLOG="$d/log"
  ALERTS="$d/alerts"; NOTIFY="$d/notify.txt"
  date +%s >"$LASTOK"
  REPO="$d/repo"; PASSFILE="$d/pw"
  printf 'fixture-pass-%s-%s\n' "$RANDOM" "$RANDOM" >"$PASSFILE"
  if ! "$RESTIC" init --repo "$REPO" --password-file "$PASSFILE" >/dev/null 2>&1; then
    echo "FIXTURE-ERROR: restic init failed ($RESTIC)" >&2; exit 2
  fi
  NOTIFY_STUB="$d/notify-stub.sh"
  cat >"$NOTIFY_STUB" <<NOTIFYEOF
#!/bin/bash
echo "notify \$1" >>"$NOTIFY"
NOTIFYEOF
  chmod +x "$NOTIFY_STUB"
  RUN_ENV=(DR_TEST_ONLY=1
    DR_USAGE_PCT=84
    DR_STATE_FILE="$STATE"
    DR_JOURNAL="$JOURNAL"
    DR_LAST_OK="$LASTOK"
    DR_ALERT_STATE_FILE="$ALERTS"
    DR_LOCK_FILE="$LOCK"
    DR_LEDGER="$LEDGER"
    DR_LOG="$TLOG"
    DR_NOTIFY_CMD="$NOTIFY_STUB"
    DR_RESTIC_REPO="$REPO"
    DR_RESTIC_PASSWORD_FILE="$PASSFILE"
    DR_TEST_IRREPLACEABLE_DIR="$I"
    DR_TEST_REPLACEABLE_DIR="$R")
}

run_rotate() {
  local arg extras=() args=() passthrough=0
  for arg in "$@"; do
    if [ "$arg" = "--" ]; then passthrough=1; continue; fi
    if [ "$passthrough" = 0 ]; then extras+=("$arg"); else args+=("$arg"); fi
  done
  env "${RUN_ENV[@]}" "${extras[@]}" "$SCRIPT" "${args[@]}"
}

FAILS=0
report() {
  if [ "$3" = PASS ]; then echo "PASS $1 $2"
  else echo "FAIL $1 $2"; FAILS=$((FAILS + 1)); fi
}

scenario_ae3() {
  fixture ae3
  # Гейт open, DR_USAGE_PCT=84 (< HARD_PCT=90) — сводка только в DR_LOG.
  run_rotate >/dev/null 2>&1
  notify_lines=$(wc -l <"$NOTIFY" 2>/dev/null || echo 0)
  if [ "$notify_lines" -eq 0 ] && grep -q 'SUMMARY-LOG-ONLY' "$TLOG" 2>/dev/null; then
    report 1 "AE3: gate open, pct<HARD — notify не вызвана" PASS
  else
    report 1 "AE3: gate open, pct<HARD — notify не вызвана (lines=$notify_lines)" FAIL
  fi
  # Гейт закрыт (удаляем репозиторий) — сводка уходит в DR_NOTIFY_CMD.
  rm -rf "$REPO"
  run_rotate >/dev/null 2>&1
  notify_count=$(wc -l <"$NOTIFY" 2>/dev/null || echo 0)
  if [ "$notify_count" -gt 0 ]; then
    report 2 "AE3: gate closed — notify вызвана ($notify_count раз)" PASS
  else
    report 2 "AE3: gate closed — notify не вызвана" FAIL
  fi
}

scenario_ae4() {
  fixture ae4
  # Закрываем гейт, чтобы сгенерировать алерт.
  rm -rf "$REPO"
  run_rotate >/dev/null 2>&1
  if [ ! -s "$NOTIFY" ]; then
    report 3 "AE4: нет алертов для проверки" FAIL
    return
  fi
  if grep -Eq '/root/|\{|\.json|\.env' "$NOTIFY" 2>/dev/null; then
    report 3 "AE4: тексты без /root/, {, .json, .env" FAIL
  else
    report 3 "AE4: тексты без /root/, {, .json, .env" PASS
  fi
}

scenario_u3_static() {
  local bad=0 word line
  for word in /root/ owner_list GATE_REASON ecosystem crontab pm2; do
    while IFS= read -r line; do
      case "$line" in
        *"$word"*)
          echo "U3-STATIC: maybe_alert содержит '$word': $line" >&2
          bad=1
          ;;
      esac
    done < <(grep 'maybe_alert' "$SCRIPT")
  done
  if [ "$bad" -eq 0 ]; then
    report 4 "U3: maybe_alert без /root/, owner_list, GATE_REASON, ecosystem, crontab, pm2" PASS
  else
    report 4 "U3: maybe_alert без /root/, owner_list, GATE_REASON, ecosystem, crontab, pm2" FAIL
  fi
}

scenario_u3_gate() {
  fixture u3gate
  rm -rf "$REPO"
  run_rotate >/dev/null 2>&1
  if [ ! -s "$NOTIFY" ]; then
    report 5 "U3: заглушка при закрытом гейте" FAIL
    return
  fi
  if grep -q 'приостановлена' "$NOTIFY" && ! grep -q 'closed:' "$NOTIFY"; then
    report 5 "U3: заглушка cодержит «приостановлена», без closed:" PASS
  else
    report 5 "U3: заглушка cодержит «приостановлена», без closed:" FAIL
  fi
}

scenario_ae3
scenario_ae4
scenario_u3_static
scenario_u3_gate

echo "PASS $((5 - FAILS))/5"
[ "$FAILS" -eq 0 ] && exit 0
echo "$FAILS/5 FAILED"
exit 1
