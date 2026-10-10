#!/bin/bash
# Self-check гейта disk-rotate.sh (spec:055): «сначала копия restic, удаление
# в следующем прогоне». Запуск вручную, как root:
#   bash scripts/tests/disk-rotate-gate-selfcheck.sh
#
# Каждый сценарий работает в собственной поддиректории-фикстуре под /tmp
# (свои state, journal, repo, lastok, alerts), чтобы сценарии не влияли друг
# на друга. По завершении вся временная фикстура убирается.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-rotate.sh"
RESTIC=

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# Host-wide ledger sizes are irrelevant to fixture behavior; never scan host data.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/du" <<'DUEOF'
#!/bin/bash
case "$*" in
  '-sm /root/workspaces'|'-sm /var/lib/docker'|'-sm /root/backups'|'-sm /root/.local'|'-sm /tmp') printf '0\tfixture\n' ;;
  *) exec /usr/bin/du "$@" ;;
esac
DUEOF
chmod +x "$TMP/bin/du"
export PATH="$TMP/bin:$PATH"

# --- текущая фикстура (глобальные пути, пересобираются fixture <<имя>>) ---
I= R= STATE= JOURNAL= LASTOK= LOCK= LEDGER= TLOG= ALERTS= NOTIFY= S=
NOTIFY_STUB= REPO= PASSFILE=
RUN_ENV=()
A= B= C= D= E= F= SP=
O_A= O_B= O_C= O_D= O_E= O_F=

mock_restic() { # fixture-local stub: only the operations exercised by this selfcheck
  RESTIC="$S/restic"
  cat >"$RESTIC" <<'PY'
#!/usr/bin/env python3
import datetime
import json
import os
import pathlib
import shutil
import sys

raw_args = sys.argv[1:]
args = list(raw_args)

def option(name):
    try:
        return raw_args[raw_args.index(name) + 1]
    except (ValueError, IndexError):
        return None

repo = option("--repo") or option("-r") or os.environ.get("RESTIC_REPOSITORY")
if not repo:
    print("mock-restic: repository missing", file=sys.stderr)
    sys.exit(2)
root = pathlib.Path(repo)
index = root / "index.json"

while args and args[0] in ("-r", "--repo", "--password-file"):
    del args[:2]
cmd = args[0] if args else ""

def load_index():
    return json.loads(index.read_text()) if index.exists() else []

def save_index(items):
    index.write_text(json.dumps(items))

if cmd == "init":
    root.mkdir(parents=True, exist_ok=True)
    (root / "config").write_text("mock\n")
    save_index([])
elif cmd == "cat" and len(args) > 1 and args[1] == "config":
    if not (root / "config").is_file():
        sys.exit(1)
elif cmd == "check":
    sys.exit(int(os.environ.get("RESTIC_CHECK_RC", "0")))
elif cmd == "backup":
    listfile = option("--files-from-verbatim")
    if not listfile:
        sys.exit(2)
    paths = [line for line in pathlib.Path(listfile).read_text().splitlines() if line]
    if not paths or any(not pathlib.Path(path).is_file() for path in paths):
        print("mock-restic: source missing", file=sys.stderr)
        sys.exit(1)
    items = load_index()
    snapshot_id = f"mock{len(items) + 1:08d}"
    saved = root / "snapshots" / snapshot_id
    saved.mkdir(parents=True)
    files = []
    for n, path in enumerate(paths):
        source = pathlib.Path(path)
        target = saved / str(n)
        shutil.copy2(source, target)
        stat = source.stat()
        files.append({"path": path, "size": stat.st_size,
                      "mtime": datetime.datetime.fromtimestamp(stat.st_mtime, datetime.timezone.utc).isoformat(),
                      "saved": str(n)})
    items.append({"id": snapshot_id, "short_id": snapshot_id, "tags": [option("--tag") or ""], "files": files})
    save_index(items)
    print(json.dumps({"message_type": "summary", "snapshot_id": snapshot_id}))
elif cmd == "snapshots":
    items = load_index()
    tag = option("--tag")
    if tag:
        items = [item for item in items if tag in item["tags"]]
    if option("--latest") and items:
        items = [items[-1]]
    if "--json" in args:
        print(json.dumps([{key: item[key] for key in ("id", "short_id", "tags")} for item in items]))
    else:
        for item in items:
            print(f"{item['short_id']} {' '.join(item['tags'])}")
elif cmd == "ls":
    ids = [arg for arg in args[1:] if not arg.startswith("-")]
    item = next((item for item in load_index() if item["id"] == ids[-1]), None) if ids else None
    if not item:
        sys.exit(1)
    for file in item["files"]:
        print(json.dumps({"struct_type": "node", "type": "file", "path": file["path"],
                          "size": file["size"], "mtime": file["mtime"]}))
elif cmd == "restore":
    ids = [arg for arg in args[1:] if not arg.startswith("-")]
    target = option("--target")
    item = next((item for item in load_index() if item["id"] == ids[0]), None) if ids else None
    if not item or not target:
        sys.exit(1)
    for file in item["files"]:
        destination = pathlib.Path(target) / file["path"].lstrip("/")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / "snapshots" / item["id"] / file["saved"], destination)
