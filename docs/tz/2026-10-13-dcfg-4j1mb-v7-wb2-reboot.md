# TZ dcfg-4j1mb v7 WB2 — fix repeat bootstrap, paste only
Reason: ship-test 5/6 fail rc=30: a second bootstrap in the same repo is rejected because `ship/min-ci` already exists (non-fast-forward), and a left-over PR for that head would fail `gh pr create`. `ship/min-ci` is ship's own disposable branch, rebuilt from `origin/$base` each time.
File: `bin/ship`, function `ci_bootstrap` only.
1. Replace `git -C "$tmp/w" push -q origin "HEAD:refs/heads/$cb"` with `git -C "$tmp/w" push -q origin "+HEAD:refs/heads/$cb"` and append on the line before it nothing; add above `ci_bootstrap(){` nothing else.
2. Replace `&& gh pr create -R "$slug" --head "$cb" --base "$base" --title "ci: enable min-ci" --body "ship: repository had no pull_request CI (atom $atom)" >/dev/null \` with
```
		&& { gh pr create -R "$slug" --head "$cb" --base "$base" --title "ci: enable min-ci" --body "ship: repository had no pull_request CI (atom $atom)" >/dev/null || gh pr view "$cb" -R "$slug" >/dev/null; } \
```
3. Run `bin/ship-test` once. Output: FAIL lines, PASS count (`grep -c '^PASS '`), `git diff --stat`. If 5/6 still fail, print the failing trace lines only, do not edit tests.
Forbidden: other files, network.
