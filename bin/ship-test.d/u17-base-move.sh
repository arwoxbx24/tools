# U17 (ADR-31/32): a reopened PR must wait for a run created after `since`.
. "$bin/git-auto-lib"

printf 'pass\n' > "$d/bucket"
printf '[{"status":"completed","createdAt":"2026-10-10T10:00:00Z"}]\n' > "$d/runs-pr"
GA_CI_APPEAR=1 GA_CI_POLL=1 ga_ci_wait pr x/rep 7 sha1 2026-10-10T10:00:01Z >/dev/null 2>&1; rc=$?
[[ $rc == 30 ]] && p u17-1 || f u17-1

printf '[{"status":"completed","createdAt":"2026-10-10T10:00:01Z"}]\n' > "$d/runs-pr"
GA_CI_POLL=1 ga_ci_wait pr x/rep 7 sha1 2026-10-10T10:00:01Z >/dev/null 2>&1; rc=$?
[[ $rc == 0 ]] && p u17-2 || f u17-2

# U17-3: unchanged base merges without reopening the PR.
mkrepo r17 1; w17=$(mkwt r17 claude/u17); printf 'change\n' >> "$w17/f.txt"
: > "$GH_JOURNAL"; rm -f "$GH_CREATED"
ship "$w17" >/dev/null 2>&1; rc=$?
grep -q '^pr merge' "$GH_JOURNAL"; merged=$?
grep -q '^pr close' "$GH_JOURNAL"; closed=$?
[[ $rc == 0 && $merged == 0 && $closed != 0 ]] && p u17-3 || f u17-3
rm -f "$d/runs-pr" "$d/bucket"