elif cmd == "forget":
    pass
else:
    print(f"mock-restic: unsupported {' '.join(args)}", file=sys.stderr)
    sys.exit(2)
PY
  chmod +x "$RESTIC"
}

fixture() { # имя -> новая фикстура в $TMP/$имя (свой restic, state, journal, lastok)
  local name=$1
  local d="$TMP/$name"
  S="$d"
  I="$d/irreplaceable"
  R="$d/replaceable"
  mkdir -p "$I" "$R"
  STATE="$d/state.tsv"
  JOURNAL="$d/journal.tsv"
  LASTOK="$d/lastok"
  LOCK="$d/lock"
  LEDGER="$d/ledger.tsv"
  TLOG="$d/log"
  ALERTS="$d/alerts"
  NOTIFY="$d/notify.txt"
  date +%s >"$LASTOK"   # гейт открыт по умолчанию
  REPO="$d/repo"
  PASSFILE="$d/pw"
  printf 'fixture-pass-%s-%s\n' "$RANDOM" "$RANDOM" >"$PASSFILE"
  mock_restic
  if ! "$RESTIC" init --repo "$REPO" --password-file "$PASSFILE" >/dev/null 2>&1; then
    echo "FIXTURE-ERROR: restic init failed ($RESTIC)" >&2
    exit 2
  fi
  # Заглушка доставки сводки: пишет строку в файл фикстуры.
  NOTIFY_STUB="$d/notify-stub.sh"
  cat >"$NOTIFY_STUB" <<NOTIFYEOF
#!/bin/bash
echo "\$1" >>"$NOTIFY"
NOTIFYEOF
  chmod +x "$NOTIFY_STUB"

  RUN_ENV=(DR_TEST_ONLY=1
    DR_USAGE_PCT=85
    DR_STATE_FILE="$STATE"
    DR_JOURNAL="$JOURNAL"
    DR_LAST_OK="$LASTOK"
    DR_ALERT_STATE_FILE="$ALERTS"
    DR_LOCK_FILE="$LOCK"
    DR_LEDGER="$LEDGER"
    DR_ZONES_TSV="$S/zones.tsv"
    DR_LOG="$TLOG"
    DR_LOGROTATE_STATE="$d/logrotate.state"
    DR_NOTIFY_CMD="$NOTIFY_STUB"
    NOTIFY_ENV="$d/empty-notify.env"
    DR_RESTIC_REPO="$REPO"
    DR_RESTIC_PASSWORD_FILE="$PASSFILE"
    DR_JOURNAL_COPY="$d/journal-copy.tsv"
    RESTIC="$RESTIC"
    DR_TEST_IRREPLACEABLE_DIR="$I"
    DR_TEST_REPLACEABLE_DIR="$R")

  A="$I/crit.data";   B="$I/mod.data";   C="$I/shadow.data"
  D="$I/hot.data";    E="$I/lastok.data"; F="$R/rep.data"
  SP="$I/spaced file.data"
  O_A="$d/orig-A"; O_B="$d/orig-B"; O_C="$d/orig-C"
  O_D="$d/orig-D"; O_E="$d/orig-E"; O_F="$d/orig-F"
}

