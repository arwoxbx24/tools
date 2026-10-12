# Code-channel executor scope check

Allowed files:
- bin/code-channel
- bin/code-channel-test

## U1 — Reject an executor path outside the TZ

Given an isolated real Git working tree and a TZ with `Allowed files:` containing only `bin/x`, when the actual `code-channel` wrapper runs an executor that creates `worktree-tmp/a`, then the wrapper exits nonzero and prints `out-of-scope: worktree-tmp/a`. It must not fall back to another provider after this violation. A changed in-scope `bin/x` remains accepted.

## Contract

The `Allowed files:` block is a list of exact, relative, literal paths, one `- path` per line, ending at the first blank line. The wrapper captures that block before the provider run and checks the paths created or changed by that run. A TZ without this block keeps the existing behavior for legacy callers. The coordinator will document the block for new code runs; do not change provider configuration, models, secrets, audit mode, or Beads.

## Implementation and acceptance

The worker owns only `bin/code-channel` and `bin/code-channel-test`. Add one focused test in the existing isolated fixture; show the new case failing once before the fix, then passing. Preserve existing tests. Run `bash -n bin/code-channel bin/code-channel-test` and one final `bash bin/code-channel-test`; the latter prints `PASS scope_outside` and a passing summary. No direct commit, push, PR, or external service call. The coordinator updates `docs/code-channel.md` and submits the TZ and owned files through guarded `ship-post --submit`. Roll back unsubmitted changes in the own worktree if acceptance fails.

## Focused continuation

The first executor run timed out after reading the two owned files and made no code changes. Start with the existing fixture in `bin/code-channel-test`; add its single outside-path case. Then put the guard at the shared provider-result boundary in `bin/code-channel`, using the existing Git snapshot/status flow. Avoid further architecture search. Report one-line pass summaries or full failure output.

The second run added the test but timed out before implementation. The first red run printed `FAIL scope_outside: rc=23` because the test fixture's mock executor could not create `worktree-tmp/a`: its parent directory was absent. Create that directory in the existing fixture before the case, confirm a red result caused by the missing scope guard, then implement the guard and run the final named checks. Do not add more cases.
