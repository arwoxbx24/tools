#!/usr/bin/env bash
# ags-search-watch-test: black-box contract tests for ags-search-watch.sh using
# stub curl/gh on PATH. Spins up a throwaway state dir, never touches the real
# agentskill.sh API, GitHub, or Telegram.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/ags-search-watch.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Test stub for curl. Routes by URL and reads scenario fixtures from $AGS_TEST_TMP.
url=""
use_k=""
text=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--max-time" ] || [ "$prev" = "-w" ]; then prev=""; continue; fi
  if [ "$prev" = "-K" ]; then [ "$arg" = "-" ] && use_k=1; prev=""; continue; fi
  case "$arg" in
    -s) ;;
    --max-time|-w|-K) prev="$arg" ;;
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
    if [ -f "$AGS_TEST_TMP/tg.fail" ]; then
      printf '{"ok":false}'
    else
      printf '%s\n' "$text" >> "$AGS_TEST_TMP/sent.log"
      printf '{"ok":true}'
    fi
    ;;
  *q=python*)
    printf '%s\n%s' "$(cat "$AGS_TEST_TMP/spython.body")" "$(cat "$AGS_TEST_TMP/spython.code")"
    ;;
  *q=telegram*)
    printf '%s\n%s' "$(cat "$AGS_TEST_TMP/stelegram.body")" "$(cat "$AGS_TEST_TMP/stelegram.code")"
    ;;
esac
EOF

cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Test stub for gh api. Prints the issue state fixture; exits nonzero if gh.fail
# is present (simulates a gh failure => "unknown" state).
if [ -f "$AGS_TEST_TMP/gh.fail" ]; then exit 1; fi
printf '%s\n' "$(cat "$AGS_TEST_TMP/gh.state" 2>/dev/null)"
EOF

chmod +x "$tmp/bin/curl" "$tmp/bin/gh"

export PATH="$tmp/bin:$PATH"
export AGS_STATE_DIR="$tmp/state"
export AGS_TEST_TMP="$tmp"
export TG_BOT_TOKEN=test
export TG_CHAT_ID=1

STATE="$tmp/state/ags-search-watch.state"
WRKS='✅ Поиск навыков agentskill.sh заработал (проверено дважды подряд). /learn снова можно использовать. Нужен атом: вернуть поиск в маршрут навыков.'
CLSD='⚠️ Автор agentskill.sh закрыл задачу о сломанном поиске, но поиск всё ещё не работает. /learn пока не использовать. Нужен атом: следим дальше.'

set_search_ok() {
  printf '%s\n' '{"results":[{"slug":"python"},{"slug":"telegram-bot"}]}' > "$tmp/spython.body"
  printf '200\n' > "$tmp/spython.code"
  printf '%s\n' '{"results":[{"slug":"telegram-bot"},{"slug":"pytelegram"}]}' > "$tmp/stelegram.body"
  printf '200\n' > "$tmp/stelegram.code"
}

set_search_broken() { # empty results, still 200 => search "not working"
  printf '%s\n' '{"results":[]}' > "$tmp/spython.body"
  printf '200\n' > "$tmp/spython.code"
  printf '%s\n' '{"results":[]}' > "$tmp/stelegram.body"
  printf '200\n' > "$tmp/stelegram.code"
}

set_search_err() { # non-200 => request/transport failure
  printf '%s\n' '{}' > "$tmp/spython.body"
  printf '500\n' > "$tmp/spython.code"
  printf '%s\n' '{}' > "$tmp/stelegram.body"
  printf '500\n' > "$tmp/stelegram.code"
}

reset() {
  rm -f "$STATE" "$tmp/sent.log" "$tmp/gh.fail" "$tmp/tg.fail"
  : > "$tmp/gh.state"
}

n_sent() { # pattern -> count
  local pat="$1"
  grep -c "$pat" "$tmp/sent.log" 2>/dev/null || true
}

PASS=0
FAIL=0

case1() { # done=1 => immediate exit 0, no alerts, state untouched
  reset; set_search_ok
  printf 'ok_streak=2\ndone=1\n' > "$STATE"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  printf '%s' "$out" | grep -q 'done skipped' && [ "$rc" = 0 ] && \
    { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; } && \
    [ "$(grep '^ok_streak=' "$STATE")" = 'ok_streak=2' ]
}

