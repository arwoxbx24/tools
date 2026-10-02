#!/bin/bash
# Self-check codex-worktrees.sh (spec:090 C3 / CR-01). Запуск вручную:
#   bash scripts/tests/codex-worktrees-selfcheck.sh
# Фикстура в mktemp -d: bare-репо origin и 4 worktree-клона. Ничего не удаляет.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-zones/codex-worktrees.sh"
TMP="$(mktemp -d)"
SLEEP_PID=
trap 'rm -rf -- "$TMP"; [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; true' EXIT

WT="$TMP/wt"
mkdir -p "$WT"

ORIGIN="$TMP/origin.git"
git init -q --bare -b main "$ORIGIN"
SEED="$TMP/seed"
mkdir -p "$SEED"
git -C "$SEED" init -q
git -C "$SEED" config user.email selfcheck@test
git -C "$SEED" config user.name selfcheck
printf 'base\n' >"$SEED/base"
git -C "$SEED" add base
git -C "$SEED" commit -qm base
git -C "$SEED" remote add origin "$ORIGIN"
git -C "$SEED" push -q -u origin HEAD:main

# (a) candidate: HEAD в origin/main, чисто
git clone -q "$ORIGIN" "$WT/dcfg-aaa1"
# (b) kept-not-merged: лишний коммит поверх main
git clone -q "$ORIGIN" "$WT/dcfg-bbb1"
git -C "$WT/dcfg-bbb1" config user.email selfcheck@test
git -C "$WT/dcfg-bbb1" config user.name selfcheck
git -C "$WT/dcfg-bbb1" commit -q --allow-empty -m extra
# (c) kept-dirty: неотслеживаемый файл
git clone -q "$ORIGIN" "$WT/dcfg-ccc1"
printf 'dirty\n' >"$WT/dcfg-ccc1/untracked.txt"
# (d) kept-busy: процесс sleep с cwd внутри worktree
git clone -q "$ORIGIN" "$WT/dcfg-ddd1"
(
  cd "$WT/dcfg-ddd1" || exit 1
  exec sleep 30
) &
SLEEP_PID=$!

# Фейковый bd: атом всегда закрыт
FAKEBD="$TMP/fakebd"
cat >"$FAKEBD" <<'EOF'
#!/bin/bash
printf '%s\n' '[{"status":"closed"}]'
EOF
chmod +x "$FAKEBD"

ZONE_MODE=dry-run DZ_CODEX_WT="$WT" DZ_ZONES_TSV="$TMP/zones.tsv" \
  DZ_BD="$FAKEBD" bash "$SCRIPT"
rc=$?

PASS=0
FAIL=0
check_state() { # name expected
  local got
  got=$(awk -F'\t' -v n="$1" '$3 ~ (n "$") {print $9}' "$TMP/zones.tsv")
  if [ "$got" = "$2" ]; then
    PASS=$((PASS + 1))
    echo "PASS $1 -> $2"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $1 -> got '$got', want '$2'"
  fi
}

check_state dcfg-aaa1 candidate
check_state dcfg-bbb1 kept-not-merged
check_state dcfg-ccc1 kept-dirty
check_state dcfg-ddd1 kept-busy

# Сопутствующие инварианты: rc=0, строка run-done, каталоги целы.
if [ "$rc" -ne 0 ]; then
  echo "FAIL script rc=$rc"
  FAIL=$((FAIL + 1))
fi
grep -q $'\trun-done$' "$TMP/zones.tsv" || {
  echo "FAIL нет строки run-done"
  FAIL=$((FAIL + 1))
}
for d in dcfg-aaa1 dcfg-bbb1 dcfg-ccc1 dcfg-ddd1; do
  [ -d "$WT/$d" ] || {
    echo "FAIL удалён каталог $d"
    FAIL=$((FAIL + 1))
  }
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS $PASS/4"
  exit 0
fi
echo "FAIL $PASS/4"
exit 1
