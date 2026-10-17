#!/bin/bash
# ccstatusline Custom Command: prints one field of our statusline panel as plain text (no ANSI, ccstatusline colors it)
# usage: statusline-segment.sh <folder|lines|ctx|ship|sdk|five|week|sess>   (Claude Code status JSON on stdin)

usage() {
  cat <<'EOF'
usage: statusline-segment.sh <folder|lines|ctx|ship|sdk|five|week|sess>
  reads Claude Code status JSON on stdin, prints one plain-text line
EOF
}

field=${1-}
case $field in
  --help) usage; exit 0 ;;
  folder|lines|ctx|ship|sdk|five|week|sess) ;;
  *) usage >&2; exit 2 ;;
esac

input=$(cat)

# jq call: needed fields as strings, "" when absent; \x1f separator is not whitespace, so empty fields survive read
fields=$(jq -r 'def n: (numbers | tostring) // "";
[
  (.workspace.current_dir // .cwd // ""),
  (.cost.total_lines_added | n),
  (.cost.total_lines_removed | n),
  (.context_window.used_percentage | n),
  (.context_window.context_window_size | n),
  (if ((.context_window // {}) | has("current_usage")) and .context_window.current_usage == null then "1" else "" end),
  (.rate_limits.five_hour.used_percentage | n),
  (.rate_limits.five_hour.resets_at | n),
  (.rate_limits.seven_day.used_percentage | n),
  (.rate_limits.seven_day.resets_at | n),
  (.session_id // "")
] | join("\u001f")' <<<"$input" 2>/dev/null)
IFS=$'\x1f' read -r dir added removed ctx_pct ctx_win cu_null h5_pct h5_reset d7_pct d7_reset sid <<<"$fields"

whole() { printf '%.0f' "$1"; }

money() { printf '$%d.%02d' $(( $1 / 100 )) $(( $1 % 100 )); }

bar() { # pct -> 10 cells: ▰ used, ▱ left
  local p=$1 n i out=""
  (( p = p < 0 ? 0 : p > 100 ? 100 : p ))
  n=$(( (p * 10 + 50) / 100 ))
  for (( i = 0; i < 10; i++ )); do
    if (( i < n )); then out+='▰'; else out+='▱'; fi
  done
  printf '%s' "$out"
}

cap_usd() { if (( $1 % 100 == 0 )); then printf '$%d' $(( $1 / 100 )); else money "$1"; fi; }

reset_hm() { [[ $1 =~ ^[0-9]+$ ]] && date -d "@$1" +%H:%M 2>/dev/null; }
reset_dm() { [[ $1 =~ ^[0-9]+$ ]] && date -d "@$1" '+%d.%m' 2>/dev/null; }

seg_folder() {
  [[ -n $dir ]] || return
  echo "📁 ${dir%/}"
}

seg_lines() {
  [[ -n $added && -n $removed ]] || return
  local a r
  a=$(whole "$added"); r=$(whole "$removed")
  (( a + r > 0 )) && echo "+$a/-$r"
}

seg_ctx() {
  [[ -n $ctx_pct ]] || return
  [[ -z $cu_null ]] || { echo "ctx ↻ compacted"; return; }
  local c limit=$CLAUDE_CODE_AUTO_COMPACT_WINDOW used left
  # shortcut: reads only user settings, not project settings or modelSettings; upgrade if those set a window
  [[ -z $limit ]] && limit=$(jq -r '.autoCompactWindow | numbers' "$HOME/.claude/settings.json" 2>/dev/null)
  [[ $limit =~ ^[0-9]+$ ]] || limit=""
  if [[ $ctx_win =~ ^[0-9]+$ && -n $limit ]] && (( limit > ctx_win )); then limit=$ctx_win; fi
  c=$(whole "$ctx_pct")
  if [[ $ctx_win =~ ^[0-9]+$ ]] && (( ctx_win > 0 )); then
    used=$(jq -n --argjson p "$ctx_pct" --argjson w "$ctx_win" '$p * $w / 100 | round')
    if [[ $limit =~ ^[0-9]+$ ]] && (( limit > 0 )); then
      left=$(( limit > used ? limit - used : 0 ))
      echo "ctx $(bar $(( used * 100 / limit ))) $((used / 1000))k/$((limit / 1000))k │ left $((left / 1000))k"
    else
      echo "ctx $(bar "$c") $((used / 1000))k/$((ctx_win / 1000))k"
    fi
    return
  fi
  echo "ctx $(bar "$c") $c%"
}

# ship: this session's deliveries only; atoms submitted in the last 24 h whose title carries our session tag; in flight ⏳, stuck ✗, delivered ✓ N
# shortcut: ownership cached per session forever; an atom never changes session
seg_ship() {
  local st=${SHIP_POST_STATE_DIR:-/root/workspaces/tools/state/ship-post}
  local post=${SHIP_POST_BIN:-/root/workspaces/tools/bin/ship-post} bd=${BD_BIN:-bd}
  local cache=${TMPDIR:-/tmp}/statusline-ship-$sid sess=${sid:0:4}
  local atoms atom own line state delivered=0 busy=() stuck=() ship
  [[ -n $sid ]] || return
  [[ -d $st/submissions ]] || { echo "ship ✓ 0"; return; }
  atoms=$(find "$st/submissions" -type f -mmin -1440 -printf '%h\n' 2>/dev/null | awk -F/ '{print $NF}' | sort -u)
  while IFS= read -r atom; do
    [[ -n $atom ]] || continue
    own=$(awk -v a="$atom" '$1 == a {print $2; exit}' "$cache" 2>/dev/null)
    if [[ -z $own ]]; then
      if [[ $("$bd" show "$atom" --json | jq -r '.[0].title // empty') == *"-$sess]"* ]]; then own=own; else own=foreign; fi
      echo "$atom $own" >>"$cache"
    fi
    [[ $own == own ]] || continue
    line=$("$post" --status "$atom" | head -n1)
    state=$(awk '{print $3}' <<<"$line")
    case $state in
      delivered) delivered=$((delivered + 1)) ;;
      parked|failed) stuck+=("$atom") ;;
      *) busy+=("$atom") ;;
    esac
  done <<<"$atoms"
  if (( ${#busy[@]} > 0 )); then
    ship="⏳ ${busy[0]}"
    (( ${#busy[@]} > 1 )) && ship+=" +$(( ${#busy[@]} - 1 ))"
  elif (( ${#stuck[@]} > 0 )); then
    ship="✗ ${stuck[0]}"
    (( ${#stuck[@]} > 1 )) && ship+=" +$(( ${#stuck[@]} - 1 ))"
  elif (( delivered > 0 )); then
    ship="✓ $delivered"
  else
    ship="✓ 0"
  fi
  (( delivered > 0 && ${#busy[@]} + ${#stuck[@]} > 0 )) && ship+=" │ ✓ $delivered"
  echo "ship $ship"
}

seg_sess() {
  [[ -n $sid ]] || return
  echo "claude ${sid: -6}"
}

seg_sdk() {
  local bin=${SDK_AGENT_BIN:-/root/workspaces/tools/bin/sdk-agent} json scaled cap spent left bound aborted line
  # sdk-agent owns the ledger and the cap: its cap --json is the only source; non-zero rc or non-JSON → no segment
  json=$("$bin" cap --json 2>/dev/null) || return
  # jq call: cap, spent, left and aborted_bound in integer cents; aborted stays a count
  scaled=$(jq -r '[.cap, .spent, .left, .aborted_bound] | map(. * 100 | round) | join(" ")' <<<"$json" 2>/dev/null) || return
  read -r cap spent left bound <<<"$scaled"
  aborted=$(jq -r '.aborted' <<<"$json" 2>/dev/null) || return
  [[ $cap =~ ^[0-9]+$ ]] && (( cap > 0 )) || return
  [[ $spent =~ ^[0-9]+$ && $left =~ ^[0-9]+$ && $bound =~ ^[0-9]+$ && $aborted =~ ^[0-9]+$ ]] || return
  line="SDK $(bar $(( spent * 100 / cap ))) $(money "$spent")/$(cap_usd "$cap") │ left $(money "$left")"
  (( aborted > 0 )) && line+=" │ aborted $aborted ≤$(money "$bound")"
  echo "$line"
}

limit_seg() {  # label, used_percentage, resets_at, reset formatter
  [[ -n $2 ]] || return
  local p t s
  p=$(whole "$2")
  s="$1 $(bar "$p") $p%"
  t=$("$4" "$3"); [[ -n $t ]] && s+=" │ reset $t"
  echo "$s"
}

seg_five() { limit_seg 5h "$h5_pct" "$h5_reset" reset_hm; }
seg_week() { limit_seg wk "$d7_pct" "$d7_reset" reset_dm; }

"seg_$field"
exit 0
