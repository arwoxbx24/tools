#!/usr/bin/env bash
# forms-gw-guard-test: black-box contract tests for forms-gw-guard.sh using
# stub yc/curl on PATH. Spins up a throwaway state dir, never touches real YC.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/forms-gw-guard.sh"
REAL_DATE="$(command -v date)"
SWITCH="$SCRIPT_DIR/forms-fallback-switch.sh"

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
header=""
prev=""
method=GET
body=""
for arg in "$@"; do
  if [ "$prev" = "-X" ]; then method="$arg"; prev=""; continue; fi
  if [ "$prev" = "--data-binary" ]; then body="${arg#@}"; prev=""; continue; fi
  if [ "$prev" = "-o" ]; then out_file="$arg"; prev=""; continue; fi
  if [ "$prev" = "-w" ] || [ "$prev" = "--max-time" ] || [ "$prev" = "-H" ]; then prev=""; continue; fi
  if [ "$prev" = "-K" ]; then [ "$arg" = "-" ] && use_k=1; prev=""; continue; fi
  case "$arg" in
    -s|-sS|-k) ;;
    -o|-w|--max-time|-H|-K|-X|--data-binary) prev="$arg" ;;
    *) [ -z "$url" ] && url="$arg" ;;
  esac
done
printf '%s\n' "$@" >> "$GUARD_TEST_TMP/curl.argv.log"
if [ -n "$use_k" ]; then
  while IFS= read -r line; do
    case "$line" in
      url\ =\ *)
        [ -n "$url" ] || { url="${line#url = }"; url="${url#\"}"; url="${url%\"}"; };;
      header\ =\ *)
        header="${line#header = }"; header="${header#\"}"; header="${header%\"}";;
      data-urlencode\ =\ *)
        text="${line#data-urlencode = \"text=}"; text="${text%\"}";;
    esac
  done
fi
case "$url" in
  https://vibe.test/v1/*)
    printf '%s %s\n' "$method" "$url" >> "$GUARD_TEST_TMP/api.log"
    printf '%s\n' "$header" >> "$GUARD_TEST_TMP/api.header.log"
    status=200
    response='{"data":{}}'
    if [ "$(cat "$GUARD_TEST_TMP/api.denied")" = "$method" ]; then
      status=403; response='{"error":{"code":"SCOPE_DENIED"}}'
    elif [ "$method" = PATCH ]; then
      jq -erj '.content' "$body" > "$GUARD_TEST_TMP/draft.html" || exit 90
      cp "$GUARD_TEST_TMP/draft.html" "$GUARD_TEST_TMP/last-patch.html"
      if [ -f "$GUARD_TEST_TMP/mismatch" ]; then
        printf 'mismatch' > "$GUARD_TEST_TMP/draft.html"
        rm "$GUARD_TEST_TMP/mismatch"
      fi
    elif [ "$method" = GET ]; then
      response=$(jq -n --rawfile h "$GUARD_TEST_TMP/draft.html" '{data:{html:$h}}')
    elif [ "$method" = POST ]; then
      cp "$GUARD_TEST_TMP/draft.html" "$GUARD_TEST_TMP/published.html"
    else
      exit 91
    fi
    [ -n "$out_file" ] || exit 92
    printf '%s' "$response" > "$out_file"
    printf '%s' "$status"
    ;;
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
    [ ! -f "$GUARD_TEST_TMP/resume.fail" ] || exit 1
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
unset FALLBACK_PAGE_ID FALLBACK_BLOCK_ID FALLBACK_API_URL VIBE_API_URL VIBECODE_API_KEY

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

