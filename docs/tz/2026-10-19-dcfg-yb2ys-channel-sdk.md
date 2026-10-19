# TZ dcfg-yb2ys.1 — code-channel ladder: only `sdk` (owner word 19.10)

Owner (19.10): «sdk-agent tools code full sonet model», «Я приказал работа - это именно СДК Агент - это приоритет жёсткий приоритет». `config/code-channel.json` is already switched in this branch (`sdk` enabled, `go` disabled); `bin/code-channel --plan` now prints exactly one line: `sdk claude-haiku-5-5 -`. CI test 22 and the docs still describe `go` as active. Bring them in line. No other change.

FILE: bin/code-channel-test
FILE: docs/code-channel.md

## bin/code-channel-test
In the `check 22` call (the `CC_CONFIG='' check 22 '[[ $rc == 0 && $out == $'"'"'go opencode-go/deepseek-v4-pro - audit=opencode-go/deepseek-v4-pro'"'"' ]]'` line) replace the expected string `go opencode-go/deepseek-v4-pro - audit=opencode-go/deepseek-v4-pro` with `sdk claude-haiku-5-5 -`. Keep the quoting form exactly as it is; change nothing else in the file.

## docs/code-channel.md
1. Ladder table row `| \`sdk\` | выключен (owner 18.10: переключено на OpenCode Go) | …` → first two cells become `| \`sdk\` | включён (owner 19.10: «sdk-agent tools code full sonet model» — жёсткий приоритет) |`; keep the third cell unchanged.
2. Ladder table row `| \`go\` | включён (owner 18.10: «использовать опенкод гоу модель дипсиик про для агентов») | …` → first two cells become `| \`go\` | выключен (owner 19.10: переключено на sdk-agent); включается словом владельца |`; keep the third cell unchanged.
3. Paragraph starting `Включена ровно одна запись — активный канал; сейчас \`go\` (owner 18.10), \`sdk\` выключена.` → replace that first sentence with `Включена ровно одна запись — активный канал; сейчас \`sdk\` (owner 19.10), \`go\` выключена.`; keep the rest of the paragraph unchanged.

Constraints: minimal diff, no new files, no other lines touched, no secrets, no model pin change in bin/sdk-agent (haiku pin stays).
Done-check: `grep -c "sdk claude-haiku-5-5 -" bin/code-channel-test` = 1; `grep -c "сейчас \`sdk\` (owner 19.10)" docs/code-channel.md` = 1.
