#!/bin/bash
# pre-push branch guard: semantic ref check in git-hooks/dispatch.
set -u
HOOKS="$(cd "$(dirname "$0")/../git-hooks" && pwd -P)"
G="$(mktemp -d -p /var/tmp)"
X="$(mktemp -d)"
trap 'rm -rf -- "$G" "$X"' EXIT
ok=0
fail=0
pass() { ok=$((ok+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1: $2"; }

git init -q --bare "$G/r.git"
git init -q --bare "$X/r.git"
git clone -q "$G/r.git" "$G/w"
cd "$G/w" || exit 1
echo a >f
git add f
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git branch -M main
git branch claude/x
err="$G/err"

# 1. push_new
if git -c core.hooksPath="$HOOKS" push -q origin main claude/x 2>"$err"; then pass push_new; else bad push_new "rc=$? $(cat "$err")"; fi

# 2. fast_forward
git checkout -q claude/x
echo b >>f
git -c user.name=t -c user.email=t@example.invalid commit -qam ff
if git -c core.hooksPath="$HOOKS" push -q origin claude/x 2>"$err"; then pass fast_forward; else bad fast_forward "rc=$? $(cat "$err")"; fi

# 3. delete_no_tag
if git -c core.hooksPath="$HOOKS" push origin --delete claude/x 2>"$err"; then
	bad delete_no_tag "push succeeded"
elif grep -q "no archive tag" "$err" && [ -n "$(git ls-remote origin refs/heads/claude/x)" ]; then
	pass delete_no_tag
else
	bad delete_no_tag "rc=$? stderr=$(cat "$err")"
fi

# 4. non_ff
git reset -q --hard HEAD^
before=$(git ls-remote origin refs/heads/claude/x | cut -f1)
if git -c core.hooksPath="$HOOKS" push --force origin claude/x 2>"$err"; then
	bad non_ff "push succeeded"
elif grep -q "non-fast-forward" "$err" && [ "$(git ls-remote origin refs/heads/claude/x | cut -f1)" = "$before" ]; then
	pass non_ff
else
	bad non_ff "rc=$? stderr=$(cat "$err")"
fi

# 5. delete_main
main_sha=$(git ls-remote origin refs/heads/main | cut -f1)
git -c core.hooksPath="$HOOKS" push -q origin "$main_sha:refs/tags/archive/main-20261022" 2>"$err"
if git -c core.hooksPath="$HOOKS" push origin :main 2>"$err"; then
	bad delete_main "push succeeded"
elif [ -n "$(git ls-remote origin refs/heads/main)" ]; then
	pass delete_main
else
	bad delete_main "main gone, rc=$? stderr=$(cat "$err")"
fi

# 6. safe_delete_route
sha=$(git ls-remote origin refs/heads/claude/x | cut -f1)
git -c core.hooksPath="$HOOKS" push -q origin "$sha:refs/tags/archive/claude-x-20261022" 2>"$err" || bad safe_delete_route "tag push: $(cat "$err")"
if git -c core.hooksPath="$HOOKS" push -q --force-with-lease=refs/heads/claude/x:"$sha" origin :refs/heads/claude/x 2>"$err"; then
	if [ -z "$(git ls-remote origin refs/heads/claude/x)" ]; then pass safe_delete_route; else bad safe_delete_route "branch still on remote"; fi
else
	bad safe_delete_route "rc=$? $(cat "$err")"
fi

# 7. tmp_exempt
git clone -q "$X/r.git" "$X/w"
cd "$X/w" || exit 1
echo a >f
git add f
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git -c core.hooksPath="$HOOKS" push -q origin HEAD:claude/y 2>"$err" || bad tmp_exempt "branch push: $(cat "$err")"
if git -c core.hooksPath="$HOOKS" push -q origin --delete claude/y 2>"$err"; then pass tmp_exempt; else bad tmp_exempt "rc=$? $(cat "$err")"; fi

echo "итог: PASS $ok, FAIL $fail"
[ "$fail" -eq 0 ]
