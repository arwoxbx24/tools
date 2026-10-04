# u4b (spec:099): ядро ship-promote — перенос dev→prod.

# stub bd: show --json отдаёт массив (реальный bd, D1); note/close логирует.
cat > "$d/bin/bd" <<'EOF'
#!/usr/bin/env bash
printf 'bd %s\n' "$*" >> "$GH_TEST_DIR/bd.log"
[[ ${1:-} == show && ${3:-} == --json ]] && printf '[{"status":"%s","notes":"%s"}]\n' "$(cat "$GH_TEST_DIR/bd-status" 2>/dev/null || echo open)" "$(cat "$GH_TEST_DIR/bd-notes" 2>/dev/null || echo '')"
[[ ${BD_FAIL:-0} == 1 ]] && exit 1
exit 0
EOF
chmod +x "$d/bin/bd"

# fixturera: bare main (prod) + dev впереди на 1 коммит; live-копия (клон) на main.
pf(){ # <name> [1 добавить коммит в main вне dev]
	local n=$1
	git init -q --bare "$d/origin-$n.git"
	git -C "$d/origin-$n.git" symbolic-ref HEAD refs/heads/main
	git clone -q "$d/origin-$n.git" "$GA_PROJECTS/$n"
	git -C "$GA_PROJECTS/$n" config user.email t@t
	git -C "$GA_PROJECTS/$n" config user.name t
	( cd "$GA_PROJECTS/$n" && printf 'x\n' > f.txt && git add . && git commit -q -m base \
		&& git branch -M main && git push -q -u origin main && git fetch -q origin )
	git -C "$GA_PROJECTS/$n" branch dev
	( cd "$GA_PROJECTS/$n" && git checkout -q dev && printf 'd\n' > d.txt && git add . \
		&& git commit -q -m dev && git push -q -u origin dev && git rev-parse HEAD > "$d/sha-$n" \
		&& git checkout -q main && git fetch -q origin )
	[[ ${2:-0} == 1 ]] && ( cd "$GA_PROJECTS/$n" && printf 'm\n' > m.txt && git add . \
		&& git commit -q -m mainextra && git push -q origin main && git fetch -q origin )
}

