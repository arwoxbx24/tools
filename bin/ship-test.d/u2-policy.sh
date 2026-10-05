# U2 (FR-002, FR-006, FR-021): политика — --reload в two, ci-none в two.
# Подключается через `.` из bin/ship-test: доступны $d, $GH_JOURNAL, mkrepo, mkwt, ship, p, f.

# u2-1 (v2 ADR-11): клиентский репо под GA_CLIENTS_ROOT без dev -> не отказ политики.
mkrepo u2a; w2a=$(mkwt u2a claude/u2a1); printf 's\n' >> "$w2a/f.txt"
gh_before=$(wc -l < "$GH_JOURNAL")
br_before=$(git ls-remote --heads "$d/origin-u2a.git" | wc -l)
export GA_CLIENTS_ROOT="$GA_PROJECTS"
out=$(ship "$w2a" 2>&1); rc=$?
unset GA_CLIENTS_ROOT
gh_after=$(wc -l < "$GH_JOURNAL")
br_after=$(git ls-remote --heads "$d/origin-u2a.git" | wc -l)
[[ $out != *'нужна ветка dev'* && $out != *'policy'* ]] && p u2-1 || f u2-1

# u2-2 (Edge --reload): репо с dev, ship с --reload x -> 10, gh не зван.
mkrepo u2b
git -C "$GA_PROJECTS/u2b" branch dev
git -C "$GA_PROJECTS/u2b" push -q -u origin dev
git -C "$GA_PROJECTS/u2b" fetch -q origin
w2b=$(mkwt u2b claude/u2b1); printf 's\n' >> "$w2b/f.txt"
gh_before=$(wc -l < "$GH_JOURNAL")
out=$(ship "$w2b" --reload x 2>&1); rc=$?
gh_after=$(wc -l < "$GH_JOURNAL")
[[ $rc == 10 && $out == *'только ship-promote'* && $gh_after == $gh_before ]] && p u2-2 || f u2-2

# u2-3 (Edge ci-none): репо с dev, в origin/dev нет workflow pull_request -> 30.
mkrepo u2c
git -C "$GA_PROJECTS/u2c" branch dev
git -C "$GA_PROJECTS/u2c" push -q -u origin dev
git -C "$GA_PROJECTS/u2c" fetch -q origin
w2c=$(mkwt u2c claude/u2c1); printf 's\n' >> "$w2c/f.txt"
out=$(ship "$w2c" 2>&1); rc=$?
[[ $rc == 30 && $out == *'нет CI pull_request'* ]] && p u2-3 || f u2-3
