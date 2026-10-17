#!/bin/bash
# tests for statusline-segment.sh: fixture status JSON on stdin, exact/substring output, exit codes, timing
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
seg=$here/statusline-segment.sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/input.json" <<'EOF'
{
  "model": {"display_name": "Opus 5.5"},
  "cwd": "/root/workspaces/projects",
  "cost": {"total_lines_added": 184, "total_lines_removed": 3},
  "context_window": {"used_percentage": 17.1, "context_window_size": 1000000},
  "rate_limits": {
    "five_hour": {"used_percentage": 5, "resets_at": 1792235400},
    "seven_day": {"used_percentage": 13, "resets_at": 1792594800}
  }
}
EOF

export TZ=Europe/Moscow CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000
capbin() {  # path, json: fixture sdk-agent whose cap --json prints json
  printf "#!/bin/bash\necho '%s'\n" "$2" >"$1"; chmod +x "$1"
}
# default sdk-agent for the seg_sdk cases below: the live binary is not needed
capbin "$tmp/sdk-agent" '{"cap":6,"spent":3.77,"reserved":0,"aborted":0,"aborted_bound":0,"left":2.23}'
export SDK_AGENT_BIN="$tmp/sdk-agent"
total=0 pass=0

check() {  # name, got, want: exact match
  total=$((total + 1))
  if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else echo "FAIL $1: got [$2] want [$3]" >&2; fi
}

match() {  # name, got, ERE: regex match
  total=$((total + 1))
  if [[ $2 =~ $3 ]]; then pass=$((pass + 1)); else echo "FAIL $1: got [$2] want match [$3]" >&2; fi
}

field_out() {  # field -> out (stdout), ms (wall time)
  local t0 t1
  t0=$(date +%s%N)
  out=$("$seg" "$1" <"$tmp/input.json")
  t1=$(date +%s%N)
  ms=$(( (t1 - t0) / 1000000 ))
}

declare -A got
for f in folder lines ctx ship sdk five week sess; do
  field_out "$f"; got[$f]=$out
  total=$((total + 1))
  if (( ms < 300 )); then pass=$((pass + 1)); else echo "FAIL $f: took ${ms} ms" >&2; fi
done

check folder "${got[folder]}" "📁 /root/workspaces/projects"
check lines "${got[lines]}" "+184/-3"
check ctx "${got[ctx]}" "ctx ▰▰▰▰▰▰▱▱▱▱ 171k/300k │ left 129k"
check five "${got[five]}" "5h ▰▱▱▱▱▱▱▱▱▱ 5% │ reset 14:10"
check week "${got[week]}" "wk ▰▱▱▱▱▱▱▱▱▱ 13% │ reset 21.10"
match sdk "${got[sdk]}" '^SDK [▰▱]{10} \$[0-9]+\.[0-9]{2}/\$[0-9]+(\.[0-9]{2})? │ left \$[0-9]+\.[0-9]{2}$'
# sdk: a run without a price counts as the 2.00 USD per-run ceiling; yesterday's runs do not count
now=$(date +%s)
printf '%s\n' "{\"ts\": $now, \"total_cost_usd\": 0.25}" "{\"ts\": $now}" "{\"ts\": $((now - 172800)), \"total_cost_usd\": 1}" >"$tmp/runs.jsonl"
printf 'readonly MAX_BUDGET="2.00"\nreadonly DAILY_CAP="3.00"\n' >"$tmp/agent-cap3"
capbin "$tmp/agent-cap3" '{"cap":3,"spent":2.25,"reserved":0,"aborted":0,"aborted_bound":0,"left":0.75}'
check sdk-runs "$(SDK_AGENT_BIN="$tmp/agent-cap3" SDK_AGENT_RUNS_LOG="$tmp/runs.jsonl" "$seg" sdk <"$tmp/input.json")" 'SDK ▰▰▰▰▰▰▰▰▱▱ $2.25/$3 │ left $0.75'
printf 'readonly MAX_BUDGET="2.00"\nreadonly DAILY_CAP="5.00"\n' >"$tmp/agent-cap5"
capbin "$tmp/agent-cap5" '{"cap":5,"spent":2.25,"reserved":0,"aborted":0,"aborted_bound":0,"left":2.75}'
check sdk-cap5 "$(SDK_AGENT_BIN="$tmp/agent-cap5" SDK_AGENT_RUNS_LOG="$tmp/runs.jsonl" "$seg" sdk <"$tmp/input.json")" 'SDK ▰▰▰▰▰▱▱▱▱▱ $2.25/$5 │ left $2.75'
cp "$tmp/runs.jsonl" "$tmp/inflight-runs.jsonl"
printf '{"ts": %s, "budget": 0.50}\n' "$now" >"$tmp/inflight-runs.jsonl.inflight"
capbin "$tmp/agent-cap3" '{"cap":3,"spent":2.25,"reserved":0.5,"aborted":0,"aborted_bound":0,"left":0.25}'
check sdk-inflight "$(SDK_AGENT_BIN="$tmp/agent-cap3" SDK_AGENT_RUNS_LOG="$tmp/inflight-runs.jsonl" "$seg" sdk <"$tmp/input.json")" 'SDK ▰▰▰▰▰▰▰▰▱▱ $2.25/$3 │ left $0.25'
printf 'readonly MAX_BUDGET="2.00"\n' >"$tmp/agent-nocap"
printf '#!/bin/bash\nexit 1\n' >"$tmp/agent-nocap"; chmod +x "$tmp/agent-nocap"
check sdk-nocap "$(SDK_AGENT_BIN="$tmp/agent-nocap" SDK_AGENT_RUNS_LOG="$tmp/runs.jsonl" "$seg" sdk <"$tmp/input.json")" ''
total=$((total + 1))
if [[ "${got[*]}" == *▓* || "${got[*]}" == *░* || "${got[*]}" == *·* || "${got[*]}" == *█* || "${got[*]}" == *─* ]]; then echo "FAIL no-bars: [${got[*]}]" >&2; else pass=$((pass + 1)); fi

