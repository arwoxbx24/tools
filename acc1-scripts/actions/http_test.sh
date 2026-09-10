#!/bin/bash
# http_test.sh — HTTP connectivity test with retries
# Params JSON: {"url":"https://X.b244.ru","expected_status":"200,301,302","retries":"3","delay":"10"}
set -euo pipefail
PARAMS="${1:?}"
URL=$(echo "$PARAMS" | jq -r '.url')
EXPECTED=$(echo "$PARAMS" | jq -r '.expected_status // "200,301,302"')
RETRIES=$(echo "$PARAMS" | jq -r '.retries // "3"')
DELAY=$(echo "$PARAMS" | jq -r '.delay // "10"')

for i in $(seq 1 "$RETRIES"); do
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" 2>/dev/null || echo "000")
    if echo "$EXPECTED" | grep -qw "$STATUS"; then
        echo "HTTP $STATUS OK: $URL"
        exit 0
    fi
    echo "Attempt $i/$RETRIES: HTTP $STATUS (expected: $EXPECTED)" >&2
    [[ $i -lt $RETRIES ]] && sleep "$DELAY"
done
echo "FAILED: $URL returned $STATUS after $RETRIES attempts"
exit 1
