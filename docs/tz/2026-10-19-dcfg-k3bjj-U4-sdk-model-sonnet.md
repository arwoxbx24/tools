# TZ U4 — sdk-agent: model pin haiku → sonnet (owner word 19.10 «sdk-agent tools code full sonet model, жёстко выполнять»)

Atom dcfg-k3bjj.8. Minimal diff: two lines, nothing else. Principles: KISS, YAGNI; no refactor, no comments, no other changes.

FILE: bin/sdk-agent

## Task
1. In the line `readonly MODEL="claude-haiku-5-5"` replace `claude-haiku-5-5` with `claude-sonnet-5-5`.
2. In the usage text line `Runs the Claude Agent SDK engine with model claude-haiku-5-5 and an API key (never the subscription).` replace `claude-haiku-5-5` with `claude-sonnet-5-5`.
Nothing else: the model-usage check that compares `modelUsage` keys with `$MODEL` stays as is (it already uses the variable), budgets and caps stay as they are.

## Done when
`grep -c 'claude-sonnet-5-5' bin/sdk-agent` prints 2 and `grep -c 'claude-haiku-5-5' bin/sdk-agent` prints 0.
