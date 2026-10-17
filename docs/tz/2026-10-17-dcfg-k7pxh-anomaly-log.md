# TZ dcfg-k7pxh — agent-errors-baseline: anomaly mode (spec 109)

Spec: /root/workspaces/projects/specs/109-agent-anomaly-log (spec.md, data-model.md, contracts/cli.md, research.md). Owner 17.10: log only real breakages, defined by exact machine patterns; no noise.

FILE: bin/agent-errors-baseline
FILE: bin/agent-errors-baseline-test

## U1 — `--anomalies` mode (T002–T007)
Extend the existing script (bash + jq + awk only, keep its style). Do not change the weekly path: without `--anomalies` the output must stay byte-identical.

CLI (contracts/cli.md):
```
agent-errors-baseline [--days N] [--corpus DIR]
agent-errors-baseline --anomalies [--session ID] [--days N] [--corpus DIR]
```
- `--session ID`: only files whose basename starts with ID. None found → print `no transcript for ID`, then the total line with zeros.
- `--days N`, `--corpus DIR`: reuse the existing file selection (no second scanner).
- rc 0 always. `--help` gains the new usage line (usage on stdout, rc 0).

Record shapes (FACT, real Claude Code transcripts, one JSON object per line):
- Stop hook feedback: `.type=="user"` and `(.message.content|type)=="string"` and `.message.content|startswith("Stop hook feedback:")` (has `"isMeta":true`).
- Real user prompt: `.type=="user"`, `.isMeta!=true`, string content not starting with `Stop hook feedback:` and not starting with `<task-notification>`.
- Tool call: `.type=="assistant"`, item of `.message.content[]` with `.type=="tool_use"` (`.name`, `.id`, `.input.command` for Bash).
- Tool result: `.type=="user"`, item of `.message.content[]` with `.type=="tool_result"`, `.tool_use_id`, `.is_error`, `.content` (string or array).
- Denial: tool_result with `is_error:true` and content containing `has been denied`; tool name = the `.name` of the tool_use with that id.
- Assistant text: item `.type=="text"`, `.text`.
NOISE RULE (FR-006): never match free text anywhere in a line; a tool_result whose text contains "Stop hook feedback:" is NOT feedback.

Turn = records after a real user prompt or a Stop hook feedback record, up to the next one.

Classes (data-model.md):
- S1: 2nd and each further Stop hook feedback with no real user prompt since the previous feedback → row on that feedback record.
- S2: 3rd and each further consecutive turn with zero tool_use that is ended by Stop hook feedback → row on that feedback record.
- R1: identical Bash `input.command` with an `is_error:true` result, 3rd and further time in one file → row on the tool_result.
- D1: denial of the same tool name, 2nd and further time in one file → row on the tool_result.
- F1: turn with zero tool_use whose last assistant text contains `DONE` → row on that assistant record.

Output: one row per anomaly, tab-separated `<session>\t<line>\t<class>\t<quote>`; session = file basename without `.jsonl`; line = 1-based; quote = text of the record, newlines → spaces, cut to 200 chars. Last line: `anomalies=N S1=a S2=b R1=c D1=d F1=e skipped_lines=K` (K = lines that are not valid JSON; never abort).

## U2 — self-test cases (T003)
In `bin/agent-errors-baseline-test` add fixture JSONL written to a mktemp dir (same style as the existing cases): one positive case per class S1 S2 R1 D1 F1 (expected count 1 each), and one noise case: a tool_result whose content is "Stop hook feedback: x" twice → S1=0. Plus: the weekly output for an existing fixture is unchanged.

Principles: KISS, YAGNI, DRY (reuse existing file loop), fail open on bad lines, minimal diff (≤100 added lines in the main script).
Recon: repowise / codebase-memory first; index checked: repowise/CBM — if missing, `tools/bin/code-memory-enable`.
Forbidden: secrets, `.env`, keys, `~/.ssh`, `/etc`, `.beads`, `.repowise`, other files, rm/rm -rf, git push, network, global installs, writing outside the mktemp dir in tests.
