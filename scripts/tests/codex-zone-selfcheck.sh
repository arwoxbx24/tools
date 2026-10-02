#!/bin/bash
# Self-check codex-zone.sh (spec:090, A2): dry-run — измерение зоны и релизов,
# ничего не удаляется, enforce -> rc=2. Запуск:
#   bash scripts/tests/codex-zone-selfcheck.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-zones/codex-zone.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

DZ_CODEX_HOME="$TMP/home"
DZ_CODEX_WT="$TMP/wt"
DZ_ZONES_TSV="$TMP/zones.tsv"
FAKEBIN="$TMP/bin"

# Фикстура зоны Codex.
mkdir -p "$DZ_CODEX_HOME/sessions" "$DZ_CODEX_HOME/.tmp"
mkdir -p "$DZ_CODEX_HOME/packages/standalone/releases"/{0.1.0,0.2.0,0.3.0}
ln -s releases/0.3.0 "$DZ_CODEX_HOME/packages/standalone/current"
mkdir -p "$DZ_CODEX_WT"

# Стуб lsof: ничего не открыто (rc=1, пусто) — прогон не зависит от хоста.
mkdir -p "$FAKEBIN"
printf '#!/bin/bash\nexit 1\n' >"$FAKEBIN/lsof"
chmod +x "$FAKEBIN/lsof"
export PATH="$FAKEBIN:$PATH"

before=$(find "$DZ_CODEX_HOME" | sort)

env DZ_CODEX_HOME="$DZ_CODEX_HOME" DZ_CODEX_WT="$DZ_CODEX_WT" \
    DZ_ZONES_TSV="$DZ_ZONES_TSV" ZONE_MODE=dry-run bash "$SCRIPT" \
    >"$TMP/out" 2>"$TMP/err"
rc_dry=$?

FAILS=0
report() { # name status
  if [ "$2" = PASS ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    FAILS=$((FAILS + 1))
  fi
}

# 1. Строк zone=codex не меньше четырёх.
n_codex=$(awk -F'\t' '$2=="codex"{c++} END{print c+0}' "$DZ_ZONES_TSV")
if [ "$rc_dry" -eq 0 ] && [ "$n_codex" -ge 4 ]; then
  report "zone=codex строк >= 4 ($n_codex)" PASS
else
  report "zone=codex строк >= 4 (rc=$rc_dry, n=$n_codex)" FAIL
fi

# 2. 0.3.0 и 0.2.0 сохранены (kept-*).
kept_ok=PASS
for rel in 0.3.0 0.2.0; do
  if ! awk -F'\t' -v p="$DZ_CODEX_HOME/packages/standalone/releases/$rel" \
       '$3==p && $9 ~ /^kept-/{f=1} END{exit !f}' "$DZ_ZONES_TSV"; then
    kept_ok=FAIL
  fi
done
report "0.3.0/0.2.0 kept" "$kept_ok"

# 3. 0.1.0 — кандидат.
if awk -F'\t' -v p="$DZ_CODEX_HOME/packages/standalone/releases/0.1.0" \
     '$3==p && $9=="candidate"{f=1} END{exit !f}' "$DZ_ZONES_TSV"; then
  report "0.1.0 candidate" PASS
else
  report "0.1.0 candidate" FAIL
fi

# 4. Ни один файл зоны не удалён.
after=$(find "$DZ_CODEX_HOME" | sort)
if [ "$before" = "$after" ]; then
  report "файлы зоны не удалены" PASS
else
  report "файлы зоны не удалены" FAIL
fi

# 5. enforce -> rc=2.
env DZ_CODEX_HOME="$DZ_CODEX_HOME" DZ_CODEX_WT="$DZ_CODEX_WT" \
    DZ_ZONES_TSV="$DZ_ZONES_TSV" ZONE_MODE=enforce bash "$SCRIPT" \
    >"$TMP/enforce.out" 2>"$TMP/enforce.err"
rc5=$?
if [ "$rc5" -eq 2 ]; then
  report "ZONE_MODE=enforce -> rc 2" PASS
else
  report "ZONE_MODE=enforce -> rc 2 (rc=$rc5)" FAIL
fi

echo "PASS $((5 - FAILS))/5"
[ "$FAILS" -eq 0 ] && exit 0
exit 1
