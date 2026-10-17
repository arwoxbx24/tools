# TZ dcfg-5bc84 — goal-guard: honor stop_hook_active (loop guard)

Atom: dcfg-5bc84 (epic dcfg-82rso). Owner 17.10: Stop hooks re-blocked agents in a loop; hard control without recursion.

## U1 — early exit when Claude Code is already continuing because of a stop hook
FILE: bin/goal-guard
(the only code file to change)

Cause (fact): goal-guard never reads `stop_hook_active`, so after a block the agent calls a tool, the harness 8-continuation cap resets ("The count of consecutive continuations resets each time Claude calls a tool."), and goal-guard blocks again.
Source: https://code.claude.com/docs/en/hooks#stop — "The `stop_hook_active` field is `true` when Claude Code is already continuing as a result of a stop hook. Check this value or process the transcript to avoid blocking on a condition that will never resolve."

Change:
1. Right after line `[ -n "$json" ] || exit 0` add one line that exits 0 when the stdin JSON has `stop_hook_active == true`, e.g.
   `jq -e '.stop_hook_active == true' >/dev/null <<<"$json" && exit 0`
   Missing or false field → behavior unchanged (Codex and old versions keep working).
2. In the `--help` usage line add the clause `; пропускает остановку при stop_hook_active=true` before the closing `)`. Usage stays on stdout, rc 0.
Nothing else changes: counter, max=8, regexes, messages, fail-open style.

Check (lead runs it, not the executor):
- payload with `"stop_hook_active":true` + open session atom → empty stdout, rc 0;
- same payload with `false` → exactly one `{"decision":"block",...}` line;
- `bin/goal-guard --help` → rc 0, usage on stdout.

Principles: KISS, YAGNI, minimal diff, fail open at the system boundary.
Recon: repowise / codebase-memory first; index checked: repowise/CBM — if missing, `tools/bin/code-memory-enable`.
Forbidden: secrets, `.env`, keys, `~/.ssh`, `/etc`, `.beads`, `.repowise` index, other files, rm/rm -rf, git push, global installs, network writes.
