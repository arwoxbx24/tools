#!/bin/bash
# Ночной запуск зон disk-rotate (spec:090 C4; FR-090-09/10). Через pm2
# (ecosystem: name=disk-zone-codex, cron 15 2 * * *). Все зоны выполняются
# независимо: сбой одной не останавливает остальные; итоговый rc — максимум.
# Журнал зон — общий DZ_ZONES_TSV.
set -u

ZONE_MODE=${ZONE_MODE:-dry-run}
export ZONE_MODE
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_DOCKER_BACKUPS=${DZ_DOCKER_BACKUPS:-/root/backups/docker}

DIR="$(cd "$(dirname "$0")" && pwd -P)"

mkdir -p "$(dirname "$DZ_ZONES_TSV")"

RC=0
run_zone() { # script — выполняет зону, не прерывая цепочку
  bash "$1"
  local rc=$?
  [ "$rc" -gt "$RC" ] && RC=$rc
}

run_zone "$DIR/codex-zone.sh"
run_zone "$DIR/codex-worktrees.sh"
run_zone "$DIR/claude-zone.sh"

# FR-090-09: доля сжатых по расширению файлов в последнем каталоге архивов.
last_dir=$(ls -1d "$DZ_DOCKER_BACKUPS"/*/ 2>/dev/null | sort | tail -n1)
if [ -n "$last_dir" ] && [ -d "$last_dir" ]; then
  total=$(find "$last_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
  total=${total//[[:space:]]/}
  ncomp=$(find "$last_dir" -maxdepth 1 -type f \
    \( -name '*.gz' -o -name '*.zst' -o -name '*.xz' -o -name '*.tgz' \) \
    2>/dev/null | wc -l)
  ncomp=${ncomp//[[:space:]]/}
  printf 'zone=docker-backup class=И state=compressed-%s/%s\n' \
    "$ncomp" "$total" >>"$DZ_ZONES_TSV"
fi

exit "$RC"
