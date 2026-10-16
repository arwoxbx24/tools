# TZ dcfg-khdsp.1 U3 — sdk-agent: no duplicate block, code mode sees the project and runs the TZ check (owner 16.10)

Why: CI jscpd failed on PR tools#275: "sdk-agent [189:3-198:8] / sdk-agent [266:3-275:8]" (new clone). Owner 16.10: the SDK hand must do what OpenCode does — see the project, change files, validate.
Index: repowise/CBM checked, not needed (single bash file, read whole by the wrapper). Principles: KISS, YAGNI, DRY; minimal diff; keep every existing check and message.

## U3
1. `bin/sdk-agent`: move the duplicated worktree/TZ checks of `cmd_code` and `cmd_read` (the lines from `local wt=${POS[0]} tz=${POS[1]}` through `[[ -r $tz ]] || die "TZ file not readable: $tz"`) into one function `open_worktree` that sets globals `WT_REAL` and `TZ`; both commands call it and use those globals. Same error texts and exit codes.
2. `cmd_code`: run the engine with tools `Read,Grep,Glob` inside the worktree (same call form as `cmd_read`: `run_engine "$EFFORT" "$BUDGET" "$prompt" "$CODE_SCHEMA" "" "Read,Grep,Glob" "$WT_REAL"`), and add to the prompt: "You may read any file of the repository with Read, Grep, Glob." The output guard (only listed paths written) stays unchanged.
3. `cmd_code`: allowed number of listed paths 1..20 (was 1..5); message text updated to `1..20`.
4. `cmd_code`: after writing files, if the TZ has a line starting `Check: ` take the first such line, run its text with `bash -c` inside `$WT_REAL`, print `sdk-agent: check rc=<rc>` to stderr; exit 7 if rc is not 0. No Check line -> nothing runs (as now).
5. Usage text: add one line `code: model may read the whole worktree; TZ line "Check: <command>" is run after writing (rc 7 on failure).`
6. `bin/sdk-agent-test`: keep all existing checks passing (adjust only an expectation that names `1..5`).

7. Security (U3.7, replaces the `bash -c` of item 4): the Check text is split on spaces into words, no shell. Refuse (print `sdk-agent: refused check: <text>` to stderr, exit 7, run nothing) if the text contains any of the characters ; & | $ ` < > ( ) \ ' " or a newline, or if the first word starts with `/`, contains a `..` segment, or is not an executable regular file inside `$WT_REAL` (realpath must stay under `$WT_REAL`). Otherwise run the words as an argv array inside `$WT_REAL` (`(cd -- "$WT_REAL" && "./${words[0]}" "${words[@]:1}")`).
8. Items 1-6 are already in `bin/sdk-agent`; change only the Check block for item 7 and the usage line (say "Check: <executable inside worktree> [args]", no shell). No new test; existing tests must pass.

Files: `bin/sdk-agent` `bin/sdk-agent-test` `docs/tz/2026-10-16-dcfg-khdsp-U3-sdk-parity.md`
Check: bin/sdk-agent-test
