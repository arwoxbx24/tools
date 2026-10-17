# TZ dcfg-80rgm.6 MIN code — INFRA incidents close themselves; 130 is not INFRA (owner 17.10)

FILE: bin/ship-post

Executor: sdk-agent code. Exactly the three edits below, nothing else. Do not add any other line, condition or remapping.

1. `record_failure`: change the line `case $rc in 23) return 0 ;; esac` to `case $rc in 23|130) return 0 ;; esac`. In `scan_repo`, change `case $code in 23) ;;` to `case $code in 23|130) ;;`.
2. `record_failure`: right after the `esac` that closes the code table (before `note="ship-post exit $rc: ...`), add: if `$SHIP_POST_STATE_DIR/incidents/parked/$atom` exists, remove label `delivery-blocked` with `bd_cmd update "$atom" --remove-label delivery-blocked >/dev/null || return 1` and `rm -f` that file. Declare `pf` in the function's `local` line.
3. `ack_delivery`: inside `if [[ -f $pf ]]`, after `rm -f -- "$pf"`, add: if no file in `$SHIP_POST_STATE_DIR/incidents/parked/` has a line equal to `$inc` (`grep -qxF -- "$inc" .../parked/* 2>/dev/null` fails) → `bd_home close "$inc" --reason "ship-post: all parked atoms delivered" >/dev/null || return 1` and remove every file directly in `$SHIP_POST_STATE_DIR/incidents/` whose whole content equals `$inc`.

Each `old` must be unique in the file: include the enclosing function line or 2-3 neighbouring lines (for example `rm -f -- "$pf"` occurs several times; anchor edit 3 on the line `bd_home update "$inc" --append-notes "delivered`).

Prohibitions: only this file; no network; no secrets.
