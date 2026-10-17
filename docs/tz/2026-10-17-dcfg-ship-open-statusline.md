# TZ dcfg-03laj v2 — courier segment: live delivery state, every second (owner 17.10)

FILE: hooks/statusline-command.sh

Executor: sdk-agent code. Read only `hooks/statusline-command.sh` lines 100-140. One block replacement, nothing else.

v2 reason: owner wants to watch a delivery live (status line will re-run every second via `refreshInterval: 1`) and a small green check after success; the 24h count is not useful. v1 also hid parked deliveries older than 24h. A per-second run cannot call ship-post per atom (35 ms each), so only file tests are used.

## U1
Replace lines 102-138 (from `sp=/root/workspaces/tools/bin/ship-post` through the `fi` that closes `if [[ -x $sp && -d $st ]]; then`) with exactly:

```
# courier live state: file tests only (runs every second); mirrors ship-post do_status: receipt = delivered, parked file or .failed = stuck, else in flight
# shortcut: only submissions of the last 15 min count as in flight; slower deliveries are normally parked by the courier
st=/root/workspaces/tools/state/ship-post
if [[ -d $st ]]; then
  busy=() recent=0
  while IFS=/ read -r atom sha; do
    if compgen -G "$st/receipts/*/$atom/$sha" >/dev/null; then
      [[ -n $(find "$st"/receipts/*/"$atom"/"$sha" -mmin -10 2>/dev/null) ]] && recent=1
    elif [[ ! -e $st/incidents/parked/$atom ]] && ! compgen -G "$st/receipts/*/$atom/$sha.failed" >/dev/null; then
      busy+=("$atom")
    fi
  done < <(find "$st/submissions" -type f -mmin -15 -printf '%h/%f\n' 2>/dev/null | awk -F/ '{print $(NF-1) "/" $NF}' | sort -u)
  stuck=$(find "$st/incidents/parked" -type f 2>/dev/null | wc -l)
  ship=""
  if (( ${#busy[@]} > 0 )); then
    ship=$'\033[33m'"⏳ ${busy[0]}"$'\033[0m'
    (( ${#busy[@]} > 1 )) && ship+=" +$(( ${#busy[@]} - 1 ))"
  elif (( recent )); then
    ship=$'\033[32m✓\033[0m'
  fi
  (( stuck > 0 )) && ship+="${ship:+ }"$'\033[31m'"✗$stuck"$'\033[0m'
  [[ -n $ship ]] && seg2+=("ship $ship")
fi
```

## Acceptance (Claude runs after the edit)
1) live: stuck count equals `find .../incidents/parked -type f | wc -l` (5 now); a delivery submitted < 15 min ago without receipt shows `⏳ <atom>`; delivered < 10 min ago and none in flight shows `✓`
2) one run (`time`) < 0.15 s; `{}` rc 0, no `?`/`null`; `bash -n` rc 0

Prohibitions: only the file above; ship-post state read-only; no network; no secrets.
