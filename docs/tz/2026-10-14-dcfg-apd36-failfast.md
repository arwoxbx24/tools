# TZ dcfg-apd36 — code-channel: no resume after an upstream refusal

## U1
Goal: when `opencode run` in the code loop (`bin/code-channel:298-312`) fails and its output contains `Upstream request failed:`, the loop stops at once (no `--session` resume); the run keeps its non-zero rc and the existing reconcile path.

Why: 14.10 15:55 `code-channel go … --model opencode-go/deepseek-v4.1-flash` got `Error: Upstream request failed: This Go model requires Global regions. Select Global in your workspace's Privacy settings to use it.` three times; the loop resumed the same session twice and wasted 227 s. An upstream refusal is not fixed by resuming.

Change:
1. Line 299: keep the output streaming to the terminal as now, and also keep a copy in a `mktemp` file (e.g. `… 2>&1 | tee "$oc_out"; run=${PIPESTATUS[0]}`), removed by the script's existing cleanup or a `trap`; follow how the file already makes temp files.
2. After `[[ $run == 0 ]] && break`: `grep -q 'Upstream request failed:' "$oc_out" && { printf 'code-channel: отказ провайдера, без продолжения сессии\n' >&2; break; }`.
3. `bin/code-channel-test`: one case — stub `opencode` prints `Error: Upstream request failed: test` and exits 1 → code-channel calls the stub once (no `--session` call in the args log) and exits non-zero. Follow how existing cases stub `opencode` (no network, no paid call). Existing cases keep passing.

Acceptance (worktree root):
- `bin/code-channel-test` → its PASS total line including the new case
- `bash -n bin/code-channel` exit 0; `git diff --check` exit 0

Rules: SOLID, DRY, KISS, YAGNI; minimal diff; разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`. No secrets. Do not commit; do not push.
Rollback: revert this commit.
