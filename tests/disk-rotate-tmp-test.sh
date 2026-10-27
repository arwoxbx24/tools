#!/bin/bash
# disk-rotate-tmp-test: cleanup_tmp чистит верхний уровень /tmp (dcfg-oglfz).
# Вызывает настоящую cleanup_tmp из scripts/disk-rotate.sh (source, DR_SOURCE_ONLY=1);
# настоящий /tmp и /var/log не трогаются, корень подменяется DR_TMP_ROOT.
# Запуск: bash tests/disk-rotate-tmp-test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/../scripts" && pwd -P)/disk-rotate.sh"

TMP="$(mktemp -d)"
ROOT="$(mktemp -d)"
CX="$(mktemp -d)"
BUSY_PID=""
OPENFD_PID=""
CC_PID=""

cleanup() {
  [ -n "$BUSY_PID" ] && kill "$BUSY_PID" 2>/dev/null
  [ -n "$OPENFD_PID" ] && kill "$OPENFD_PID" 2>/dev/null
  [ -n "$CC_PID" ] && kill "$CC_PID" 2>/dev/null
  rm -rf -- "$ROOT" "$TMP" "$CX"
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

# codex-clean: полный прогон скрипта в тестовом режиме (DR_TEST_ONLY=1) на фикстуре $CX; restic — заглушка.
LEDGER="$TMP/ledger.tsv"
LIVE_CX="$CX/live-sibling.txt"
STUB="$TMP/restic-stub"
NOTIFY="$TMP/notify"
cat >"$STUB" <<'EOF'
#!/bin/bash
case "$1" in
  backup) echo '{"message_type":"summary","snapshot_id":"stub0001"}' ;;
  ls) find -P "$STUB_ROOT" -type f -print0 | while IFS= read -r -d '' f; do
        jq -cn --arg p "$f" --argjson s "$(stat -c %s "$f")" --arg m "$(date -Is -r "$f")" \
          '{struct_type:"node",type:"file",path:$p,size:$s,mtime:$m}'
      done ;;
  snapshots) echo '[{"tags":["predelete"]}]' ;;
esac
exit 0
EOF
chmod +x "$STUB"
cat >"$NOTIFY" <<EOF
#!/bin/bash
echo "\$1" >>"$TMP/notify.log"
EOF
chmod +x "$NOTIFY"
date +%s >"$TMP/last-ok"

run_codex() { # один прогон скрипта: только codex-классы на фикстуре
  DR_TEST_ONLY=1 DR_CODEX_HOME="$CX" DR_CODEX_CLEAN_IDLE_MIN="${CC_IDLE_MIN:-1440}" STUB_ROOT="$CX" GATE_MODE=enforce DR_USAGE_PCT=50 \
    RESTIC="$STUB" DR_RESTIC_REPO="$TMP/repo" DR_RESTIC_PASSWORD_FILE="$TMP/pw" \
    DR_LAST_OK="$TMP/last-ok" DR_NOTIFY_CMD="$NOTIFY" DR_ZONES_TSV="$TMP/zones.tsv" \
    DR_LOG="$TMP/log" DR_JOURNAL="$TMP/journal.tsv" DR_JOURNAL_COPY="$TMP/journal-copy.tsv" \
    DR_LOCK_FILE="$TMP/lock-cx" DR_LEDGER="$LEDGER" DR_STATE_FILE="$TMP/fixed.tsv" \
    DR_LOGROTATE_STATE="$TMP/logrotate.state" DR_ALERT_STATE_FILE="$TMP/alert.tsv" \
    bash "$SCRIPT" >/dev/null 2>&1
}

