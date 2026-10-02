#!/bin/bash
# Self-check ночного запуска зон run-night.sh (spec:090 C4, FR-090-09/10,
# ADR-090-9). Всё в mktemp -d: фейковые DZ_* пути, стубы pnpm/journalctl/lsof/bd/df
# в $TMP/bin первым в PATH. Сценарии: обычный прогон, нехватка ресурсов (deferred),
# повтор в те же сутки (skipped-done), удержанный lock (locked).
#   bash scripts/tests/disk-zones-run-night-selfcheck.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RUN="$ROOT/disk-zones/run-night.sh"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
FB="$TMP/bin"; mkdir -p "$FB"
export PATH="$FB:$PATH"

# Фейковые зоны.
DZ_CODEX_HOME="$TMP/codex-home"; mkdir -p "$DZ_CODEX_HOME"
DZ_CODEX_WT="$TMP/codex-wt"; mkdir -p "$DZ_CODEX_WT"
DZ_VARLOG="$TMP/varlog"; mkdir -p "$DZ_VARLOG"
DZ_AGENT_WORK="$TMP/agent-work"; mkdir -p "$DZ_AGENT_WORK"
DZ_DOCKER_BACKUPS="$TMP/docker-backups"
mkdir -p "$DZ_DOCKER_BACKUPS/2026-10-02_06"
printf 'tar data\n' >"$DZ_DOCKER_BACKUPS/2026-10-02_06/a.tar.gz"
printf 'sql data\n' >"$DZ_DOCKER_BACKUPS/2026-10-02_06/b.sql"

# Стубы: стабильные ответы, ничего не меняют.
printf '#!/bin/bash\nif [ "$1" = store ] && [ "$2" = path ]; then echo "%s"; fi\n' \
  "$TMP/pnpm-store" >"$FB/pnpm"
printf '#!/bin/bash\necho "Archived and active journals take up 200M in the file system."\n' \
  >"$FB/journalctl"
printf '#!/bin/bash\nexit 1\n' >"$FB/lsof"
printf '#!/bin/bash\nexit 1\n' >"$FB/bd"
# Стуб df: всегда много свободного места (Available=~100 GiB в KiB) -> ресурс ок.
printf '#!/bin/bash\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "overlay 104857600 52428800 104807600 50%% /"\n' \
  >"$FB/df"
chmod +x "$FB/pnpm" "$FB/journalctl" "$FB/lsof" "$FB/bd" "$FB/df"
mkdir -p "$TMP/pnpm-store"

# Заглушки источников ресурсов (ADR-090-9: источники переопределяемы).
LOAD="$TMP/loadavg";        printf '0.02 0.05 0.08 1/100 1234\n' >"$LOAD"
MEM_OK="$TMP/meminfo-ok";   printf 'MemTotal: 1000000 kB\nMemAvailable: 500000 kB\n' >"$MEM_OK"
MEM_LOW="$TMP/meminfo-low"; printf 'MemTotal: 1000000 kB\nMemAvailable: 50000 kB\n' >"$MEM_LOW"

# Базовое окружение: ресурсы в порядке (память ок, нагрузка мала, диск ок).
BASE_ENV=(ZONE_MODE=dry-run DZ_MEMINFO="$MEM_OK" DZ_LOADAVG="$LOAD" DZ_DF_ROOT="$TMP"
  DZ_CODEX_HOME="$DZ_CODEX_HOME" DZ_CODEX_WT="$DZ_CODEX_WT"
  DZ_VARLOG="$DZ_VARLOG" DZ_AGENT_WORK="$DZ_AGENT_WORK" DZ_DOCKER_BACKUPS="$DZ_DOCKER_BACKUPS")

TSV="$TMP/zones.tsv"
SRC=( "$DZ_CODEX_HOME" "$DZ_CODEX_WT" "$DZ_VARLOG" "$DZ_AGENT_WORK" "$DZ_DOCKER_BACKUPS" )
fp() { find "${SRC[@]}" -type f 2>/dev/null | sort | xargs -r sha256sum | sort; }
nchanged() {
  diff <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) 2>/dev/null \
    | grep -c '^<'
}