snapshots() { "$RESTIC" -r "$REPO" --password-file "$PASSFILE" snapshots "$@"; }

run_rotate() { # [ENV=A...] -- [ARGS...] -> запускает disk-rotate.sh в текущей фикстуре
  local arg extras=() args=() passthrough=0
  for arg in "$@"; do
    if [ "$arg" = "--" ]; then passthrough=1; continue; fi
    if [ "$passthrough" = 0 ]; then extras+=("$arg"); else args+=("$arg"); fi
  done
  env "${RUN_ENV[@]}" "${extras[@]}" "$SCRIPT" "${args[@]}"
}

FAILS=0
report() { # num name status
  if [ "$3" = PASS ]; then
    echo "PASS $1 $2"
  else
    echo "FAIL $1 $2"
    FAILS=$((FAILS + 1))
  fi
}

jline() { # файл -> последняя строка журнала для этого пути (кол. 6)
  awk -F'\t' -v p="$1" '$6==p{print}' "$JOURNAL" 2>/dev/null | tail -1
}

scenario_1() { # незаменимый файл, прогон 1: фиксируется (снимок) и НЕ удаляется
  fixture scen1
  printf 'critical payload line\n' >"$A"
  cp -f "$A" "$O_A"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  if [ -f "$A" ] \
     && snapshots --tag predelete 2>/dev/null | grep -q 'predelete' \
     && grep -q $'\tfixed\t' "$JOURNAL" 2>/dev/null; then
    report 1 "незаменимый файл, прогон 1" PASS
  else
    report 1 "незаменимый файл, прогон 1" FAIL
  fi
}

scenario_2() { # тот же файл, прогоны 1+2: удаление во втором, команда в колонке 9
  fixture scen2
  printf 'critical payload line\n' >"$A"
  cp -f "$A" "$O_A"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local line snap restore
  line=$(jline "$A")
  snap=$(printf '%s' "$line" | cut -f8)
  restore=$(printf '%s' "$line" | cut -f9)
  if [ ! -e "$A" ] && [ -n "$line" ] && [ -n "$snap" ] && [ -n "$restore" ] \
     && printf '%s' "$line" | grep -q $'\tdeleted\t'; then
    report 2 "тот же файл, прогон 2" PASS
  else
    report 2 "тот же файл, прогон 2" FAIL
  fi
}

scenario_3() { # файл изменён между прогонами: не удаляется, снова fixed
  fixture scen3
  printf 'modify base\n' >"$B"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  printf 'x' >>"$B"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local n
  n=$(grep -F "$B" "$JOURNAL" 2>/dev/null | grep -c $'\tfixed\t')
  if [ -f "$B" ] && [ "$n" -ge 2 ]; then
    report 3 "файл изменён между прогонами" PASS
  else
    report 3 "файл изменён между прогонами" FAIL
  fi
}

scenario_4() { # заменимый файл, прогон 1: удаление сразу
  fixture scen4
  printf 'replaceable junk\n' >"$F"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  if [ ! -e "$F" ]; then
    report 4 "заменимый файл, прогон 1" PASS
  else
    report 4 "заменимый файл, прогон 1" FAIL
  fi
}

scenario_5() { # DR_LAST_OK старше 36 ч: незаменимое не удаляется, код 5
  fixture scen5
  printf 'backup-age guard\n' >"$E"
  echo 1 >"$LASTOK"   # старый epoch (заведомо старше 36 ч)
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq 5 ] && [ -f "$E" ]; then
    report 5 "DR_LAST_OK старше 36 ч" PASS
  else
    report 5 "DR_LAST_OK старше 36 ч (rc=$rc)" FAIL
  fi
}

