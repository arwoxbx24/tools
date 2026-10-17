# TZ dcfg-gvjs1 — status line: delivery courier summary, last 24h (owner 17.10)

FILE: hooks/statusline-command.sh

Executor: sdk-agent code. Read only `hooks/statusline-command.sh` (lines 83-132). Minimal diff; existing segments, `bar`, `paint`, `join` unchanged. KISS, YAGNI. Insert the new block after line 100 (end of line 2 segments), before `# line 3`.

## U1
Goal: line 2 ends with `ship 24h ✓D ⏳P ✗X (last ✓ HH:MM)`; the status line itself never waits for the courier.

1. Paths: `sp=/root/workspaces/tools/bin/ship-post`, `st=/root/workspaces/tools/state/ship-post`, `cache=/tmp/statusline-ship.txt`.
2. Function `ship_refresh` (prints one line `D P X LAST`, LAST = epoch seconds of newest delivered receipt or 0):
   - atoms: `find "$st/submissions" -type f -mmin -1440 -printf '%h\n' 2>/dev/null | sed 's#.*/##' | sort -u`
   - for each atom: third word of `"$sp" --status "$atom"`: `delivered` → D+1; `parked` or `failed` → X+1; anything else (`submitted`, `delivering`) → P+1.
   - LAST: `find "$st/receipts" -type f -regextype posix-extended -regex '.*/[0-9a-f]{40}' -printf '%T@\n' 2>/dev/null | sort -n | tail -n1`, integer part; empty → 0.
3. Refresh in background when `$cache` is missing or older than 60 s (`find "$cache" -mmin -1` prints nothing): run `ship_refresh` in a subshell that holds `flock -n` on `/tmp/statusline-ship.lock` (exit if busy), writes to `$cache.tmp` then `mv` onto `$cache`; the subshell gets `</dev/null >/dev/null 2>&1 &` so the status line does not wait for it (Claude Code waits for stdout to close). One comment line: `# background: ~40 atoms x 35 ms would block the status line`.
4. If `$cache` is readable and has 4 whole numbers: segment `ship 24h ✓D ⏳P ✗X`, add ` (last ✓ $(date -d "@LAST" +%H:%M))` when LAST > 0. Color the whole counts part with existing escape codes: red `\033[31m` if X > 0, else yellow `\033[33m` if P > 0, else green `\033[32m`; reset `\033[0m` after. Append to `seg2`. Cache missing → no segment.
5. Only when `[[ -x $sp && -d $st ]]`; otherwise skip silently.

## U2 (v2 17.10: U1 step 1 was not applied, `sp`/`st`/`cache` are undefined, so the block never runs)
Insert exactly these three lines directly above the line `ship_refresh() {` and change nothing else:
```
sp=/root/workspaces/tools/bin/ship-post
st=/root/workspaces/tools/state/ship-post
cache=/tmp/statusline-ship.txt
```

## Acceptance (Claude runs after the edit)
1) live state: first run starts refresh; second run shows `ship 24h ✓`; D+P+X equals the count of unique atoms from step 2
2) `time` of a run with an expired cache < 0.2 s
3) `{}` → rc 0, no `?`/`null`; `bash -n` → rc 0

Prohibitions: only the file above; ship-post and its state are read-only (only `--status`); no network; no secrets.
