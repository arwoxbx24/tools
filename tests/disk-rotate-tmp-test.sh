#!/bin/bash
# disk-rotate-tmp-test: cleanup_tmp чистит верхний уровень /tmp (dcfg-oglfz).
# Вызывает настоящую cleanup_tmp из scripts/disk-rotate.sh (source, DR_SOURCE_ONLY=1);
# настоящий /tmp и /var/log не трогаются, корень подменяется DR_TMP_ROOT.
# Запуск: bash tests/disk-rotate-tmp-test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/../scripts" && pwd -P)/disk-rotate.sh"

TMP="$(mktemp -d)"
ROOT="$(mktemp -d)"
BUSY_PID=""
OPENFD_PID=""

cleanup() {
  [ -n "$BUSY_PID" ] && kill "$BUSY_PID" 2>/dev/null
  [ -n "$OPENFD_PID" ] && kill "$OPENFD_PID" 2>/dev/null
  rm -rf -- "$ROOT" "$TMP"
}
trap cleanup EXIT

DR_LOG="$TMP/log"
DR_JOURNAL="$TMP/journal.tsv"
DR_LOCK_FILE="$TMP/lock"
DR_TMP_ROOT="$ROOT"
DR_SOURCE_ONLY=1
. "$SCRIPT"

MODE=run

# Фикстура: старые записи — кандидаты на удаление, свежие и защищённые — остаются.
mkdir -p "$ROOT/old-dir"
touch -d '2 days ago' "$ROOT/old-dir/inner"
touch -d '2 days ago' "$ROOT/old-dir"
touch -d '2 days ago' "$ROOT/old-file"
touch "$ROOT/fresh-file"
mkdir -p "$ROOT/tmux-0" "$ROOT/claude-0"
touch -d '2 days ago' "$ROOT/tmux-0" "$ROOT/claude-0"
touch -d '2 days ago' "$ROOT/x.lock"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.close()' "$ROOT/sock"
touch -d '2 days ago' "$ROOT/sock"
mkdir -p "$ROOT/busy"
touch -d '2 days ago' "$ROOT/busy"

# Живой процесс с cwd внутри busy/ — busy не должен удаляться.
( cd "$ROOT/busy" && exec sleep 30 ) &
BUSY_PID=$!
for _ in $(seq 1 100); do
  [ "$(readlink /proc/$BUSY_PID/cwd 2>/dev/null)" = "$ROOT/busy" ] && break
  sleep 0.05
done

# Открытый на запись файл в openfd/ (cwd вне корня) — openfd не должен удаляться.
mkdir -p "$ROOT/openfd"
( cd / && exec sleep 30 ) 3>>"$ROOT/openfd/w.log" &
OPENFD_PID=$!
touch -d '2 days ago' "$ROOT/openfd"
for _ in $(seq 1 100); do
  [ "$(readlink /proc/$OPENFD_PID/fd/3 2>/dev/null)" = "$ROOT/openfd/w.log" ] && break
  sleep 0.05
done

cleanup_tmp

FAILS=0
check_gone() { [ -e "$1" ] && { echo "FAIL $2"; FAILS=$((FAILS + 1)); }; }
check_kept() { [ ! -e "$1" ] && { echo "FAIL $2"; FAILS=$((FAILS + 1)); }; }

check_gone "$ROOT/old-dir"  old-dir
check_gone "$ROOT/old-file" old-file
check_kept "$ROOT/fresh-file" fresh-file
check_kept "$ROOT/tmux-0"    tmux-0
check_kept "$ROOT/claude-0"  claude-0
check_kept "$ROOT/x.lock"    x.lock
check_kept "$ROOT/sock"      sock
check_kept "$ROOT/busy"      busy
check_kept "$ROOT/openfd"    openfd

if [ "$FAILS" -eq 0 ]; then
  echo "TMP-TEST pass"
  exit 0
fi
echo "TMP-TEST fail"
exit 1
