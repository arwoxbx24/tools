# TZ dcfg-l7t7f — code-channel: close SDK audit B defects

Why: SDK audit B 16.10 found these defects in bin/code-channel. Line numbers below refer to origin/main 9f9e850.
Index: repowise/CBM checked; one bash file + its test. Principles: KISS, YAGNI, fail fast, minimal diff; keep all existing messages and exit codes not named here.
Out of scope: "rc=0 without changes" policy, resume_model, SQL in run log, ignored files in snapshot.

## U1 — bin/code-channel, bin/code-channel-test
Skills: caveman:surgical-patch (fix in 2 files), ponytail:ponytail (minimal code), superpowers:test-driven-development (each new test fails first, then passes), security-review (trust boundary: TZ text and env → executor)
1. Real sdk rc, no silent fallback over partial edits. `run_sdk` (line 110): keep printing the rc. Return 0 on 0. On non-zero: if `form_snap` differs from the `before` taken in the ladder loop (line 350), print `code-channel: form=sdk rc=<r> изменено рабочее дерево — лестница остановлена` to stderr and exit with `<r>` (so sdk rc 7 "Check failed after writes" ends the run non-zero). Only when the tree is unchanged return 17 (falls to the next form, as now). Single-form path `form == sdk` (line 334) exits with the real rc.
2. Test-only override. Line 9: honor `CODE_CHANNEL_SDK_AGENT` only when `CODE_CHANNEL_TEST_LOG` is set (the test harness already exports it); otherwise always `$root/bin/sdk-agent`.
3. TZ must not list itself. Before any form runs (right after `tz_abs` is set, line ~88): for every backticked path in the TZ `Files:` line, if `realpath -m -- "$project/<path>"` equals `$tz_abs`, print `code-channel: ТЗ в собственном Files: <path>` and exit 3.
4. Scope check also after sdk. `cc_scope_check` (line 94) is called only inside `run_form` (line 330). Call it the same way after `run_sdk` returns 0 in code mode (capture `cc_pre` before the sdk run as run_form does); out-of-scope → exit 26, no fallback.
5. Remove the `pgrep` single-run lock (lines ~45–71: the exclude/queue loop and the `already running` check). The per-worktree `flock` (line ~90, exit 25) already serialises runs on one worktree; pgrep matched the caller's own pipeline (`code-channel auto P T | grep x` → false "already running").
6. Audit tree check on any rc. In the ladder, in audit mode, compare `form_snap` with `before` also when rc ≠ 0; changed → the existing message and exit 22.
7. Tests in bin/code-channel-test (fake sdk at line 43 already supports `SDK_RC`, `SDK_TOUCH`), one per item:
   - `SDK_RC=7 SDK_TOUCH=x OPENCODE_TOUCH=go-made` auto → exit 7, `go-made` absent, opencode not called;
   - `SDK_RC=6` (no touch) auto → falls to go as now (existing case stays green);
   - without `CODE_CHANNEL_TEST_LOG`, `CODE_CHANNEL_SDK_AGENT=/bin/false` is ignored (check by a dry form that does not reach the engine, e.g. a TZ listing itself → exit 3 before any run, and the fake log is empty);
   - TZ whose `Files:` lists the TZ path → exit 3, no executor called;
   - sdk rc 0 touching a file not in `Files:` → exit 26;
   - `code-channel auto P T | cat` → not "already running";
   - audit with sdk rc ≠ 0 that touched a file → exit 22.
   Update the final PASS total.

Files: `bin/code-channel` `bin/code-channel-test`
