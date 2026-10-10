#!/bin/bash
# Self-check инвариантов disk-rotate.sh (spec:054 п.6). Запуск вручную, как root:
#   bash scripts/tests/disk-rotate-selfcheck.sh
# Использует временную фикстуру и убирает её за собой.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-rotate.sh"
LEDGER=/var/log/disk-rotate-ledger.tsv
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

FAILS=0
report() { # name status
  if [ "$2" = PASS ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    FAILS=$((FAILS + 1))
  fi
}

use_pct() { df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}'; }

# 1. --dry-run не меняет занятость диска (Use% до/после)
u1=$(use_pct)
"$SCRIPT" --dry-run >"$TMP/dry1.out" 2>"$TMP/dry1.err"
rc1=$?
u2=$(use_pct)
if [ "$rc1" -eq 0 ] && [ "$u1" = "$u2" ]; then
  report "dry-run не меняет Use% диска ($u1 -> $u2)" PASS
else
  report "dry-run не меняет Use% диска ($u1 -> $u2, rc=$rc1)" FAIL
fi

# 2. Ни один путь из запретного списка не попадает в перечень кандидатов
if awk -F'\t' '$4!="backups" && $4 !~ /^codex-/' "$TMP/dry1.out" | grep -qE '/root/backups|/root/.codex|hh-scoring|secrets/'; then
  report "запретный список отсутствует в кандидатах" FAIL
else
  report "запретный список отсутствует в кандидатах" PASS
fi

# 3. Идемпотентность вывода --dry-run подряд
"$SCRIPT" --dry-run >"$TMP/dry2.out" 2>"$TMP/dry2.err"
if cmp -s <(grep -v 'closed zone' "$TMP/dry1.out" | cut -f1,4) <(grep -v 'closed zone' "$TMP/dry2.out" | cut -f1,4); then
  report "идемпотентность вывода --dry-run" PASS
else
  report "идемпотентность вывода --dry-run" FAIL
fi

# 4. Удерживаемая блокировка -> код 4, без перечня кандидатов
exec 9<>/var/run/disk-rotate.lock
if ! flock -n 9; then
  report "удерживаемая блокировка -> код 4" FAIL
else
  "$SCRIPT" --dry-run >"$TMP/locked.out" 2>"$TMP/locked.err"
  rc4=$?
  flock -u 9
  exec 9>&-
  if [ "$rc4" -eq 4 ] && [ ! -s "$TMP/locked.out" ]; then
    report "удерживаемая блокировка -> код 4" PASS
  else
    report "удерживаемая блокировка -> код 4 (rc=$rc4, out=$([ -s "$TMP/locked.out" ] && echo non-empty || echo empty))" FAIL
  fi
fi

# 5. Строка ledger содержит ровно 9 колонок, разделённых табуляцией
if [ -s "$LEDGER" ]; then
  ncols=$(tail -1 "$LEDGER" | awk -F'\t' '{print NF}')
  if [ "$ncols" -eq 9 ]; then
    report "ledger: ровно 9 колонок ($ncols)" PASS
  else
    report "ledger: ровно 9 колонок (got $ncols)" FAIL
  fi
else
  report "ledger: ровно 9 колонок (нет ledger)" FAIL
fi

# 6. Удерживаемая блокировка -> код 4 и ledger не растёт
l1=$(wc -l <"$LEDGER" 2>/dev/null || echo 0)
exec 9<>/var/run/disk-rotate.lock
if flock -n 9; then
  "$SCRIPT" --dry-run >"$TMP/locked2.out" 2>"$TMP/locked2.err"
  rc6=$?
  flock -u 9
  exec 9>&-
  l2=$(wc -l <"$LEDGER" 2>/dev/null || echo 0)
  if [ "$rc6" -eq 4 ] && [ "$l1" = "$l2" ]; then
    report "блокировка: код 4 и ledger не растёт ($l1 -> $l2)" PASS
  else
    report "блокировка: код 4 и ledger не растёт (rc=$rc6, $l1 -> $l2)" FAIL
  fi
else
  report "блокировка: код 4 и ledger не растёт (не удалось захватить)" FAIL
fi

if [ "$FAILS" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
fi
echo "$FAILS invariant(s) FAILED"
exit 1
