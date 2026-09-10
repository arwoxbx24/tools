#!/usr/bin/env bash
# grok.sh — CLI wrapper for xAI Grok API (OpenAI-compatible)
# Usage: grok.sh [--model MODEL] [--system SYS_MSG] "prompt"
set -euo pipefail

ENV_FILE="/root/workspaces/secrets/services/xai.env"
BASE_URL="https://api.x.ai/v1"
DEFAULT_MODEL="grok-3-latest"

usage() {
    cat >&2 <<'EOF'
Usage: grok.sh [OPTIONS] "prompt text"

Options:
  --model MODEL       Override model (default: grok-3-latest)
  --system SYS_MSG    System message
  --help              Show this help

Examples:
  grok.sh "say hi in 3 words"
  grok.sh --model grok-3-mini-fast "explain TCP in one sentence"
  grok.sh --system "You are a haiku poet" "write about servers"
EOF
    exit 0
}

# Parse args
MODEL="$DEFAULT_MODEL"
SYSTEM_MSG=""
PROMPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage ;;
        --model)
            [[ $# -lt 2 ]] && { echo "ERROR: --model requires a value" >&2; exit 1; }
            MODEL="$2"; shift 2 ;;
        --system)
            [[ $# -lt 2 ]] && { echo "ERROR: --system requires a value" >&2; exit 1; }
            SYSTEM_MSG="$2"; shift 2 ;;
        --)
            shift; PROMPT="$*"; break ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        *)
            PROMPT="$1"; shift ;;
    esac
done

[[ -z "$PROMPT" ]] && { echo "ERROR: prompt is required" >&2; usage; }

# Load API key
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: env file not found: $ENV_FILE" >&2
    exit 1
fi

# Source safely — only export XAI_API_KEY
XAI_API_KEY=""
while IFS='=' read -r key val; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key="${key// /}"
    if [[ "$key" == "XAI_API_KEY" ]]; then
        XAI_API_KEY="${val}"
        break
    fi
done < "$ENV_FILE"

if [[ -z "$XAI_API_KEY" ]]; then
    echo "ERROR: XAI_API_KEY not found in $ENV_FILE" >&2
    exit 1
fi

echo "MODEL: $MODEL" >&2

# Build messages JSON
if [[ -n "$SYSTEM_MSG" ]]; then
    MESSAGES=$(jq -n \
        --arg sys "$SYSTEM_MSG" \
        --arg usr "$PROMPT" \
        '[{"role":"system","content":$sys},{"role":"user","content":$usr}]')
else
    MESSAGES=$(jq -n \
        --arg usr "$PROMPT" \
        '[{"role":"user","content":$usr}]')
fi

PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --argjson messages "$MESSAGES" \
    '{model:$model,messages:$messages,temperature:0.7}')

# Call API — key passed via header, not logged
HTTP_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    --max-time 60 \
    -X POST "${BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${XAI_API_KEY}" \
    -d "$PAYLOAD")

HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
RESPONSE=$(echo "$HTTP_RESPONSE" | sed '/HTTP_CODE:[0-9]*/d')

# Extract content
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [[ -z "$CONTENT" ]]; then
    # .error may be a string (xAI) or object with .message (OpenAI-style)
    ERROR=$(echo "$RESPONSE" | jq -r 'if (.error | type) == "string" then .error elif .error.message then .error.message else "unknown error" end' 2>/dev/null || echo "unknown error")
    echo "ERROR [HTTP $HTTP_CODE]: API call failed — $ERROR" >&2
    echo "Raw response: $RESPONSE" >&2
    exit 1
fi

echo "$CONTENT"
