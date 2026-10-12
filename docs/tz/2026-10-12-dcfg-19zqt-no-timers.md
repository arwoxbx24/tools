# TZ dcfg-19zqt — code-channel: no run timers

## U1

Owner order 12.10: no timers in the code channel and no hardcoded values. The channel runs in background (code-atom.js, PR #388), the caller never waits, so a timer only kills live work.

Files: `bin/code-channel`, `bin/code-channel-test` only.

1. `bin/code-channel`: at the 4 call sites (`timeout 1800 codex exec` twice, `timeout 1800 opencode run` twice) remove the `timeout 1800 ` prefix so the command starts with `codex exec` / `opencode run`. Keep everything else, including existing rc handling.
2. `bin/code-channel-test`: checks 38 and 39 currently compare the stub timeout log with a number. Change both to assert that the timeout stub was NOT invoked (the stub log file is absent or empty), keeping each check's existing rc condition. Do not touch other checks.

Rules: no other files, no model runs, do not commit. Index: repowise/CBM checked; разведка — repowise.

Done check:
1. `grep -cE "timeout [0-9]" bin/code-channel` → `0`
2. `bash -n bin/code-channel` → rc 0
3. `bash bin/code-channel-test` → all PASS, rc 0 (the one test run of this atom)
