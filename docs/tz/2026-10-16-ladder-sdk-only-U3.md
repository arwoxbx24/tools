# TZ dcfg-8kv99 v2 U3 — revert unrequested edit of check 53

Why: the U2 run changed check 53 (line ~200) without request: `*switch\ go→codex\ rc=1*` became `*switch\\ go→codex\\ rc=1*`.

## U3 — bin/code-channel-test
Skills: caveman:surgical-patch (one line)
1. In check 53 restore exactly the origin/main text `[[ $err == *switch\ go→codex\ rc=1* ]]` (single backslash before each space). Keep check 22 as it is now. Change nothing else.

Files: `bin/code-channel-test`
