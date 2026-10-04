# U7b (FR-006, ADR-8, Edge :100): не вливать чужой PR в prod; ci-none до PR; база не пересчитывается.
# Подключается через `.` из bin/ship-test: доступны $d, $GH_JOURNAL, mkrepo, mkwt, ship, p, f.

# u7b-1 (D3): режим two, открытый PR ветки с базой main -> 10 pr-base, pr merge не зван.
mkrepo u7a 1
git -C "$GA_PROJECTS/u7a" branch dev
git -C "$GA_PROJECTS/u7a" push -q -u origin dev
git -C "$GA_PROJECTS/u7a" fetch -q origin
w7a=$(mkwt u7a claude/u7a1); printf 's\n' >> "$w7a/f.txt"
printf 'main\n' > "$d/pr-base"
merge_before=$(grep -c '^pr merge' "$GH_JOURNAL" 2>/dev/null); merge_before=${merge_before:-0}
out=$(ship "$w7a" 2>&1); rc=$?
merge_after=$(grep -c '^pr merge' "$GH_JOURNAL" 2>/dev/null); merge_after=${merge_after:-0}
rm -f "$d/pr-base"
[[ $rc == 10 && $out == *'нужен dev'* && $merge_after == $merge_before ]] && p u7b-1 || f u7b-1

# u7b-2 (D5): режим two без workflow pull_request -> 30 ci-none ДО pr create.
mkrepo u7b
git -C "$GA_PROJECTS/u7b" branch dev
git -C "$GA_PROJECTS/u7b" push -q -u origin dev
git -C "$GA_PROJECTS/u7b" fetch -q origin
w7b=$(mkwt u7b claude/u7b1); printf 's\n' >> "$w7b/f.txt"
create_before=$(grep -c '^pr create' "$GH_JOURNAL" 2>/dev/null); create_before=${create_before:-0}
out=$(ship "$w7b" 2>&1); rc=$?
create_after=$(grep -c '^pr create' "$GH_JOURNAL" 2>/dev/null); create_after=${create_after:-0}
[[ $rc == 30 && $create_after == $create_before && $out == *'нет CI pull_request'* ]] && p u7b-2 || f u7b-2

# u7b-3 (Edge :100): без dev; dev появилась на origin после preflight (первый pr:list) — PR всё ещё в main.
: > "$d/mk-dev-on-list"
mkrepo u7c
w7c=$(mkwt u7c claude/u7c1); printf 's\n' >> "$w7c/f.txt"
rm -f "$GH_CREATED"
out=$(ship "$w7c" 2>&1); rc=$?
last=$(grep '^pr create' "$GH_JOURNAL" | tail -n1)
rm -f "$d/mk-dev-on-list"
[[ $rc == 0 && $last == *'--base main'* ]] && p u7b-3 || f u7b-3
