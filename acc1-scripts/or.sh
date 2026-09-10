#!/usr/bin/env bash
# or.sh — CLI wrapper for OpenRouter API (OpenAI-compatible)
# Usage: or.sh [--model MODEL] [--system SYS_MSG] [--free] [--paid] [--long] [--usage] "prompt"
set -euo pipefail

ENV_FILE="/root/workspaces/secrets/services/openrouter.env"
BASE_URL="https://openrouter.ai/api/v1"
DEFAULT_MODEL="qwen/qwen3-coder:free"
FREE_MODEL="google/gemma-3-4b-it:free"
PAID_MODEL="rekaai/reka-edge"
MAX_TOKENS_DEFAULT=500
MAX_TOKENS_LONG=4000
USAGE_LOG="/tmp/or-usage.log"

# Rate table (per 1M tokens): "input output"
declare -A RATE_TABLE
RATE_TABLE["qwen/qwen3-coder:free"]="0 0"
RATE_TABLE["google/gemma-3-4b-it:free"]="0 0"
RATE_TABLE["rekaai/reka-edge"]="0.10 0.10"
RATE_TABLE["openai/gpt-4o-mini"]="0.15 0.60"
RATE_TABLE["anthropic/claude-3.5-haiku"]="1.00 5.00"

usage() {
    cat >&2 <<'EOF'
Usage: or.sh [OPTIONS] "prompt text"

Options:
  --model MODEL       Override model
  --system SYS_MSG    System message
  --free              Use free model: google/gemma-3-4b-it:free
  --paid              Use paid model: rekaai/reka-edge (opt-in)
  --long              Remove token limit (max=4000, default=500)
  --usage             Show last 20 usage log entries + total cost
  --help              Show this help

Default model: qwen/qwen3-coder:free (free, no cost)

Rate table (per 1M tokens input/output):
  qwen/qwen3-coder:free        $0.00 / $0.00
  google/gemma-3-4b-it:free    $0.00 / $0.00
  rekaai/reka-edge             $0.10 / $0.10
  openai/gpt-4o-mini           $0.15 / $0.60
  anthropic/claude-3.5-haiku   $1.00 / $5.00

Examples:
  or.sh "say hi in 3 words"
  or.sh --paid "explain TCP in one sentence"
  or.sh --model "anthropic/claude-3.5-haiku" "explain TCP"
  or.sh --system "You are a haiku poet" "write about servers"
  or.sh --free "1+1="
  or.sh --long "write a detailed essay about TCP"
  or.sh --usage
EOF
    exit 0
}

show_usage() {
    if [[ ! -f "$USAGE_LOG" ]]; then
        echo "No usage log found at $USAGE_LOG" >&2
        exit 0
    fi
    echo "=== Last 20 entries ==="
    tail -20 "$USAGE_LOG"
    echo ""
    echo "=== Total cost estimate ==="
    # Sum all cost_estimate values from log lines
    awk -F'cost_estimate=\\$' 'NF>1 {gsub(/[^0-9.]/, "", $2); sum += $2} END {printf "Total: $%.4f\n", sum}' "$USAGE_LOG"
    exit 0
}

# Parse args
MODEL="$DEFAULT_MODEL"
SYSTEM_MSG=""
PROMPT=""
MAX_TOKENS="$MAX_TOKENS_DEFAULT"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage ;;
        --usage) show_usage ;;
        --model)
            [[ $# -lt 2 ]] && { echo "ERROR: --model requires a value" >&2; exit 1; }
            MODEL="$2"; shift 2 ;;
        --system)
            [[ $# -lt 2 ]] && { echo "ERROR: --system requires a value" >&2; exit 1; }
            SYSTEM_MSG="$2"; shift 2 ;;
        --free)
            MODEL="$FREE_MODEL"; shift ;;
        --paid)
            MODEL="$PAID_MODEL"; shift ;;
        --long)
            MAX_TOKENS="$MAX_TOKENS_LONG"; shift ;;
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

OPENROUTER_API_KEY=""
while IFS='=' read -r key val; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key="${key// /}"
    if [[ "$key" == "OPENROUTER_API_KEY" ]]; then
        val="${val#\"}" ; val="${val%\"}"
        val="${val#\'}" ; val="${val%\'}"
        OPENROUTER_API_KEY="${val}"
        break
    fi
done < "$ENV_FILE"

if [[ -z "$OPENROUTER_API_KEY" ]]; then
    echo "ERROR: OPENROUTER_API_KEY not found in $ENV_FILE" >&2
    exit 1
fi

echo "MODEL: $MODEL | max_tokens: $MAX_TOKENS" >&2

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
    --argjson max_tokens "$MAX_TOKENS" \
    '{model:$model,messages:$messages,temperature:0.7,max_tokens:$max_tokens}')

# Call API
HTTP_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    --max-time 60 \
    -X POST "${BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "HTTP-Referer: https://claude-expert.local" \
    -H "X-Title: claude-expert-cli" \
    -d "$PAYLOAD")

HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
RESPONSE=$(echo "$HTTP_RESPONSE" | sed '/HTTP_CODE:[0-9]*/d')

# Extract content
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [[ -z "$CONTENT" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error // "unknown error"' 2>/dev/null || echo "unknown error")
    echo "ERROR [HTTP $HTTP_CODE]: API call failed — $ERROR" >&2
    echo "Raw response: $RESPONSE" >&2
    exit 1
fi

echo "$CONTENT"

# Usage logging
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
PROMPT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // "?"' 2>/dev/null)
COMPLETION_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // "?"' 2>/dev/null)

# Calculate cost estimate
COST_ESTIMATE="?"
if [[ -n "${RATE_TABLE[$MODEL]+_}" ]]; then
    RATES="${RATE_TABLE[$MODEL]}"
    RATE_IN=$(echo "$RATES" | awk '{print $1}')
    RATE_OUT=$(echo "$RATES" | awk '{print $2}')
    if [[ "$PROMPT_TOKENS" != "?" && "$COMPLETION_TOKENS" != "?" ]]; then
        # cost = (prompt_tokens * rate_in + completion_tokens * rate_out) / 1_000_000
        COST_ESTIMATE=$(awk "BEGIN {printf \"%.6f\", ($PROMPT_TOKENS * $RATE_IN + $COMPLETION_TOKENS * $RATE_OUT) / 1000000}")
    elif [[ "$RATE_IN" == "0" && "$RATE_OUT" == "0" ]]; then
        COST_ESTIMATE="0.000000"
    fi
fi

LOG_LINE="${TIMESTAMP} | model=${MODEL} | prompt_tokens=${PROMPT_TOKENS} | completion_tokens=${COMPLETION_TOKENS} | cost_estimate=\$${COST_ESTIMATE}"

# Ensure log exists with secure permissions before writing
touch "$USAGE_LOG"
chmod 600 "$USAGE_LOG"
echo "$LOG_LINE" >> "$USAGE_LOG"

echo "[usage] ${LOG_LINE}" >&2
