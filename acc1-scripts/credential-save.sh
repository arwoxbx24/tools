#!/bin/bash
# credential-save.sh — V251 Mandatory Credential Capture
# Saves credentials to appropriate secrets location with metadata
# Usage: credential-save.sh --type TYPE --service SERVICE --scope SCOPE --value VALUE [options]
set +e

# === PARSE ARGUMENTS ===
TYPE=""
SERVICE=""
SCOPE=""
VALUE=""
PROJECT=""
EXPIRES="never"
REFRESH=""
LABEL=""
KEY_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)     TYPE="$2"; shift 2 ;;
        --service)  SERVICE="$2"; shift 2 ;;
        --scope)    SCOPE="$2"; shift 2 ;;
        --value)    VALUE="$2"; shift 2 ;;
        --project)  PROJECT="$2"; shift 2 ;;
        --expires)  EXPIRES="$2"; shift 2 ;;
        --refresh)  REFRESH="$2"; shift 2 ;;
        --label)    LABEL="$2"; shift 2 ;;
        --key)      KEY_NAME="$2"; shift 2 ;;
        --help|-h)
            cat << 'USAGE'
credential-save.sh — V251 Mandatory Credential Capture

USAGE:
  credential-save.sh --type TYPE --service SERVICE --scope SCOPE --value VALUE [options]

REQUIRED:
  --type      api_key|password|login|token|session|ssh_key|connection_string|oauth|refresh_token
  --service   Service name (xai, github, wordpress, stroyremont, nginx-proxy-manager, etc.)
  --scope     internal (our services) | client (client project) | temp (temporary)
  --value     The credential value

OPTIONAL:
  --project   Project name (REQUIRED if scope=client, e.g., stroyremont)
  --expires   Expiration date YYYY-MM-DD or "never" (default: never)
  --refresh   Refresh token value (for OAuth/session tokens)
  --label     Custom label/description
  --key       Custom ENV variable name (default: auto-generated from SERVICE_TYPE)

EXAMPLES:
  # Internal API key
  credential-save.sh --type api_key --service xai --scope internal --value "xai-abc123..."

  # Client project password
  credential-save.sh --type password --service wordpress --scope client --project stroyremont --value "P4ss..."

  # OAuth token with refresh and expiry
  credential-save.sh --type oauth --service google --scope internal \
    --value "ya29.xxx" --refresh "1//xxx" --expires 2026-03-04

  # Temporary token
  credential-save.sh --type token --service test-api --scope temp --value "tok_xxx" --expires 2026-03-04
USAGE
            exit 0
            ;;
        *)  echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# === VALIDATE REQUIRED PARAMS ===
ERRORS=""
[ -z "$TYPE" ] && ERRORS="${ERRORS}--type is required\n"
[ -z "$SERVICE" ] && ERRORS="${ERRORS}--service is required\n"
[ -z "$SCOPE" ] && ERRORS="${ERRORS}--scope is required\n"
[ -z "$VALUE" ] && ERRORS="${ERRORS}--value is required\n"

# Validate type
case "$TYPE" in
    api_key|password|login|token|session|ssh_key|connection_string|oauth|refresh_token) ;;
    *) ERRORS="${ERRORS}Invalid --type: $TYPE\n" ;;
esac

# Validate scope
case "$SCOPE" in
    internal|client|temp) ;;
    *) ERRORS="${ERRORS}Invalid --scope: $SCOPE\n" ;;
esac

# Client scope requires project
if [ "$SCOPE" = "client" ] && [ -z "$PROJECT" ]; then
    ERRORS="${ERRORS}--project is required when scope=client\n"
fi

if [ -n "$ERRORS" ]; then
    echo -e "ERROR:\n${ERRORS}" >&2
    echo "Run with --help for usage" >&2
    exit 1
fi

