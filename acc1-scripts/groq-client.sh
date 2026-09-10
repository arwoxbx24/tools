#!/bin/bash
# Groq API client with token tracking
# Usage: groq-client.sh "prompt" [system_prompt]
set -euo pipefail

CONFIG_DIR="/root/workspaces/tools/acc1-scripts"
ENV_FILE="$CONFIG_DIR/config/.env"
USAGE_FILE="$CONFIG_DIR/data/groq-usage.json"
DAILY_LIMIT=1000000  # tokens per day

# Load API key
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "${GROQ_API_KEY:-}" ]]; then
    echo "Error: GROQ_API_KEY not set in $ENV_FILE" >&2
    echo "FALLBACK_MODE"
    exit 1
fi

# Initialize usage file
init_usage() {
    mkdir -p "$(dirname "$USAGE_FILE")"
    if [[ ! -f "$USAGE_FILE" ]]; then
        echo '{"daily_limit":1000000,"current_usage":0,"last_reset":"'$(date +%Y-%m-%d)'","requests_count":0}' > "$USAGE_FILE"
    fi
}

# Check limit
check_limit() {
    local usage=$(jq -r '.current_usage' "$USAGE_FILE")
    local limit=$(jq -r '.daily_limit' "$USAGE_FILE")
    local percent=$((usage * 100 / limit))

    # Reset on new day
    local last_reset=$(jq -r '.last_reset' "$USAGE_FILE")
    local today=$(date +%Y-%m-%d)
    if [[ "$last_reset" != "$today" ]]; then
        jq '.current_usage=0 | .requests_count=0 | .last_reset="'$today'"' "$USAGE_FILE" > "$USAGE_FILE.tmp" && mv "$USAGE_FILE.tmp" "$USAGE_FILE"
        percent=0
    fi

    # Notifications
    if [[ $percent -ge 98 ]]; then
        echo "🛑 GROQ LIMIT REACHED (${percent}%). Switching to local mode." >&2
        return 1
    elif [[ $percent -ge 90 ]]; then
        echo "⚠️  Groq limit: $((100-percent))% remaining" >&2
    elif [[ $percent -ge 70 ]]; then
        echo "ℹ️  Groq usage: ${percent}%" >&2
    fi
    return 0
}

# Update usage
update_usage() {
    local tokens=$1
    jq ".current_usage += $tokens | .requests_count += 1" "$USAGE_FILE" > "$USAGE_FILE.tmp" && mv "$USAGE_FILE.tmp" "$USAGE_FILE"
}

# Query Groq API
query_groq() {
    local prompt="$1"
    local system="${2:-You are a helpful assistant for document analysis. Provide concise and structured responses.}"

    # Escape JSON special characters using jq
    local prompt_json=$(echo "$prompt" | jq -Rs .)
    local system_json=$(echo "$system" | jq -Rs .)

    local response=$(curl -s https://api.groq.com/openai/v1/chat/completions \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "llama-3.3-70b-versatile",
            "messages": [
                {"role": "system", "content": '"$system_json"'},
                {"role": "user", "content": '"$prompt_json"'}
            ],
            "max_tokens": 2000
        }')

    # Check for API errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "Error: $(echo "$response" | jq -r '.error.message')" >&2
        echo "FALLBACK_MODE"
        return 1
    fi

    # Extract tokens and update stats
    local total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // 0')
    if [[ "$total_tokens" -gt 0 ]]; then
        update_usage "$total_tokens"
    fi

    # Return response
    echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Support stdin input
if [[ "${1:-}" == "--stdin" ]] || [[ "${1:-}" == "-" ]]; then
    PROMPT=$(cat)
    SYSTEM="${2:-You are a helpful assistant for document analysis. Provide concise and structured responses.}"
else
    PROMPT="${1:-}"
    SYSTEM="${2:-You are a helpful assistant for document analysis. Provide concise and structured responses.}"
fi

# Main
init_usage
if check_limit; then
    query_groq "$PROMPT" "$SYSTEM"
else
    echo "FALLBACK_MODE"
    exit 1
fi
