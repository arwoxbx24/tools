#!/bin/bash
# Self-check журнала зон disk-rotate.sh (spec:090, U1-fix). Через DR_ZONES_ONLY=1
# запускается только зона журнала (без уборки и du по всему диску); всё состояние —
# в mktemp -d, реальный /var/lib/disk-rotate/zones.tsv не меняется.
#
# Запуск (root):
#   bash scripts/tests/disk-rotate-zones-selfcheck.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-rotate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

ZTSV27="$TMP/zones27.tsv"
ZTSV1="$TMP/zones1.tsv"
TLOG="$TMP/log"
LEDGER="$TMP/ledger.tsv"
ALERTS="$TMP/alerts"
DJOURNAL="$TMP/journal.tsv"
LOCK="$TMP/lock"

REAL_TSV=/var/lib/disk-rotate/zones.tsv
real_mtime() { [ -f "$REAL_TSV" ] && stat -c %Y "$REAL_TSV" 2>/dev/null || echo missing; }
REAL_BEFORE=$(real_mtime)

# Изоляция: всё в tmp; DR_TEST_ONLY=1 пропускает уборку (без du); алерт-заглушка — без сети.
RUN_ENV=(DR_ZONES_ONLY=1 DR_TEST_ONLY=1
  DR_NOTIFY_CMD=true
  DR_LOG="$TLOG"
  DR_LEDGER="$LEDGER"
  DR_ALERT_STATE_FILE="$ALERTS"
  DR_LOCK_FILE="$LOCK")

run_zone() { # zones_tsv -> stdout
  env "${RUN_ENV[@]}" DR_ZONES_TSV="$1" DR_JOURNAL="$DJOURNAL" \
    "$SCRIPT" --dry-run 2>&1
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

# сценарий 1: run-done codex возрастом 27 ч -> zone-silent codex ровно 1 раз
old=$(date -d '-27 hours' '+%Y-%m-%dT%H:%M:%S')
printf '%s\tcodex\t/\tИ\t100\t100\t0\t0\trun-done\n' "$old" >"$ZTSV27"
out27=$(run_zone "$ZTSV27")
n27=$(printf '%s' "$out27" | grep -c 'zone-silent codex')
if [ "$n27" -eq 1 ]; then
  report 1 "codex молчит 27ч -> zone-silent x1" PASS
else
  report 1 "codex молчит 27ч (zone-silent=$n27)" FAIL
fi

# сценарий 2: run-done codex возрастом 1 ч -> zone-silent codex ни разу
fresh=$(date -d '-1 hour' '+%Y-%m-%dT%H:%M:%S')
printf '%s\tcodex\t/\tИ\t100\t100\t0\t0\trun-done\n' "$fresh" >"$ZTSV1"
out1=$(run_zone "$ZTSV1")
n1=$(printf '%s' "$out1" | grep -c 'zone-silent codex')
if [ "$n1" -eq 0 ]; then
  report 2 "codex свежий 1ч -> zone-silent x0" PASS
else
  report 2 "codex свежий 1ч (zone-silent=$n1)" FAIL
fi

# сценарий 3: tmp-журнал зон содержит строку зоны claude
if grep -q 'claude' "$ZTSV27" 2>/dev/null; then
  report 3 "журнал зон содержит claude" PASS
else
  report 3 "журнал зон содержит claude" FAIL
fi

# сценарий 4: реальный /var/lib/disk-rotate/zones.tsv не изменился
if [ "$(real_mtime)" = "$REAL_BEFORE" ]; then
  report 4 "реальный zones.tsv не изменён" PASS
else
  report 4 "реальный zones.tsv изменён" FAIL
fi

echo "PASS $((4 - FAILS))/4"
[ "$FAILS" -eq 0 ] && exit 0
echo "$FAILS/4 FAILED"
exit 1
