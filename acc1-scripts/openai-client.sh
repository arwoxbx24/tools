#!/bin/bash
# OpenAI/ChatGPT API Client
# Usage: openai-client.sh "prompt" [model] [--json]
# Models: gpt-4.1-mini (default), gpt-4o, gpt-4.1, o1-mini (code/reasoning)
# ⛔ BANNED: gpt-3.5-turbo (wastes tokens, poor quality)

set -e

PROMPT="$1"
MODEL="gpt-4.1-mini"
JSON_MODE=""

# Parse arguments (skip first - it's prompt)
shift || true
for arg in "$@"; do
  case $arg in
    --json) JSON_MODE="true" ;;
    gpt-*|o1-*) MODEL="$arg" ;;
  esac
done

# Load API key
source /root/workspaces/tools/acc1-scripts/config/.env 2>/dev/null || true

if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "❌ OPENAI_API_KEY not set in /root/workspaces/tools/acc1-scripts/config/.env"
  exit 1
fi

if [[ -z "$PROMPT" ]]; then
  echo "Usage: openai-client.sh \"prompt\" [model] [--json]"
  echo "Models: gpt-4.1-mini, gpt-4.1, gpt-4o, o1-mini"
  echo "⛔ BANNED: gpt-3.5-turbo"
  exit 1
fi

# Block banned models
if [[ "$MODEL" == "gpt-3.5-turbo" ]]; then
  echo "⛔ gpt-3.5-turbo is BANNED! Using gpt-4.1-mini instead."
  MODEL="gpt-4.1-mini"
fi

# Build request
if [[ "$JSON_MODE" == "true" ]]; then
  RESPONSE_FORMAT=',"response_format":{"type":"json_object"}'
  FULL_PROMPT="$PROMPT\n\nRespond in valid JSON format."
else
  RESPONSE_FORMAT=""
  FULL_PROMPT="$PROMPT"
fi

REQUEST=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [{"role": "user", "content": "$FULL_PROMPT"}],
  "max_tokens": 2048
  $RESPONSE_FORMAT
}
EOF
)

# Call API
RESPONSE=$(curl -s --max-time 60 --connect-timeout 10 https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$REQUEST") || { echo "Error: OpenAI API request failed" >&2; exit 1; }

# Extract response
RESULT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null) || RESULT=""

if [[ -z "$RESULT" ]]; then
  echo "$RESPONSE" | jq -r '.error.message // .' >&2 || echo "$RESPONSE" >&2
  exit 1
fi

echo "$RESULT"