PASS=0; FAIL=0
rep() { # name ok — ok=0 значит PASS
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "PASS $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}

# --- сценарий 1: обычный прогон; ресурсы в порядке -> зоны выполняются.
before=$(fp)
env "${BASE_ENV[@]}" DZ_ZONES_TSV="$TSV" DZ_STATE="$TMP/state" DZ_LOCK="$TMP/lock" \
    bash "$RUN" >/dev/null 2>&1
RC=$?
after=$(fp)
CHANGED=$(nchanged "$before" "$after")

# 1. rc=0
[ "$RC" -eq 0 ]; rep "rc=0" $?

# 2. в журнале строки зон codex, claude, docker-backup
ok=0
for z in codex claude docker-backup; do
  if ! grep -q "$z" "$TSV"; then ok=1; break; fi
done
rep "зоны codex/claude/docker-backup" "$ok"

# 3. строка compressed-1/2
grep -q 'compressed-1/2' "$TSV"; rep "строка compressed-1/2" $?

# 4. 0 изменённых файлов (dry-run, sha256 до/после)
rep "dry-run 0 изменённых файлов" "$CHANGED"

# 5. run-night.sh не вызывает codex-worktrees.sh (git — контур другого агента).
[ "$(grep -c codex-worktrees "$RUN")" = 0 ]
rep "run-night.sh не вызывает codex-worktrees" $?

# --- сценарий 2 (a): нехватка ресурсов -> state=deferred-resources, rc 0.
env "${BASE_ENV[@]}" DZ_MEMINFO="$MEM_LOW" \
    DZ_ZONES_TSV="$TMP/tsv-a" DZ_STATE="$TMP/state-a" DZ_LOCK="$TMP/lock-a" \
    DZ_WAIT_MAX=2 DZ_WAIT_STEP=1 \
    bash "$RUN" >/dev/null 2>&1
RCA=$?
grep -q 'deferred-resources' "$TMP/tsv-a"; GA=$?
[ "$RCA" -eq 0 ] && [ "$GA" -eq 0 ]
rep "a ресурсы 5% -> deferred-resources, rc 0" $?

# --- сценарий 3 (b): повтор в те же сутки -> зоны пропущены (state=skipped-done).
printf '%s %s\n' "$(date -u +%F)" codex         >"$TMP/state-b"
printf '%s %s\n' "$(date -u +%F)" claude       >>"$TMP/state-b"
printf '%s %s\n' "$(date -u +%F)" docker-backup >>"$TMP/state-b"
env "${BASE_ENV[@]}" DZ_ZONES_TSV="$TMP/tsv-b" DZ_STATE="$TMP/state-b" DZ_LOCK="$TMP/lock-b" \
    bash "$RUN" >/dev/null 2>&1
RCB=$?
SKIP=$(grep -c 'state=skipped-done' "$TMP/tsv-b" || true)
NCODE=$(grep -c $'\tcodex\t' "$TMP/tsv-b" || true)
[ "$RCB" -eq 0 ] && [ "$SKIP" -ge 2 ] && [ "$NCODE" -eq 0 ]
rep "b повтор в те же сутки -> зоны пропущены" $?

# --- сценарий 4 (c): удержанный lock -> state=locked, rc 0.
exec 10>"$TMP/lock-c"
flock -n 10
env "${BASE_ENV[@]}" DZ_ZONES_TSV="$TMP/tsv-c" DZ_STATE="$TMP/state-c" DZ_LOCK="$TMP/lock-c" \
    bash "$RUN" >/dev/null 2>&1
RCC=$?
flock -u 10; exec 10>&-
grep -q 'state=locked' "$TMP/tsv-c"; GC=$?
[ "$RCC" -eq 0 ] && [ "$GC" -eq 0 ]
rep "c удержанный flock -> state=locked, rc 0" $?

echo "PASS $PASS/8"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
