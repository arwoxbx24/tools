#!/bin/bash
# Замер зоны Claude и сжатие старого (spec:090 FR-090-03/04/08).
# Класс К: pnpm store + journal; класс С: ротированные логи и старые файлы.
set -u
ZONE_MODE=${ZONE_MODE:-dry-run}
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_VARLOG=${DZ_VARLOG:-/var/log}
DZ_AGENT_WORK=${DZ_AGENT_WORK:-/root/workspaces/projects/.agent-work}
DZ_AGE_DAYS=${DZ_AGE_DAYS:-14}
DZ_JOURNAL_MAX=${DZ_JOURNAL_MAX:-200M}
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
jsize() { journalctl --disk-usage 2>/dev/null | sed -nE 's/.*take up ([0-9]+)[KMG]? in the file system.*/\1/p' | head -n1; }
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

# 2. Класс К: journal.
jb=$(jsize); jb=${jb:-0}
if [ "$ZONE_MODE" = dry-run ]; then
  row "$DZ_VARLOG" К "$jb" "$jb" 0 0 measured
else
  journalctl --vacuum-size="$DZ_JOURNAL_MAX" >/dev/null 2>&1; rc=$?
  ja=$(jsize); ja=${ja:-0}
  fr=$((jb - ja)); [ "$fr" -lt 0 ] && fr=0
  row "$DZ_VARLOG" К "$jb" "$ja" "$fr" "$rc" freed
fi

# 3. Класс С: ротированные varlog + старые файлы agent-work.
process_file() { # path
  local f=$1 sb sa fr b1 a1 rc out
  if excluded "$f"; then row "$f" С 0 0 0 0 excluded; return; fi
  if [ "$ZONE_MODE" = dry-run ]; then
    sb=$(size_mb "$f"); sb=${sb:-0}
    row "$f" С "$sb" "$sb" 0 0 candidate
    return
  fi
  out=$(dz_compress "$f" 2>/dev/null); rc=$?
  case "$rc" in
    0) set -- $out; shift; b1=$1; a1=$2
       sb=$(mb "$b1"); sa=$(mb "$a1"); fr=$((sb - sa)); [ "$fr" -lt 0 ] && fr=0
       row "$f" С "$sb" "$sa" "$fr" 0 ok;;
    2) row "$f" С 0 0 0 2 compress-verify-fail;;
    3) row "$f" С 0 0 0 3 busy;;
    4) row "$f" С 0 0 0 4 lsof-error;;
  esac
}
cands() {
  find "$DZ_VARLOG" -maxdepth 1 -type f \( -name '*.[0-9]' -o -name '*.log.[0-9]' \) 2>/dev/null
  find "$DZ_AGENT_WORK" -type f -mtime +"$DZ_AGE_DAYS" \( ! -name '*.zst' ! -name '*.gz' \) 2>/dev/null
}
while IFS= read -r f; do [ -n "$f" ] && process_file "$f"; done < <(cands)

RC=0
row - - 0 0 0 "$RC" run-done
exit "$RC"
