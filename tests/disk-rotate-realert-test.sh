#!/bin/bash
# disk-rotate-realert-test: повтор тревоги exhausted раз в 24 ч (dcfg-demsy.23).
# Вызывает настоящую maybe_alert из scripts/disk-rotate.sh (через source, DR_SOURCE_ONLY=1),
# реальная отправка (Телеграм) не выполняется, /var/log не трогается.
# Запуск: bash tests/disk-rotate-realert-test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/../scripts" && pwd -P)/disk-rotate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

DR_LOG="$TMP/log"
DR_ALERT_STATE_FILE="$TMP/alert-state.tsv"
DR_LOCK_FILE="$TMP/lock"
DR_NOTIFY_CMD="$TMP/notify-stub.sh"
DR_REALERT_SEC=86400
DR_SOURCE_ONLY=1
. "$SCRIPT"

NOTIFY_FILE="$TMP/notify.txt"
cat >"$DR_NOTIFY_CMD" <<STUBEOF
#!/bin/bash
echo "notify \$1" >> "$NOTIFY_FILE"
STUBEOF
chmod +x "$DR_NOTIFY_CMD"

reset_fixture() { # строка состояния
  : >"$NOTIFY_FILE"
  printf '%s\n' "$1" >"$DR_ALERT_STATE_FILE"
  : >"$DR_LOG"
}

state_value() { # состояние -> значение
  awk -F= -v st="$1" '$1==st{print $2}' "$DR_ALERT_STATE_FILE" 2>/dev/null
}

FAILS=0
pos=skip
neg=skip

# pos: exhausted=now-90000 (возраст > DR_REALERT_SEC) -> отправить, epoch обновлён
now=$(date +%s)
old=$((now - 90000))
reset_fixture "exhausted=$old"
maybe_alert exhausted "диск занят после уборки"
new=$(state_value exhausted)
if [ -s "$NOTIFY_FILE" ] && [[ "$new" =~ ^[0-9]+$ ]] && [ "$new" != "$old" ]; then
  pos=sent
else
  echo "FAIL pos: exhausted=now-90000 -> заглушка не вызвана или epoch не обновлён (notify=$(wc -l <"$NOTIFY_FILE" 2>/dev/null), state=$new)"
fi

# neg: exhausted=now-3600 (возраст < DR_REALERT_SEC) -> пропуск
now=$(date +%s)
reset_fixture "exhausted=$((now - 3600))"
maybe_alert exhausted "диск занят после уборки"
if [ ! -s "$NOTIFY_FILE" ] && grep -q 'ALERT-SKIP exhausted' "$DR_LOG"; then
  neg=skip
else
  echo "FAIL neg: exhausted=now-3600 -> заглушка вызвана или нет ALERT-SKIP (notify=$(wc -l <"$NOTIFY_FILE" 2>/dev/null))"
fi

# legacy: exhausted=2026-10-06 (не число) -> отправить
reset_fixture "exhausted=2026-10-06"
maybe_alert exhausted "диск занят после уборки"
if [ -s "$NOTIFY_FILE" ]; then
  echo "PASS legacy: exhausted=2026-10-06 -> заглушка вызвана"
else
  echo "FAIL legacy: exhausted=2026-10-06 -> заглушка не вызвана"
  FAILS=$((FAILS + 1))
fi

# other: backup=now-90000 -> повтор только для exhausted, заглушка НЕ вызвана
now=$(date +%s)
reset_fixture "backup=$((now - 90000))"
maybe_alert backup "бэкап давно не делался"
if [ ! -s "$NOTIFY_FILE" ]; then
  echo "PASS other: backup=now-90000 -> заглушка не вызвана"
else
  echo "FAIL other: backup=now-90000 -> заглушка вызвана (повтор только для exhausted)"
  FAILS=$((FAILS + 1))
fi

echo "AC4 pos=$pos neg=$neg"
if [ "$pos" = sent ] && [ "$neg" = skip ] && [ "$FAILS" -eq 0 ]; then
  exit 0
fi
exit 1
