#!/bin/bash
# validate-mcp-google.sh — MCP Google Docs Prerequisites Validator
# Checks ALL required APIs, credentials, and scopes before MCP can work
# Usage: validate-mcp-google.sh [--force] [--quiet] [--help]
set +e

MCP_DIR="/root/workspaces/tools/acc1-scripts/mcp-servers/mcp-googledocs-server"
CRED_FILE="$MCP_DIR/credentials.json"
TOK_FILE="$MCP_DIR/token.json"
CACHE_FILE="/root/workspaces/tools/acc1-scripts/data/mcp-google-validated.txt"
MCP_CONFIG="/root/workspaces/tools/acc1-scripts/.mcp.json"
CACHE_TTL=86400

FORCE=0
QUIET=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --help)
      echo "Usage: validate-mcp-google.sh [--force] [--quiet] [--help]"
      echo ""
      echo "Options:"
      echo "  --force   Skip cache, always recheck"
      echo "  --quiet   No output, only exit code"
      echo "  --help    Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

trap 'rm -f /tmp/mcp-*-check.json' EXIT

if [ $FORCE -eq 0 ] && [ -f "$CACHE_FILE" ]; then
  CACHED_TS=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$((NOW - CACHED_TS))
  if [ $AGE -lt $CACHE_TTL ]; then
    HOURS=$((AGE / 3600))
    [ $QUIET -eq 0 ] && echo "MCP Google: Validated ${HOURS}h ago (use --force to recheck)" >&2
    exit 0
  fi
fi

PASSED=0
FAILED=0

function pass() {
  local MSG="$1"
  [ $QUIET -eq 0 ] && echo "✅ $MSG" >&2
  ((PASSED++))
}

function fail() {
  local MSG="$1"
  [ $QUIET -eq 0 ] && echo "❌ $MSG" >&2
  ((FAILED++))
}

function check_api_disabled() {
  local RESP_FILE="$1"
  local API_NAME="$2"
  local API_DOMAIN="$3"

  if grep -q "has not been used in project" "$RESP_FILE" 2>/dev/null; then
    PROJECT=$(grep -oP 'project \K[0-9]+' "$RESP_FILE" 2>/dev/null || echo "UNKNOWN")
    echo "   -> Enable: https://console.developers.google.com/apis/api/${API_DOMAIN}/overview?project=${PROJECT}" >&2
    fail "$API_NAME API: NOT ENABLED in project $PROJECT"
  else
    fail "$API_NAME API: HTTP $HTTP_CODE"
  fi
}

[ $QUIET -eq 0 ] && cat >&2 <<EOF
MCP GOOGLE DOCS — Validation
================================
EOF

# Check 1: credentials.json exists
if [ ! -f "$CRED_FILE" ]; then
  fail "1. credentials.json: NOT FOUND at $CRED_FILE"
else
  if jq -e '.web.client_id // .installed.client_id' "$CRED_FILE" > /dev/null 2>&1; then
    pass "1. credentials.json: Found (client_id present)"
  else
    fail "1. credentials.json: Invalid format (no client_id)"
  fi
fi

# Check 2: token.json exists  
if [ ! -f "$TOK_FILE" ]; then
  fail "2. token.json: NOT FOUND at $TOK_FILE"
else
  if jq -e '.refresh_token' "$TOK_FILE" > /dev/null 2>&1; then
    pass "2. token.json: Found (refresh_token present)"
  else
    fail "2. token.json: Invalid format (no refresh_token)"
  fi
fi

if [ $FAILED -gt 0 ]; then
  [ $QUIET -eq 0 ] && cat >&2 <<EOF
================================
Result: $PASSED/2 passed (remaining checks skipped)
EOF
  exit 1
fi

# Check 3: Token exchange
CLIENT_ID=$(jq -r '.client_id' "$TOK_FILE" 2>/dev/null)
CLIENT_SEC=$(jq -r '.client_secret' "$TOK_FILE" 2>/dev/null)
REF_TOK=$(jq -r '.refresh_token' "$TOK_FILE" 2>/dev/null)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SEC" ] || [ -z "$REF_TOK" ]; then
  fail "3. Token exchange: Missing credentials in token.json"
