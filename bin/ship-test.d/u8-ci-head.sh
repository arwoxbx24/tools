# U8 (ADR-6, FR-018): pr ждёт прогон head SHA, не старый коммит PR. u8-1..u8-3.
# Доступны $d, $GH_TEST_DIR, p, f. ga_ci_wait дёргает gh-заглушку (run:list).
. "$bin/git-auto-lib"

# u8-1: buckets старого прогона fail, для head прогона ещё нет -> 30, не 40.
printf 'fail\n' > "$d/bucket"
printf '[]\n' > "$d/runs-pr"
GA_CI_APPEAR=2 GA_CI_POLL=1 ga_ci_wait pr x/rep 7 sha1 >/dev/null 2>&1; rc=$?
[[ $rc == 30 ]] && p u8-1 || f u8-1

# u8-2: прогон head in_progress, затем checks pass -> 0.
printf '[{"status":"in_progress"}]\n' > "$d/runs-pr"
printf 'pass\n' > "$d/bucket"
GA_CI_POLL=1 ga_ci_wait pr x/rep 7 sha1 >/dev/null 2>&1; rc=$?
[[ $rc == 0 ]] && p u8-2 || f u8-2

# u8-3: без sha (3 аргумента), bucket pass -> 0 (обратная совместимость).
rm -f "$d/runs-pr"
printf 'pass\n' > "$d/bucket"
GA_CI_POLL=1 ga_ci_wait pr x/rep 7 >/dev/null 2>&1; rc=$?
rm -f "$d/bucket"
[[ $rc == 0 ]] && p u8-3 || f u8-3
