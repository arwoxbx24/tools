# TZ dcfg-8kv99 v2 U2 — code-channel-test follows the SDK-only ladder

Why: CI run 38887863323 `FAIL 22: rc=0 out=sdk claude-haiku-5-5 -`. Check 22 reads the real config/code-channel.json and still expects the go entry, which U1 disabled on purpose.

## U2 — bin/code-channel-test
Skills: caveman:surgical-patch (one line)
1. Line 112, check 22: the expected output becomes only `sdk claude-haiku-5-5 -` (drop the `\ngo opencode-go/deepseek-v4-pro - audit=opencode-go/deepseek-v4-pro` part). Change nothing else.

Files: `bin/code-channel-test`
