# Research: repo-visibility

## R1 Visibility change
- Decision: `gh repo edit arwoxbx24/<repo> --visibility public --accept-visibility-change-consequences`.
- Rationale: `gh repo edit --help` (20.10): "--visibility string … {public,private,internal}"; "When the `--visibility` flag is used, `--accept-visibility-change-consequences` flag is required."
- Alternatives: `gh api -X PATCH /repos/…` — write API, denied by house rule for agents.

## R2 Secret scan before publishing
- Decision: both `bin/secret-gate scan <mirror>` and `gitleaks git --no-banner --redact --log-opts=--all --report-format json --report-path <file> <mirror>`; findings = BLOCKED lines of secret-gate + `jq length` of the gitleaks report.
- Rationale: secret-gate finds our real secret values (`bin/secret-gate:175-182`: rc 1 + `secret-gate: BLOCKED` lines, rc 2 on error); gitleaks finds generic token patterns and is already the pre-push gate (`git-hooks/pre-push:39`); `gitleaks git --help` lists `--log-opts`, `--report-format`, `--report-path`, `--exit-code` (default 1).
- Alternatives: one scanner only — misses either our values or third-party tokens.

## R3 Full history
- Decision: `gh repo clone arwoxbx24/<repo> <tmp>/mirror -- --mirror` (all refs incl. `refs/pull/*`).
- Rationale: the tools publication 17.10 was accepted on a mirror scan incl. refs/pull (bd dcfg-tf331.3 notes).

## R4 Minutes
- Decision: `gh api "/organizations/<org>/settings/billing/usage?year=<Y>&month=<M>"`, sum `quantity` of items with `product=="actions"` and `unitType=="Minutes"` per `repositoryName`, round to integer.
- Rationale: measured 20.10 — agent-contour 501, arwox-v3-src 25, eurosteklo 10, tools 1587.
- Visibility: `gh repo list <org> --limit 1000 --json name,visibility`.
