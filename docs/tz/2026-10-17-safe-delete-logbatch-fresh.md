# TZ dcfg-kyvur — safe-delete log_batch on a fresh backup dir

Atom: dcfg-kyvur. Method: systematic debugging / 5 Whys (root cause confirmed below). Skills: superpowers:systematic-debugging, caveman:surgical-patch.
Recon: repowise / grep -n (done by architect; facts below are exact).

FILE: bin/safe-delete
FILE: bin/safe-delete-test

## Root cause (fact)
Reproduction: `safe-delete --bk <fresh dir> cache <dir>/node_modules` → rc 1, `line 18: <bk>/ledger.tsv: No such file or directory`; dir already removed, no ledger line.
`bin/safe-delete:18` `log_batch` runs `n=$(wc -l <"$led")` before anything has created `$led`; the input redirect fails when the file is missing. `log` (line 17) appends first, so only `log_batch` is affected. Callers: lines 137, 161, 166, 197, 263 — fix once in `log_batch`.

## U1 — edits
1. `bin/safe-delete` line 18, inside the flock block, before `n=$(wc -l <"$led")`: insert `: >>"$led" || return 1;` (creates an empty ledger if missing, no-op otherwise). Change nothing else in the file.
2. `bin/safe-delete-test`: after T86 (before the line `[[ $ok == 87 ]] || exit 1`) add test T87 in the same style as T86:
   - `mkdir -p "$d/p87/node_modules"`; `printf 'x\n' > "$d/p87/node_modules/f"`
   - run `"$bin/safe-delete" --bk "$d/bk87" cache "$d/p87/node_modules"` with output to /dev/null, rc into `r87` (`$d/bk87` does not exist before the call)
   - `n87=$(grep -c . "$d/bk87/ledger.tsv" 2>/dev/null)`
   - PASS when `r87 == 0`, `! -e "$d/p87/node_modules"`, `n87 == 1`: `echo 'PASS T87 fresh_ledger_batch'; ok=$((ok+1))`; else `echo "FAIL T87: rc=$r87 n=$n87"`.
   - change `[[ $ok == 87 ]]` to `[[ $ok == 88 ]]`.

## Acceptance
1) same command on a fresh bk dir → rc 0 and ledger has 1 line. 2) `bin/safe-delete-test` → `итог: PASS 88, FAIL 0`.

## Bans
No other edits, no new files, no rm -rf outside test temp dirs, no secrets/.env, no ~/.ssh, no /etc, no git push.