# === DETERMINE TARGET FILE ===
SECRETS_BASE="/root/workspaces/secrets"
case "$SCOPE" in
    client)
        # Client projects: save in project directory
        TARGET_DIR="/root/claude-projects/${PROJECT}"
        TARGET_FILE="${TARGET_DIR}/.secrets.env"
        # Also save to centralized location
        CENTRAL_FILE="${SECRETS_BASE}/projects/${PROJECT}.env"
        ;;
    internal)
        TARGET_FILE="${SECRETS_BASE}/services/${SERVICE}.env"
        CENTRAL_FILE=""
        ;;
    temp)
        TARGET_FILE="${SECRETS_BASE}/temp/credentials.env"
        CENTRAL_FILE=""
        ;;
esac

# === GENERATE KEY NAME ===
if [ -z "$KEY_NAME" ]; then
    # Convert service + type to uppercase KEY
    # e.g., xai + api_key → XAI_API_KEY
    SERVICE_UPPER=$(echo "$SERVICE" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '.' '_')
    TYPE_UPPER=$(echo "$TYPE" | tr '[:lower:]' '[:upper:]')
    KEY_NAME="${SERVICE_UPPER}_${TYPE_UPPER}"
fi

# === PREPARE METADATA BLOCK ===
SAVED_AT=$(date -u +"%Y-%m-%d %H:%M UTC")
METADATA="# Service: ${SERVICE}
# Type: ${TYPE}
# Scope: ${SCOPE}${PROJECT:+
# Project: ${PROJECT}}
# Saved: ${SAVED_AT}
# Expires: ${EXPIRES}${REFRESH:+
# Has refresh token: yes}${LABEL:+
# Label: ${LABEL}}"

# === WRITE TO TARGET FILE ===
write_credential() {
    local FILE="$1"
    local DIR=$(dirname "$FILE")

    # Create directory if needed
    mkdir -p "$DIR" 2>/dev/null

    # Check if key already exists
    if [ -f "$FILE" ] && grep -q "^${KEY_NAME}=" "$FILE" 2>/dev/null; then
        # Update existing: remove old entry (key + preceding comments)
        # Find line number of the key
        local KEY_LINE=$(grep -n "^${KEY_NAME}=" "$FILE" | head -1 | cut -d: -f1)
        if [ -n "$KEY_LINE" ]; then
            # Remove up to 7 comment lines before the key + the key line itself
            local START=$((KEY_LINE - 7))
            [ "$START" -lt 1 ] && START=1
            # Find actual start of comment block
            local ACTUAL_START=$KEY_LINE
            for i in $(seq $((KEY_LINE - 1)) -1 $START); do
                if sed -n "${i}p" "$FILE" | grep -q "^#"; then
                    ACTUAL_START=$i
                else
                    break
                fi
            done
            # Also remove refresh token line if exists
            local END=$KEY_LINE
            local NEXT_LINE=$((KEY_LINE + 1))
            if sed -n "${NEXT_LINE}p" "$FILE" 2>/dev/null | grep -q "^${KEY_NAME}_REFRESH"; then
                END=$NEXT_LINE
            fi
            # Check for expires line too
            NEXT_LINE=$((END + 1))
            if sed -n "${NEXT_LINE}p" "$FILE" 2>/dev/null | grep -q "^${KEY_NAME}_EXPIRES"; then
                END=$NEXT_LINE
            fi
            sed -i "${ACTUAL_START},${END}d" "$FILE"
        fi
        echo "[V251] Updated existing ${KEY_NAME} in ${FILE}"
    else
        echo "[V251] Adding new ${KEY_NAME} to ${FILE}"
    fi

    # Append new entry
    {
        echo ""
        echo "$METADATA"
        echo "${KEY_NAME}=\"${VALUE}\""
        [ -n "$REFRESH" ] && echo "${KEY_NAME}_REFRESH=\"${REFRESH}\""
        [ "$EXPIRES" != "never" ] && echo "${KEY_NAME}_EXPIRES=\"${EXPIRES}\""
    } >> "$FILE"

    # Set permissions
    chmod 600 "$FILE" 2>/dev/null
}