scenario_6() { # shadow, два прогона: не удаляется, в журнале would-delete
  fixture scen6
  printf 'shadow payload\n' >"$C"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local n
  n=$(grep -F "$C" "$JOURNAL" 2>/dev/null | grep -c $'\twould-delete\t')
  if [ -f "$C" ] && [ "$n" -ge 1 ]; then
    report 6 "shadow, два прогона" PASS
  else
    report 6 "shadow, два прогона" FAIL
  fi
}

scenario_7() { # 96%: незаменимое удаляется в том же прогоне, со снимком
  fixture scen7
  printf 'hot payload\n' >"$D"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=96 -- >/dev/null 2>&1
  local line snap
  line=$(jline "$D")
  snap=$(printf '%s' "$line" | cut -f8)
  if [ ! -e "$D" ] && [ -n "$snap" ] && [ "$snap" != "-" ] \
     && printf '%s' "$line" | grep -q $'\tdeleted\t'; then
    report 7 "DR_USAGE_PCT=96, один прогон" PASS
  else
    report 7 "DR_USAGE_PCT=96, один прогон" FAIL
  fi
}

scenario_8() { # команда из колонки 9: restore == оригинал
  fixture scen8
  printf 'critical payload line\n' >"$A"
  cp -f "$A" "$O_A"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local line cmd restored
  line=$(jline "$A")
  cmd=$(printf '%s' "$line" | cut -f9)
  if [ -z "$cmd" ]; then
    report 8 "restore из колонки 9" FAIL
    return
  fi
  # Полный путь к restic (в свежем окружении его нет на PATH извне).
  cmd=$(printf '%s' "$cmd" | sed -E "s#^restic #$RESTIC #")
  # Направляем restore в фикстуру, чтобы не писать вне /tmp.
  cmd=$(printf '%s' "$cmd" | sed -E "s#--target[[:space:]]+[^ ]+#--target $S/restore#")
  mkdir -p "$S/restore"
  export RESTIC_REPOSITORY="$REPO" RESTIC_PASSWORD_FILE="$PASSFILE"
  bash -c "$cmd" >/dev/null 2>&1
  restored=$(find "$S/restore" -type f -name "$(basename "$A")" 2>/dev/null | head -1)
  if [ -n "$restored" ] && [ -f "$O_A" ] && cmp -s "$O_A" "$restored"; then
    report 8 "restore из колонки 9" PASS
  else
    report 8 "restore из колонки 9" FAIL
  fi
}

