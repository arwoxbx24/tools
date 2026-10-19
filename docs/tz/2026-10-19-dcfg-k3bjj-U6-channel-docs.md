# TZ U6 — tools docs follow the switch to the sdk channel and the Sonnet pin (owner words 19.10)

Atom dcfg-k3bjj.8 (real run on the Sonnet pin). Minimal diff: three lines in two files, nothing else. KISS, YAGNI: no rewording beyond the facts below, no other lines.

FILE: docs/code-channel.md
FILE: TOOLS-REGISTRY.md

## Facts (merged in tools PR 350, 19.10)
- `config/code-channel.json`: only `sdk` is `enabled: true`; `go` is `false`. Owner word 19.10: «Канал кода и исследований переключён на SDK-агент».
- `bin/sdk-agent` model pin is `claude-sonnet-5-5` (owner word 19.10 «sdk-agent tools code full sonet model»). Daily cap is 7.00 USD (owner 17.10), per-run budget ≤ 2.00 USD.

## Task
1. `docs/code-channel.md`, the table row that starts with `| \`sdk\` |`: replace the status cell `выключен (owner 18.10: переключено на OpenCode Go)` with `включён (owner 19.10: переключено на SDK-агент)` and replace `claude-haiku-5-5` with `claude-sonnet-5-5` in the same row. Nothing else in the row changes.
2. `docs/code-channel.md`, the paragraph line that starts with `Включена ровно одна запись — активный канал; сейчас \`go\` (owner 18.10), \`sdk\` выключена.`: replace that opening fragment with `Включена ровно одна запись — активный канал; сейчас \`sdk\` (owner 19.10), \`go\` выключена.` The rest of the line stays as is.
3. `TOOLS-REGISTRY.md`, the row that starts with `| \`tools/bin/sdk-agent\` |`: replace `model claude-haiku-5-5` with `model claude-sonnet-5-5` and `daily cap 5.00 USD` with `daily cap 7.00 USD`. Nothing else in the row changes.

## Done when
`grep -c 'claude-haiku-5-5' docs/code-channel.md TOOLS-REGISTRY.md` prints 0 for both files; `grep -c 'сейчас \`sdk\` (owner 19.10)' docs/code-channel.md` prints 1; `grep -c 'daily cap 7.00 USD' TOOLS-REGISTRY.md` prints 1.
