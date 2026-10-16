# TZ — tools-smoke runs only on pull_request (atom dcfg-rxkq1.1)

Cause: GitHub Actions quota 1805/2000 min (owner alert 16.10, reset 01.11, owner: no paid overage). `tools-smoke` runs twice per delivery: on the PR (250 runs since 01.10) and again on push to main after merge (225 runs). Delivery waits only for pull_request runs: `bin/git-auto-lib:149,152` (`gh run list ... --event pull_request`), `bin/ship:204,275` (`ga_ci_wait pr`). The push-main run is read by nothing.

## U1
File: `.github/workflows/tools-smoke.yml`. No other files.
1. In the `on:` block remove the `push:` trigger and its `branches: [main]` line. Keep `pull_request:` exactly as is. Jobs unchanged.

## Check
- Red before edit: `grep -c 'push:' .github/workflows/tools-smoke.yml` → 1.
- Green after: same command → 0; `grep -c 'pull_request:' .github/workflows/tools-smoke.yml` → 1.

## Prohibitions
No commit, no push, no other files, no secrets.
