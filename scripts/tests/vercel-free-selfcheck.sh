#!/usr/bin/env bash
set -uo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
sentinel=$(mktemp)
trap 'rm -f -- "$sentinel"' EXIT
export sentinel
curl() { printf 'called' > "$sentinel"; return 99; }
export -f curl
"$root/bin/vercel-free" openai/gpt-5 /nonexistent-request.json >/dev/null 2>&1
rc=$?
[[ $rc != 0 && ! -s "$sentinel" ]] || { echo "FAIL paid_id_rc=$rc"; exit 1; }
printf 'PASS paid_id_rc=%s network_calls=0\n' "$rc"
