# TZ U5 — sdk-agent model pin → claude-sonnet-5-5 and code-channel-test 22 expectation for the sdk ladder

Atom dcfg-k3bjj.8 (supersedes TZ U4, which was not run). Owner word 19.10 «sdk-agent tools code full sonet model, жёстко выполнять». Minimal diff: three lines in two files, nothing else. KISS, YAGNI: no refactor, no comments, no other changes.

FILE: bin/sdk-agent
FILE: bin/code-channel-test

## Task
1. `bin/sdk-agent`: in the line `readonly MODEL="claude-haiku-5-5"` replace `claude-haiku-5-5` with `claude-sonnet-5-5`.
2. `bin/sdk-agent`: in the usage text line `Runs the Claude Agent SDK engine with model claude-haiku-5-5 and an API key (never the subscription).` replace `claude-haiku-5-5` with `claude-sonnet-5-5`.
3. `bin/code-channel-test`: the `check 22` line currently expects the plan output of the `go` ladder:
   `CC_CONFIG='' check 22 '[[ $rc == 0 && $out == $'"'"'go opencode-go/deepseek-v4-pro - audit=opencode-go/deepseek-v4-pro'"'"' ]]' \`
   The live ladder `config/code-channel.json` now has only `sdk` enabled with model `claude-sonnet-5-5`, and `code-channel --plan` prints `sdk claude-sonnet-5-5 -` for it (CI run 39288771334 printed `out=sdk claude-haiku-5-5 -` before the model change). Replace the expected string so the line becomes:
   `CC_CONFIG='' check 22 '[[ $rc == 0 && $out == $'"'"'sdk claude-sonnet-5-5 -'"'"' ]]' \`
   Keep the quoting form and the continuation backslash exactly as they are.

## Done when
`grep -c 'claude-sonnet-5-5' bin/sdk-agent` prints 2, `grep -c 'claude-haiku-5-5' bin/sdk-agent` prints 0, `grep -c "sdk claude-sonnet-5-5 -" bin/code-channel-test` prints 1.
