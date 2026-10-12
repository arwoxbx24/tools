Done (do not touch): `bin/ship-post` now defers fetch failure after commit; `bin/ship-post-test` contains U14 and ST6/ST7 cases; `code-channel: mode=code form=go provider=opencode-go model=opencode-go/glm-5.3-flash precheck=- run=0 t=365`. The previous run left `U14_close_on_unreachable` failing (`checks=3 failures=1`) and reported `status` as `checks=7 failures=0`, but ST6 does not prove the required behavior.

# Complete ship-post tail acceptance

## U1 — Fix the real Git fixture, not submit behavior

The mock `bd close` writes only the atom ID to `$d/bd.closes` (`bin/ship-post-test:88`), so the current U14 assertion that searches that file for `--reason submitted <sha>` cannot pass. The fixture already uses a real Git commit and a remote that rejects fetch. Rename the case exactly `U14_fetch_failure_close`; assert rc 0, `$d/bd.closes` equals the atom ID, current post-submit `git rev-parse HEAD` matches the submission receipt path, output contains the deferred conflict warning, and no second submit is needed. Preserve the existing reachable-conflict rc50 case. Show `PASS U14_fetch_failure_close` and `failures=0` in one focused run.

## U2 — Prove stale parked incident behavior

Current ST6 creates a delivered receipt, so receipt priority bypasses the parked lookup; it also derives `sha2` from the same string as `sha` and truncates it. Use two different actual Git commit SHAs from the fixture repository. For ST6, leave the newer SHA submitted without a delivered receipt, add an incident row with the older SHA, and assert `submitted` for the newer SHA. For ST7, use an incident row with the current SHA and assert `parked`. `do_status` must require the incident row SHA to equal the selected current SHA; a row without SHA cannot prove the link. Show `PASS ST6`, `PASS ST7`, `failures=0` in one focused run.

## Limits

Edit only `bin/ship-post` and `bin/ship-post-test`; preserve all passed behavior. No new abstractions or unrelated comments. One focused run per affected group, then one full `bash bin/ship-post-test` run if both pass; print only PASS case names, count and failures summary. No direct commit, push, Beads or PR. Report exact failing output if acceptance does not pass. Do not rerun a passed check on unchanged code.
