# dcfg-xs248
## U1
Owner R021: watchdog error evidence (time/code/time_total/first200 body bytes), separate slow warning >10s. Existing flow; no historical research.
Acceptance: bash scripts/tests/forms-evidence-selfcheck.sh => PASS evidence_lines=1 slow_code=302 network_calls=0. Total diff <=30; ship-post.
Scope watchdog + selfcheck + TZ. Rollback revert additions; no production request or restart in test.