case2() { # first success: no message, ok_streak 0->1, done stays 0
  reset; set_search_ok; printf 'closed\n' > "$tmp/gh.state"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; } && \
    [ "$rc" = 0 ] && [ "$(grep '^ok_streak=' "$STATE")" = 'ok_streak=1' ] && \
    [ -z "$(grep '^done=' "$STATE" 2>/dev/null)" ]
}

case3() { # second success: works message once, done=1
  reset; set_search_ok; printf 'ok_streak=1\n' > "$STATE"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$(n_sent "$WRKS")" = 1 ] && \
    [ "$(grep '^done=' "$STATE")" = 'done=1' ] && [ "$(grep '^ok_streak=' "$STATE")" = 'ok_streak=2' ]
}

case4() { # broken + closed + not notified => closed message once, closed_notified=1
  reset; set_search_broken; printf 'closed\n' > "$tmp/gh.state"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && [ "$(n_sent "$CLSD")" = 1 ] && \
    [ "$(grep '^closed_notified=' "$STATE")" = 'closed_notified=1' ]
}

case5() { # broken + closed + already notified => no duplicate
  reset; set_search_broken; printf 'closed\n' > "$tmp/gh.state"
  printf 'closed_notified=1\n' > "$STATE"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  printf '%s' "$out" | grep -q 'closed already notified' && [ "$rc" = 0 ] && \
    { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; }
}

case6() { # broken + issue open => no message
  reset; set_search_broken; printf 'open\n' > "$tmp/gh.state"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; }
}

case7() { # gh failure => unknown, no message, still exit 0
  reset; set_search_broken; printf 'closed\n' > "$tmp/gh.state"; : > "$tmp/gh.fail"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; }
}

case8() { # transport error (500) => still exit 0, no message
  reset; set_search_err; printf 'open\n' > "$tmp/gh.state"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; }
}

case9() { # AE6: ok -> err -> ok on fresh state => 0 messages, ok_streak=1
  reset; set_search_ok
  bash "$SCRIPT" >/dev/null 2>&1
  set_search_err
  bash "$SCRIPT" >/dev/null 2>&1
  set_search_ok
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && \
    { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; } && \
    [ "$(grep '^ok_streak=' "$STATE")" = 'ok_streak=1' ]
}

case10() { # AE7: two ok with tg.fail => 0 sent, done!=1; ok without => 1 works, done=1
  reset; set_search_ok
  : > "$tmp/tg.fail"
  bash "$SCRIPT" >/dev/null 2>&1
  bash "$SCRIPT" >/dev/null 2>&1
  { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; } && \
    [ -z "$(grep '^done=' "$STATE" 2>/dev/null)" ] && {
      rm -f "$tmp/tg.fail"
      bash "$SCRIPT" >/dev/null 2>&1
      [ "$(n_sent "$WRKS")" = 1 ] && [ "$(grep '^done=' "$STATE")" = 'done=1' ]
    }
}

case11() { # broken + closed + tg.fail => closed_notified != 1
  reset; set_search_broken; printf 'closed\n' > "$tmp/gh.state"
  : > "$tmp/tg.fail"
  out=$(bash "$SCRIPT" 2>&1); rc=$?
  [ "$rc" = 0 ] && \
    { [ ! -e "$tmp/sent.log" ] || [ ! -s "$tmp/sent.log" ]; } && \
    [ -z "$(grep '^closed_notified=' "$STATE" 2>/dev/null)" ]
}

if case1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 1 (done skip)\n'; fi
if case2; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 2 (first ok)\n'; fi
if case3; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 3 (works twice)\n'; fi
if case4; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 4 (closed notify)\n'; fi
if case5; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 5 (closed debounce)\n'; fi
if case6; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 6 (open no notify)\n'; fi
if case7; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 7 (gh unknown)\n'; fi
if case8; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 8 (transport err)\n'; fi
if case9; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 9 (AE6 streak reset)\n'; fi
if case10; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 10 (AE7 notify fail)\n'; fi
if case11; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case 11 (closed notify fail)\n'; fi

TOTAL=11
if [ "$FAIL" = 0 ]; then
  printf 'PASS %d/%d\n' "$PASS" "$TOTAL"
  exit 0
else
  printf 'FAIL %d/%d\n' "$FAIL" "$TOTAL"
  exit 1
fi
