#!/bin/bash
# Self-check dz_compress (FR-090-04, spec:090 U2), запуск вручную:
#   bash scripts/tests/disk-zones-compress-selfcheck.sh
# 3 сценария в каталоге mktemp -d: обычный (rc=0), CORRUPT (rc=2),
# MUTATE (rc=2). Печать PASS n/3, rc=0 только при 3/3.
set -u

LIB="$(cd "$(dirname "$0")/.." && pwd -P)/disk-zones/lib-compress.sh"
BASE="$(mktemp -d)"
trap 'rm -rf -- "$BASE"' EXIT

PASS=0
FAIL=0
DZ_RC=0
DZ_OUT=

report() { # num name ok
  if [ "$3" = PASS ]; then
    PASS=$((PASS + 1))
    echo "PASS $1 $2"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $1 $2"
  fi
}

run_dz() { # dir file -> устанавливает DZ_RC, DZ_OUT
  local dir=$1 f=$2 out
  out=$(cd "$dir" && source "$LIB" && dz_compress "$f" 2>&1)
  DZ_RC=$?
  DZ_OUT=$out
}

scenario_1() { # обычный: rc=0, оригинала нет, zstd -dc == исходные байты
  local d="$BASE/s1"; mkdir -p "$d"
  printf 'payload compress\n' >"$d/f"
  cp -f "$d/f" "$d/orig"
  run_dz "$d" "$d/f"
  local ok=FAIL
  if [ "$DZ_RC" -eq 0 ] && [ ! -e "$d/f" ] && [ -e "$d/f.zst" ]; then
    zstd -q -dc -- "$d/f.zst" >"$d/back" 2>/dev/null
    cmp -s "$d/orig" "$d/back" && ok=PASS
  fi
  report 1 "обычный" "$ok"
}

scenario_2() { # CORRUPT: rc=2, оригинал цел (sha256 тот же), .zst нет
  local d="$BASE/s2"; mkdir -p "$d"
  printf 'corrupt payload\n' >"$d/f"
  local sha_before sha_after ok=FAIL
  sha_before=$(cd "$d" && sha256sum f | awk '{print $1}')
  DZ_TEST_CORRUPT=1 run_dz "$d" "$d/f"
  sha_after=$(cd "$d" && sha256sum f | awk '{print $1}')
  if [ "$DZ_RC" -eq 2 ] && [ -f "$d/f" ] && [ ! -e "$d/f.zst" ] \
     && [ "$sha_before" = "$sha_after" ]; then
    ok=PASS
  fi
  report 2 "CORRUPT" "$ok"
}

scenario_3() { # MUTATE: rc=2, оригинал цел
  local d="$BASE/s3"; mkdir -p "$d"
  printf 'mutate payload\n' >"$d/f"
  local ok=FAIL
  DZ_TEST_MUTATE=1 run_dz "$d" "$d/f"
  if [ "$DZ_RC" -eq 2 ] && [ -f "$d/f" ] && [ ! -e "$d/f.zst" ]; then
    ok=PASS
  fi
  report 3 "MUTATE" "$ok"
}

scenario_1
scenario_2
scenario_3

echo "PASS $PASS/3"
[ "$PASS" -eq 3 ] && exit 0
exit 1
