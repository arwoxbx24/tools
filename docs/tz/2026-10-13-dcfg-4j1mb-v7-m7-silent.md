# TZ dcfg-4j1mb v7 M7 — one-token fix, paste only
Reason (real run 13.10): break-glass printed `incident=✓ Created issue: dcfg-jxo72 — ...` (full human output) instead of the id; the INFRA incident path uses `--silent`.
File: `bin/ship-post`, function `do_break_glass`: in `incident=$(bd_home create "[ship-post] break-glass $atom $head_sha" -t bug -p 0 -l contour:delivery,break-glass \` insert ` --silent` after `contour:delivery,break-glass`. Nothing else.
Run `bash -n bin/ship-post`; output rc and `git diff --stat`.
Forbidden: `git stash`, `git checkout`, `git reset`, `git restore`, any test run, other files, network.
