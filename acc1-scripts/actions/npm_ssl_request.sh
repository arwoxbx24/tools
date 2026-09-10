#!/bin/bash
# npm_ssl_request.sh — Request Let's Encrypt SSL via NPM API
# Params JSON: {"proxy_host_id":"123"}
set -euo pipefail
PARAMS="${1:?}"
HOST_ID=$(echo "$PARAMS" | jq -r '.proxy_host_id')
[[ -z "$HOST_ID" || "$HOST_ID" == "null" ]] && { echo "ERROR: proxy_host_id required"; exit 1; }

source "/root/workspaces/secrets/services/npm.env" 2>/dev/null || exit 1
TOKEN=$(curl -s -X POST "http://localhost:81/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASSWORD\"}" | jq -r '.token')

# Get current host to check domain
HOST_DATA=$(curl -s "http://localhost:81/api/nginx/proxy-hosts/$HOST_ID" -H "Authorization: Bearer $TOKEN")
DOMAIN=$(echo "$HOST_DATA" | jq -r '.domain_names[0]')
NPM_EMAIL_LE="${NPM_EMAIL}"

# Request Let's Encrypt cert
CERT_RESULT=$(curl -s -X POST "http://localhost:81/api/nginx/certificates" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"domain_names\": [\"$DOMAIN\"],
    \"meta\": {\"letsencrypt_email\": \"$NPM_EMAIL_LE\", \"letsencrypt_agree\": true, \"dns_challenge\": false},
    \"provider\": \"letsencrypt\"
  }")

CERT_ID=$(echo "$CERT_RESULT" | jq -r '.id // empty')
[[ -z "$CERT_ID" ]] && { echo "ERROR: SSL cert request failed: $CERT_RESULT"; exit 1; }

# Attach cert to proxy host + enable SSL
curl -s -X PUT "http://localhost:81/api/nginx/proxy-hosts/$HOST_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"certificate_id\": $CERT_ID, \"ssl_forced\": true, \"http2_support\": true}" > /dev/null

echo "SSL cert $CERT_ID attached to host $HOST_ID ($DOMAIN)"
