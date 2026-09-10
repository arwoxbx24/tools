#!/bin/bash
# timeweb_dns.sh — Create DNS A record via twc CLI
# Params JSON: {"subdomain":"X","domain":"b244.ru","record_type":"A"}
set -euo pipefail
PARAMS="${1:?}"
SUBDOMAIN=$(echo "$PARAMS" | jq -r '.subdomain')
DOMAIN=$(echo "$PARAMS" | jq -r '.domain // "b244.ru"')
TYPE=$(echo "$PARAMS" | jq -r '.record_type // "A"')

# Get server IP from secrets
SERVER_IP=$(cat "/root/workspaces/secrets/services/server.env" 2>/dev/null | grep SERVER_IP | cut -d= -f2 || echo "")
[[ -z "$SERVER_IP" ]] && { echo "ERROR: SERVER_IP not found in secrets"; exit 1; }

# Check if record already exists
EXISTING=$(twc domain record list "$DOMAIN" -o json 2>/dev/null | jq -r ".[] | select(.data==\"$SERVER_IP\" and .subdomain==\"$SUBDOMAIN\") | .id" 2>/dev/null)
if [[ -n "$EXISTING" ]]; then
    echo "DNS record already exists (id: $EXISTING)"
    exit 2  # Idempotent skip
fi

# Create record
RESULT=$(twc domain record add "$DOMAIN" --type "$TYPE" --subdomain "$SUBDOMAIN" --value "$SERVER_IP" -o json 2>&1)
RECORD_ID=$(echo "$RESULT" | jq -r '.id // empty')
echo "DNS record created: ${SUBDOMAIN}.${DOMAIN} → $SERVER_IP (id: $RECORD_ID)"