scenario_9() { # --restore-drill: перед drill файл должен остаться на диске и быть в снимке
  fixture scen9
  printf 'drill payload\n' >"$C"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local out rc
  out=$(run_rotate -- --restore-drill 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | grep -Eq 'drill: [0-9]+ files, [0-9]+ match, 0 mismatch'; then
    report 9 "--restore-drill" PASS
  else
    report 9 "--restore-drill (rc=$rc)" FAIL
  fi
}

scenario_10() { # имя файла с пробелом: обрабатывается без искажения пути
  fixture scen10
  printf 'space payload\n' >"$SP"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  [ -f "$SP" ] && run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local line
  line=$(jline "$SP")
  if [ ! -e "$SP" ] && [ -n "$line" ] \
     && [ "$(printf '%s' "$line" | cut -f6)" = "$SP" ] \
     && printf '%s' "$line" | grep -q $'\tdeleted\t'; then
    report 10 "имя файла с пробелом" PASS
  else
    report 10 "имя файла с пробелом" FAIL
  fi
}

scenario_11() { # --dry-run с DR_TEST_ONLY=1: ни одного пути вне тестовых каталогов
  fixture scen11
  printf 'guard content\n' >"$A"
  printf 'rep junk\n' >"$F"
  local out bad
  out=$(run_rotate -- --dry-run 2>&1)
  bad=$(printf '%s' "$out" | grep -E '^/' | grep -vE "^($I|$R)(/|$)" | head -1)
  if [ -z "$bad" ]; then
    report 11 "запретный список и границы (--dry-run)" PASS
  else
    report 11 "запретный список и границы (--dry-run: $bad)" FAIL
  fi
}

scenario_12() { # state в несуществующем подкаталоге: каталог создаётся, файл пишется
  fixture scen12
  printf 'state-dir payload\n' >"$A"
  local S_STATE="$S/missing/state.tsv"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 DR_STATE_FILE="$S_STATE" -- >/dev/null 2>&1
  local n
  n=$(awk -F'\t' 'NF==6{c++} END{print c+0}' "$S_STATE" 2>/dev/null)
  if [ -f "$S_STATE" ] && [ "$n" -ge 1 ]; then
    report 12 "state в несуществующем подкаталоге" PASS
  else
    report 12 "state в несуществующем подкаталоге" FAIL
  fi
}

scenario_13() { # GATE_RC unbound regression: --dry-run без gate_process
  fixture scen13
  local out rc
  out=$(run_rotate -- --dry-run 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    report 13 "GATE_RC unset (--dry-run + test-only)" PASS
  else
    report 13 "GATE_RC unset (--dry-run + test-only, rc=$rc, out=$(printf '%s' "$out" | tail -1))" FAIL
  fi
}

scenario_14() { # handle() label=$cls unbound regression: заменимый файл в dry-run
  fixture scen14
  printf 'replaceable junk\n' >"$F"
  local out rc
  out=$(run_rotate DR_USAGE_PCT=5 -- --dry-run 2>&1)
  rc=$?
  # Dry-run must complete, not mask a shell error as a gate status.
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF "$F"; then
    report 14 "handle label=\$cls (dry-run + low-usage)" PASS
  else
    local last
    last=$(printf '%s' "$out" | tail -3)
    report 14 "handle label=\$cls (dry-run + low-usage, rc=$rc, last=$last)" FAIL
  fi
}

scenario_15() { # dry/live protected-path alignment: оба режима через handle
  fixture scen15
  printf 'protected content\n' >"$A"
  printf 'replaceable junk\n' >"$F"
  local dry_out live_out bad_dry bad_live rc_dry rc_live
  # dry-run
  dry_out=$(run_rotate -- --dry-run 2>&1)
  rc_dry=$?
  # live (usage 85 → cache, trashes F и удаляет заменимые)
  live_out=$(run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- 2>&1)
  rc_live=$?
  # ни в одном из режимов не должно быть путей из DENY_LIST
  bad_dry=$(printf '%s' "$dry_out" | grep -E '^/' | grep -vE "^($I|$R)(/|$)" | head -1)
  bad_live=$(printf '%s' "$live_out" | grep -E '(backups|secrets|hh-scoring|\.codex)' | head -1)
  if [ "$rc_dry" -eq 0 ] && [ "$rc_live" -eq 0 ] && [ -z "$bad_dry" ] && [ -z "$bad_live" ]; then
    report 15 "dry/live protected-path alignment" PASS
  else
    report 15 "dry/live protected-path alignment (dry=$bad_dry live=$bad_live)" FAIL
  fi
}

scenario_16() { # forecast counts regular disposable files once
  fixture scen16
  dd if=/dev/zero of="$F" bs=4096 count=1 status=none
  dd if=/dev/zero of="$R/second.data" bs=4096 count=2 status=none
  local out rc expected total count
  expected=$(du -sk "$F" "$R/second.data" | awk '{n+=$1} END{print n}')
  out=$(run_rotate -- --dry-run 2>&1); rc=$?
  total=$(printf '%s\n' "$out" | sed -n 's/^total candidates: \([0-9]*\)K$/\1/p')
  count=$(printf '%s\n' "$out" | grep -c "^$R/")
  if [ "$rc" -eq 0 ] && [ "$total" = "$expected" ] && [ "$count" -eq 2 ]; then
    report 16 "disposable forecast equals unique-file sum" PASS
  else
    report 16 "disposable forecast (rc=$rc, total=$total expected=$expected count=$count)" FAIL
  fi
}

scenario_17() {
  fixture scen17
  local yc="$S/yc"
  printf '#!/bin/bash\necho '\''{"used_size":"90","max_size":"100"}'\''\n' >"$yc"; chmod +x "$yc"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 DR_YC="$yc" -- >/dev/null 2>&1
  grep -q '90%' "$NOTIFY" && report 17 "S3 alert" PASS || report 17 "S3 alert" FAIL
}

source_gate_functions() { # extracts the actual production gate functions without its live entry point
  local assignment
  for assignment in "${RUN_ENV[@]}"; do export "$assignment"; done
  RC_GATE_CLOSED=5
  sed -n '/^journal_row() {/,/^handle() {/p' "$SCRIPT" | sed '$d' >"$S/gate-functions.sh"
  # shellcheck disable=SC1090
  source "$S/gate-functions.sh"
  use_pct() { printf '85\n'; }
}

fake_tools() { # synthetic git/bd/lsof only for the classifier and projects gate
  BIN="$S/bin"
  mkdir -p "$BIN"
  cat >"$BIN/git" <<'GITEOF'
#!/bin/bash
case " $* " in
  *" merge-base "*) exit 0 ;;
  *" status --porcelain --ignored "*)
    if [[ "$*" == *dcfg-ignored* ]]; then printf '!! node_modules/cache\n';
    elif [[ "$*" == *dcfg-race* ]]; then
      n=0; [ -f "$GIT_STATUS_CALLS" ] && n=$(cat "$GIT_STATUS_CALLS")
      n=$((n + 1)); printf '%s\n' "$n" >"$GIT_STATUS_CALLS"
      [ "$n" -gt 1 ] && printf '!! node_modules/cache\n'
    else printf '%s' "${FAKE_GIT_IGNORED:-}"; fi
    ;;
  *" status --porcelain "*) printf '%s' "${FAKE_GIT_PORCELAIN:-}" ;;
  *" ls-files --others "*) printf '%s' "${FAKE_GIT_OTHERS:-}" ;;
  *" rev-parse --path-format=absolute --git-common-dir "*) printf '%s\n' "${FAKE_GIT_ROOT:-/tmp/mock-root/.git}" ;;
  *" worktree remove "*) printf 'remove\n' >>"$GIT_CALL_LOG" ;;
