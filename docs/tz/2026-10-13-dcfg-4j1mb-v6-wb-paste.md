# TZ dcfg-4j1mb v6 — W-B paste-only (ship no-CI bootstrap)

v6 reason: v3 design added a commit to the atom branch, but the courier accepts only the exact submitted head (`bin/ship-post:506`) → would fail with code 23. v3 run made no edits. Paste the code below; do not explore.
Files: `bin/ship`, `bin/ship-test`, `bin/ship-test.d/zlvq3-docs-only.sh` only.

1. `bin/ship`: replace the whole block that starts with `if [[ $ci == none && $docs_only == 0 ]]; then` and contains `echo 'prod:wait-owner no-ci'` (7 lines, ~173-179) with:
```
# dcfg-4j1mb: no CI -> min-ci merged into $base by its own PR; the atom PR keeps its exact head and is re-opened to get a pull_request run.
ci_bootstrap(){
	local tmp cb=ship/min-ci rc=0
	tmp=$(mktemp -d) || return 1
	g worktree add -q --detach "$tmp/w" "origin/$base" || return 1
	{ "$bin/git-ci-enable" "$tmp/w" >/dev/null \
		&& git -C "$tmp/w" add .github/workflows \
		&& git -C "$tmp/w" commit -q -m "ci: enable min-ci" --trailer "Atom: $atom" --trailer "ТЗ: $tz" --trailer "Agent: $agent" \
		&& git -C "$tmp/w" push -q origin "HEAD:refs/heads/$cb" \
		&& gh pr create -R "$slug" --head "$cb" --base "$base" --title "ci: enable min-ci" --body "ship: repository had no pull_request CI (atom $atom)" >/dev/null \
		&& { gh pr merge "$cb" -R "$slug" --merge --delete-branch >/dev/null || gh pr merge "$cb" -R "$slug" --squash --delete-branch >/dev/null; }; } || rc=1
	g worktree remove --force "$tmp/w" >/dev/null 2>&1
	rm -rf "$tmp"
	return "$rc"
}
if [[ $ci == none && $docs_only == 0 ]]; then
	ci_bootstrap || { echo 'ship: min-ci bootstrap failed' >&2; leave 30 ci-enable; }
	echo 'ci:bootstrap min-ci'
	gh pr close "$num" -R "$slug" >/dev/null && gh pr reopen "$num" -R "$slug" >/dev/null || leave 70 gh
	ci=ci
fi
```
Do NOT touch the mode-two `ci-none` refusal (~152-155).
2. Tests encode the old owner policy (owner changed it 13.10: no-CI repos deliver automatically). Update only these assertions:
   - `bin/ship-test` test 9 (~line 281) and test 18 (~line 359): replace `$out == *'prod:wait-owner no-ci'* && $merge9 != 0` with `$out == *'ci:bootstrap min-ci'* && $(grep -c '^pr merge' "$GH_JOURNAL") -ge 2` (use `$merge18` analog for 18; keep the other conditions; drop conditions that require the worktree to remain if the run now merges and cleans up — read the 5 lines above each test to decide, nothing more).
   - `bin/ship-test.d/zlvq3-docs-only.sh:16`: replace `*'prod:wait-owner no-ci'*` with `*'ci:bootstrap min-ci'*` and `$merge_mixed != 0` with `$merge_mixed == 0`.
3. Run `bin/ship-test` once. Output: failing tests in full, the final PASS/FAIL count line, `git diff --stat`.
Forbidden: network, real remotes, other files, `rm -rf` outside temp dirs.
