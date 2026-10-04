# U4a: CI ожидание fail-closed (FR-018, FR-019) — u4a-1..u4a-4.

# u4a-1: bucket pending -> 40, merge не вызван.
mkrepo k40a 1; w40a=$(mkwt k40a claude/k40a); printf 's\n' >> "$w40a/f.txt"
printf 'pending\n' > "$d/bucket"; rm -f "$GH_CREATED"
before=$(grep -c '^pr merge' "$GH_JOURNAL" || true)
out=$(ship "$w40a" 2>&1); rc=$?
after=$(grep -c '^pr merge' "$GH_JOURNAL" || true)
rm -f "$d/bucket"; rm -f "$GH_CREATED"
[[ $rc == 40 && $after -eq $before ]] && p u4a-1 || f u4a-1

# u4a-2: pr list/create пусто -> 30, stderr 'номер PR не получен'.
mkrepo k40b; w40b=$(mkwt k40b claude/k40b); printf 's\n' >> "$w40b/f.txt"
: > "$d/pr-empty"
( cd "$w40b" && GH_ORIGIN="$(git -C "$w40b" config remote.origin.url)" "$bin/ship" "$w40b" --atom "$atom" --tz "$tz#U1" ) 2>"$d/u4a2.err" >/dev/null; rc=$?
err=$(<"$d/u4a2.err"); rm -f "$d/pr-empty"
[[ $rc == 30 && $err == *'номер PR не получен'* ]] && p u4a-2 || f u4a-2

# u4a-3: успешная доставка -> 0, журнал содержит 'merged 7 '.
mkrepo k40c; w40c=$(mkwt k40c claude/k40c); printf 's\n' >> "$w40c/f.txt"
out=$(ship "$w40c"); rc=$?
grep -q 'merged 7 ' "$GA_LOG_DIR/ship.log" && mrg=0 || mrg=1
[[ $rc == 0 && $mrg == 0 ]] && p u4a-3 || f u4a-3

# u4a-4: ga_ci_wait sha напрямую — completed+success=0; in_progress=40; [] =40.
. "$bin/git-auto-lib"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs"
GA_CI_CAP=2 GA_CI_POLL=1 ga_ci_wait sha x/rep sha1 br >/dev/null 2>&1; rc1=$?
printf '[{"status":"in_progress","conclusion":""}]\n' > "$d/runs"
GA_CI_CAP=2 GA_CI_POLL=1 ga_ci_wait sha x/rep sha1 br >/dev/null 2>&1; rc2=$?
printf '[]\n' > "$d/runs"
GA_CI_CAP=2 GA_CI_POLL=1 ga_ci_wait sha x/rep sha1 br >/dev/null 2>&1; rc3=$?
rm -f "$d/runs"
[[ $rc1 == 0 && $rc2 == 40 && $rc3 == 40 ]] && p u4a-4 || f u4a-4
