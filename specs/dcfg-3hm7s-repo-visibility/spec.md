# Feature Specification: repo-visibility — publish a repo only by owner word, with a lock

**Feature Branch**: `claude/dcfg-3hm7s-repo-visibility`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "tools/bin/repo-visibility: open a repo of org arwoxbx24 to public only by owner word — allowlist + never_public list in config/repo-visibility.json, full-history secret scan on a mirror clone must be 0, then the visibility change; report of this month's Actions minutes per repo with private total and all repos total vs 2000 included."

## Паспорт ТЗ *(mandatory, csb 01.10)*

**Контур**: `[CLAUDE-config-f94f]` · **Атом цели**: `dcfg-3hm7s` · **Spec**: `specs/dcfg-3hm7s-repo-visibility` (tools repo)

### §0 Инициализация — аудит среды
- Worktree `/root/workspaces/tools/.worktrees/claude/dcfg-3hm7s`, branch `claude/dcfg-3hm7s-repo-visibility` from `origin/main` 35975e3 (`git worktree add` output, 20.10).
- Tools: `gh` `/usr/bin/gh`, `jq-1.7`, `gitleaks` `/root/.local/bin/gitleaks` (`gitleaks git --help`: `--log-opts`, `--redact`, `--report-format`, `--report-path`, `--exit-code` default 1), `secret-gate` `/root/workspaces/tools/bin/secret-gate` (not on PATH; `scan <repo>`: rc 0 clean, rc 1 with `secret-gate: BLOCKED …` lines on stderr, rc 2 error — `bin/secret-gate:180-182`, `:12`).
- `gh` is signed in as a member of org `arwoxbx24`; personal account is out of scope (owner 20.10).
- Owner physical steps: none.

### §1 Бизнес
Owner 20.10: «Как нам эти динамические процессы… перевести из точечного разрешения в публичное по моему требованию?»; client projects (`projects/clients/*`), `stroyremont`, `agent-contour` stay private; `arwox-v3-src` may be public. Paid plans are impossible (trade restriction, owner 20.10), so free Actions minutes come only from public repos (docs.github.com/en/billing/concepts/product-billing/github-actions: "GitHub Actions usage is free for self-hosted runners and for public repositories that use standard GitHub-hosted runners.").
Value: one safe command opens an approved repo; one command shows where the 2000 included private minutes go.

### §2 Аналитика
- Billing source: `GET /organizations/arwoxbx24/settings/billing/usage?year=<Y>&month=<M>` → `usageItems[]` with `product`, `unitType`, `quantity`, `repositoryName` (measured 20.10: agent-contour 501, arwox-v3-src 25, eurosteklo 10, tools 1587 minutes).
- Visibility source: `gh repo list arwoxbx24 --json name,visibility` (65 repos, 58 PRIVATE, 20.10).

### §3 Архитектура
- ADR-1: a bash command in `tools/bin` + a JSON config; no service, no cron, no daemon (owner: «чтобы мы не вешали какие-то PM-сервисы»).
- ADR-2: deny by default — only names in `public` may be opened; `never_public` is checked first and wins.
- ADR-3: secret scan = house `secret-gate scan` (our real secret values) + `gitleaks git` (generic patterns), both over all refs of a mirror clone; the count of findings is printed, the findings never.
- ADR-4: an already PUBLIC repo is reported without a scan or change (idempotent).

### §4 Код
New files only: `bin/repo-visibility`, `config/repo-visibility.json`, `bin/repo-visibility-test`.

### §5 DevOps
No process, no deploy. Rollback of a publication: `gh repo edit arwoxbx24/<repo> --visibility private --accept-visibility-change-consequences` (stars/watchers lost — GitHub docs warning; data already seen while public cannot be recalled, hence the scan before).

### §6 Исполнители и модели
Lead Opus — spec, TZ, acceptance; code — `sdk-agent code` (active channel `sdk`).

### §7 Цель и приёмка
See Success Criteria; negative cases: a repo not in the allowlist and a `never_public` repo are refused and stay PRIVATE.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Publish an approved repo by owner word (Priority: P1)

The owner names a repo to open; the agent runs one command; the repo becomes public only if it is approved and has no secrets in its whole history.

**Why this priority**: it is the only free source of Actions minutes for our own code.

**Independent Test**: run publish on a not-approved repo, a never-public repo and an approved repo; check visibility after each.

