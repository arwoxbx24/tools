#!/bin/bash
# Self-check ночного запуска зон run-night.sh (spec:090 C4, FR-090-09/10).
# Всё в mktemp -d: фейковые DZ_* пути, стубы pnpm/journalctl/lsof/bd в $TMP/bin
# первым в PATH. Запуск:
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
chmod +x "$FB/pnpm" "$FB/journalctl" "$FB/lsof" "$FB/bd"
mkdir -p "$TMP/pnpm-store"

TSV="$TMP/zones.tsv"
SRC=( "$DZ_CODEX_HOME" "$DZ_CODEX_WT" "$DZ_VARLOG" "$DZ_AGENT_WORK" "$DZ_DOCKER_BACKUPS" )
fp() { find "${SRC[@]}" -type f 2>/dev/null | sort | xargs -r sha256sum | sort; }
nchanged() {
  diff <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) 2>/dev/null \
    | grep -c '^<'
}

before=$(fp)

env ZONE_MODE=dry-run DZ_ZONES_TSV="$TSV" \
    DZ_CODEX_HOME="$DZ_CODEX_HOME" DZ_CODEX_WT="$DZ_CODEX_WT" \
    DZ_VARLOG="$DZ_VARLOG" DZ_AGENT_WORK="$DZ_AGENT_WORK" \
    DZ_DOCKER_BACKUPS="$DZ_DOCKER_BACKUPS" \
    bash "$RUN" >/dev/null 2>&1
RC=$?

after=$(fp)
CHANGED=$(nchanged "$before" "$after")

PASS=0; FAIL=0
rep() { # name ok — ok=0 значит PASS
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "PASS $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}

# 1. rc=0
[ "$RC" -eq 0 ]; rep "rc=0" $?

# 2. в журнале строки зон codex, codex-wt, claude, docker-backup
ok=0
for z in codex codex-wt claude docker-backup; do
  if ! grep -q "$z" "$TSV"; then ok=1; break; fi
done
rep "зоны codex/codex-wt/claude/docker-backup" "$ok"

# 3. строка compressed-1/2
grep -q 'compressed-1/2' "$TSV"; rep "строка compressed-1/2" $?

# 4. 0 изменённых файлов (dry-run, sha256 до/после)
rep "dry-run 0 изменённых файлов" "$CHANGED"

echo "PASS $PASS/4"
[ "$FAIL" -eq 0 ] && [ "$CHANGED" -eq 0 ]
