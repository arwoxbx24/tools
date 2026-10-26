#!/bin/bash
# disk-rotate-zwrpf-test: класс runner (остатки GitHub Actions runner) проходит через гейт restic.
# Фикстуры в собственном mktemp-каталоге; реальные /opt, /root/actions-runner-2, docker, secrets и gitmirror не трогаются.
# Запуск: bash tests/disk-rotate-zwrpf-test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/scripts/disk-rotate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

# Host-wide sizes are irrelevant to fixture behavior; never scan host data.
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

FX="$TMP/fx"
S="$FX"
mkdir -p "$FX"
RESTIC="$FX/restic"
REPO="$FX/repo"
PASSFILE="$FX/pw"
JOURNAL="$FX/journal.tsv"
NOTIFY="$FX/notify.txt"
HH="$FX/hh-scoring-fx/runner"
DENIED_ROOTS="/root/workspaces/secrets/zwrpf-fx /home/gitmirror/zwrpf-fx /var/lib/docker/zwrpf-fx"
RUNNER_ROOTS="$FX/runner $HH $DENIED_ROOTS"

mock_restic() { # fixture-local stub: only the operations exercised by this test
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

mock_restic
printf 'zwrpf-fixture-pass\n' >"$PASSFILE"
if ! "$RESTIC" init --repo "$REPO" --password-file "$PASSFILE" >/dev/null 2>&1; then
  echo "FIXTURE-ERROR: restic init failed" >&2
  exit 2
fi
cat >"$FX/notify-stub.sh" <<NOTIFYEOF
#!/bin/bash
echo "\$1" >>"$NOTIFY"
NOTIFYEOF
chmod +x "$FX/notify-stub.sh"
date +%s >"$FX/lastok"

RUN_ENV=(DR_TEST_ONLY=1
  GATE_MODE=enforce
  DR_USAGE_PCT=85
  DR_STATE_FILE="$FX/state.tsv"
  DR_JOURNAL="$JOURNAL"
  DR_LAST_OK="$FX/lastok"
  DR_ALERT_STATE_FILE="$FX/alerts"
  DR_LOCK_FILE="$FX/lock"
  DR_LEDGER="$FX/ledger.tsv"
  DR_ZONES_TSV="$FX/zones.tsv"
  DR_LOG="$FX/log"
  DR_LOGROTATE_STATE="$FX/logrotate.state"
  DR_NOTIFY_CMD="$FX/notify-stub.sh"
  NOTIFY_ENV="$FX/empty-notify.env"
  DR_RESTIC_REPO="$REPO"
  DR_RESTIC_PASSWORD_FILE="$PASSFILE"
  DR_JOURNAL_COPY="$FX/journal-copy.tsv"
  RESTIC="$RESTIC")

run_rotate() { # обычный прогон скрипта над фикстурой
  env "${RUN_ENV[@]}" DR_RUNNER_ROOTS="$RUNNER_ROOTS" "$SCRIPT" >/dev/null 2>&1
}

make_runner() { # корень -> раскладка runner: две версии bin/externals, _work со старым, свежим и _tool
  local r=$1
  mkdir -p "$r/bin.1.0" "$r/externals.1.0" "$r/bin.2.0" "$r/externals.2.0" "$r/_work/stale" "$r/_work/fresh" "$r/_work/_tool"
  ln -sfn bin.2.0 "$r/bin"
  ln -sfn externals.2.0 "$r/externals"
  printf 'old bin\n' >"$r/bin.1.0/old.bin"
  printf 'old ext\n' >"$r/externals.1.0/old.ext"
  printf 'cur bin\n' >"$r/bin.2.0/cur.bin"
  printf 'cur ext\n' >"$r/externals.2.0/cur.ext"
  printf 'stale\n' >"$r/_work/stale/a.txt"
  printf 'fresh\n' >"$r/_work/fresh/b.txt"
  printf 'tool\n' >"$r/_work/_tool/t.bin"
  touch -d '10 days ago' "$r/_work/stale/a.txt" "$r/_work/stale" "$r/_work/_tool/t.bin"
}

snapshot_made() { "$RESTIC" -r "$REPO" --password-file "$PASSFILE" snapshots --tag predelete 2>/dev/null | grep -q predelete; }
kept() { local f; for f in "$@"; do [ -e "$f" ] || return 1; done; }
gone() { local f; for f in "$@"; do [ ! -e "$f" ] || return 1; done; }
roots_absent() { local r; for r in $DENIED_ROOTS; do [ ! -e "$r" ] || return 1; done; }
run1_ok() { kept "$FX/runner/bin.1.0/old.bin" && snapshot_made; }
run2_gone() { gone "$FX/runner/bin.1.0/old.bin" "$FX/runner/externals.1.0/old.ext" "$FX/runner/_work/stale/a.txt"; }
runner_deleted() { awk -F'\t' '$4=="runner" && $5=="deleted"{f=1} END{exit !f}' "$JOURNAL" 2>/dev/null; }
kept_current() { kept "$FX/runner/bin.2.0/cur.bin" "$FX/runner/externals.2.0/cur.ext" "$FX/runner/_work/fresh/b.txt" "$FX/runner/_work/_tool/t.bin"; }
hh_intact() { kept "$HH/bin.1.0/old.bin" "$HH/externals.1.0/old.ext" "$HH/bin.2.0/cur.bin" "$HH/externals.2.0/cur.ext" "$HH/_work/stale/a.txt" "$HH/_work/fresh/b.txt" "$HH/_work/_tool/t.bin"; }
denied_logged() { local r; for r in $DENIED_ROOTS; do grep -qxF "runner denied: $r" "$FX/log" 2>/dev/null || return 1; done; }
denied_not_journaled() { local r; for r in $DENIED_ROOTS; do grep -qF "$r" "$JOURNAL" 2>/dev/null && return 1; done; return 0; }

FAILS=0
N=0
check() { # имя проверка... -> PASS/FAIL с номером
  local name=$1; shift
  N=$((N + 1))
  if "$@"; then echo "PASS $N $name"; else echo "FAIL $N $name"; FAILS=$((FAILS + 1)); fi
}

make_runner "$FX/runner"
make_runner "$HH"
check "denied roots absent before run" roots_absent
run_rotate
check "run 1: old.bin kept, copy in restic" run1_ok
run_rotate
check "run 2: old versions and stale work removed" run2_gone
check "run 2: journal has runner deleted row" runner_deleted
check "current, fresh and _tool kept" kept_current
check "negative: hh-scoring files all kept" hh_intact
check "negative: denied roots logged" denied_logged
check "negative: denied roots not journaled" denied_not_journaled

if [ "$FAILS" -eq 0 ]; then
  echo PASS
  exit 0
fi
echo FAIL
exit 1
