# u6 (spec:099): живая копия на prod — базовая ветка из ga_base, dev не используется.
# u6-1: основная ветка master (без dev) -> доставка, живая копия на master содержит sha слияния.
git init -q --bare "$d/origin-u61.git"
git -C "$d/origin-u61.git" symbolic-ref HEAD refs/heads/master
git clone -q "$d/origin-u61.git" "$GA_PROJECTS/u61"
git -C "$GA_PROJECTS/u61" config user.email t@t
git -C "$GA_PROJECTS/u61" config user.name t
( cd "$GA_PROJECTS/u61" && printf 'x\n' > f.txt && git add . && git commit -q -m base \
	&& git branch -M master && git push -q -u origin master && git fetch -q origin )
git -C "$d/tzrepo" checkout -q main
( cd "$d/tzrepo" && printf 'Файлы: f.txt, x.txt\nПроверка: test -n "$(git diff --name-only origin/master...HEAD)" && echo 3\n' > tz-u6-1.md \
	&& git add . && git commit -q -m tzu61 && git push -q origin main && git fetch -q origin )
git -C "$GA_PROJECTS/u61" worktree add -q -b claude/u61 "$GA_WT_ROOT/claude/u61" master
w61="$GA_WT_ROOT/claude/u61"; printf 's61\n' >> "$w61/f.txt"
rm -f "$GH_CREATED"
( cd "$w61" && GH_ORIGIN="$d/origin-u61.git" "$bin/ship" "$w61" --atom "$atom" --tz "$d/tzrepo/tz-u6-1.md#U1" ) >/dev/null 2>&1; rc61=$?
live61=$(git -C "$GA_PROJECTS/u61" rev-parse --abbrev-ref HEAD)
git -C "$GA_PROJECTS/u61" fetch -q origin
"$bin/git-state" --live u61 "$(cat "$d/merge-sha")" >/dev/null 2>&1; gs61=$?
[[ $rc61 == 0 && $live61 == master && $gs61 == 0 ]] && p u6-1 || f u6-1

# u6-2: репо с dev -> two-режим; PR в dev, живая копия остаётся на prod, журнал live:deferred dev.
mkrepo u62 1
git -C "$GA_PROJECTS/u62" branch dev
git -C "$GA_PROJECTS/u62" push -q -u origin dev
git -C "$GA_PROJECTS/u62" fetch -q origin
w62=$(mkwt u62 claude/u62); printf 's62\n' >> "$w62/f.txt"
before62=$(git -C "$GA_PROJECTS/u62" rev-parse HEAD)
printf '[{"name":"min-ci","bucket":"pass"}]\n' > "$d/checks.json"; rm -f "$d/checks-late" "$d/ci-poll"
rm -f "$GH_CREATED"
( cd "$w62" && GH_ORIGIN="$d/origin-u62.git" "$bin/ship" "$w62" --atom "$atom" --tz "$tz#U1" ) >/dev/null 2>&1; rc62=$?
rm -f "$d/checks.json" "$d/ci-poll"
after62=$(git -C "$GA_PROJECTS/u62" rev-parse HEAD)
git -C "$GA_PROJECTS/u62" fetch -q origin
new62=$(git -C "$GA_PROJECTS/u62" rev-list --count "$before62"..refs/remotes/origin/main 2>/dev/null || echo 999)
core62=$(grep '^pr create' "$GH_JOURNAL" | tail -n1)
def62=$(grep -c 'live:deferred dev' "$GA_LOG_DIR/ship.log" || true)
[[ $rc62 == 0 && $before62 == "$after62" && $core62 == *'--base dev'* && $new62 == 0 && ${def62:-0} -gt 0 ]] && p u6-2 || f u6-2

# u6-3/4: ga_base local — origin на несуществующий путь, решения только по локальным refs.
. "$bin/git-auto-lib"
git init -q "$d/live3"; git -C "$d/live3" config user.email t@t; git -C "$d/live3" config user.name t
( cd "$d/live3" && printf 'x\n' > f.txt && git add . && git commit -q -m base \
	&& git branch -M main && git update-ref refs/remotes/origin/main HEAD && git update-ref refs/remotes/origin/dev HEAD )
git -C "$d/live3" remote add origin "$d/no-such-origin.git"
read -r l3m l3b l3p < <(ga_base "$d/live3" local) || l3m=fail
[[ $l3m == two && $l3b == dev && $l3p == main ]] && p u6-3 || f u6-3
git -C "$d/live3" update-ref -d refs/remotes/origin/dev
read -r l4m l4b l4p < <(ga_base "$d/live3" local) || l4m=fail
[[ $l4m == one && $l4b == main && $l4p == main ]] && p u6-4 || f u6-4