line=$(printf '%s' '{"context_window":{"used_percentage":87,"context_window_size":300000,"current_usage":null}}' | "$seg" ctx)
total=$((total + 1))
if [[ $line == 'ctx ↻ compacted' ]]; then pass=$((pass + 1)); echo 'PASS ctx_after_compact'; else echo "FAIL ctx_after_compact: got [$line]" >&2; fi

capbin "$tmp/agent-cap6" '{"cap":6,"spent":3.77,"reserved":0,"aborted":3,"aborted_bound":1.5,"left":0.73}'
line=$(SDK_AGENT_BIN="$tmp/agent-cap6" "$seg" sdk <"$tmp/input.json")
total=$((total + 1))
if [[ $line == *'$3.77/$6'* && $line == *'left $0.73'* && $line == *'aborted 3 ≤$1.50'* ]]; then pass=$((pass + 1)); echo 'PASS sdk_matches_cap'; else echo "FAIL sdk_matches_cap: got [$line]" >&2; fi

# ship: only this session's deliveries; fake ship-post state, bd and ship-post live in a temp dir
sf=$tmp/shipfx
mkdir -p "$sf/tmp" "$sf/state/submissions/r/w/own-a" "$sf/state/submissions/r/w/own-b" "$sf/state/submissions/r/w/foreign-c"
touch "$sf/state/submissions/r/w/own-a/sha1" "$sf/state/submissions/r/w/own-b/sha2" "$sf/state/submissions/r/w/foreign-c/sha3"
cat >"$sf/bd" <<'EOF'
#!/bin/bash
case $2 in
  own-a|own-b) echo '[{"title":"[CLAUDE-x-83bc] t"}]' ;;
  *) echo '[{"title":"[CLAUDE-x-zzzz] t"}]' ;;
esac
EOF
cat >"$sf/ship-post" <<'EOF'
#!/bin/bash
echo "$2 abc1234 $(cat "$(dirname "$0")/state-$2")"
EOF
chmod +x "$sf/bd" "$sf/ship-post"
ship_run() {  # session_id, states of own-a, own-b, foreign-c -> ship field
  printf '%s' "$2" >"$sf/state-own-a"; printf '%s' "$3" >"$sf/state-own-b"; printf '%s' "$4" >"$sf/state-foreign-c"
  printf '{"session_id":"%s"}' "$1" | TMPDIR=$sf/tmp SHIP_POST_STATE_DIR=$sf/state SHIP_POST_BIN=$sf/ship-post BD_BIN=$sf/bd "$seg" ship
}
check ship-a "$(ship_run 83bcb363-test submitted delivered delivered)" "ship ⏳ own-a │ ✓ 1"
check ship-b "$(ship_run 83bcb363-test delivered delivered delivered)" "ship ✓ 2"
check ship-c "$(ship_run 83bcb363-test parked delivered delivered)" "ship ✗ own-a │ ✓ 1"
check ship-d "$(ship_run 9999aaaa-test delivered delivered delivered)" "ship ✓ 0"
check ship-e "$(ship_run 83bcb363-test delivered delivered parked)" "ship ✓ 2"
mkdir -p "$sf/state2/submissions"
check ship-empty "$(printf '{"session_id":"83bcb363-test"}' | TMPDIR=$sf/tmp SHIP_POST_STATE_DIR=$sf/state2 SHIP_POST_BIN=$sf/ship-post BD_BIN=$sf/bd "$seg" ship)" "ship ✓ 0"
check sess "$(printf '{"session_id":"f4ea9812-0000-183f5b37174d"}' | "$seg" sess)" "claude 37174d"
check sess-empty "$(printf '{}' | "$seg" sess)" ""

"$seg" bogus <"$tmp/input.json" >/dev/null 2>&1; rc=$?
check unknown-field-rc "$rc" 2
"$seg" --help </dev/null >/dev/null; rc=$?
check help-rc "$rc" 0

echo "PASS $pass/$total"
[[ $pass -eq $total ]]
