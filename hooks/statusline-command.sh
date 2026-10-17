#!/bin/bash
input=$(cat)

# jq call 1: every field as a string, "" when absent; \x1f separator is not whitespace, so empty fields survive read
fields=$(jq -r 'def n: (numbers | tostring) // "";
[
  (.model.display_name // ""),
  (.effort.level // (if .thinking.enabled == true then "thinking" else "" end)),
  (.workspace.project_dir // .cwd // ""),
  (.worktree.branch // ""),
  (.cost.total_lines_added | n),
  (.cost.total_lines_removed | n),
  (.context_window.used_percentage | n),
  (.rate_limits.five_hour.used_percentage | n),
  (.rate_limits.five_hour.resets_at | n),
  (.rate_limits.seven_day.used_percentage | n),
  (.rate_limits.seven_day.resets_at | n),
  ((.prompt_cache.hit_ratio | numbers | . * 100 | tostring) // ""),
  (if .prompt_cache.warm == true then "warm" elif .prompt_cache.warm == false then "cold" else "" end),
  (.cost.total_cost_usd | n),
  (.workspace.current_dir // ""),
  (.context_window.context_window_size | n)
] | join("\u001f")' <<<"$input" 2>/dev/null)
IFS=$'\x1f' read -r model effort dir branch added removed ctx_pct h5_pct h5_reset d7_pct d7_reset cache_pct warm session_cost cur_dir ctx_win <<<"$fields"

color_for() {
  if (( $1 >= 80 )); then printf '\033[31m'
  elif (( $1 >= 50 )); then printf '\033[33m'
  else printf '\033[32m'; fi
}

# colored number, reset after
paint() { printf '%s%s\033[0m' "$(color_for "$1")" "$2"; }

whole() { printf '%.0f' "$1"; }

bar() {
  local filled=$(( ($1 + 5) / 10 )) out="" i
  (( filled < 0 )) && filled=0
  (( filled > 10 )) && filled=10
  for (( i = 0; i < 10; i++ )); do
    if (( i < filled )); then out+="▓"; else out+="░"; fi
  done
  printf '%s' "$out"
}

reset_hm() { [[ $1 =~ ^[0-9]+$ ]] && date -d "@$1" +%H:%M 2>/dev/null; }
reset_dm() { [[ $1 =~ ^[0-9]+$ ]] && date -d "@$1" '+%d.%m %H:%M' 2>/dev/null; }

join() {
  local out="" seg
  for seg in "$@"; do
    [[ -z $seg ]] && continue
    if [[ -z $out ]]; then out=$seg; else out+="  ·  $seg"; fi
  done
  printf '%s' "$out"
}

# line 1
seg1=()
[[ -n $model ]] && seg1+=("$model")
[[ -n $effort ]] && seg1+=("$effort")
if [[ -n $dir ]]; then
  project=${dir%/}
  project=${project##*/}
  shown="📁 $project"
  if [[ -n $cur_dir && $cur_dir != "$dir" && $cur_dir == "$dir"/* ]]; then shown+=" › ${cur_dir#"$dir"/}"; fi
  seg1+=("$shown")
fi
[[ -z $branch && -n $dir ]] && branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[[ -n $branch ]] && seg1+=("⎇ $branch")
if [[ -n $added && -n $removed ]]; then
  a=$(whole "$added"); r=$(whole "$removed")
  (( a + r > 0 )) && seg1+=("+$a/-$r")
fi

# shortcut: reads only user settings, not project settings or modelSettings; upgrade if those set a window
limit=$CLAUDE_CODE_AUTO_COMPACT_WINDOW
[[ -z $limit ]] && limit=$(jq -r '.autoCompactWindow | numbers' "$HOME/.claude/settings.json" 2>/dev/null)
[[ $limit =~ ^[0-9]+$ ]] || limit=""
if [[ $ctx_win =~ ^[0-9]+$ && -n $limit ]] && (( limit > ctx_win )); then limit=$ctx_win; fi

# line 2
seg2=()
if [[ -n $ctx_pct ]]; then
  c=$(whole "$ctx_pct")
  suffix=""
  if [[ $ctx_win =~ ^[0-9]+$ && $limit =~ ^[0-9]+$ ]] && (( ctx_win > 0 && limit > 0 )); then
    c=$(( (c * ctx_win + limit / 2) / limit ))
    suffix=" of $((limit / 1000))k"
  fi
  seg2+=("context $(paint "$c" "$(bar "$c") $c%")$suffix")
fi
if [[ -n $cache_pct ]]; then
  k=$(whole "$cache_pct")
  seg2+=("cache $k%")
fi
if [[ -n $session_cost ]]; then
  seg2+=("session \$$(printf '%.2f' "$session_cost")")
fi

# courier live state: file tests only (runs every second); mirrors ship-post do_status: receipt = delivered, parked file or .failed = stuck, else in flight
# shortcut: only submissions of the last 15 min count as in flight; slower deliveries are normally parked by the courier
st=/root/workspaces/tools/state/ship-post
if [[ -d $st ]]; then
  busy=() recent=0
  while IFS=/ read -r atom sha; do
    if compgen -G "$st/receipts/*/$atom/$sha" >/dev/null; then
      [[ -n $(find "$st"/receipts/*/"$atom"/"$sha" -mmin -10 2>/dev/null) ]] && recent=1
    elif [[ ! -e $st/incidents/parked/$atom ]] && ! compgen -G "$st/receipts/*/$atom/$sha.failed" >/dev/null; then
      busy+=("$atom")
    fi
  done < <(find "$st/submissions" -type f -mmin -15 -printf '%h/%f\n' 2>/dev/null | awk -F/ '{print $(NF-1) "/" $NF}' | sort -u)
  stuck=$(find "$st/incidents/parked" -type f 2>/dev/null | wc -l)
  ship=""
  if (( ${#busy[@]} > 0 )); then
    ship=$'\033[33m'"⏳ ${busy[0]}"$'\033[0m'
    (( ${#busy[@]} > 1 )) && ship+=" +$(( ${#busy[@]} - 1 ))"
  elif (( recent )); then
    ship=$'\033[32m✓\033[0m'
  fi
  (( stuck > 0 )) && ship+="${ship:+ }"$'\033[31m'"✗$stuck"$'\033[0m'
  [[ -n $ship ]] && seg2+=("ship $ship")
fi

# line 3: limits, SDK spend appended below
seg3=()
if [[ -n $h5_pct ]]; then
  h=$(whole "$h5_pct")
  s="5h $(paint "$h" "$(bar "$h") $h%")"
  t=$(reset_hm "$h5_reset"); [[ -n $t ]] && s+=" (reset $t)"
  seg3+=("$s")
fi
if [[ -n $d7_pct ]]; then
  d=$(whole "$d7_pct")
  s="week $(paint "$d" "$(bar "$d") $d%")"
  t=$(reset_dm "$d7_reset"); [[ -n $t ]] && s+=" (reset $t)"
  seg3+=("$s")
fi

# jq call 2: SDK spend today, in integer cents; ts is assumed to be epoch seconds
runs=/root/workspaces/tools/sdk-agent/runs.jsonl
if [[ -r $runs ]]; then
  midnight=$(date -d 'today 00:00' +%s)
  cents=$(jq -s --argjson m "$midnight" '[.[] | select((.ts | type) == "number" and .ts >= $m) | (.total_cost_usd // 0)] | add // 0 | . * 100 | round' "$runs" 2>/dev/null)
  if [[ $cents =~ ^[0-9]+$ ]]; then
    sdk_pct=$(( cents / 3 ))
    sdk_usd="\$$((cents / 100)).$(printf '%02d' $((cents % 100)))"
    seg3+=("SDK today $(paint "$sdk_pct" "$(bar "$sdk_pct") $sdk_usd") / \$3.00")
  fi
fi

for seg in "$(join "${seg1[@]}")" "$(join "${seg2[@]}")" "$(join "${seg3[@]}")"; do
  [[ -n $seg ]] && printf '%s\n' "$seg"
done
exit 0
