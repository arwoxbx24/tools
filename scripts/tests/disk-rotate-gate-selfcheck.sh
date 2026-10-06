#!/bin/bash
# Self-check гейта disk-rotate.sh (spec:055): «сначала копия restic, удаление
# в следующем прогоне». Запуск вручную, как root:
#   bash scripts/tests/disk-rotate-gate-selfcheck.sh
#
# Каждый сценарий работает в собственной поддиректории-фикстуре под /tmp
# (свои state, journal, repo, lastok, alerts), чтобы сценарии не влияли друг
# на друга. По завершении вся временная фикстура убирается.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-rotate.sh"
RESTIC=/root/workspaces/tools/bin/restic

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# --- текущая фикстура (глобальные пути, пересобираются fixture <<имя>>) ---
I= R= STATE= JOURNAL= LASTOK= LOCK= LEDGER= TLOG= ALERTS= NOTIFY= S=
NOTIFY_STUB= REPO= PASSFILE=
RUN_ENV=()
A= B= C= D= E= F= SP=
O_A= O_B= O_C= O_D= O_E= O_F=

fixture() { # имя -> новая фикстура в $TMP/$имя (свой restic, state, journal, lastok)
  local name=$1
  local d="$TMP/$name"
  S="$d"
  I="$d/irreplaceable"
  R="$d/replaceable"
  mkdir -p "$I" "$R"
  STATE="$d/state.tsv"
  JOURNAL="$d/journal.tsv"
  LASTOK="$d/lastok"
  LOCK="$d/lock"
  LEDGER="$d/ledger.tsv"
  TLOG="$d/log"
  ALERTS="$d/alerts"
  NOTIFY="$d/notify.txt"
  date +%s >"$LASTOK"   # гейт открыт по умолчанию
  REPO="$d/repo"
  PASSFILE="$d/pw"
  printf 'fixture-pass-%s-%s\n' "$RANDOM" "$RANDOM" >"$PASSFILE"
  if ! "$RESTIC" init --repo "$REPO" --password-file "$PASSFILE" >/dev/null 2>&1; then
    echo "FIXTURE-ERROR: restic init failed ($RESTIC)" >&2
    exit 2
  fi
  # Заглушка доставки сводки: пишет строку в файл фикстуры.
  NOTIFY_STUB="$d/notify-stub.sh"
  cat >"$NOTIFY_STUB" <<NOTIFYEOF
#!/bin/bash
echo "notify \$(date +%s)" >>"$NOTIFY"
NOTIFYEOF
  chmod +x "$NOTIFY_STUB"

  RUN_ENV=(DR_TEST_ONLY=1
    DR_USAGE_PCT=85
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

  A="$I/crit.data";   B="$I/mod.data";   C="$I/shadow.data"
  D="$I/hot.data";    E="$I/lastok.data"; F="$R/rep.data"
  SP="$I/spaced file.data"
  O_A="$d/orig-A"; O_B="$d/orig-B"; O_C="$d/orig-C"
  O_D="$d/orig-D"; O_E="$d/orig-E"; O_F="$d/orig-F"
}

snapshots() { "$RESTIC" -r "$REPO" --password-file "$PASSFILE" snapshots "$@"; }

run_rotate() { # [ENV=A...] -- [ARGS...] -> запускает disk-rotate.sh в текущей фикстуре
  local arg extras=() args=() passthrough=0
  for arg in "$@"; do
    if [ "$arg" = "--" ]; then passthrough=1; continue; fi
    if [ "$passthrough" = 0 ]; then extras+=("$arg"); else args+=("$arg"); fi
  done
  env "${RUN_ENV[@]}" "${extras[@]}" "$SCRIPT" "${args[@]}"
}

FAILS=0
report() { # num name status
  if [ "$3" = PASS ]; then
    echo "PASS $1 $2"
  else
    echo "FAIL $1 $2"
    FAILS=$((FAILS + 1))
  fi
}

jline() { # файл -> последняя строка журнала для этого пути (кол. 6)
  awk -F'\t' -v p="$1" '$6==p{print}' "$JOURNAL" 2>/dev/null | tail -1
}

scenario_1() { # незаменимый файл, прогон 1: фиксируется (снимок) и НЕ удаляется
  fixture scen1
  printf 'critical payload line\n' >"$A"
  cp -f "$A" "$O_A"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  if [ -f "$A" ] \
     && snapshots --tag predelete 2>/dev/null | grep -q 'predelete' \
     && grep -q $'\tfixed\t' "$JOURNAL" 2>/dev/null; then
    report 1 "незаменимый файл, прогон 1" PASS
  else
    report 1 "незаменимый файл, прогон 1" FAIL
  fi
}

scenario_2() { # тот же файл, прогоны 1+2: удаление во втором, команда в колонке 9
  fixture scen2
  printf 'critical payload line\n' >"$A"
  cp -f "$A" "$O_A"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local line snap restore
  line=$(jline "$A")
  snap=$(printf '%s' "$line" | cut -f8)
  restore=$(printf '%s' "$line" | cut -f9)
  if [ ! -e "$A" ] && [ -n "$line" ] && [ -n "$snap" ] && [ -n "$restore" ] \
     && printf '%s' "$line" | grep -q $'\tdeleted\t'; then
    report 2 "тот же файл, прогон 2" PASS
  else
    report 2 "тот же файл, прогон 2" FAIL
  fi
}

scenario_3() { # файл изменён между прогонами: не удаляется, снова fixed
  fixture scen3
  printf 'modify base\n' >"$B"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  printf 'x' >>"$B"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local n
  n=$(grep -F "$B" "$JOURNAL" 2>/dev/null | grep -c $'\tfixed\t')
  if [ -f "$B" ] && [ "$n" -ge 2 ]; then
    report 3 "файл изменён между прогонами" PASS
  else
    report 3 "файл изменён между прогонами" FAIL
  fi
}

scenario_4() { # заменимый файл, прогон 1: удаление сразу
  fixture scen4
  printf 'replaceable junk\n' >"$F"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  if [ ! -e "$F" ]; then
    report 4 "заменимый файл, прогон 1" PASS
  else
    report 4 "заменимый файл, прогон 1" FAIL
  fi
}

scenario_5() { # DR_LAST_OK старше 36 ч: незаменимое не удаляется, код 5
  fixture scen5
  printf 'backup-age guard\n' >"$E"
  echo 1 >"$LASTOK"   # старый epoch (заведомо старше 36 ч)
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq 5 ] && [ -f "$E" ]; then
    report 5 "DR_LAST_OK старше 36 ч" PASS
  else
    report 5 "DR_LAST_OK старше 36 ч (rc=$rc)" FAIL
  fi
}

