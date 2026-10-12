# Ship-post submit and status tails

## U1 — Fetch unavailable after local commit

Given an isolated real Git remote that rejects fetch after `ship-post --submit` creates a local commit, when the agent submits once, then the command closes the own atom with that SHA, writes its submission receipt, prints a deferred conflict-check warning, and returns 0. A reachable conflicting base still returns 50 before closure. The courier performs its normal later fetch and mergeability gate.

## U2 — Parked status belongs to the current SHA

Given an isolated state directory with two real commit SHAs for one atom and an incident row for the older SHA, when `ship-post --status <atom>` runs, then it reports the current SHA as `submitted`, not `parked`. A row for the current SHA still reports `parked`.

## Scope and acceptance

The worker owns only `bin/ship-post` and `bin/ship-post-test`. Use existing Git fixtures and add one focused case per behavior within the existing groups. Show each new case failing before the fix, then passing. Run `bash -n bin/ship-post bin/ship-post-test`, `SHIP_POST_TEST_GROUP=u14 bash bin/ship-post-test`, and `SHIP_POST_TEST_GROUP=status bash bin/ship-post-test`; each group must print `failures=0`. Run the full `bash bin/ship-post-test` suite once after both cases pass. No direct commit, push, or PR. The coordinator submits this TZ and the two owned code files through guarded `ship-post --submit`. Roll back unsubmitted changes with a normal revert if acceptance fails.
