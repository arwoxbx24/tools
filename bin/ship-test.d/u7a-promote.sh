# u7a (spec:099 Edge :101-102, D2, D4): приёмка ship-promote.
. "$bin/git-auto-lib"

# gh/run:list читает runs-<branch> (маркер shift-on-dev при первом dev-вызове двигает origin/dev); bd/show — массив (D1).
cat > "$d/bin/gh" <<'EOF'
#!/usr/bin/env bash
br=$(printf '%s\n' "$*" | sed -n 's/.*--branch \([^ ]*\).*/\1/p')
if [[ $br == dev && -f "$GH_TEST_DIR/shift-on-dev" && ! -f "$GH_TEST_DIR/dev-shifted" ]]; then
	: > "$GH_TEST_DIR/dev-shifted"
	( cd "$GA_PROJECTS/$GH_SHIFT_REPO" && git checkout -q dev && printf 's\n'>sh.txt && git add . && git commit -q -m s && git push -q origin dev )
fi
cat "$GH_TEST_DIR/runs-$br" 2>/dev/null || printf '[]\n'
EOF
chmod +x "$d/bin/gh"
cat > "$d/bin/bd" <<'EOF'
#!/usr/bin/env bash
printf 'bd %s\n' "$*" >> "$GH_TEST_DIR/bd.log"
[[ ${1:-} == show && ${3:-} == --json ]] && printf '[{"status":"%s","notes":"%s"}]\n' "$(cat "$GH_TEST_DIR/bd-status" 2>/dev/null || echo open)" "$(cat "$GH_TEST_DIR/bd-notes" 2>/dev/null || echo '')"
[[ ${BD_FAIL:-0} == 1 ]] && exit 1
exit 0
EOF
chmod +x "$d/bin/bd"

pup(){ # bare main (prod)+dev на 1 коммит; sha в $d/sha-<name>
	local n=$1
	git init -q --bare "$d/origin-$n.git"; git -C "$d/origin-$n.git" symbolic-ref HEAD refs/heads/main
	git clone -q "$d/origin-$n.git" "$GA_PROJECTS/$n"
	git -C "$GA_PROJECTS/$n" config user.email t@t; git -C "$GA_PROJECTS/$n" config user.name t
	( cd "$GA_PROJECTS/$n" && printf 'x\n'>f.txt && git add . && git commit -q -m base && git branch -M main && git push -q -u origin main && git fetch -q origin )
	git -C "$GA_PROJECTS/$n" branch dev
	( cd "$GA_PROJECTS/$n" && git checkout -q dev && printf 'd\n'>d.txt && git add . && git commit -q -m dev && git push -q -u origin dev && git rev-parse HEAD >"$d/sha-$n" && git checkout -q main && git fetch -q origin )
}

# u7a-1 (Edge :101): dev сдвинулась после CI -> 0, origin/prod = SHA до сдвига.
pup w1; export GH_SHIFT_REPO=w1; : > "$d/shift-on-dev"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-dev"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-main"
before=$(cat "$d/sha-w1")
( cd "$GA_PROJECTS/w1" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/w1" --atom a7 --quote 'цитата' ) 2>"$d/u7a1.err" >/dev/null; rc=$?
rm -f "$d/shift-on-dev" "$d/runs-dev" "$d/runs-main"
git -C "$GA_PROJECTS/w1" fetch -q origin; tip=$(git -C "$GA_PROJECTS/w1" rev-parse refs/remotes/origin/main)
[[ $rc == 0 && $tip == "$before" ]] && p u7a-1 || f u7a-1

# u7a-2 (Edge :102): pre-receive отклоняет push в prod -> 30.
pup w2
mkdir -p "$d/ghooks"
cat > "$d/ghooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
while read -r _ _ ref; do [[ $ref == refs/heads/main ]] && exit 1; done
EOF
chmod +x "$d/ghooks/pre-receive"
git -C "$d/origin-w2.git" config core.hooksPath "$d/ghooks"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-dev"
printf '[{"status":"completed","conclusion":"success"}]\n' > "$d/runs-main"
( cd "$GA_PROJECTS/w2" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/w2" --atom a7 --quote 'цитата' ) 2>"$d/u7a2.err" >/dev/null; rc=$?
rm -f "$d/runs-dev" "$d/runs-main"
[[ $rc == 30 ]] && p u7a-2 || f u7a-2

# u7a-3 (D2): вложенный клон, путь с хвостовым /; нет unbound, rc != 1.
mkdir -p "$GA_PROJECTS/clients"
git init -q --bare "$d/origin-cfoo.git"; git -C "$d/origin-cfoo.git" symbolic-ref HEAD refs/heads/main
git clone -q "$d/origin-cfoo.git" "$GA_PROJECTS/clients/foo"
git -C "$GA_PROJECTS/clients/foo" config user.email t@t; git -C "$GA_PROJECTS/clients/foo" config user.name t
( cd "$GA_PROJECTS/clients/foo" && printf 'x\n'>f.txt && git add . && git commit -q -m base && git branch -M main && git push -q -u origin main && git fetch -q origin )
( cd "$GA_PROJECTS/clients/foo" && "$bin/ship-promote" "$GA_PROJECTS/clients/foo/" --atom a7 --quote 'цитата' ) 2>"$d/u7a3.err" >/dev/null; rc=$?
err=$(<"$d/u7a3.err")
[[ $rc != 1 && $err != *unbound* ]] && p u7a-3 || f u7a-3

# u7a-4 (D4): в origin только feature/dev -> ga_base печатает one.
git init -q --bare "$d/origin-w4.git"; git -C "$d/origin-w4.git" symbolic-ref HEAD refs/heads/main
git clone -q "$d/origin-w4.git" "$GA_PROJECTS/w4"
git -C "$GA_PROJECTS/w4" config user.email t@t; git -C "$GA_PROJECTS/w4" config user.name t
( cd "$GA_PROJECTS/w4" && printf 'x\n'>f.txt && git add . && git commit -q -m base && git branch -M main && git push -q -u origin main && git fetch -q origin )
git -C "$GA_PROJECTS/w4" branch feature/dev; git -C "$GA_PROJECTS/w4" push -q origin feature/dev; git -C "$GA_PROJECTS/w4" fetch -q origin
out=$(ga_base "$GA_PROJECTS/w4")
[[ $out == one* ]] && p u7a-4 || f u7a-4
