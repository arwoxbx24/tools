#!/usr/bin/env bash
# forms-gw-guard-test: black-box contract tests for forms-gw-guard.sh using
# stub yc/curl on PATH. Spins up a throwaway state dir, never touches real YC.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/forms-gw-guard.sh"
REAL_DATE="$(command -v date)"

tmp=$(mktemp -d /tmp/forms-gw-guard-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

cat > "$tmp/bin/date" <<'EOF'
#!/usr/bin/env bash
if [ "$#" = 1 ] && [ "$1" = '+%s' ]; then
  cat "$GUARD_TEST_TMP/clock"
else
  exec "$GUARD_TEST_REAL_DATE" "$@"
fi
EOF

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Test stub for curl. Routes by URL and reads scenario fixtures from $GUARD_TEST_TMP.
url=""
out_file=""
use_k=""
text=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out_file="$arg"; prev=""; continue; fi
  if [ "$prev" = "-w" ] || [ "$prev" = "--max-time" ] || [ "$prev" = "-H" ]; then prev=""; continue; fi
  if [ "$prev" = "-K" ]; then [ "$arg" = "-" ] && use_k=1; prev=""; continue; fi
  case "$arg" in
    -s|-k) ;;
    -o|-w|--max-time|-H|-K) prev="$arg" ;;
    *) [ -z "$url" ] && url="$arg" ;;
  esac
done
if [ -n "$use_k" ]; then
  while IFS= read -r line; do
    case "$line" in
      url\ =\ *)
        url="${line#url = }"; url="${url#\"}"; url="${url%\"}";;
      data-urlencode\ =\ *)
        text="${line#data-urlencode = \"text=}"; text="${text%\"}";;
    esac
  done
fi
case "$url" in
  *sendMessage*)
    printf '%s\n' "$text" >> "$GUARD_TEST_TMP/sent.log"
    printf '{"ok":true}\n'
    ;;
  *getMe*)
    printf '{"ok":true,"result":{"username":"StatusTrackers_bot"}}\n'
    ;;
  *billingAccounts*)
    printf '{"billingAccounts":[{"active":true,"balance":"%s"}]}\n' "$(cat "$GUARD_TEST_TMP/balance")"
    ;;
  *)
    [ -n "$out_file" ] && cat "$GUARD_TEST_TMP/forms.body" > "$out_file"
    printf '%s 0\n' "$(cat "$GUARD_TEST_TMP/forms.code")"
    ;;
esac
EOF

cat > "$tmp/bin/yc" <<'EOF'
#!/usr/bin/env bash
# Test stub for yc. Scenarios are driven by files in $GUARD_TEST_TMP.
case "$*" in
  "iam create-token"*)
    printf 'stub-token\n'
    ;;
  "serverless api-gateway get"*)
    printf '{"status":"%s"}\n' "$(cat "$GUARD_TEST_TMP/gw.status")"
    ;;
  "serverless api-gateway resume"*)
    printf '%s\n' "resume" > "$GUARD_TEST_TMP/resume.called"
    printf 'ACTIVE\n' > "$GUARD_TEST_TMP/gw.status"
    printf '302\n' > "$GUARD_TEST_TMP/forms.code"
    printf 'ok\n' > "$GUARD_TEST_TMP/forms.body"
    ;;
esac
EOF
chmod +x "$tmp/bin/curl" "$tmp/bin/yc"
chmod +x "$tmp/bin/date"

export PATH="$tmp/bin:$PATH"
export GUARD_STATE_DIR="$tmp/state"
export GUARD_TEST_TMP="$tmp"
export GUARD_TEST_REAL_DATE="$REAL_DATE"
export TG_BOT_TOKEN=test
export TG_CHAT_ID=1
export GUARD_REMINDER_SEC=3600
unset GUARD_GW_ID GUARD_FORMS_URL GUARD_BALANCE_MIN GUARD_DEBOUNCE_SEC

PASS=0
FAIL=0

case1() { # ACTIVE: forms 302, balance enough
  printf '100000\n' > "$tmp/clock"
  printf '302\n' > "$tmp/forms.code"
  printf 'ok\n' > "$tmp/forms.body"
  printf 'ACTIVE\n' > "$tmp/gw.status"
  printf '100\n' > "$tmp/balance"
  rm -f "$tmp/sent.log" "$tmp/resume.called" "$tmp/state/state.json"
  out=$(bash "$GUARD" 2>&1); rc=$?
  [ "$rc" = 0 ] && [ ! -f "$tmp/resume.called" ] && \
    { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; }
}