**Acceptance Scenarios**:

1. **Given** `arwox-biz` is not in `public`, **When** `publish arwox-biz`, **Then** `refused: arwox-biz not in public allowlist`, rc 1, repo stays PRIVATE.
2. **Given** `eurosteklo` is in `never_public`, **When** `publish eurosteklo`, **Then** `refused: eurosteklo is never_public`, rc 1, repo stays PRIVATE.
3. **Given** `arwox-v3-src` is in `public` and its history has 0 findings, **When** `publish arwox-v3-src`, **Then** lines `secrets: 0` and `arwox-v3-src: PUBLIC`, rc 0, GitHub shows PUBLIC.
4. **Given** an approved repo with ≥1 finding, **When** publish, **Then** `secrets: <N>` and `refused: <repo> has secrets in history`, rc 1, no visibility change.
5. **Given** an approved repo already PUBLIC, **When** publish, **Then** `<repo>: PUBLIC`, rc 0, no scan, no change.

### User Story 2 - See where the private minutes go (Priority: P2)

**Why this priority**: the owner decides what to open next from these numbers.

**Independent Test**: run report; compare with the billing API.

**Acceptance Scenarios**:

1. **Given** this month's billing usage, **When** `report`, **Then** one line `<repo> <VISIBILITY> <minutes>` per repo with minutes, then `private total: <sum of PRIVATE>/2000`, then `all repos total: <sum of all>/2000`.

### Edge Cases

- A name in both `public` and `never_public` → never_public refusal.
- Scanner error (rc other than 0/1, missing report) → `refused: <repo> scan failed`, rc 1, no change.
- Visibility after the change is not PUBLIC → `failed: <repo> is <VISIBILITY>`, rc 1.
- A billed repo absent from the repo list (deleted) → visibility `UNKNOWN`, not in the private total.
- No arguments / unknown command → usage on stderr, rc 2; `--help` → usage on stdout, rc 0, no external call.
- The mirror clone is removed on every exit path.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `publish <repo>` MUST refuse names in `never_public` (checked first) and names absent from `public`, with rc 1 and no external change.
- **FR-002**: Before any change `publish` MUST scan all refs of a fresh mirror clone with `secret-gate scan` and `gitleaks git`, print `secrets: <N>` (sum of findings) and change visibility only when N = 0 and both scanners succeeded.
- **FR-003**: After the change `publish` MUST read the visibility back and print `<repo>: PUBLIC` only when GitHub reports PUBLIC.
- **FR-004**: `publish` MUST NOT print finding contents, and MUST delete its temporary directory on every exit.
- **FR-005**: `report` MUST print per-repo Actions minutes of the current month with visibility, the private total and the all-repos total against `included_minutes` from the config.
- **FR-006**: `--help`/`-h` MUST print `usage:` on stdout with rc 0 and call nothing (tools help contract, `tests/test_agent_tools.py:113-178`).
- **FR-007**: The org, the included minutes and both lists MUST come from `config/repo-visibility.json`.

### Key Entities

- **Config**: `org`, `included_minutes`, `public[]`, `never_public[]`.
- **Usage line**: repo, visibility, minutes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: the test script prints `PASS 6/6` (6 cases: never_public, not allowlisted, findings > 0, clean publish, already public, report).
- **SC-002**: real runs on `arwox-biz` and `eurosteklo` are refused and both stay PRIVATE.
- **SC-003**: a real run on `arwox-v3-src` prints `secrets: 0`, `arwox-v3-src: PUBLIC`, and GitHub shows PUBLIC.
- **SC-004**: a real `report` prints `agent-contour PRIVATE 501` and `private total: 511/2000` (usage as measured 20.10).

## Assumptions

- `never_public` = `agent-contour`, `stroyremont`, every org repo of a `projects/clients/*` client (`eurosteklo`, `sanatory-avto`, `okna-plus`, `clients-okna-plus`, `asense-store`, `agramak`) and the other client names (`Savinsname`, `agida-bream-tech`, `mikhail-travel`, `planeta-autostekla`, `techsplav`) in case such repos appear.
- `public` = `tools`, `arwox-v3-src` (owner 20.10); adding a name later is the owner word.
- The monthly quota is already 2000/2000 used until the reset (~01.11); `private total` is the forecast for the next month, `all repos total` shows the month as billed.
- A new test is not added to tools CI in this atom (`.github` is outside the executor's allowed paths).