else
  METHOD="POST"
  URL="https://oauth2.googleapis.com/token"
  RESPONSE=$(curl -s --max-time 10 -X $METHOD "$URL" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SEC" \
    -d "refresh_token=$REF_TOK" \
    -d "grant_type=refresh_token" 2>/dev/null)

  ACC_TOK=$(echo "$RESPONSE" | jq -r '.access_token // empty' 2>/dev/null)
  if [ -z "$ACC_TOK" ]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error_description // .error // "unknown"' 2>/dev/null)
    fail "3. Token exchange: FAILED ($ERROR)"
  else
    pass "3. Token exchange: Success"
  fi
fi

if [ -z "$ACC_TOK" ]; then
  [ $QUIET -eq 0 ] && cat >&2 <<EOF
================================
Result: $PASSED/3 passed (remaining checks skipped)
EOF
  exit 1
fi

# Check 4: Token scopes
TOK_INFO=$(curl -s --max-time 10 "https://oauth2.googleapis.com/tokeninfo?access_token=$ACC_TOK" 2>/dev/null)
SCOPES=$(echo "$TOK_INFO" | jq -r '.scope // empty' 2>/dev/null)

if [ -z "$SCOPES" ]; then
  fail "4. Token scopes: Could not retrieve"
else
  MISSING=""
  echo "$SCOPES" | grep -q "auth/documents" || MISSING="${MISSING} documents"
  echo "$SCOPES" | grep -q "auth/drive" || MISSING="${MISSING} drive"
  echo "$SCOPES" | grep -q "auth/spreadsheets" || MISSING="${MISSING} spreadsheets"

  if [ -n "$MISSING" ]; then
    fail "4. Token scopes: Missing:$MISSING"
  else
    pass "4. Token scopes: All required scopes present"
  fi
fi

# Check 5: Drive API enabled
HTTP_CODE=$(curl -s -o /tmp/mcp-drive-check.json -w "%{http_code}" --max-time 10 \
  "https://www.googleapis.com/drive/v3/about?fields=user" \
  -H "Authorization: Bearer $ACC_TOK" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
  EMAIL=$(jq -r '.user.emailAddress' /tmp/mcp-drive-check.json 2>/dev/null)
  pass "5. Drive API: Enabled ($EMAIL)"
else
  check_api_disabled /tmp/mcp-drive-check.json "Drive" "drive.googleapis.com"
fi

# Check 6: Docs API enabled
HTTP_CODE=$(curl -s -o /tmp/mcp-docs-check.json -w "%{http_code}" --max-time 10 \
  "https://docs.googleapis.com/v1/documents/VALIDATION_CHECK" \
  -H "Authorization: Bearer $ACC_TOK" 2>/dev/null)

if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "200" ]; then
  pass "6. Docs API: Enabled"
else
  check_api_disabled /tmp/mcp-docs-check.json "Docs" "docs.googleapis.com"
fi

# Check 7: Sheets API enabled
HTTP_CODE=$(curl -s -o /tmp/mcp-sheets-check.json -w "%{http_code}" --max-time 10 \
  "https://sheets.googleapis.com/v4/spreadsheets/VALIDATION_CHECK" \
  -H "Authorization: Bearer $ACC_TOK" 2>/dev/null)

if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "200" ]; then
  pass "7. Sheets API: Enabled"
else
  check_api_disabled /tmp/mcp-sheets-check.json "Sheets" "sheets.googleapis.com"
fi

# Check 8: MCP config
if [ -f "$MCP_CONFIG" ] && jq -e '.mcpServers["google-docs"]' "$MCP_CONFIG" > /dev/null 2>&1; then
  pass "8. MCP config: google-docs present"
else
  fail "8. MCP config: google-docs not in .mcp.json"
fi

[ $QUIET -eq 0 ] && cat >&2 <<EOF
================================
Result: $PASSED/8 passed
EOF

if [ $FAILED -eq 0 ]; then
  date +%s > "$CACHE_FILE"
  exit 0
else
  exit 1
fi