esac
exit 0
GITEOF
  cat >"$BIN/bd" <<'BDEOF'
#!/bin/bash
if [ -n "${BD_JSON:-}" ]; then printf '%s\n' "$BD_JSON"; else printf '[{"id":"%s","status":"closed"}]\n' "$2"; fi
BDEOF
  cat >"$BIN/lsof" <<'LSOFEOF'
#!/bin/bash
printf '%s' "${LSOF_OUT:-}"
printf '%s' "${LSOF_ERR:-}" >&2
exit "${LSOF_RC:-1}"
LSOFEOF
  chmod +x "$BIN/git" "$BIN/bd" "$BIN/lsof"
}

run_classifier() { # root -> emits zones TSV, with fake tools configured by caller
  local root=$1
  PATH="$BIN:$PATH" ZONE_MODE=dry-run DZ_CODEX_WT="$root" DZ_ZONES_TSV="$S/zones.tsv" \
    DZ_BD="$BIN/bd" GIT_CALL_LOG="$S/git-calls" GIT_STATUS_CALLS="$S/status-calls" \
    bash "$(dirname "$SCRIPT")/disk-zones/codex-worktrees.sh" >"$S/classifier.out" 2>"$S/classifier.err"
}

scenario_18() { # projects call preserves a legacy/test state row verbatim
  fixture scen18
  printf 'legacy payload\n' >"$A"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local project="$S/projects/current.data" other_line
  other_line=$(cat "$STATE")
  mkdir -p "${project%/*}"; printf 'current payload\n' >"$project"
  MODE=run GATE_MODE=enforce JOURNAL_MODE=enforce RUN_ID=scen18 REFIX_PATHS=()
  FIXED_COUNT=0 FIXED_MB=0 DEFERRED_COUNT=0 PROJECTS_ALLOW=("$S/projects/*")
  source_gate_functions
  restic_env
  printf '%s\n' "$project" >"$S/list"
  fix_candidates projects "$S/list"
  : >"$JOURNAL"
  verify_and_delete projects
  if [ ! -e "$project" ] && [ -f "$A" ] && grep -qxF "$other_line" "$STATE" \
     && ! grep -qF "$A" "$JOURNAL" 2>/dev/null; then
    report 18 "mixed state keeps other class byte-for-byte" PASS
  else
    report 18 "mixed state keeps other class byte-for-byte" FAIL
  fi
}

