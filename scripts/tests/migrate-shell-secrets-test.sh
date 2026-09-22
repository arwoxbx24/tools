#!/bin/bash
# Self-check скрипта migrate-shell-secrets.sh (spec:054). Запуск:
#   bash scripts/tests/migrate-shell-secrets-test.sh
# Использует временную фикстуру на mktemp -d и убирает её за собой.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/migrate-shell-secrets.sh"
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

PROFILE="$TMP/profile.sh"
ENVFILE="$TMP/secrets/mysvc.env"
FAKE="sk-TESTTESTTESTTEST01"

cat > "$PROFILE" <<EOF
# comment
export NORMAL=hello
[ -z "\$PS1" ] && return
VOYAGE_API_KEY=$FAKE
JINA_API_KEY=$FAKE
EOF
cp -f "$PROFILE" "$TMP/profile.orig"

# 1. --dry-run не меняет фикстуру и не печатает значения
OUT="$(bash "$SCRIPT" --profile "$PROFILE" --env-file "$ENVFILE" --dry-run)"
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qF "$FAKE" <<<"$OUT" && ! grep -q '^VOYAGE_API_KEY=' <<<"$OUT"; then
  report "dry-run: имена без значений, rc=0" PASS
else
  report "dry-run: имена без значений, rc=0 (rc=$rc)" FAIL
fi
if cmp -s "$PROFILE" "$TMP/profile.orig"; then
  report "dry-run: фикстура не изменена" PASS
else
  report "dry-run: фикстура не изменена" FAIL
fi

# 2. боевой запуск создаёт env-файл 600 и убирает строки из профиля
bash "$SCRIPT" --profile "$PROFILE" --env-file "$ENVFILE"
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$ENVFILE" ] && [ "$(stat -c %a "$ENVFILE")" = 600 ]; then
  report "боевой запуск создаёт env-файл 600" PASS
else
  report "боевой запуск создаёт env-файл 600 (rc=$rc)" FAIL
fi
if ! grep -q '^VOYAGE_API_KEY=' "$PROFILE" && ! grep -q '^JINA_API_KEY=' "$PROFILE"; then
  report "секретные строки удалены из профиля" PASS
else
  report "секретные строки удалены из профиля" FAIL
fi

# 3. блок подключения выше строки раннего выхода
LINE_EE="$(grep -n -- '\[ -z "\$PS1" \] && return' "$PROFILE" | cut -d: -f1 | head -1)"
LINE_BLOCK="$(grep -nF -- "$ENVFILE" "$PROFILE" | cut -d: -f1 | head -1)"
if [ -n "$LINE_EE" ] && [ -n "$LINE_BLOCK" ] && [ "$LINE_BLOCK" -lt "$LINE_EE" ]; then
  report "блок подключения выше строки раннего выхода ($LINE_BLOCK < $LINE_EE)" PASS
else
  report "блок подключения выше строки раннего выхода (block=$LINE_BLOCK, ee=$LINE_EE)" FAIL
fi

# 4. повторный запуск: nothing to migrate, файлы не изменены
cp -f "$PROFILE" "$TMP/profile2"
cp -f "$ENVFILE" "$TMP/env2"
OUT2="$(bash "$SCRIPT" --profile "$PROFILE" --env-file "$ENVFILE")"
rc=$?
if [ "$rc" -eq 0 ] && grep -q "nothing to migrate" <<<"$OUT2" \
  && cmp -s "$PROFILE" "$TMP/profile2" && cmp -s "$ENVFILE" "$TMP/env2"; then
  report "повторный запуск: nothing to migrate, файлы не изменены" PASS
else
  report "повторный запуск: nothing to migrate, файлы не изменены (rc=$rc)" FAIL
fi

# 5. bash -n фикстуры после миграции = 0
if bash -n "$PROFILE"; then
  report "bash -n фикстуры после миграции = 0" PASS