fallback_setup() {
  printf '100000\n' > "$tmp/clock"
  printf '000\n' > "$tmp/forms.code"
  printf 'unavailable\n' > "$tmp/forms.body"
  printf 'ACTIVE\n' > "$tmp/gw.status"
  printf '100\n' > "$tmp/balance"
  printf '\n' > "$tmp/api.denied"
  rm -f "$tmp/sent.log" "$tmp/api.log" "$tmp/api.header.log" "$tmp/curl.argv.log" "$tmp/state/state.json" "$tmp/published.html" "$tmp/mismatch" "$tmp/resume.fail"
  export FALLBACK_PAGE_ID=362 FALLBACK_BLOCK_ID=9116 FALLBACK_API_URL=https://vibe.test
  export VIBECODE_API_KEY=synthetic-test-key
  export FALLBACK_SNAPSHOT="$tmp/snapshot.json"
  printf '<form action="https://forms.arwox.ru/"><button type="submit" style="color:red">Send</button></form>\n%.0s' {1..3} > "$tmp/normal.html"
  printf '<form action="https://forms.arwox.ru/"><p>Форма работает через резервный канал</p>\n<a href="https://b24-pne9rr.bitrix24.site/crm_form_yoolu/" target="_blank" rel="noopener" style="color:red">Оставить заявку</a></form>\n%.0s' {1..3} > "$tmp/outage.html"
  jq -n --rawfile h "$tmp/normal.html" '{data:{html:("<div id=\"block9116\" class=\"block-wrapper\">"+$h+"</div>")}}' > "$FALLBACK_SNAPSHOT"
  cp "$tmp/normal.html" "$tmp/draft.html"
}

run_guard() { bash "$GUARD" > "$tmp/guard.log" 2>&1; }
api_count() { if [ -f "$tmp/api.log" ]; then grep -c "^$1 " "$tmp/api.log" || true; else printf 0; fi; }

case5() { # deterministic variants, wrapper stripped, style retained
  fallback_setup
  bash "$SWITCH" build "$FALLBACK_SNAPSHOT" > "$tmp/build.log" 2>&1 || return 1
  cmp "$tmp/normal.html" "$tmp/state/fallback-normal.html" && \
    cmp "$tmp/outage.html" "$tmp/state/fallback-outage.html"
}
case6() { # two failures publish outage once, further failures do not rewrite
  fallback_setup
  run_guard; run_guard; run_guard
  [ "$(api_count PATCH)" = 1 ] && [ "$(api_count POST)" = 1 ] && \
    cmp "$tmp/outage.html" "$tmp/published.html" && \
    jq -e '.fallback_mode == "outage" and .fallback_failures >= 2' "$tmp/state/state.json" >/dev/null && \
    grep -q 'резервный канал' "$tmp/sent.log"
}
case7() { # one failed check never touches the API
  fallback_setup
  run_guard
  [ "$(api_count PATCH)" = 0 ] && [ ! -s "$tmp/api.log" ]
}
case8() { # two successes restore normal, first success cannot switch
  fallback_setup
  run_guard; run_guard
  printf '302\n' > "$tmp/forms.code"
  run_guard
  [ "$(api_count PATCH)" = 1 ] || return 1
  run_guard; run_guard
  [ "$(api_count PATCH)" = 2 ] && [ "$(api_count POST)" = 2 ] && \
    cmp "$tmp/normal.html" "$tmp/published.html" && \
    jq -e '.fallback_mode == "normal"' "$tmp/state/state.json" >/dev/null && \
    grep -q 'стандартный блок' "$tmp/sent.log"
}
case9() { # read-back mismatch restores the exact previous draft, no publication
  fallback_setup
  touch "$tmp/mismatch"
  run_guard; run_guard
  [ "$(api_count PATCH)" = 2 ] && [ "$(api_count POST)" = 0 ] && \
    cmp "$tmp/normal.html" "$tmp/draft.html" && \
    jq -e '(.fallback_mode // "normal") == "normal"' "$tmp/state/state.json" >/dev/null && \
    grep -q 'fallback_rollback' "$tmp/sent.log"
}
case10() { # foreign draft is preserved, wrapped recognized draft is accepted
  fallback_setup
  printf 'editor changes' > "$tmp/draft.html"
  run_guard; run_guard
  [ "$(api_count PATCH)" = 0 ] && [ "$(api_count POST)" = 0 ] && \
    grep -q 'fallback_foreign_draft' "$tmp/sent.log" || return 1
  [ "$(cat "$tmp/draft.html")" = 'editor changes' ] || return 1
  fallback_setup
  jq -rj '.data.html' "$FALLBACK_SNAPSHOT" > "$tmp/draft.html"
  run_guard; run_guard
  [ "$(api_count PATCH)" = 1 ] && cmp "$tmp/outage.html" "$tmp/published.html"
}
case11() { # 403 at read, write or publication alerts, mode remains normal
  local method
  for method in GET PATCH POST; do
    fallback_setup
    printf '%s\n' "$method" > "$tmp/api.denied"
    run_guard; run_guard
    [ ! -f "$tmp/published.html" ] && \
      jq -e '(.fallback_mode // "normal") == "normal"' "$tmp/state/state.json" >/dev/null && \
      grep -q '403' "$tmp/sent.log" || return 1
  done
}
case12() { # either unset id disables guard and direct apply before any API use
  local id
  for id in FALLBACK_PAGE_ID FALLBACK_BLOCK_ID; do
    fallback_setup
    export "$id="
    run_guard; run_guard
    bash "$SWITCH" apply outage > "$tmp/apply.log" 2>&1 || return 1
    [ ! -s "$tmp/api.log" ] || return 1
  done
}
case13() { # gw_failed participates in the same consecutive failure counter
  fallback_setup
  printf '403\n' > "$tmp/forms.code"
  printf 'form is stopped and cannot be used\n' > "$tmp/forms.body"
  printf 'STOPPED\n' > "$tmp/gw.status"
  touch "$tmp/resume.fail"
  run_guard; run_guard
  [ "$(api_count PATCH)" = 1 ] && cmp "$tmp/outage.html" "$tmp/published.html"
}