scenario_6() { # shadow, два прогона: не удаляется, в журнале would-delete
  fixture scen6
  printf 'shadow payload\n' >"$C"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local n
  n=$(grep -F "$C" "$JOURNAL" 2>/dev/null | grep -c $'\twould-delete\t')
  if [ -f "$C" ] && [ "$n" -ge 1 ]; then
    report 6 "shadow, два прогона" PASS
  else
    report 6 "shadow, два прогона" FAIL
  fi
}

scenario_7() { # 96%: незаменимое удаляется в том же прогоне, со снимком
  fixture scen7
  printf 'hot payload\n' >"$D"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=96 -- >/dev/null 2>&1
  local line snap
  line=$(jline "$D")
  snap=$(printf '%s' "$line" | cut -f8)
  if [ ! -e "$D" ] && [ -n "$snap" ] && [ "$snap" != "-" ] \
     && printf '%s' "$line" | grep -q $'\tdeleted\t'; then
    report 7 "DR_USAGE_PCT=96, один прогон" PASS
  else
    report 7 "DR_USAGE_PCT=96, один прогон" FAIL
  fi
}

scenario_8() { # команда из колонки 9: restore == оригинал
  fixture scen8
  printf 'critical payload line\n' >"$A"
  cp -f "$A" "$O_A"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local line cmd restored
  line=$(jline "$A")
  cmd=$(printf '%s' "$line" | cut -f9)
  if [ -z "$cmd" ]; then
    report 8 "restore из колонки 9" FAIL
    return
  fi
  # Полный путь к restic (в свежем окружении его нет на PATH извне).
  cmd=$(printf '%s' "$cmd" | sed -E "s#^restic #$RESTIC #")
  # Направляем restore в фикстуру, чтобы не писать вне /tmp.
  cmd=$(printf '%s' "$cmd" | sed -E "s#--target[[:space:]]+[^ ]+#--target $S/restore#")
  mkdir -p "$S/restore"
  export RESTIC_REPOSITORY="$REPO" RESTIC_PASSWORD_FILE="$PASSFILE"
  bash -c "$cmd" >/dev/null 2>&1
  restored=$(find "$S/restore" -type f -name "$(basename "$A")" 2>/dev/null | head -1)
  if [ -n "$restored" ] && [ -f "$O_A" ] && cmp -s "$O_A" "$restored"; then
    report 8 "restore из колонки 9" PASS
  else
    report 8 "restore из колонки 9" FAIL
  fi
}

