# TZ dcfg-4j1mb v7 M3b — fix M3 diff, paste only
Reason: in M3 the new `wait-owner)` case arm is unreachable (first arm already matches `wait-owner`), and `tmp_err` is a temp file never removed.
File: `bin/ship-post`, function `scan_repo` only.

1. Delete the line `  tmp_err=$(mktemp)` and restore the two lines around it to their original single-space indent:
```
 local ok=0 failed=0 skip=0 started=0 jobs_max p
 jobs_max=${SHIP_POST_JOBS:-8}
```
2. Replace the whole `st=$(bd_cmd show "$atom" --json 2>"$tmp_err") || { ... failed=$((failed+1)); continue; }` block (7 lines) with (2-space indent like neighbours):
```
  st=$(bd_cmd show "$atom" --json) || {
   if bd_cmd show "$atom" --json 2>&1 >/dev/null | grep -q 'not found'; then
    uf=$(receipt_file "$repo" "$atom" "$head")
    [[ -e $uf ]] || { mkdir -p "$(dirname "$uf")"; jq -n --arg a "$atom" --arg s "$head" '{stage:"unknown-atom",atom:$a,sha:$s}' > "$uf"; }
    echo "skip $atom unknown-atom"; skip=$((skip+1)); continue
   fi
   failed=$((failed+1)); continue; }
```
3. In the `case $(jq -r '.stage // empty' "$rf" ...) in` block, the arms must be exactly (tab indent like the original):
```
	   wait-owner) [[ -f $rf.log ]] && grep -q 'prod:wait-owner no-ci' "$rf.log" && rm -f -- "$rf" || continue ;; # dcfg-4j1mb: old no-CI stop re-runs once
	   prod-hold|unknown-atom) continue ;;
	   'wait-owner no-ci') rm -f -- "$rf" ;; # legacy dcfg-ta2r0: ship never ran; run it once
	   *) (BEADS_ACTOR=$actor; ack_delivery "$rf" "$atom") || failed=$((failed+1)); continue ;;
```
   Remove the other `wait-owner)` arm and the empty line added by M3.
4. Run `bash -n bin/ship-post`; output rc and `git diff`.
Forbidden: other files, network.