case14() { # transitions and API-key header bypass the six-hour default debounce
  fallback_setup
  run_guard; run_guard
  printf '302\n' > "$tmp/forms.code"
  run_guard; run_guard
  printf '000\n' > "$tmp/forms.code"
  run_guard; run_guard
  printf '302\n' > "$tmp/forms.code"
  run_guard; run_guard
  [ "$(grep -c 'резервный канал' "$tmp/sent.log")" = 2 ] && \
    [ "$(grep -c 'стандартный блок' "$tmp/sent.log")" = 2 ] && \
    ! grep -q 'synthetic-test-key' "$tmp/curl.argv.log" && \
    grep -qx 'X-API-Key: synthetic-test-key' "$tmp/api.header.log"
}

case15() { # apply errors notify each time under six hours with their own state key
  fallback_setup
  printf 'editor changes' > "$tmp/draft.html"
  run_guard; run_guard; run_guard
  [ "$(grep -c 'fallback_foreign_draft' "$tmp/sent.log")" = 2 ] && \
    jq -e 'has("fallback_foreign_draft") and (has("fallback_switch") | not)' "$tmp/state/state.json" >/dev/null || return 1
  fallback_setup
  touch "$tmp/mismatch"
  run_guard; run_guard
  grep -q 'fallback_rollback' "$tmp/sent.log" && \
    jq -e 'has("fallback_rollback") and (has("fallback_switch") | not)' "$tmp/state/state.json" >/dev/null || return 1
  fallback_setup
  printf 'GET\n' > "$tmp/api.denied"
  run_guard; run_guard; run_guard
  [ "$(grep -c 'fallback_api_http_403' "$tmp/sent.log")" = 2 ] && \
    jq -e 'has("fallback_api_http_403") and (has("fallback_switch") | not)' "$tmp/state/state.json" >/dev/null
}

case16() { # default snapshot comes from the script's repository directory
  mkdir -p "$tmp/default/forms-fallback"
  cp "$SWITCH" "$tmp/default/forms-fallback-switch.sh"
  jq '.data.html |= sub(">"; ">repository snapshot")' \
    "$SCRIPT_DIR/forms-fallback/9116-before.json" > "$tmp/default/forms-fallback/9116-before.json"
  env -u FALLBACK_SNAPSHOT GUARD_STATE_DIR="$tmp/default/state" \
    bash "$tmp/default/forms-fallback-switch.sh" build > "$tmp/build.log" 2>&1 || return 1
  grep -q '^repository snapshot' "$tmp/default/state/fallback-normal.html"
}

for i in {1..16}; do
  if "case$i"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL case %s\n' "$i"; fi
done
if [ "$FAIL" = 0 ]; then
  printf 'PASS %d/16\n' "$PASS"
  exit 0
else
  printf 'FAIL %d/16 (PASS %d/16)\n' "$FAIL" "$PASS"
  exit 1
fi