ledger_state() { awk -F'\t' -v m="codex-clean:$1" '$2 == m {s = $6} END {print s}' "$LEDGER"; }
expect_eq() { [ "$2" = "$3" ] || { echo "FAIL $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); }; }

mkdir -p "$CX/codex-clean.idle1/sub" "$CX/codex-clean.fresh1" "$CX/codex-clean.busy1"
echo a >"$CX/codex-clean.idle1/a.log"
echo b >"$CX/codex-clean.idle1/sub/b.bin"
echo c >"$CX/codex-clean.fresh1/c.log"
echo d >"$CX/codex-clean.busy1/d.log"
echo live >"$LIVE_CX"
touch -d '2 days ago' "$CX/codex-clean.idle1/a.log" "$CX/codex-clean.idle1/sub/b.bin" \
  "$CX/codex-clean.idle1/sub" "$CX/codex-clean.idle1" \
  "$CX/codex-clean.busy1/d.log" "$CX/codex-clean.busy1" "$LIVE_CX"

# Живой процесс с cwd внутри busy1 — каталог не должен уходить в гейт.
( cd "$CX/codex-clean.busy1" && exec sleep 600 ) &
CC_PID=$!
for _ in $(seq 1 100); do
  [ "$(readlink /proc/$CC_PID/cwd 2>/dev/null)" = "$CX/codex-clean.busy1" ] && break
  sleep 0.05
done

# Прогон 1: idle1 уходит в гейт (копия и ещё не удалён), fresh1 и busy1 остаются.
run_codex
check_kept "$CX/codex-clean.idle1/a.log" idle-copied-not-yet-deleted
expect_eq idle-run1 "$(ledger_state codex-clean.idle1)" pending
expect_eq fresh-run1 "$(ledger_state codex-clean.fresh1)" fresh
expect_eq busy-run1 "$(ledger_state codex-clean.busy1)" in-use

# Прогон 2: idle1 проверен по снимку и удалён целиком; остальное не тронуто.
run_codex
check_gone "$CX/codex-clean.idle1" idle-dir-deleted
expect_eq idle-run2 "$(ledger_state codex-clean.idle1)" deleted
check_kept "$CX/codex-clean.fresh1/c.log" fresh-dir-kept
expect_eq fresh-run2 "$(ledger_state codex-clean.fresh1)" fresh
check_kept "$CX/codex-clean.busy1/d.log" in-use-dir-kept
expect_eq busy-run2 "$(ledger_state codex-clean.busy1)" in-use
check_kept "$LIVE_CX" sibling-live-file-kept
expect_eq sibling-content "$(cat "$LIVE_CX" 2>/dev/null)" live

# codex-clean: битый DR_CODEX_CLEAN_IDLE_MIN — bad-config, без гейта и без удаления.
mkdir -p "$CX/codex-clean.badcfg1"
echo e >"$CX/codex-clean.badcfg1/e.log"
touch -d '2 days ago' "$CX/codex-clean.badcfg1/e.log" "$CX/codex-clean.badcfg1"
CC_IDLE_MIN=abc run_codex
expect_eq badcfg-abc "$(ledger_state codex-clean.badcfg1)" bad-config
check_kept "$CX/codex-clean.badcfg1" badcfg-abc-dir-kept
check_kept "$CX/codex-clean.badcfg1/e.log" badcfg-abc-file-kept
CC_IDLE_MIN=0 run_codex
expect_eq badcfg-zero "$(ledger_state codex-clean.badcfg1)" bad-config
check_kept "$CX/codex-clean.badcfg1/e.log" badcfg-zero-file-kept

# --codex-clean --dry-run: только вердикты codex-clean, ничего не удаляется.
mkdir -p "$CX/codex-clean.dryidle"
echo f >"$CX/codex-clean.dryidle/f.log"
touch -d '2 days ago' "$CX/codex-clean.dryidle/f.log" "$CX/codex-clean.dryidle"
DRY_OUT=$(DR_CODEX_HOME="$CX" DR_LOG="$TMP/log" DR_JOURNAL="$TMP/journal.tsv" \
  DR_JOURNAL_COPY="$TMP/journal-copy.tsv" DR_LOCK_FILE="$TMP/lock-cx" DR_LEDGER="$LEDGER" \
  DR_STATE_FILE="$TMP/fixed.tsv" DR_LOGROTATE_STATE="$TMP/logrotate.state" \
  DR_ALERT_STATE_FILE="$TMP/alert.tsv" DR_LAST_OK="$TMP/last-ok" \
  bash "$SCRIPT" --codex-clean --dry-run 2>/dev/null)
expect_eq dryidle-eligible "$(grep -cx 'codex-clean codex-clean.dryidle: eligible' <<<"$DRY_OUT")" 1
expect_eq dry-no-other-output "$(grep -vcE '^(codex-clean |$)' <<<"$DRY_OUT")" 0
check_kept "$CX/codex-clean.dryidle" dryidle-dir-kept
check_kept "$CX/codex-clean.dryidle/f.log" dryidle-file-kept

kill "$CC_PID" 2>/dev/null
wait "$CC_PID" 2>/dev/null
CC_PID=""

if [ "$FAILS" -eq 0 ]; then
  echo "TMP-TEST pass"
  exit 0
fi
echo "TMP-TEST fail"
exit 1
