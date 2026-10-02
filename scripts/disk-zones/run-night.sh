#!/bin/bash
# Ночной запуск зон disk-rotate (spec:090 C4, FR-090-09/10, ADR-090-9).
# Через pm2 (ecosystem: name=disk-zone-codex, cron 15 2 * * *).
# Сторож ресурсов + состояние + один прогон за раз: весь прогон под
# nice/ionice, неблокирующий flock, перед каждой зоной dz_resources_ok,
# успешные зоны записываются в DZ_STATE и в те же сутки пропускаются.
# Зоны выполняются независимо: сбой одной не останавливает остальные;
# итоговый rc — максимум. Журнал зон — общий DZ_ZONES_TSV.
set -u

ZONE_MODE=${ZONE_MODE:-dry-run}
export ZONE_MODE
DZ_ZONES_TSV=${DZ_ZONES_TSV:-/var/lib/disk-rotate/zones.tsv}
DZ_LOCK=${DZ_LOCK:-/var/lib/disk-rotate/run.lock}
DZ_STATE=${DZ_STATE:-/var/lib/disk-rotate/run-night.state}
DZ_DOCKER_BACKUPS=${DZ_DOCKER_BACKUPS:-/root/backups/docker}
DZ_WAIT_STEP=${DZ_WAIT_STEP:-60}
DZ_WAIT_MAX=${DZ_WAIT_MAX:-1800}

DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$DIR/lib-resources.sh"

mkdir -p "$(dirname "$DZ_ZONES_TSV")" "$(dirname "$DZ_LOCK")" "$(dirname "$DZ_STATE")"

# ADR-090-9: весь прогон под пониженным приоритетом; ionice нет -> без него.
if [ "${DZ_NICE_DONE:-0}" != 1 ]; then
  export DZ_NICE_DONE=1
  if command -v ionice >/dev/null 2>&1; then
    exec nice -n 19 ionice -c3 bash "$0" "$@"
  else
    exec nice -n 19 bash "$0" "$@"
  fi
fi

# Один прогон за раз: неблокирующий flock; занят -> строка locked, выход 0.
exec 9>"$DZ_LOCK" || exit 1
if ! flock -n 9; then
  printf 'state=locked\n' >>"$DZ_ZONES_TSV"
  exit 0
fi

zone_done_today() { # name -> 0, если зона уже записана в DZ_STATE сегодня (UTC)
  local name=$1 today
  today=$(date -u +%F)
  awk -v z="$name" -v d="$today" '$1==d && $2==z {f=1} END{exit !f}' "$DZ_STATE" 2>/dev/null
}

need_resources() { # name -> 0 ресурсы есть; 1 не дождались (строка deferred)
  local name=$1 waited=0
  if dz_resources_ok; then return 0; fi
  while [ "$waited" -lt "$DZ_WAIT_MAX" ]; do
    sleep "$DZ_WAIT_STEP"
    waited=$((waited + DZ_WAIT_STEP))
    dz_resources_ok && return 0
  done
  printf 'zone=%s state=deferred-resources\n' "$name" >>"$DZ_ZONES_TSV"
  return 1
}

# FR-090-09: доля сжатых по расширению файлов в последнем каталоге архивов.
zone_docker_backup() {
  local last_dir total ncomp
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
}

RC=0
DEFER=0
run_zone() { # name cmd — ресурсы, выполнение, состояние
  local name=$1 cmd=$2 rc
  if zone_done_today "$name"; then
    printf 'zone=%s state=skipped-done\n' "$name" >>"$DZ_ZONES_TSV"
    return 0
  fi
  if ! need_resources "$name"; then
    DEFER=1
    return 0
  fi
  if [ "$name" = docker-backup ]; then
    zone_docker_backup
    rc=$?
  else
    bash "$cmd"
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    printf '%s %s\n' "$(date -u +%F)" "$name" >>"$DZ_STATE"
  fi
  [ "$rc" -gt "$RC" ] && RC=$rc
}

for z in codex claude docker-backup; do
  [ "$DEFER" -eq 1 ] && break
  if [ "$z" = docker-backup ]; then
    run_zone docker-backup zone_docker_backup
  else
    run_zone "$z" "$DIR/$z-zone.sh"
  fi
done

[ "$DEFER" -eq 1 ] && exit 0
exit "$RC"
