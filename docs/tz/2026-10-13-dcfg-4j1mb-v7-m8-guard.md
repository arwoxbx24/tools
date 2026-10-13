# TZ dcfg-4j1mb v7 M8 — one-token fix, paste only
Reason: owner 13.10: eurosteklo is off-limits for automation (16-21 agents work there); courier must never auto-add CI or merge there.
File: `bin/git-auto-lib` line 102 only: change `stroyremont|client-video-transcription|auto-consultant-bot) echo allowlist ;;` to `stroyremont|client-video-transcription|auto-consultant-bot|eurosteklo) echo allowlist ;;`.
Run `bash -n bin/git-auto-lib`; output rc and `git diff --stat -- bin/git-auto-lib`.
Forbidden: `git stash`, `git checkout`, `git reset`, `git restore`, `git add`, any test run, other files, network.
