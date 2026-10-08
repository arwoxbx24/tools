#!/bin/bash
# npm_proxy_create.sh — Create NPM proxy host via REST API
# Params JSON: {"domain":"X.b244.ru","forward_host":"172.17.0.1","forward_port":"3000"}
set -euo pipefail
PARAMS="${1:?}"
DOMAIN=$(echo "$PARAMS" | jq -r '.domain')
FWD_HOST=$(echo "$PARAMS" | jq -r '.forward_host // "172.17.0.1"')
FWD_PORT=$(echo "$PARAMS" | jq -r '.forward_port')

# Load NPM credentials
source "${NPM_ENV_FILE:-/root/workspaces/secrets/system/services/npm.env}" 2>/dev/null || { echo "ERROR: npm.env not found"; exit 1; }
NPM_PASSWORD=${NPM_PASSWORD:-${NPM_PASS:-}}

# Get auth token
TOKEN=$(curl -s -X POST "http://localhost:81/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASSWORD\"}" | jq -r '.token // empty')
[[ -z "$TOKEN" ]] && { echo "ERROR: NPM auth failed"; exit 1; }

# Check if proxy host already exists
EXISTING=$(curl -s "http://localhost:81/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" | jq -r ".[] | select(.domain_names[] == \"$DOMAIN\") | .id" 2>/dev/null)
if [[ -n "$EXISTING" ]]; then
    echo "$EXISTING"
    exit 2  # Idempotent skip
fi

# Create proxy host
RESULT=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"domain_names\": [\"$DOMAIN\"],
    \"forward_scheme\": \"http\",
    \"forward_host\": \"$FWD_HOST\",
    \"forward_port\": $FWD_PORT,
    \"access_list_id\": 0,
    \"certificate_id\": 0,
    \"ssl_forced\": false,
    \"meta\": {\"letsencrypt_agree\": false},
    \"advanced_config\": \"\",
    \"locations\": [],
    \"block_exploits\": true,
    \"caching_enabled\": false,
    \"allow_websocket_upgrade\": true,
    \"http2_support\": false,
    \"hsts_enabled\": false,
    \"hsts_subdomains\": false
  }")

HOST_ID=$(echo "$RESULT" | jq -r '.id // empty')
[[ -z "$HOST_ID" ]] && { echo "ERROR: Failed to create proxy host: $RESULT"; exit 1; }
echo "$HOST_ID"
