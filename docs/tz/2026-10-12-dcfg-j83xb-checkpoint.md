# TZ dcfg-j83xb — code-channel: `timeout 1800` as a checkpoint, continue the OpenCode session while there is progress

## U1

Architecture (owner 12.10: OpenCode Go must finish tasks of any size; goal AC2 requires `grep -c "timeout 1800" bin/code-channel` = 4). A 1800 s timer is a checkpoint, not a task kill: when an `opencode run` code segment ends with rc 124 and the worktree changed during that segment (existing `form_snap`), the channel continues the same OpenCode session; a task is stopped only after a full 1800 s segment with zero worktree change (a real hang).

Source: https://opencode.ai/docs/cli/ — `opencode run` flags: "`--session` | `-s` | Session ID to continue"; "`--title` | | Title for the session"; "`--model` | `-m` | Model to use in the form of provider/model".

Files: `bin/code-channel`, `bin/code-channel-test` only. разведка — repowise; index checked.

1. `bin/code-channel`, the four executor invocations get the prefix `timeout 1800` (the literal text `timeout 1800` must appear exactly 4 times in the file):
   - codex audit call (`codex exec -p quota-terra "${codex_args[@]}" -s read-only "$prompt"`) → `timeout 1800 codex exec …` (behavior otherwise unchanged).
   - codex code call (`codex exec -p quota-terra "${codex_args[@]}" -s workspace-write …`) → `timeout 1800 codex exec …` (behavior otherwise unchanged).
   - opencode audit call (`opencode run --agent audit …`) → `timeout 1800 opencode run --agent audit …` (no continuation in audit).
   - opencode code call (`opencode run --title "$id_run" -m "$model" "$prompt" < /dev/null; run=$?`) → replace with ONE loop containing the single `timeout 1800 opencode run` line:
     ```
     oc_args=(--title "$id_run") oc_prompt=$prompt seg_before=$(form_snap)
     while :; do
         timeout 1800 opencode run "${oc_args[@]}" -m "$model" "$oc_prompt" < /dev/null; run=$?
         [[ $run == 124 ]] || break
         seg_after=$(form_snap)
         [[ $seg_after != "$seg_before" ]] || break
         sid=$(sqlite3 -readonly "$db" "select id from session where title='$id_run' order by time_created desc limit 1" 2>/dev/null)
         [[ -n $sid ]] || break
         printf 'code-channel: контрольная точка 1800 с, есть правки — продолжаю сессию %s\n' "$sid" >&2
         seg_before=$seg_after oc_args=(--session "$sid") oc_prompt='Продолжи задачу из этой сессии с места остановки и доведи её до конца.'
     done
     ```
     Use the same `$db` path variable the script already uses in `reconcile` for the session lookup (if `$db` is local to `reconcile`, compute it the same way it is computed there; do not invent a new path). Keep `reconcile "$run"` and the exit logic after the loop unchanged.
   - No other numeric constants, no sleep, no other timers. `timeout 590` must stay absent.
2. `bin/code-channel-test`:
   - check 38: replace `! -s $tlog` with `grep -qx 1800 "$tlog"` (keep `rc == 124`: no progress → stop).
   - check 39: replace `! -s $tlog` with `grep -qx 1800 "$tlog"` (keep `rc == 0`).
   - add one new check before the final summary line, using config `$go`: `env OPENCODE_SEQUENCE=124,0 OPENCODE_TOUCH=checkpoint-progress.txt SQLITE_SESSION_ID=session-123 SQLITE_RESULT='opencode-go|mimo-v2.6-flash' "$root/bin/code-channel" go "$project" "$tz"` → expect `rc == 0`, exactly 2 lines `^opencode ` in `$log`, and `grep -Fq -- "--session session-123" "$log"`. Clear `$log` before it the same way neighboring checks do if they do.
   - update the final `PASS N/N` summary line to the new total. Do not change other checks.

Rules: no other files, no model test runs, do not commit.

Done check:
1. `grep -c "timeout 1800" bin/code-channel` → `4`
2. `grep -c "timeout 590" bin/code-channel` → `0`
3. `bash -n bin/code-channel` → rc 0
4. `bash bin/code-channel-test` → all PASS, rc 0
