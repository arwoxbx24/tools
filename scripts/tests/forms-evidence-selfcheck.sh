#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd); eval "$(sed -n '/^check_form()/,/^}/p' "$root/scripts/schedulers/forms-gw-guard.sh")"
BODY_FILE=$(mktemp); trap 'rm -f -- "$BODY_FILE"' EXIT; GUARD_FORMS_URL=https://example.invalid/
log(){ printf '%s %s\n' "$1" "${2:-}"; }; notify(){ printf 'notify %s\n' "$*"; }; curl(){ printf 'gateway unavailable' >"$BODY_FILE"; printf '%s' "$sample"; }
sample='503 0 0.2'; out=$(check_form); [[ $(grep -c '^evidence code=503 time_total=0.2 body=gateway unavailable$' <<<"$out") == 1 ]]
sample='302 0 11.1'; out=$(check_form); [[ "$out" == *'медленно code=302 time_total=11.1'* && "$out" == *'notify form_slow'* && "$out" != *'code=000'* ]]
echo 'PASS evidence_lines=1 slow_code=302 network_calls=0'