scenario_9() { # --restore-drill: перед drill файл должен остаться на диске и быть в снимке
  fixture scen9
  printf 'drill payload\n' >"$C"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local out rc
  out=$(run_rotate -- --restore-drill 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -Eq 'drill: [0-9]+ files, [0-9]+ match, 0 mismatch'; then
    report 9 "--restore-drill" PASS
  else
    report 9 "--restore-drill (rc=$rc)" FAIL
  fi
}

scenario_10() { # имя файла с пробелом: обрабатывается без искажения пути
  fixture scen10
  printf 'space payload\n' >"$SP"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  [ -f "$SP" ] && run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local line
  line=$(jline "$SP")
  if [ ! -e "$SP" ] && [ -n "$line" ] \
     && [ "$(printf '%s' "$line" | cut -f6)" = "$SP" ] \
     && printf '%s' "$line" | grep -q $'\tdeleted\t'; then
    report 10 "имя файла с пробелом" PASS
  else
    report 10 "имя файла с пробелом" FAIL
  fi
}

scenario_11() { # --dry-run с DR_TEST_ONLY=1: ни одного пути вне тестовых каталогов
  fixture scen11
  printf 'guard content\n' >"$A"
  printf 'rep junk\n' >"$F"
  local out bad
  out=$(run_rotate -- --dry-run 2>&1)
  bad=$(printf '%s' "$out" | grep -E '^/' | grep -vE "^($I|$R)(/|$)" | head -1)
  if [ -z "$bad" ]; then
    report 11 "запретный список и границы (--dry-run)" PASS
  else
    report 11 "запретный список и границы (--dry-run: $bad)" FAIL
  fi
}

scenario_12() { # state в несуществующем подкаталоге: каталог создаётся, файл пишется
  fixture scen12
  printf 'state-dir payload\n' >"$A"
  local S_STATE="$S/missing/state.tsv"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 DR_STATE_FILE="$S_STATE" -- >/dev/null 2>&1
  local n
  n=$(awk -F'\t' 'NF==6{c++} END{print c+0}' "$S_STATE" 2>/dev/null)
  if [ -f "$S_STATE" ] && [ "$n" -ge 1 ]; then
    report 12 "state в несуществующем подкаталоге" PASS
  else
    report 12 "state в несуществующем подкаталоге" FAIL
  fi
}

scenario_13() { # GATE_RC unbound regression: --dry-run без gate_process
  fixture scen13
  local out rc
  out=$(run_rotate -- --dry-run 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    report 13 "GATE_RC unset (--dry-run + test-only)" PASS
  else
    report 13 "GATE_RC unset (--dry-run + test-only, rc=$rc, out=$(printf '%s' "$out" | tail -1))" FAIL
  fi
}

scenario_14() { # handle() label=$cls unbound regression: заменимый файл в dry-run
  fixture scen14
  printf 'replaceable junk\n' >"$F"
  local out rc
  out=$(run_rotate DR_USAGE_PCT=5 -- --dry-run 2>&1)
  rc=$?
  # Dry-run must complete, not mask a shell error as a gate status.
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF "$F"; then
    report 14 "handle label=\$cls (dry-run + low-usage)" PASS
  else
    local last
    last=$(printf '%s' "$out" | tail -3)
    report 14 "handle label=\$cls (dry-run + low-usage, rc=$rc, last=$last)" FAIL
  fi
}

scenario_15() { # dry/live protected-path alignment: оба режима через handle
  fixture scen15
  printf 'protected content\n' >"$A"
  printf 'replaceable junk\n' >"$F"
  local dry_out live_out bad_dry bad_live rc_dry rc_live
  # dry-run
  dry_out=$(run_rotate -- --dry-run 2>&1)
  rc_dry=$?
  # live (usage 85 → cache, trashes F и удаляет заменимые)
  live_out=$(run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- 2>&1)
  rc_live=$?
  # ни в одном из режимов не должно быть путей из DENY_LIST
  bad_dry=$(printf '%s' "$dry_out" | grep -E '^/' | grep -vE "^($I|$R)(/|$)" | head -1)
  bad_live=$(printf '%s' "$live_out" | grep -E '(backups|secrets|hh-scoring|\.codex)' | head -1)
  if [ "$rc_dry" -eq 0 ] && [ "$rc_live" -eq 0 ] && [ -z "$bad_dry" ] && [ -z "$bad_live" ]; then
    report 15 "dry/live protected-path alignment" PASS
  else
    report 15 "dry/live protected-path alignment (dry=$bad_dry live=$bad_live)" FAIL
  fi
}

scenario_16() { # forecast counts regular disposable files once
  fixture scen16
  dd if=/dev/zero of="$F" bs=4096 count=1 status=none
  dd if=/dev/zero of="$R/second.data" bs=4096 count=2 status=none
  local out rc expected total count
  expected=$(du -sk "$F" "$R/second.data" | awk '{n+=$1} END{print n}')
  out=$(run_rotate -- --dry-run 2>&1); rc=$?
  total=$(printf '%s\n' "$out" | sed -n 's/^total candidates: \([0-9]*\)K$/\1/p')
  count=$(printf '%s\n' "$out" | grep -c "^$R/")
  if [ "$rc" -eq 0 ] && [ "$total" = "$expected" ] && [ "$count" -eq 2 ]; then
    report 16 "disposable forecast equals unique-file sum" PASS
  else
    report 16 "disposable forecast (rc=$rc, total=$total expected=$expected count=$count)" FAIL
  fi
}

if [ "${1:-}" = accounting ]; then
  scenario_16
  exit "$FAILS"
fi

scenario_1
scenario_2
scenario_3
scenario_4
scenario_5
scenario_6
scenario_7
scenario_8
scenario_9
scenario_10
scenario_11
scenario_12
scenario_13
scenario_14
scenario_15
scenario_16

echo "PASS $((16 - FAILS))/16"
[ "$FAILS" -eq 0 ] && exit 0
echo "$FAILS/16 FAILED"
exit 1
