#!/bin/bash
# Замер зоны Codex и классификация релизов standalone (spec:090 C2, ADR-090-6).
# A2 реализует только ZONE_MODE=dry-run: измерение и сухая классификация,
# ничего не удаляется. Журнал — TSV в DZ_ZONES_TSV.
set -u

ZONE_MODE=${ZONE_MODE:-dry-run}
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_CODEX_HOME=${DZ_CODEX_HOME:-/root/.codex}
DZ_CODEX_WT=${DZ_CODEX_WT:-/root/workspaces/projects/.worktrees/codex}

if [ "$ZONE_MODE" != "dry-run" ]; then
  echo "enforce не реализован в A2" >&2
  exit 2
fi

# ts zone path class size_before_mb size_after_mb freed_mb rc state
row() { # path class size_before size_after freed rc state
  printf '%s\tcodex\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" \
    | tee -a "$DZ_ZONES_TSV"
}

size_mb() { du -sm "$1" 2>/dev/null | awk '{print $1}'; }

mkdir -p "$(dirname "$DZ_ZONES_TSV")"

measure() { # path class state
  local p=$1 cls=$2 st=$3 sb
  sb=$(size_mb "$p"); sb="${sb:-0}"
  row "$p" "$cls" "$sb" "$sb" 0 0 "$st"
}

# 1. Каждый подкаталог DZ_CODEX_HOME (глубина 1) + DZ_CODEX_WT целиком.
while IFS= read -r d; do
  [ -n "$d" ] || continue
  measure "$d" И measured
done < <(find "$DZ_CODEX_HOME" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
measure "$DZ_CODEX_WT" И measured

# 2. Релизы standalone (ADR-090-6): сохраняемый набор и кандидаты.
releases_dir="$DZ_CODEX_HOME/packages/standalone/releases"
mapfile -t rels < <(ls -1 "$releases_dir" 2>/dev/null | sort -V)

if [ "${#rels[@]}" -gt 0 ]; then
  declare -A keep=()
  # цель символической ссылки current
  cur_link="$DZ_CODEX_HOME/packages/standalone/current"
  if [ -L "$cur_link" ] || [ -e "$cur_link" ]; then
    cur=$(readlink -f "$cur_link" 2>/dev/null)
    [ -n "$cur" ] && keep[$(basename "$cur")]=current
  fi
  # релиз, из которого запускается codex
  codex_bin=$(readlink -f "$(command -v codex)" 2>/dev/null || true)
  if [ -n "$codex_bin" ] && [[ "$codex_bin" == "$releases_dir/"* ]]; then
    rel=${codex_bin#"$releases_dir/"}
    keep[${rel%%/*}]=bin
  fi
  # один предыдущий по версии (роллбэк)
  n=${#rels[@]}
  [ "$n" -ge 2 ] && keep[${rels[$((n - 2))]}]=prev
  # релизы, из которых исполняется процесс
  for exe in /proc/*/exe; do
    t=$(readlink -f "$exe" 2>/dev/null || true)
    [ -n "$t" ] || continue
    [[ "$t" == "$releases_dir/"* ]] || continue
    rel=${t#"$releases_dir/"}; keep[${rel%%/*}]=proc
  done
  # lsof: rc=0 с выводом — занят; rc=1 пусто — свободен; иной rc — ошибка
  LSOF_ERROR=0
  for rel in "${rels[@]}"; do
    out=$(lsof +D "$releases_dir/$rel" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      [ -n "$out" ] && keep[$rel]=lsof
    elif [ "$rc" -ne 1 ]; then
      LSOF_ERROR=1
    fi
  done
  for rel in "${rels[@]}"; do
    sb=$(size_mb "$releases_dir/$rel"); sb="${sb:-0}"
    if [ "$LSOF_ERROR" -eq 1 ]; then
      row "$releases_dir/$rel" И "$sb" "$sb" 0 0 lsof-error
    elif [ -n "${keep[$rel]:-}" ]; then
      row "$releases_dir/$rel" И "$sb" "$sb" 0 0 "kept-${keep[$rel]}"
    else
      row "$releases_dir/$rel" У "$sb" "$sb" 0 0 candidate
    fi
  done
fi

RC=0
row - - 0 0 0 "$RC" run-done
exit "$RC"
