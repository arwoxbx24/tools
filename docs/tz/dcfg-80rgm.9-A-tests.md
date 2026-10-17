# TZ dcfg-80rgm.9 A — tests: v9d fixture fix, v9b, v9e (spec 099 §v9 ADR-40, FR-041, FR-044, FR-045)

FILE: bin/ship-post-test

Executor: sdk-agent code. Edit only the v9 block (functions `v9_ship`, `test_v9`, lines ~897-934). Change no line outside it. Exact edits below, nothing else.

Root cause of red v9d (evidence 17.10): the shared fake `gh` (`bin/ship-post-test:52-53`) returns every merged SHA for any `--head` branch. After dcfg-v9d.1 merges, `remote_result` for dcfg-v9d.2 sees a foreign merged PR → code 24 → unpark, ship never called. Real `gh pr list --head <branch>` filters by branch. Fix the v9 fixture, not the shared fake.

1. In `v9_ship`, in the `MOCK_SHIP_OK` branch, replace `>> "$SHIP_POST_TEST_DIR/merged"` with `>> "$SHIP_POST_TEST_DIR/merged.$(git -C "$1" rev-parse --abbrev-ref HEAD | tr / _)"`.
2. Right after the closing `}` of `v9_ship`, add a helper:
```
v9_gh(){ # v9: gh mock filters merged PRs by --head branch, as real gh does
	cat > "$d/bin/gh" <<'V9GH'
#!/usr/bin/env bash
if [[ $1 == repo ]]; then echo '{"isPrivate":true}'; exit; fi
b=''; while (($#)); do [[ $1 == --head ]] && b=$2; shift; done
f="$SHIP_POST_TEST_DIR/merged.${b//\//_}"
if [[ -n $b && -s $f ]]; then jq -Rs '[split("\n")[] | select(length>0) | {headRefOid:.,state:"MERGED",url:"https://github.com/test/private/pull/1",mergeCommit:{oid:"merged-test"},statusCheckRollup:[]}]' "$f"; else echo '[]'; fi
V9GH
	chmod +x "$d/bin/gh"
}
```
3. In the `# v9d` block, change `echo open > "$d/status.test-infra"; v9_ship` to `echo open > "$d/status.test-infra"; v9_ship; v9_gh`.
4. At the end of `test_v9`, before its closing `}`, append verbatim (blank line first) the content of `docs/tz/dcfg-80rgm.9-tests.txt` (blocks `# v9b`, `# v9e`, `v9e_control`). Do not change its lines.

Prohibitions: only this file; no network; no secrets; do not touch `state/`, `.beads`, `~/.ssh`, `/etc`; do not delete, skip or weaken any assertion.