# u4b-1 (AE5): CI dev failure -> 40, prod не тронут.
pf b1
: > "$d/bd.log"
printf '[{"status":"completed","conclusion":"failure"}]\n' > "$d/runs-dev"
before=$(git -C "$GA_PROJECTS/b1" rev-parse refs/remotes/origin/main)
( cd "$GA_PROJECTS/b1" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/b1" --atom "$atom" --quote 'цитата' ) 2>"$d/b1.err" >/dev/null; rc=$?
rm -f "$d/runs-dev"
git -C "$GA_PROJECTS/b1" fetch -q origin
after=$(git -C "$GA_PROJECTS/b1" rev-parse refs/remotes/origin/main)
[[ $rc == 40 && $(<"$d/b1.err") == *'не зелёный'* && $before == "$after" ]] && p u4b-1 || f u4b-1

# u4b-2 (AE6): в main коммит вне dev -> 50, stderr 'влей prod в dev', prod не тронут.
pf b2 1
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-dev"
before=$(git -C "$GA_PROJECTS/b2" rev-parse refs/remotes/origin/main)
( cd "$GA_PROJECTS/b2" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/b2" --atom "$atom" --quote 'цитата' ) 2>"$d/b2.err" >/dev/null; rc=$?
rm -f "$d/runs-dev"
git -C "$GA_PROJECTS/b2" fetch -q origin
after=$(git -C "$GA_PROJECTS/b2" rev-parse refs/remotes/origin/main)
[[ $rc == 50 && $(<"$d/b2.err") == *'влей prod в dev'* && $before == "$after" ]] && p u4b-2 || f u4b-2

# u4b-3 (SC-007): CI dev и prod success -> 0, main = sha dev, bd close, live на sha.
pf b3
: > "$d/bd.log"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-dev"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-main"
( cd "$GA_PROJECTS/b3" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/b3" --atom "$atom" --quote 'цитата' ) 2>"$d/b3.err" >/dev/null; rc=$?
rm -f "$d/runs-dev" "$d/runs-main"
git -C "$GA_PROJECTS/b3" fetch -q origin
pfs=$(cat "$d/sha-b3")
ptip=$(git -C "$GA_PROJECTS/b3" rev-parse refs/remotes/origin/main)
plive=$(git -C "$GA_PROJECTS/b3" rev-parse HEAD)
[[ $rc == 0 && $ptip == "$pfs" && $plive == "$pfs" && $(<"$d/bd.log") == *close* ]] && p u4b-3 || f u4b-3

# u4b-4: повтор с тем же атомом (notes содержат promote:) -> 10.
pf b4
printf 'promote: deadbeef quote=x\n' > "$d/bd-notes"
( cd "$GA_PROJECTS/b4" && "$bin/ship-promote" "$GA_PROJECTS/b4" --atom "$atom" --quote 'цитата' ) 2>"$d/b4.err" >/dev/null; rc=$?
rm -f "$d/bd-notes"
[[ $rc == 10 && $(<"$d/b4.err") == *'атом закрыт или уже перенесён'* ]] && p u4b-4 || f u4b-4

# u4b-5 (R14): CI dev success, prod failure -> 60, шаг prod-ci, bd note prod-ci: red.
pf b5
: > "$d/bd.log"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-dev"
printf '[{"status":"completed","conclusion":"failure"}]\n' > "$d/runs-main"
( cd "$GA_PROJECTS/b5" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/b5" --atom "$atom" --quote 'цитата' ) 2>"$d/b5.err" >/dev/null; rc=$?
rm -f "$d/runs-dev" "$d/runs-main"
grep -q 'prod-ci' "$GA_LOG_DIR/ship.log" && s5=1 || s5=0
grep -q 'prod-ci: red' "$d/bd.log" && n5=1 || n5=0
[[ $rc == 60 && $s5 == 1 && $n5 == 1 ]] && p u4b-5 || f u4b-5

# u4b-6 (AE7): ship из codex-worktree атома — репо без dev и с dev; оба 0, bd close есть.
mkrepo b6m
git -C "$GA_PROJECTS/b6m" worktree add -q -b "codex/$atom-x" "$GA_WT_ROOT/codex/$atom" origin/main
printf 's\n' >> "$GA_WT_ROOT/codex/$atom/f.txt"
git -C "$GA_WT_ROOT/codex/$atom" add -A
git -C "$GA_WT_ROOT/codex/$atom" commit -q -m w
: > "$d/bd.log"
ship "$GA_WT_ROOT/codex/$atom" >/dev/null 2>&1; rc1=$?
grep -q close "$d/bd.log" && o6=1 || o6=0

mkrepo b6d 1
git -C "$GA_PROJECTS/b6d" branch dev
git -C "$GA_PROJECTS/b6d" push -q -u origin dev
git -C "$GA_PROJECTS/b6d" fetch -q origin
git -C "$GA_PROJECTS/b6d" worktree add -q -b "codex/$atom-x" "$GA_WT_ROOT/codex/b6dw" origin/main
printf 's\n' >> "$GA_WT_ROOT/codex/b6dw/f.txt"
git -C "$GA_WT_ROOT/codex/b6dw" add -A
git -C "$GA_WT_ROOT/codex/b6dw" commit -q -m w
printf '[{"name":"min-ci","bucket":"pass"}]\n' > "$d/checks.json"; rm -f "$d/checks-late" "$d/ci-poll"
: > "$d/bd.log"
ship "$GA_WT_ROOT/codex/b6dw" >/dev/null 2>&1; rc2=$?
rm -f "$d/checks.json" "$d/ci-poll"
grep -q close "$d/bd.log" && t6=1 || t6=0
[[ $rc1 == 0 && $rc2 == 0 && $o6 == 1 && $t6 == 1 ]] && p u4b-6 || f u4b-6
