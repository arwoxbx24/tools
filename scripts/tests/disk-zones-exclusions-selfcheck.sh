#!/bin/bash
# Self-check: исключения FR-090-06 (/home/gitmirror, hh-scoring,
# /root/workspaces/secrets) во всех исполнителях зон. Всё в mktemp -d,
# стубы pnpm/journalctl/lsof/bd в $TMP/bin первым в PATH. Запуск:
#   bash scripts/tests/disk-zones-exclusions-selfcheck.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CLAUDE="$ROOT/disk-zones/claude-zone.sh"
CODEXZONE="$ROOT/disk-zones/codex-zone.sh"
CODEXWT="$ROOT/disk-zones/codex-worktrees.sh"

TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
FB="$TMP/bin"; mkdir -p "$FB"
TSV="$TMP/zones.tsv"
export PATH="$FB:$PATH"

# Исключённые подкаталоги FR-090-06, каждый файл старый (>= age).
mkdir -p "$TMP/x/home/gitmirror/repo.git" "$TMP/y/hh-scoring" "$TMP/z/root/workspaces/secrets"
printf 'gitmirror data\n' >"$TMP/x/home/gitmirror/repo.git/f.1"
printf 'hh-scoring data\n' >"$TMP/y/hh-scoring/a.log.1"
printf 'secrets data\n' >"$TMP/z/root/workspaces/secrets/s.1"
touch -d '30 days ago' "$TMP/x/home/gitmirror/repo.git/f.1" \
                      "$TMP/y/hh-scoring/a.log.1" \
                      "$TMP/z/root/workspaces/secrets/s.1"
EXC=( "$TMP/x" "$TMP/y" "$TMP/z" )

# Стубы: не трогают файлы, возвращают стабильные ответы.
printf '#!/bin/bash\nif [ "$1" = store ] && [ "$2" = path ]; then echo "%s"; fi\n' \
  "$TMP/pnpm-store" >"$FB/pnpm"
printf '#!/bin/bash\necho "Archived and active journals take up 200M in the file system."\n' \
  >"$FB/journalctl"
printf '#!/bin/bash\nexit 1\n' >"$FB/lsof"
printf '#!/bin/bash\nexit 1\n' >"$FB/bd"
chmod +x "$FB/pnpm" "$FB/journalctl" "$FB/lsof" "$FB/bd"
mkdir -p "$TMP/pnpm-store"

fp() { find "$@" -type f 2>/dev/null | sort | xargs -r sha256sum | sort; }
nchanged() { # before after -> число изменённых файлов
  diff <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) 2>/dev/null \
    | grep -c '^<'
}

PASS=0; FAIL=0; CHANGED=0
rep() { # name changed
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "PASS $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (changed=$2)"; fi
}

# 1. claude-zone enforce: DZ_VARLOG и DZ_AGENT_WORK = корни с исключёнными подкаталогами.
before=$(fp "${EXC[@]}")
env ZONE_MODE=enforce DZ_ZONES_TSV="$TSV" DZ_VARLOG="$TMP/x" DZ_AGENT_WORK="$TMP" \
    DZ_AGE_DAYS=14 DZ_JOURNAL_MAX=200M bash "$CLAUDE" >/dev/null 2>&1
after=$(fp "${EXC[@]}")
c=$(nchanged "$before" "$after"); CHANGED=$((CHANGED + c))
rep "claude-zone enforce не трогает исключённые" "$c"

# 2. codex-zone dry-run: DZ_CODEX_HOME — корень с подкаталогом hh-scoring.
mkdir -p "$TMP/wt2"
before=$(fp "$TMP/y")
env DZ_CODEX_HOME="$TMP/y" DZ_CODEX_WT="$TMP/wt2" DZ_ZONES_TSV="$TSV" ZONE_MODE=dry-run \
    bash "$CODEXZONE" >/dev/null 2>&1
after=$(fp "$TMP/y")
c=$(nchanged "$before" "$after"); CHANGED=$((CHANGED + c))
rep "codex-zone dry-run не трогает hh-scoring" "$c"

# 3. codex-worktrees dry-run: DZ_CODEX_WT — корень с git-репо hh-scoring-x.
mkdir -p "$TMP/wt/hh-scoring-x"
printf 'worktree data\n' >"$TMP/wt/hh-scoring-x/file.txt"
git -C "$TMP/wt/hh-scoring-x" init -q
git -C "$TMP/wt/hh-scoring-x" add -A
git -C "$TMP/wt/hh-scoring-x" -c user.email=selfcheck@test -c user.name=selfcheck commit -qm init
before=$(fp "$TMP/wt/hh-scoring-x")
env DZ_CODEX_WT="$TMP/wt" DZ_ZONES_TSV="$TSV" ZONE_MODE=dry-run \
    bash "$CODEXWT" >/dev/null 2>&1
after=$(fp "$TMP/wt/hh-scoring-x")
c=$(nchanged "$before" "$after"); CHANGED=$((CHANGED + c))
rep "codex-worktrees dry-run не трогает hh-scoring-x" "$c"

echo "PASS $PASS/3"
echo "changed=$CHANGED"
[ "$FAIL" -eq 0 ] && [ "$CHANGED" -eq 0 ]
