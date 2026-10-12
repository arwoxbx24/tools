# TZ dcfg-j83xb v2 — continue the OpenCode session after ANY failure, from the checkpoint

Done (do not touch): v1 TZ `docs/tz/2026-10-12-dcfg-j83xb-checkpoint.md` — all its items still apply (4× `timeout 1800`, session continuation, test checks 38/39 + new check). Run 1 produced 0 changes: the provider request failed server-side after 601.17 s (`inference_failed`, HTTP 200, streaming, model glm-5.3-flash, endpoint /inference/go/openai/v1/chat/completions, owner dashboard 12.10 14:42). Hypothesis (unverified): the provider caps one streamed request near 600 s.

## U1

Owner 12.10: no error may stop the work; every retry continues from the checkpoint (the same OpenCode session keeps everything already read and done), never from zero.

Source: https://opencode.ai/docs/cli/ — `opencode run` flags: "`--session` | `-s` | Session ID to continue".

Files: `bin/code-channel`, `bin/code-channel-test`, `config/code-channel.json`. разведка — repowise; index checked.

1. Extend the v1 code-mode loop: continue the session not only on rc 124 but on ANY non-zero rc of `timeout 1800 opencode run` in code mode, as long as the session id is found (same sqlite lookup by title `$id_run`).
2. Stop condition (the only one): K consecutive segments with no worktree change (`form_snap` equal before/after the segment). K comes from the config key `"resume_idle_limit"` (top level of `config/code-channel.json`, value 3); read it with jq like the script reads other top-level keys; key absent → treat as 1 (one idle segment stops, current behavior). No numeric literal for K in the script.
3. A segment with worktree change resets the idle counter. After a stop, keep the existing `reconcile` / exit logic (rc of the last segment).
4. Each continuation prints one stderr line: `code-channel: сбой rc=<rc>, продолжаю сессию <sid> (простоев подряд <n>/<K>)`.
5. Tests: one new check — `OPENCODE_SEQUENCE=1,0`, `OPENCODE_TOUCH=resume-any-error.txt`, `SQLITE_SESSION_ID=session-123`, config with `"resume_idle_limit": 3` → rc 0, two `^opencode ` lines, second contains `--session session-123`. Update the final `PASS N/N` line. Existing checks unchanged except those listed in v1.
6. Codex rung (fallback) — out of scope.

Rules: no other files, no model test runs, do not commit. The orphaned run 1 of this atom: check `pgrep -f dcfg-j83xb`; if still alive with 0 changes, it is the stuck failed request — do not start a second run into the same worktree until it exits (the flock will refuse it with exit 25).

Done check:
1. `grep -c "timeout 1800" bin/code-channel` → `4`
2. `grep -c "timeout 590" bin/code-channel` → `0`
3. `grep -c resume_idle_limit bin/code-channel` → ≥ 1
4. `bash -n bin/code-channel` → rc 0
5. `bash bin/code-channel-test` → all PASS, rc 0