# Write to primary target
write_credential "$TARGET_FILE"

# Write to central location if client scope
if [ -n "$CENTRAL_FILE" ] && [ "$TARGET_FILE" != "$CENTRAL_FILE" ]; then
    write_credential "$CENTRAL_FILE"
    echo "[V251] Also saved to central: ${CENTRAL_FILE}"
fi

# === UPDATE tokens.json FOR EXPIRING TOKENS ===
TOKENS_FILE="${SECRETS_BASE}/tokens.json"
if [ "$EXPIRES" != "never" ] || [ -n "$REFRESH" ]; then
    if [ -f "$TOKENS_FILE" ]; then
        # Use jq to add/update token entry
        ENTRY_KEY="${SERVICE}_${TYPE}"
        SAVED_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        jq --arg key "$ENTRY_KEY" \
           --arg service "$SERVICE" \
           --arg scope "$SCOPE" \
           --arg project "${PROJECT:-null}" \
           --arg expires "${EXPIRES}" \
           --arg refresh "${REFRESH:-none}" \
           --arg saved "$SAVED_ISO" \
           --arg file "$TARGET_FILE" \
           --arg key_name "$KEY_NAME" \
           '.[$key] = {
               "key_name": $key_name,
               "service": $service,
               "scope": $scope,
               "project": (if $project == "null" then null else $project end),
               "expires_at": (if $expires == "never" then null else $expires end),
               "has_refresh": ($refresh != "none"),
               "file": $file,
               "saved_at": $saved
           }' "$TOKENS_FILE" > "${TOKENS_FILE}.tmp" && mv "${TOKENS_FILE}.tmp" "$TOKENS_FILE"

        echo "[V251] Token lifecycle tracked in tokens.json"
    fi
fi

# === ENSURE .gitignore PROTECTION ===
if [ "$SCOPE" = "client" ] && [ -d "$TARGET_DIR" ]; then
    GITIGNORE="${TARGET_DIR}/.gitignore"
    if [ -f "$GITIGNORE" ]; then
        if ! grep -q "\.secrets\.env" "$GITIGNORE" 2>/dev/null; then
            echo ".secrets.env" >> "$GITIGNORE"
            echo "[V251] Added .secrets.env to ${GITIGNORE}"
        fi
    else
        echo ".secrets.env" > "$GITIGNORE"
        echo "[V251] Created ${GITIGNORE} with .secrets.env"
    fi
fi

# === CLEAR REDIS MARKER ===
# Try to get session ID from environment or use pattern
SESSION_ID=$(redis-cli KEYS "credential:pending:*" 2>/dev/null | head -1 | sed 's/credential:pending://')
if [ -n "$SESSION_ID" ]; then
    # Decrement count in marker
    CURRENT=$(redis-cli GET "credential:pending:${SESSION_ID}" 2>/dev/null)
    if [ -n "$CURRENT" ]; then
        CURRENT_COUNT=$(echo "$CURRENT" | jq -r '.count // 1' 2>/dev/null)
        NEW_COUNT=$((CURRENT_COUNT - 1))
        if [ "$NEW_COUNT" -le 0 ]; then
            redis-cli DEL "credential:pending:${SESSION_ID}" >/dev/null 2>&1
            echo "[V251] ✓ All credentials saved. Marker cleared. Work can continue."
        else
            # Update count
            redis-cli SET "credential:pending:${SESSION_ID}" \
                "$(echo "$CURRENT" | jq --argjson count "$NEW_COUNT" '.count = $count')" \
                EX 1800 >/dev/null 2>&1
            echo "[V251] Saved 1 credential. ${NEW_COUNT} more pending."
        fi
    fi
fi

echo "[V251] SAVED: ${SERVICE} ${TYPE} (${SCOPE}) → ${TARGET_FILE}"
exit 0
