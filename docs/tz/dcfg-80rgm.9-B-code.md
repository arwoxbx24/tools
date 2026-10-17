# TZ dcfg-80rgm.9 B — code: F1b «already in main» = delivered; F3 retry after re-close (spec 099 §v9 ADR-40, FR-044, FR-045)

FILE: bin/ship-post

Executor: sdk-agent code. First run repowise on `bin/ship-post::deliver_one` and `bin/ship-post::scan_repo` (scan_repo has high nesting: minimal edit, no restructuring). Exactly the edits below, nothing else: no other line, condition, remapping or regexp change.

1. F1b `deliver_one`: in the failure path the lines are
```
  remote_result "$wt" "$head" "$branch"; rc=$?
  if [[ $rc == 0 ]]; then write_delivery_receipt "$repo" "$atom" "$head" "$head"; return $?; fi
  if [[ $rc == 23 ]]; then ship_rc=23
```
   Insert between the second and third line:
```
  # dcfg-80rgm F1b: ship failed but the SHA is already on origin/<base> (e.g. GraphQL 'No commits'): delivered, not INFRA.
  base=$(git -C "$wt" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); base=${base#origin/}; [[ -n $base ]] || base=main
  if git -C "$wt" merge-base --is-ancestor "$head" "origin/$base" 2>/dev/null; then remote_proof=${remote_proof:-null}; write_delivery_receipt "$repo" "$atom" "$head" "$head"; return $?; fi
```
   Add `base` at the end of the `local` line of `deliver_one`. No fetch.
2. F3 `scan_repo`: replace the line `    10|50|80) skip=$((skip+1)); continue ;;` with:
```
    10|50|80) # dcfg-80rgm F3: the atom was closed again after the marker -> deliver again
     ce=$(date -d "$(jq -r '.[0].closed_at // empty' <<<"$st")" +%s 2>/dev/null) || ce=0
     (( ce > $(stat -c %Y "$rf.failed") )) || { skip=$((skip+1)); continue; }
     mv -f -- "$rf.failed" "$rf.failed.resubmitted"; rm -f -- "$rf.failed.reported" ;;
```
   Add `ce` to the `local` line of `scan_repo` if a `local` line exists there.
3. `ack_delivery`: change `local rf=$1 atom=$2 marker st pf inc` to `local rf=$1 atom=$2 marker st pf inc f`.

Each `old` must be unique: anchor on 2-3 neighbouring lines.

Prohibitions: only this file; no network; no secrets; do not touch `state/`, `.beads`, `~/.ssh`, `/etc`.
