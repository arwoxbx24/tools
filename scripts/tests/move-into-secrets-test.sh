#!/bin/bash
# Self-check скрипта move-into-secrets.sh (spec:054). Запуск:
#   bash scripts/tests/move-into-secrets-test.sh
# Использует временную фикстуру на mktemp -d и убирает её за собой.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/move-into-secrets.sh"
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

ROOT="$TMP/secrets"
FAKE="sk-TESTTESTTESTTEST01"

# 1. перенос обычного файла: исходник нет, цель есть, права 600, каталог 700
SRC1="$TMP/source.txt"
printf '%s\n' "$FAKE" > "$SRC1"
OUT1="$(SECRETS_ROOT="$ROOT" bash "$SCRIPT" "$SRC1" "sub/dest.txt")"
rc=$?
if [ "$rc" -eq 0 ] \
  && [ ! -e "$SRC1" ] \
  && [ -f "$ROOT/sub/dest.txt" ] \
  && [ "$(stat -c %a "$ROOT/sub/dest.txt")" = 600 ] \
  && [ "$(stat -c %a "$ROOT/sub")" = 700 ] \
  && grep -q "^moved source.txt -> $ROOT/sub/dest.txt (600)\$" <<<"$OUT1"; then
  report "перенос обычного файла: 600/700, сообщение moved" PASS
else
  report "перенос обычного файла: 600/700, сообщение moved (rc=$rc)" FAIL
fi

# 2. выход за пределы корня (../escape) → код 2, файл не тронут
ESCAPE="$TMP/escape"
printf 'x\n' > "$ESCAPE"
SECRETS_ROOT="$ROOT" bash "$SCRIPT" "$ESCAPE" "../escape" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ] && [ -f "$ESCAPE" ]; then
  report "выход за пределы корня: код 2, файл не тронут" PASS
else
  report "выход за пределы корня: код 2, файл не тронут (rc=$rc)" FAIL
fi

# 3. существующая цель → код 2, исходник на месте
SRC3="$TMP/src3.txt"
printf 'x\n' > "$SRC3"
mkdir -p "$ROOT"
printf 'old\n' > "$ROOT/dest3.txt"
SECRETS_ROOT="$ROOT" bash "$SCRIPT" "$SRC3" "dest3.txt" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ] && [ -f "$SRC3" ] && [ "$(cat "$ROOT/dest3.txt")" = old ]; then
  report "существующая цель: код 2, исходник на месте" PASS
else
  report "существующая цель: код 2, исходник на месте (rc=$rc)" FAIL
fi

# 4. --dry-run ничего не меняет
SRC4="$TMP/src4.txt"
printf 'x\n' > "$SRC4"
OUT4="$(SECRETS_ROOT="$ROOT" bash "$SCRIPT" --dry-run "$SRC4" "sub/dry.txt")"
rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$SRC4" ] \
  && [ ! -e "$ROOT/sub/dry.txt" ] \
  && grep -q "(600)" <<<"$OUT4"; then
  report "--dry-run: ничего не меняет" PASS
else
  report "--dry-run: ничего не меняет (rc=$rc)" FAIL
fi

# 5. содержимое файла ни разу не попало в вывод
OUT5="$(SECRETS_ROOT="$ROOT" bash "$SCRIPT" --dry-run "$SRC4" "sub/never.txt")"
SECRETS_ROOT="$ROOT" bash "$SCRIPT" "$SRC4" "sub/never2.txt" > "$TMP/out5.txt"
CNT5="$( { printf '%s\n' "$OUT5"; cat "$TMP/out5.txt"; } | grep -c "$FAKE")"
if [ "$CNT5" -eq 0 ]; then
  report "содержимое не попало в вывод" PASS
else
  report "содержимое не попало в вывод (cnt=$CNT5)" FAIL
fi

if [ "$FAILS" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
fi
echo "$FAILS check(s) FAILED"
exit 1
