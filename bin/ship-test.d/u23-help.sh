# U23 (ADR-S1, ADR-S4): --help выходит 0 в stdout; preflight называет ожидаемый корень.
# Подключается через `.` из bin/ship-test: доступны $d, $GH_JOURNAL, mkrepo, mkwt, ship, p, f.

# u23-1: `ship --help` -> rc 0, usage в stdout, без git/gh вызовов.
out=$("$bin/ship" --help 2>/dev/null); rc=$?
[[ $rc == 0 && $out == *'usage'* ]] && p u23-1 || f u23-1

# u23-2 (ADR-S4): worktree вне корня -> rc 10, stderr содержит GA_WT_ROOT.
mkrepo u23a
wout="$d/outside/c3"
git -C "$GA_PROJECTS/u23a" worktree add -q -b claude/c3 "$wout" origin/main
printf 's\n' >> "$wout/f.txt"
err=$( ( cd "$wout" && GH_ORIGIN="$(git -C "$wout" config remote.origin.url)" "$bin/ship" "$wout" --atom "$atom" --tz "$tz#U1" ) 2>&1 >/dev/null ); rc=$?
[[ $rc == 10 && $err == *'GA_WT_ROOT'* ]] && p u23-2 || f u23-2