scenario_19() { # closed text in another item/notes is not the requested atom status
  fixture scen19
  local root="$S/worktrees" wt="$S/worktrees/dcfg-notes"
  mkdir -p "$wt"; touch "$wt/.git"; fake_tools
  BD_JSON='[{"id":"dcfg-notes","status":"open","notes":"linked atom closed"},{"id":"dcfg-linked","status":"closed"}]'
  export BD_JSON LSOF_RC=1 LSOF_OUT= LSOF_ERR=
  run_classifier "$root"
  if grep -q $'\tkept-atom-open$' "$S/zones.tsv" && ! grep -q $'\tcandidate$' "$S/zones.tsv"; then
    report 19 "bd JSON exact id and status" PASS
  else
    report 19 "bd JSON exact id and status" FAIL
  fi
}

scenario_20() { # lsof rc=1 with stderr is an error, not a free worktree
  fixture scen20
  local root="$S/worktrees" wt="$S/worktrees/dcfg-lsof"
  mkdir -p "$wt"; touch "$wt/.git"; fake_tools
  unset BD_JSON; export LSOF_RC=1 LSOF_OUT= LSOF_ERR='lsof: permission denied'
  run_classifier "$root"
  if grep -q $'\tkept-lsof-error$' "$S/zones.tsv" \
     && grep -q 'lsof: permission denied' "$S/classifier.err"; then
    report 20 "lsof stderr fails closed" PASS
  else
    report 20 "lsof stderr fails closed" FAIL
  fi
}

scenario_21() { # ignored content at classification or final check prevents removal
  fixture scen21
  local root="$S/worktrees" wt="$S/worktrees/dcfg-ignored"
  mkdir -p "$wt" "$root/dcfg-race"; touch "$wt/.git" "$root/dcfg-race/.git"
  fake_tools
  unset BD_JSON; export LSOF_RC=1 LSOF_OUT= LSOF_ERR=
  run_classifier "$root"
  export PATH="$BIN:$PATH" GIT_CALL_LOG="$S/git-calls" GIT_STATUS_CALLS="$S/status-calls"
  MODE=run GATE_MODE=enforce JOURNAL_MODE=enforce RUN_ID=scen21 REFIX_PATHS=()
  FIXED_COUNT=0 FIXED_MB=0 DEFERRED_COUNT=0 PROJECTS_ALLOW=("$root/*")
  source_gate_functions
  sed -n '/^projects_gate() {/,/^s3_line() {/p' "$SCRIPT" | sed '$d' >"$S/projects-functions.sh"
  # shellcheck disable=SC1090
  source "$S/projects-functions.sh"
  projects_candidates() { WT_CANDIDATES=("$S/worktrees/dcfg-race"); PROJECTS_NOTICES=(); }
  projects_gate
  if grep -q $'\tkept-ignored$' "$S/zones.tsv" \
     && grep -q 'kept-ignored' "$JOURNAL" \
     && ! grep -q 'remove' "$S/git-calls" 2>/dev/null; then
    report 21 "ignored worktree kept without remove" PASS
  else
    report 21 "ignored worktree kept without remove" FAIL
  fi
}

scenario_22() { # paths deleted by verify are not re-backed up in this same gate pass
  fixture scen22
  printf 'same pass payload\n' >"$A"
  run_rotate GATE_MODE=shadow DR_USAGE_PCT=85 -- >/dev/null 2>&1
  local list="$S/list"
  printf '%s\n' "$A" >"$list"
  MODE=run GATE_MODE=enforce JOURNAL_MODE=enforce RUN_ID=scen22 REFIX_PATHS=()
  FIXED_COUNT=0 FIXED_MB=0 DEFERRED_COUNT=0 PROJECTS_ALLOW=()
  source_gate_functions
  gate_process test-irreplaceable "$list" >/dev/null 2>&1 || true
  if [ ! -e "$A" ] \
     && grep -q $'\tdeleted\t' "$JOURNAL" \
     && ! grep -q 'restic-backup-failed' "$JOURNAL"; then
    report 22 "same-pass deleted paths are not refixed" PASS
  else
    report 22 "same-pass deleted paths are not refixed" FAIL
  fi
}

