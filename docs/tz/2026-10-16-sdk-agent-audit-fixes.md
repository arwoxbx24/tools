# TZ dcfg-oqtdg — sdk-agent: close SDK audit A/C defects

Why: SDK audits A and C 16.10 on bin/sdk-agent (base: branch claude/dcfg-kj836-check-listed, commit 8f07216). Line numbers are approximate; find them by the quoted code.
Index: repowise/CBM checked; one bash file + its test. Principles: KISS, YAGNI, fail fast, minimal diff; keep model pin, budget ceilings, existing exit codes and messages.
Out of scope: --restricted flag verification, prompt via stdin, multi-file atomic writes, Read deny rules for the engine.

## U1 — bin/sdk-agent, bin/sdk-agent-test
Skills: caveman:surgical-patch (fix in 2 files), ponytail:ponytail (minimal code), superpowers:test-driven-development (each new test fails first, then passes), security-review (trust boundaries: TZ text, model output, API key, spend ledger)
1. Symlink escape (`check_path`, ~line 166). Refuse a listed path when any existing component of `$WT_REAL/<path>` is a symlink (walk the components with `[[ -L ]]`), and re-apply the existing denylist to the path relative to `$WT_REAL` after `realpath -m`. Match the denylist case-insensitively (`${p,,}`) and add the names `.envrc`, `.npmrc`, `.netrc`, `id_rsa*`, `*.p12`, `.gitmodules`, and the directories `.github`, `.husky`.
2. API key not inherited by Check. Lines ~122–125 (`set -a; . "$KEY_FILE"`): load the key only for the engine call. Run `run_check` (~line 207) under `env -u ANTHROPIC_API_KEY` (and `-u` every other variable the key file defines, read from the variable names on its `NAME=` lines without printing values).
3. Check validated before the engine. Move the static validation of the `Check:` line (metacharacters, absolute path, `..`, executable inside `$WT_REAL`; the logic now in `run_check`) into a function called in `cmd_code` before `run_engine` (~line 273) → refuse with rc 7, nothing written. `run_check` after writing then only executes.
4. Spend ledger fail-closed + cap under lock. Before the engine call: `: >> "$RUNS_LOG" || die "runs log not writable: $RUNS_LOG" 6`. Check the rc of the jq append (~line 139); on failure `die ... 6`. Hold `flock` on `$RUNS_LOG.lock` from the daily-cap check through the ledger append, so parallel runs cannot all pass the cap. In the cap sum, count a line with null/missing `total_cost_usd` as the ceiling 2.00, not 0.
5. Test-only log override. Line 9: honor `SDK_AGENT_RUNS_LOG` only when `SDK_AGENT_TEST=1`; bin/sdk-agent-test exports `SDK_AGENT_TEST=1`.
6. Output guard fails closed (~lines 275–303). Before any write: `jq -e 'all(.structured_output.files[]; type=="object" and (.path|type=="string") and (.content|type=="string"))'` must succeed, else die rc 5 with nothing written. Before each write, `realpath -m` of the target must be under `$WT_REAL`, and the path must be in the listed files.
7. Do not store `.result` text in runs.jsonl (keep subtype, cost, ts, mode).
8. Tests in bin/sdk-agent-test (offline, no key, no network), one per item:
   - listed `notes.md -> .env` symlink → rc 2 `refused path`; `.ENV` listed → rc 2;
   - Check with a metacharacter → rc 7 before the engine (no key file needed);
   - unwritable `SDK_AGENT_RUNS_LOG` (with `SDK_AGENT_TEST=1`) → rc 6;
   - `SDK_AGENT_RUNS_LOG` without `SDK_AGENT_TEST=1` is ignored (grep the script for the guard is not enough: assert behavior, e.g. a cap file over the limit is ignored → not rc 6 for that reason);
   - cap boundary: spent 2.50 + `--budget 0.50` → not rc 6; spent 2.51 + 0.50 → rc 6; a line with null cost counts as 2.00.
   Existing checks stay green; update the final total.

Files: `bin/sdk-agent` `bin/sdk-agent-test`
Acceptance (run by the lead, not by Check: the test file is listed above): `bin/sdk-agent-test` prints `ok N/N`.
