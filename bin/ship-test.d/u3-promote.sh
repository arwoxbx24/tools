# u3: ship-promote preflight — всё до сети; журнал gh пуст, 0 push в origin
: > "$GH_JOURNAL"
rm -f "$GH_CREATED" "$GH_TEST_DIR/pr-base" "$GH_TEST_DIR/pr-empty"
gj0(){ wc -l < "$GH_JOURNAL" 2>/dev/null || echo 0; }
nopush(){ git -C "$GA_PROJECTS/$1" ls-remote origin "refs/heads/claude/$1" 2>/dev/null; }

cat > "$d/bin/bd" <<'EOF'
#!/usr/bin/env bash
printf 'bd %s\n' "$*" >> "$GH_TEST_DIR/bd.log"
[[ ${1:-} == show && ${3:-} == --json ]] && printf '[{"status":"%s","notes":"%s"}]\n' "$(cat "$GH_TEST_DIR/bd-status" 2>/dev/null || echo open)" "$(cat "$GH_TEST_DIR/bd-notes" 2>/dev/null || echo '')"
[[ ${BD_FAIL:-0} == 1 ]] && exit 1
exit 0
EOF
chmod +x "$d/bin/bd"

mkrepo p1; b=$(gj0)
( cd "$GA_PROJECTS/p1" && "$bin/ship-promote" "$GA_PROJECTS/p1" --atom a1 ) 2>"$d/u31a" >/dev/null; r1=$?
( cd "$GA_PROJECTS/p1" && "$bin/ship-promote" "$GA_PROJECTS/p1" --atom a1 --quote '   ' ) 2>"$d/u31b" >/dev/null; r2=$?
[[ $r1 == 10 && $r2 == 10 && $(<"$d/u31a") == *'нужна дословная цитата'* && $(<"$d/u31b") == *'нужна дословная цитата'* && $(gj0) == "$b" && -z "$(nopush p1)" ]] && p u3-1 || f u3-1

mkrepo p2; b=$(gj0)
( cd "$GA_PROJECTS/p2" && "$bin/ship-promote" "$GA_PROJECTS/p2" --atom a2 --quote 'Цитата 2' ) 2>"$d/u32" >/dev/null; r=$?
[[ $r == 10 && $(<"$d/u32") == *'у атома нет открытого PR'* && $(gj0) == $((b + 1)) && -z "$(nopush p2)" ]] && p u3-2 || f u3-2

mkrepo p3; printf 'closed\n' > "$d/bd-status"; b=$(gj0)
( cd "$GA_PROJECTS/p3" && "$bin/ship-promote" "$GA_PROJECTS/p3" --atom a3 --quote 'Цитата 3' ) 2>"$d/u33" >/dev/null; r=$?
rm -f "$d/bd-status"
[[ $r == 10 && $(<"$d/u33") == *'у атома нет открытого PR'* && $(gj0) == $((b + 1)) && -z "$(nopush p3)" ]] && p u3-3 || f u3-3

mkrepo p4
git -C "$GA_PROJECTS/p4" branch dev; git -C "$GA_PROJECTS/p4" push -q -u origin dev; git -C "$GA_PROJECTS/p4" fetch -q origin
quote='переносим ветку dev на prod'
printf '[]\n' > "$d/runs"
( cd "$GA_PROJECTS/p4" && GA_CI_CAP=2 GA_CI_POLL=1 "$bin/ship-promote" "$GA_PROJECTS/p4" --atom a4 --quote "$quote" ) 2>"$d/u34" >/dev/null; r=$?
rm -f "$d/runs"
grep -Fq "$quote" "$GA_LOG_DIR/ship.log" && j=1 || j=0
[[ $r == 40 && $(<"$d/u34") == *'не зелёный'* && $j == 1 && -z "$(nopush p4)" ]] && p u3-4 || f u3-4
