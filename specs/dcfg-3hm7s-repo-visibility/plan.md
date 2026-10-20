# Implementation Plan: repo-visibility

**Branch**: `claude/dcfg-3hm7s-repo-visibility` | **Date**: 2026-10-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/dcfg-3hm7s-repo-visibility/spec.md`

**Note**: the tools repo has no `.specify/scripts`; the feature dir is set in `.specify/feature.json`, templates come from `projects/.specify/templates`.

## Summary

One bash command `bin/repo-visibility` with two subcommands: `publish <repo>` (deny-by-default lock + full-history secret scan of a mirror clone + visibility change + read-back) and `report` (this month's Actions minutes per repo with private and all-repos totals). Lists and limits live in `config/repo-visibility.json`. A bash test with stubbed `gh`, `gitleaks` and `secret-gate` proves 6 cases.

## Technical Context

**Language/Version**: bash 5 (`set -euo pipefail`), like the other `tools/bin` commands

**Primary Dependencies**: `gh` (repo view/clone/edit/list, api read), `jq` 1.7, `gitleaks` (`/root/.local/bin`), `bin/secret-gate`

**Storage**: `config/repo-visibility.json`; temporary mirror clone under `mktemp -d`, removed by `trap`

**Testing**: `bin/repo-visibility-test` (bash, stubs on PATH, `PASS n/n` like `bin/place-files-test`); `tests/test_agent_tools.py` help contract

**Target Platform**: this Linux server, agent shell

**Project Type**: cli

**Performance Goals**: `report` and refusals < 10 s; publish dominated by clone + scan of one repo

**Constraints**: no service, no cron (owner 20.10); no finding content in output; no write API calls except `gh repo edit` in `publish`; only org `arwoxbx24`

**Scale/Scope**: 65 org repos; one repo per publish call

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- I «Только готовые решения» (constitution.md:102 «скрипты-обёртки … ЗАПРЕЩЕНЫ»): VIOLATION, justified in Complexity Tracking — GitHub's own visibility switch and the house scanners are reused, the new file is glue only.
- II «Код пишут только внешние каналы»: code by `sdk-agent code`; the lead writes spec/plan/tasks/TZ only — PASS.
- III Docs-first и детерминизм: flags from `gh repo edit --help` and `gitleaks git --help` (this session); behavior is deterministic per inputs — PASS.
- IV Тестирование обязательно: `bin/repo-visibility-test` 6 cases + real runs of SC-002…SC-004 — PASS.
- V Фиксация: bd atom `dcfg-3hm7s`, this spec, git commit/PR — PASS.

Post-design re-check: no new violations.

## Project Structure

### Documentation (this feature)

```text
specs/dcfg-3hm7s-repo-visibility/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/cli.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
bin/repo-visibility        # command
bin/repo-visibility-test   # stubbed test, PASS 6/6
config/repo-visibility.json
```

**Structure Decision**: existing tools layout (`bin/`, `config/`); no new directories.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| New wrapper `bin/repo-visibility` vs constitution I | Owner's approved /goal 20.10 names `bin/repo-visibility` (owner order ranks above project files); `/root/CLAUDE.md` «Инструменты агентов (скрипты, хуки, найденные CLI) — только `/root/workspaces/tools/`» makes tools/bin the sanctioned place; R12 Level 3 glue | Level 1: `gh repo edit` has no allowlist and no scan (`gh repo edit --help`); Level 2: no documented plugin locks visibility by list + full-history scan; a bare manual `gh repo edit` by any agent is the risk this lock removes |