case2() { # STOPPED: resume succeeds, gw_resumed sent once
  printf '100000\n' > "$tmp/clock"
  printf '403\n' > "$tmp/forms.code"
  printf 'form is stopped and cannot be used\n' > "$tmp/forms.body"
  printf 'STOPPED\n' > "$tmp/gw.status"
  printf '100\n' > "$tmp/balance"
  rm -f "$tmp/sent.log" "$tmp/resume.called" "$tmp/state/state.json"
  out=$(bash "$GUARD" 2>&1); rc=$?
  n=$(grep -c 'шлюз форм был остановлен' "$tmp/sent.log" 2>/dev/null || true)
  printf '%s' "$out" | grep -q 'resume issued' && [ "$rc" = 0 ] && [ "$n" = 1 ]
}

case3() { # low balance: sends once, second run debounced
  printf '100000\n' > "$tmp/clock"
  printf '302\n' > "$tmp/forms.code"
  printf 'ok\n' > "$tmp/forms.body"
  printf 'ACTIVE\n' > "$tmp/gw.status"
  printf '5.1\n' > "$tmp/balance"
  rm -f "$tmp/sent.log" "$tmp/resume.called" "$tmp/state/state.json"
  bash "$GUARD" >/dev/null 2>&1
  out2=$(bash "$GUARD" 2>&1)
  n=$(grep -c 'Баланс Yandex Cloud' "$tmp/sent.log" 2>/dev/null || true)
  printf '%s' "$out2" | grep -q 'debounced low_balance' && [ "$n" = 1 ]
}

case4() { # outage reminders, one recovery, then a fresh immediate alert
  printf '000\n' > "$tmp/forms.code"
  printf 'unavailable\n' > "$tmp/forms.body"
  printf 'ACTIVE\n' > "$tmp/gw.status"
  printf '100\n' > "$tmp/balance"
  rm -f "$tmp/sent.log" "$tmp/resume.called" "$tmp/state/state.json"

  printf '100000\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  printf '103599\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  before=$(grep -c 'forms.arwox.ru отвечает <000>' "$tmp/sent.log" 2>/dev/null || true)
  printf '103600\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  printf '107200\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  printf '110800\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  reminders=$(grep -c 'forms.arwox.ru отвечает <000>' "$tmp/sent.log" 2>/dev/null || true)
  grep -q 'Сбой длится 0м' "$tmp/sent.log" && \
    grep -q 'Сбой длится 1ч 0м' "$tmp/sent.log" && \
    grep -q 'Сбой длится 2ч 0м' "$tmp/sent.log" && \
    grep -q 'Сбой длится 3ч 0м' "$tmp/sent.log" || return 1

  printf '302\n' > "$tmp/forms.code"
  printf 'ok\n' > "$tmp/forms.body"
  printf '110801\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  printf '110802\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  recoveries=$(grep -c 'восстановлено' "$tmp/sent.log" 2>/dev/null || true)

  printf '000\n' > "$tmp/forms.code"
  printf 'unavailable\n' > "$tmp/forms.body"
  printf '110803\n' > "$tmp/clock"; bash "$GUARD" >/dev/null 2>&1
  fresh=$(grep -c 'forms.arwox.ru отвечает <000>' "$tmp/sent.log" 2>/dev/null || true)
  [ "$before" = 1 ] && [ "$reminders" = 4 ] && [ "$recoveries" = 1 ] && \
    [ "$fresh" = 5 ] && grep -q 'восстановлено.*Сбой длился 3ч 0м' "$tmp/sent.log"
}

if case1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 1 (active/no-alert)\n'; fi
if case2; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 2 (resume)\n'; fi
if case3; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 3 (low balance debounce)\n'; fi
if case4; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 4 (outage reminders and recovery)\n'; fi

if [ "$FAIL" = 0 ]; then
  printf 'PASS 4/4\n'
  exit 0
else
  printf 'FAIL %d/4\n' "$FAIL"
  exit 1
fi
