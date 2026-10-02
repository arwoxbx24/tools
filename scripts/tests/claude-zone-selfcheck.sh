#!/bin/bash
# Self-check claude-zone.sh (spec:090 FR-090-03/04/08), всё в mktemp -d.
# Фейковые pnpm/journalctl в $TMP/bin первым в PATH, пишут вызовы в лог.
set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/disk-zones/claude-zone.sh"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
TSV="$TMP/zones.tsv"; VL="$TMP/varlog"; AW="$TMP/agent-work"
FB="$TMP/bin"; PL="$TMP/pnpm.log"; JL="$TMP/journal.log"

mkdir -p "$FB" "$VL" "$AW" "$TMP/pnpm-store"
printf 'old syslog data\n' >"$VL/syslog.1"
printf 'already compressed\n' >"$VL/syslog.2.gz"
printf 'live log\n' >"$VL/app.log"
printf 'old report data\n' >"$AW/old-report.txt"; touch -d '20 days ago' "$AW/old-report.txt"
printf 'fresh report\n' >"$AW/fresh.txt"
printf 'scoring data\n' >"$AW/hh-scoring-secrets.txt"; touch -d '20 days ago' "$AW/hh-scoring-secrets.txt"
printf 'pkg\n' >"$TMP/pnpm-store/pkg"

# Стубы: пишут вызовы, pnpm возвращает путь store, journalctl даёт размер.
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nif [ "$1" = store ] && [ "$2" = path ]; then echo "%s"; fi\n' \
  "$PL" "$TMP/pnpm-store" >"$FB/pnpm"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nif [ "$1" = --disk-usage ]; then echo "Archived and active journals take up 200M in the file system."; fi\n' \
  "$JL" >"$FB/journalctl"
printf '#!/bin/bash\nexit 1\n' >"$FB/lsof"
chmod +x "$FB/pnpm" "$FB/journalctl" "$FB/lsof"

run() { # mode
  env ZONE_MODE="$1" DZ_ZONES_TSV="$TSV" DZ_VARLOG="$VL" DZ_AGENT_WORK="$AW" \
      DZ_AGE_DAYS=14 DZ_JOURNAL_MAX=200M PATH="$FB:$PATH" bash "$SCRIPT" >/dev/null 2>&1
}
PASS=0; FAIL=0
rep() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "PASS $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }

# 1. dry-run: файлы не изменены, prune/vacuum не вызваны.
before=$(find "$VL" "$AW" -type f -exec sha256sum {} + 2>/dev/null | sort)
rm -f -- "$PL" "$JL"; run dry-run; rc1=$?
after=$(find "$VL" "$AW" -type f -exec sha256sum {} + 2>/dev/null | sort)
[ "$rc1" -eq 0 ] && [ "$before" = "$after" ] \
  && ! grep -q 'store prune' "$PL" && ! grep -q vacuum "$JL"
rep "1 dry-run не меняет файлы, prune/vacuum не званы" $?

# 2. enforce: сжатие ротированных/старых, свежие и .gz целы.
run enforce; rc2=$?
[ "$rc2" -eq 0 ] && [ -f "$VL/syslog.1.zst" ] && [ ! -e "$VL/syslog.1" ] \
  && [ -f "$AW/old-report.txt.zst" ] && [ ! -e "$AW/old-report.txt" ] \
  && [ -f "$AW/fresh.txt" ] && [ -f "$VL/syslog.2.gz" ] && [ -f "$VL/app.log" ]
rep "2 enforce сжимает, свежие и .gz целы" $?

# 3. hh-scoring не тронут, есть строка excluded.
[ -f "$AW/hh-scoring-secrets.txt" ] && [ ! -e "$AW/hh-scoring-secrets.txt.zst" ] \
  && grep -q hh-scoring "$TSV" \
  && awk -F'\t' '$9=="excluded"{e++} END{exit !(e>0)}' "$TSV"
rep "3 hh-scoring не тронут, есть excluded" $?

# 4. Повторный enforce: сумма freed_mb = 0.
run enforce
sum=$(awk -F'\t' '{s+=$7} END{print s+0}' "$TSV")
[ "$sum" = 0 ]
rep "4 повторный enforce freed_mb=0 (sum=$sum)" $?

# 5. Стуб journalctl НЕ получил --vacuum ни в dry-run, ни в enforce.
grep -q 'store prune' "$PL" && ! grep -q -- '--vacuum' "$JL"
rep "5 стубы: store prune есть, journalctl без --vacuum" $?

# 6. node_modules и не-белый ext не тронуты и не посчитаны (enforce).
mkdir -p "$AW/node_modules"
printf '{"a":1}\n' >"$AW/node_modules/x.json"; touch -d '20 days ago' "$AW/node_modules/x.json"
printf 'PNG\n' >"$AW/a.png"; touch -d '20 days ago' "$AW/a.png"
run enforce
[ -f "$AW/node_modules/x.json" ] && [ ! -e "$AW/node_modules/x.json.zst" ] \
  && [ -f "$AW/a.png" ] && [ ! -e "$AW/a.png.zst" ] \
  && ! grep -q node_modules "$TSV"
rep "6 node_modules и a.png не тронуты и не посчитаны" $?

# 7. Сводный журнал: ≤20 строк zone claude за один прогон при 50 кандидатах.
mkdir -p "$AW/bulk"
for i in $(seq 1 50); do printf 'data %s\n' "$i" >"$AW/bulk/f$i.log"; touch -d '20 days ago' "$AW/bulk/f$i.log"; done
before=$(wc -l <"$TSV")
run dry-run
added=$(tail -n +$((before+1)) "$TSV" | awk -F'\t' '$2=="claude"{c++} END{print c+0}')
[ "$added" -le 20 ]
rep "7 сводный журнал ≤20 строк за прогон (added=$added)" $?

echo "PASS $PASS/7"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
