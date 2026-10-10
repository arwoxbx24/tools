# U22 (spec:099 v7, дефект ADR-26): репо без merge-коммитов -> pr merge --squash.
# Ответ поддельного gh api repos/<slug> задаётся файлом $d/allow-merge; по умолчанию true.
. "$bin/git-auto-lib"

# (а) allow_merge_commit=false -> строка 'pr merge ... --squash', rc 0.
mkrepo r22a 1; w22a=$(mkwt r22a claude/u22a); printf 's22a\n' >> "$w22a/f.txt"
printf 'false\n' > "$d/allow-merge"
: > "$GH_JOURNAL"; rm -f "$GH_CREATED"
ship "$w22a" >/dev/null 2>&1; rc=$?
grep -q '^pr merge .* --squash ' "$GH_JOURNAL"; squash=$?
[[ $rc == 0 && $squash == 0 ]] && p u22-1 || f u22-1
rm -f "$d/allow-merge"

# (б) по умолчанию true -> строка 'pr merge ... --merge', rc 0.
mkrepo r22b 1; w22b=$(mkwt r22b claude/u22b); printf 's22b\n' >> "$w22b/f.txt"
: > "$GH_JOURNAL"; rm -f "$GH_CREATED"
ship "$w22b" >/dev/null 2>&1; rc=$?
grep -q '^pr merge .* --merge ' "$GH_JOURNAL"; merged=$?
[[ $rc == 0 && $merged == 0 ]] && p u22-2 || f u22-2
