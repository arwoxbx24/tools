# TZ dcfg-4j1mb v2 — U4: git-ci-enable writes a self-contained min-ci

Reason for v2: `bin/git-ci-enable` writes a caller of `arwoxbx24/agent-contour/.github/workflows/min-ci.yml@main`; that file does not exist (`gh api repos/arwoxbx24/agent-contour/contents/.github/workflows` → ai-review.yml, ci.yml, pr-agent-review.yml), so every added CI would fail. Owner 13.10: no-CI repositories deliver fully automatically with a deterministic check.

Repo: this worktree (tools). Files you may edit: `bin/git-ci-enable`, `bin/git-ci-enable-test`. Nothing else.
Reconnaissance: repowise / codebase-memory first, then `grep -n`, then Read only ranges you edit. Same principles and forbidden list as `docs/tz/2026-10-13-dcfg-4j1mb-ship-chain.md`. No network in tests.

## U4
1. Keep the CLI contract: `git-ci-enable <worktree>`; existing `pull_request` workflow → `ci:present`, rc 0; otherwise write the file and print `ci:added <path>`, rc 0.
2. File name `.github/workflows/min-ci.yml` (replace `min-ci-caller.yml`). Content, self-contained, no `uses:` of other repositories:
   - `name: min-ci`, `on: pull_request`, `permissions: contents: read`.
   - one job `min-ci` on `ubuntu-latest`, `timeout-minutes: 5`.
   - step `actions/checkout@v4` with `fetch-depth: 0`.
   - step `conflict markers`: fail if any tracked file has a line starting with `<<<<<<< ` or `>>>>>>> ` (`git grep -nE '^(<<<<<<<|>>>>>>>) '` → exit 1 when found).
   - step `gitleaks`: `docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:v8.30.1 git /repo --redact --no-banner --log-opts="origin/${{ github.base_ref }}..HEAD"`.
3. `bin/git-ci-enable-test`: update expectations to the new file name and assert no `uses: arwoxbx24/` line and presence of `gitleaks:v8.30.1`.
Check: `bin/git-ci-enable-test` exit 0. End with `git diff --stat`.
