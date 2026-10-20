# Tasks: repo-visibility

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/cli.md, quickstart.md in `specs/dcfg-3hm7s-repo-visibility/`

**Tests**: requested (SC-001 `PASS 6/6`).

**Dispatch**: T001–T005 are one TZ unit for `sdk-agent code` (three new files, one writer); T006–T010 are the lead's acceptance runs.

## Phase 1: Setup

- [ ] T001 [P] Create `config/repo-visibility.json`: `org` = `"arwoxbx24"`, `included_minutes` = `2000`, `public` = `["tools","arwox-v3-src"]`, `never_public` = `["agent-contour","stroyremont","eurosteklo","sanatory-avto","okna-plus","clients-okna-plus","asense-store","agramak","Savinsname","agida-bream-tech","mikhail-travel","planeta-autostekla","techsplav"]` (data-model.md: "never_public … wins over public")

## Phase 2: Foundational

- [ ] T002 Create `bin/repo-visibility` skeleton: bash `set -euo pipefail`, config path `<bin dir>/../config/repo-visibility.json`, `--help`/`-h` → `usage: repo-visibility publish <repo> | report` on stdout rc 0 before any external call; no args / unknown → usage on stderr rc 2; `SECRET_GATE` default `<bin dir>/secret-gate`, `GITLEAKS` default `/root/.local/bin/gitleaks` (contracts/cli.md)

## Phase 3: User Story 1 - Publish by owner word (P1) 🎯 MVP

**Goal**: an approved, clean repo becomes PUBLIC; everything else is refused.
**Independent Test**: `bash bin/repo-visibility-test` cases 1–5.

- [ ] T003 [P] [US1] Write cases 1–5 in `bin/repo-visibility-test` (stub `gh`, `SECRET_GATE`, `GITLEAKS` in a `mktemp -d` dir; real config): never_public refusal (`eurosteklo`), not allowlisted (`arwox-biz`), findings > 0 → refused and no `repo edit` call, clean → `secrets: 0` + `arwox-v3-src: PUBLIC` + one `repo edit` call + the clone directory the stub received no longer exists (FR-004), already PUBLIC (`tools`) → no clone/scan/edit
- [ ] T004 [US1] Implement `publish` in `bin/repo-visibility` per contracts/cli.md rows: order never_public → allowlist → `gh repo view` PUBLIC short-cut → `gh repo clone <org>/<repo> <tmp>/mirror -- --mirror` → secret-gate (count `secret-gate: BLOCKED` stderr lines; rc 0/1 ok, else scan failed) + gitleaks (`git --no-banner --redact --log-opts=--all --report-format json --report-path <tmp>/gl.json <tmp>/mirror`; rc 0/1 ok, `jq length` of report, else scan failed) → `secrets: N` → N = 0: `gh repo edit <org>/<repo> --visibility public --accept-visibility-change-consequences` → read back → `<repo>: PUBLIC` or `failed: <repo> is <VIS>`; `trap` removes `<tmp>`; finding contents never printed

## Phase 4: User Story 2 - Minutes report (P2)

**Goal**: per-repo minutes with private and all-repos totals.
**Independent Test**: `bash bin/repo-visibility-test` case 6.

- [ ] T005 [US2] Implement `report` in `bin/repo-visibility` (`gh api "/organizations/<org>/settings/billing/usage?year=$(date +%Y)&month=$(date +%-m)"` raw JSON + `gh repo list <org> --limit 1000 --json name,visibility` raw JSON, processed by `jq`: sum `quantity` where `product=="actions" and unitType=="Minutes"` per `repositoryName`, `round`; lines `<repo> <VIS|UNKNOWN> <min>` sorted by name; `private total: <P>/<I>`; `all repos total: <A>/<I>`) and case 6 in `bin/repo-visibility-test` (fixture: agent-contour 501 PRIVATE, eurosteklo 10 PRIVATE, tools 1587 PUBLIC, arwox-v3-src 25 PUBLIC → `private total: 511/2000`, `all repos total: 2123/2000`); test ends with `PASS 6/6` or `FAIL <ok>/6` and rc 1

## Phase 5: Polish & acceptance (lead)

- [ ] T006 `bash bin/repo-visibility-test` → `PASS 6/6`; `python3 -m unittest tests.test_agent_tools.ToolHelpContractTest` → OK
- [ ] T007 Real `publish arwox-biz` → refused, view `PRIVATE` (SC-002)
- [ ] T008 Real `publish eurosteklo` → refused, view `PRIVATE` (SC-002)
- [ ] T009 Real `publish arwox-v3-src` → `secrets: 0`, `arwox-v3-src: PUBLIC`, view `PUBLIC` (SC-003)
- [ ] T010 Real `report` → `agent-contour PRIVATE 501`, `private total: 511/2000` (SC-004)

## Dependencies

T001, T002 → T003–T005 → T006 → T007–T010 (T009 is irreversible, runs after T006 passes).

## Parallel Example

T001 and T003 touch different files ([P]); dispatched as one TZ because the test depends on the command contract and one run is cheaper.

## Implementation Strategy

MVP = US1 (T001–T004); US2 adds `report`. Stop after T010.
