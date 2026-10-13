# TZ dcfg-4j1mb v7 M3 — paste only, no exploration
v7 reason: v5 single run too slow; split into 3 parallel micro edits.
File: `bin/ship-post` only, function `scan_repo` only. No test run.

1. Replace the line `st=$(bd_cmd show "$atom" --json) || { failed=$((failed+1)); continue; }` with:
```
		st=$(bd_cmd show "$atom" --json 2>"$tmp_err") || {
			if grep -q 'not found' "$tmp_err"; then
				uf=$(receipt_file "$repo" "$atom" "$head")
				[[ -e $uf ]] || { mkdir -p "$(dirname "$uf")"; jq -n --arg a "$atom" --arg s "$head" '{stage:"unknown-atom",atom:$a,sha:$s}' > "$uf"; }
				echo "skip $atom unknown-atom"; skip=$((skip+1)); continue
			fi
			failed=$((failed+1)); continue; }
```
   Define `tmp_err=$(mktemp)` near the top of `scan_repo` (keep indentation style: tabs). If `skip` is not an existing counter there, use the counter name the function already uses for skipped atoms.
2. In the `case` that has `wait-owner|prod-hold) continue`, make it `wait-owner|prod-hold|unknown-atom) continue`.
3. Next to the existing branch that handles `'wait-owner no-ci'` legacy receipts, add the same removal for a `wait-owner` receipt whose `"$rf.log"` contains `prod:wait-owner no-ci` (grep -q), so it re-runs once.
4. Run `bash -n bin/ship-post`. Output: rc and `git diff --stat`.
Forbidden: network, other files.
