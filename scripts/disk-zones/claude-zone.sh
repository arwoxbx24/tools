#!/bin/bash
# Замер зоны Claude и сжатие старого (spec:090 FR-090-03/04/08).
# Класс К: pnpm store + journal; класс С: ротированные логи и старые файлы.
set -u
ZONE_MODE=${ZONE_MODE:-dry-run}
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_VARLOG=${DZ_VARLOG:-/var/log}
DZ_AGENT_WORK=${DZ_AGENT_WORK:-/root/workspaces/projects/.agent-work}
DZ_AGE_DAYS=${DZ_AGE_DAYS:-14}
if [ "$ZONE_MODE" != dry-run ] && [ "$ZONE_MODE" != enforce ]; then
  echo "ZONE_MODE=$ZONE_MODE" >&2; exit 2
fi
. "$(dirname "$0")/lib-compress.sh"

# ts zone path class size_before_mb size_after_mb freed_mb rc state
row() {
  printf '%s\tclaude\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" | tee -a "$DZ_ZONES_TSV"
}
size_mb() { du -sm "$1" 2>/dev/null | awk '{print $1}'; }
mb() { echo "$(( ($1 + 1048575) / 1048576 ))"; }
excluded() { case "$1" in *"/home/gitmirror"*|*"hh-scoring"*|*"/root/workspaces/secrets"*) return 0;; esac; return 1; }
jsize() {
  # Дробные значения + суффиксы B|K|M|G|T -> целые МБ (округление вверх).
  journalctl --disk-usage 2>/dev/null | awk '
    tolower($0) ~ /take up/ {
      for (i = 1; i <= NF; i++) {
        if (tolower($i) ~ /^[0-9]+([.][0-9]+)?[bkmgt]$/) {
          n = tolower($i); u = substr(n, length(n)); sub(/[bkmgt]$/, "", n)
          mult = (u == "b") ? 1/1048576 : (u == "k") ? 1/1024 : (u == "m") ? 1 : (u == "g") ? 1024 : 1048576
          v = n * mult
          print (v == int(v)) ? v : int(v) + 1
          exit
        }
      }
    }'
}
mkdir -p "$(dirname "$DZ_ZONES_TSV")"

# 1. Класс К: pnpm store.
store=$(pnpm store path 2>/dev/null | tail -n1)
if [ -n "$store" ]; then
  if excluded "$store"; then
    row "$store" К 0 0 0 0 excluded
  elif [ "$ZONE_MODE" = dry-run ]; then
    sb=$(size_mb "$store"); sb=${sb:-0}
    row "$store" К "$sb" "$sb" 0 0 measured
  else
    sb=$(size_mb "$store"); sb=${sb:-0}
    pnpm store prune >/dev/null 2>&1; rc=$?
    sa=$(size_mb "$store"); sa=${sa:-0}
    fr=$((sb - sa)); [ "$fr" -lt 0 ] && fr=0
    row "$store" К "$sb" "$sa" "$fr" "$rc" freed
  fi
fi

# 2. Класс К: journal (только замер; удаление без копии запрещено).
js=$(jsize); js=${js:-0}
row journal И "$js" "$js" 0 0 measure-only

# 3. Класс С: ротированные varlog + старые файлы agent-work.
# Для agent-work: белый список расширений и запрещённые сегменты пути.
CEXT=' .log .txt .out .jsonl .json .md .csv .tsv .html '
agent_ok() { # path -> 0 если расширение в белом списке и нет запрещённых сегментов
  case "$1" in
    */node_modules/*|*/.git/*|*/.venv/*|*/__pycache__/*|*/dist/*|*/.worktrees/*) return 1;;
  esac
  case "$CEXT" in
    *" .${1##*.} "*) return 0;;
  esac
  return 1
}
declare -A RB RA RN ROK RBUSY RFAIL
collect_c() {
  local f root rel out rc b
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if excluded "$f"; then row "$f" С 0 0 0 0 excluded; continue; fi
    if [[ "$f" == "$DZ_VARLOG"/* ]]; then
      root=$DZ_VARLOG
    else
      agent_ok "$f" || continue
      root=$DZ_AGENT_WORK
      rel=${f#"$DZ_AGENT_WORK"/}
      case "$rel" in */*) root="$DZ_AGENT_WORK/${rel%%/*}";; esac
    fi
    RN[$root]=$(( ${RN[$root]:-0} + 1 ))
    if [ "$ZONE_MODE" = dry-run ]; then
      b=$(size_mb "$f"); RB[$root]=$(( ${RB[$root]:-0} + ${b:-0} ))
      continue
    fi
    out=$(dz_compress "$f" 2>/dev/null); rc=$?
    case "$rc" in
      0) set -- $out; shift
         RB[$root]=$(( ${RB[$root]:-0} + $1 ))
         RA[$root]=$(( ${RA[$root]:-0} + $2 ))
         ROK[$root]=$(( ${ROK[$root]:-0} + 1 ));;
      3) RBUSY[$root]=$(( ${RBUSY[$root]:-0} + 1 ));;
      *) RFAIL[$root]=$(( ${RFAIL[$root]:-0} + 1 ));;
    esac
  done
}
cands_c() {
  find "$DZ_VARLOG" -maxdepth 1 -type f \( -name '*.[0-9]' -o -name '*.log.[0-9]' \) 2>/dev/null
  find "$DZ_AGENT_WORK" -type f -mtime +"$DZ_AGE_DAYS" 2>/dev/null
}
collect_c < <(cands_c)

if [ "$ZONE_MODE" = dry-run ]; then
  for root in "${!RN[@]}"; do
    b=${RB[$root]:-0}
    row "$root" С "$b" "$b" 0 0 "candidates-${RN[$root]}"
  done
else
  for root in "${!RN[@]}"; do
    n=${RN[$root]}
    sb=$(mb "${RB[$root]:-0}"); sa=$(mb "${RA[$root]:-0}")
    fr=$((sb - sa)); [ "$fr" -lt 0 ] && fr=0
    state="compressed-${ROK[$root]:-0}/$n"
    [ "${RBUSY[$root]:-0}" -gt 0 ] && state="$state,busy-${RBUSY[$root]}"
    [ "${RFAIL[$root]:-0}" -gt 0 ] && state="$state,fail-${RFAIL[$root]}"
    row "$root" С "$sb" "$sa" "$fr" 0 "$state"
  done
fi

RC=0
row - - 0 0 0 "$RC" run-done
exit "$RC"
