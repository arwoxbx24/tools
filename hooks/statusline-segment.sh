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

# why: the statusline refreshes every 3 s and gh is a network call, so the result lives 60 s
seg_ship() {
  local gh=${GH_BIN:-gh} bd=${BD_BIN:-bd} repo branches branch atom own n=0 ok=0
  local cache=${TMPDIR:-/tmp}/statusline-ship-pr-$sid owned=${TMPDIR:-/tmp}/statusline-ship-$sid sess=${sid:0:4}
  [[ -n $sid ]] || return
  [[ -n $(find "$cache" -mmin -1 2>/dev/null) ]] && { cat "$cache"; return; }
  for repo in ${SHIP_REPOS:-arwoxbx24/agent-contour arwoxbx24/tools}; do
    branches=$("$gh" pr list -R "$repo" --author @me --state merged --search "merged:>=$(date +%F)" --limit 100 --json headRefName --jq '.[].headRefName') || continue
    ok=1
    while IFS= read -r branch; do
      [[ $branch =~ ^(claude|codex)/([a-z]+-[a-z0-9.]+)- ]] || continue
      atom=${BASH_REMATCH[2]}
      own=$(awk -v a="$atom" '$1 == a {print $2; exit}' "$owned" 2>/dev/null)
      if [[ -z $own ]]; then
        if [[ $("$bd" show "$atom" --json | jq -r '.[0].title // empty') == *"-$sess]"* ]]; then own=own; else own=foreign; fi
        echo "$atom $own" >>"$owned"
      fi
      [[ $own == own ]] && n=$((n + 1))
    done <<<"$branches"
  done
  (( ok )) || { echo "ship ?"; return; }
  echo "ship ✓ $n" | tee "$cache"
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
