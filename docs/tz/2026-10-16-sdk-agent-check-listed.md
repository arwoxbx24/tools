# TZ dcfg-kj836 — sdk-agent: Check must not run a file the same TZ lets the model write

Why: side-agent finding 16.10, confirmed in code: `run_check` (bin/sdk-agent) only requires an executable inside the worktree; a TZ may list that same file in `Files:`, the model rewrites it, and `Check:` runs the new content.
Index: repowise/CBM checked, not needed (one bash file). Principles: KISS, YAGNI, fail fast, minimal diff; keep all existing checks and messages.

## U1 — bin/sdk-agent, bin/sdk-agent-test
Skills: caveman:surgical-patch (fix in 1–2 files), ponytail:ponytail (minimal code), superpowers:test-driven-development (offline check fails first, then passes), security-review (trust boundary: TZ text → executed command)
1. In `cmd_code`, right after the listed paths are collected and checked (before the prompt is built and before any engine call): if the TZ has a `Check: ` line, take its first word; if `realpath -m -- "$WT_REAL/<word>"` equals `realpath -m -- "$WT_REAL/<f>"` for any listed path f, call `refuse_check "<check text>"` (prints `sdk-agent: refused check: ...`, exit 7). Nothing is sent to the engine.
2. Usage line for code: append "; the Check executable must not be a listed file".
3. `bin/sdk-agent-test`: one offline check (no key, no network): a temp git worktree with an executable `t.sh`, TZ with `Files: \`t.sh\`` and `Check: t.sh` -> `sdk-agent code` exits 7 and stderr contains `refused check`. Existing checks stay; update the final total.

Files: `bin/sdk-agent` `bin/sdk-agent-test`
Check: bin/sdk-agent-test