else
  report "bash -n фикстуры после миграции = 0" FAIL
fi

# 6. (a) строка с подстановкой команды внутри if...fi не мигрируется и остаётся
PROFILE2="$TMP/profile-2.sh"
ENVFILE2="$TMP/secrets-b/mysvcb.env"
cat > "$PROFILE2" <<EOF
# comment
if [ -f "\$HOME/creds" ]; then
  export X_TOKEN="\$(cat /tmp/fixture)"
  VOYAGE_API_KEY=$FAKE
fi
[ -z "\$PS1" ] && return
EOF
bash "$SCRIPT" --profile "$PROFILE2" --env-file "$ENVFILE2" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -qF 'export X_TOKEN="$(cat /tmp/fixture)"' "$PROFILE2" \
  && ! grep -q '^VOYAGE_API_KEY=' "$PROFILE2"; then
  report "командная подстановка не мигрируется и остаётся" PASS
else
  report "командная подстановка не мигрируется и остаётся (rc=$rc)" FAIL
fi

# 7. (b) после миграции литерала внутри if...fi файл проходит bash -n
if bash -n "$PROFILE2"; then
  report "после миграции литерала внутри if...fi bash -n = 0" PASS
else
  report "после миграции литерала внутри if...fi bash -n = 0" FAIL
fi

# 8. env-файл уже содержит запись с тем же именем и другим значением: после
#    прогона запись ровно одна и значение из профиля (сравнение по фальшивке).
PROFILE3="$TMP/profile-3.sh"
ENVFILE3="$TMP/secrets-c/mysvcc.env"
OLD="sk-OLDOLDOLDOLDOLD01"
cat > "$PROFILE3" <<EOF
MY_API_KEY=$FAKE
[ -z "\$PS1" ] && return
EOF
mkdir -p "$(dirname "$ENVFILE3")"
printf 'MY_API_KEY=%s\n' "$OLD" > "$ENVFILE3"
bash "$SCRIPT" --profile "$PROFILE3" --env-file "$ENVFILE3" >/dev/null 2>&1
rc=$?
CNT="$(grep -c '^MY_API_KEY=' "$ENVFILE3")"
if [ "$rc" -eq 0 ] && [ "$CNT" -eq 1 ] \
  && grep -q "^MY_API_KEY=$FAKE\$" "$ENVFILE3" \
  && ! grep -q "^MY_API_KEY=$OLD\$" "$ENVFILE3"; then
  report "env-файл уже имеет запись: заменена ровно одна, значение из профиля" PASS
else
  report "env-файл уже имеет запись: заменена ровно одна (rc=$rc cnt=$CNT)" FAIL
fi

# 9. env-файл содержит две строки с одним именем → после прогона остаётся ровно одна
PROFILE4="$TMP/profile-4.sh"
ENVFILE4="$TMP/secrets-d/mysvcd.env"
cat > "$PROFILE4" <<EOF
DUP_API_KEY=$FAKE
[ -z "\$PS1" ] && return
EOF
mkdir -p "$(dirname "$ENVFILE4")"
printf 'DUP_API_KEY=%s\nDUP_API_KEY=%s\n' "$OLD" "$OLD" > "$ENVFILE4"
bash "$SCRIPT" --profile "$PROFILE4" --env-file "$ENVFILE4" >/dev/null 2>&1
rc=$?
CNT="$(grep -c '^DUP_API_KEY=' "$ENVFILE4")"
if [ "$rc" -eq 0 ] && [ "$CNT" -eq 1 ] \
  && grep -q "^DUP_API_KEY=$FAKE\$" "$ENVFILE4"; then
  report "env-файл с дублями имени: остаётся ровно одна" PASS
else
  report "env-файл с дублями имени: остаётся ровно одна (rc=$rc cnt=$CNT)" FAIL
fi

if [ "$FAILS" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
fi
echo "$FAILS check(s) FAILED"
exit 1