scenario_23() { # restic check failure closes the gate before any candidate deletion
  fixture scen23
  printf 'check failure payload\n' >"$A"
  local rc
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 RESTIC_CHECK_RC=1 -- >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 5 ] && [ -f "$A" ] \
     && grep -q $'\tgate-closed:restic-check-failed$' "$JOURNAL" 2>/dev/null; then
    report 23 "restic check closes gate" PASS
  else
    report 23 "restic check closes gate (rc=$rc)" FAIL
  fi
}

scenario_24() { # turns старше 24 ч удаляются, свежие остаются
  fixture scen24
  local turns="$S/codex/plugins/data/auto-review-just-every/turns/run"
  local old="$turns/old.jsonl" fresh="$turns/fresh.jsonl"
  mkdir -p "$turns"
  printf 'old turn\n' >"$old"; touch -d '25 hours ago' "$old"
  printf 'fresh turn\n' >"$fresh"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 DR_CODEX_HOME="$S/codex" -- >/dev/null 2>&1
  if [ ! -e "$old" ] && [ -f "$fresh" ]; then
    report 24 "codex review retention" PASS
  else
    report 24 "codex review retention" FAIL
  fi
}

scenario_25() { # current и самый новый релизы остаются, старый удаляется
  fixture scen25
  local standalone="$S/codex/packages/standalone"
  local releases="$standalone/releases"
  local old="$releases/old" active="$releases/current" newest="$releases/newest"
  mkdir -p "$old" "$active" "$newest"
  printf 'old release\n' >"$old/file"; touch -d '3 days ago' "$old"
  printf 'active release\n' >"$active/file"; touch -d '2 days ago' "$active"
  printf 'new release\n' >"$newest/file"; touch -d '1 day ago' "$newest"
  ln -s releases/current "$standalone/current"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 DR_CODEX_HOME="$S/codex" -- >/dev/null 2>&1
  if [ ! -e "$old/file" ] && [ -f "$active/file" ] && [ -f "$newest/file" ]; then
    report 25 "codex release retention" PASS
  else
    report 25 "codex release retention" FAIL
  fi
}

scenario_26() { # старая сессия Codex не фиксируется и не удаляется (владелец 10.10)
  fixture scen26
  local session="$S/codex/sessions/old/session.jsonl"
  mkdir -p "${session%/*}"
  printf 'old session\n' >"$session"; touch -d '15 days ago' "$session"
  run_rotate GATE_MODE=enforce DR_USAGE_PCT=85 DR_CODEX_HOME="$S/codex" -- >/dev/null 2>&1
  if [ -f "$session" ] && ! grep -qF "$session" "$STATE" 2>/dev/null \
     && ! grep -q 'codex-sessions' "$JOURNAL" 2>/dev/null; then
    report 26 "codex sessions untouched" PASS
  else
    report 26 "codex sessions untouched" FAIL
  fi
}

if [ "${1:-}" = accounting ]; then
  scenario_16
  exit "$FAILS"
fi

scenario_1
scenario_2
scenario_3
scenario_4
scenario_5
scenario_6
scenario_7
scenario_8
scenario_9
scenario_10
scenario_11
scenario_12
scenario_13
scenario_14
scenario_15
scenario_16
scenario_17
scenario_18
scenario_19
scenario_20
scenario_21
scenario_22
scenario_23
scenario_24
scenario_25
scenario_26

echo "PASS $((26 - FAILS))/26"
[ "$FAILS" -eq 0 ] && exit 0
echo "$FAILS/26 FAILED"
exit 1
