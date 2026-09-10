#!/bin/bash
# Timeweb Cloud AI Agent Caller
# API docs: https://agent.timeweb.cloud/docs
# Usage: timeweb-agent.sh <command> [args]

set -u

REGISTRY="/root/workspaces/tools/acc1-scripts/registry/programs.json"
BASE_URL="https://agent.timeweb.cloud"
TIMEOUT=30
CONNECT_TIMEOUT=10

# ============ ERROR HANDLING ============

# Error codes
ERR_DEPS=1
ERR_REGISTRY=2
ERR_AGENT_NOT_FOUND=3
ERR_NETWORK=4
ERR_API=5
ERR_JSON=6
ERR_TIMEOUT=7
ERR_ARGS=8

# Print error and exit
error() {
    local code="$1"
    local msg="$2"
    echo "ERROR [$code]: $msg" >&2
    exit "$code"
}

# Print warning (non-fatal)
warn() {
    echo "WARN: $1" >&2
}

# Check dependencies
check_deps() {
    command -v curl >/dev/null 2>&1 || error $ERR_DEPS "curl not installed"
    command -v jq >/dev/null 2>&1 || error $ERR_DEPS "jq not installed"
}

# Check registry exists
check_registry() {
    [[ -f "$REGISTRY" ]] || error $ERR_REGISTRY "Registry not found: $REGISTRY"
    jq empty "$REGISTRY" 2>/dev/null || error $ERR_REGISTRY "Invalid JSON in registry"
}

# Safe curl wrapper with error handling
safe_curl() {
    local method="$1"
    local url="$2"
    local auth="$3"
    local data="${4:-}"

    local tmp_file="/tmp/timeweb_$$_$(date +%s).json"

    local curl_args=(
        -s
        -w "\n%{http_code}"
        --connect-timeout "$CONNECT_TIMEOUT"
        --max-time "$TIMEOUT"
        -H "Authorization: Bearer $auth"
        -H "Content-Type: application/json"
    )

    if [[ "$method" == "POST" ]]; then
        curl_args+=(-X POST -d "$data")
    else
        curl_args+=(-X GET)
    fi

    local output
    output=$(curl "${curl_args[@]}" "$url" 2>/dev/null) || {
        local curl_exit=$?
        case $curl_exit in
            6)  error $ERR_NETWORK "Could not resolve host (DNS error)" ;;
            7)  error $ERR_NETWORK "Connection refused" ;;
            28) error $ERR_TIMEOUT "Request timeout (${TIMEOUT}s)" ;;
            35) error $ERR_NETWORK "SSL/TLS connection error" ;;
            *)  error $ERR_NETWORK "Curl error (code: $curl_exit)" ;;
        esac
    }

    # Split response and http_code (last line)
    local http_code
    local response
    http_code=$(echo "$output" | tail -n1) || true
    response=$(echo "$output" | sed '$d') || true

    # Check HTTP status
    case "$http_code" in
        200|201)
            # Success - validate JSON
            if ! echo "$response" | jq empty 2>/dev/null; then
                error $ERR_JSON "Invalid JSON in response"
            fi
            echo "$response"
            ;;
        401)
            error $ERR_API "Unauthorized: Invalid API key"
            ;;
        403)
            local err_msg=$(echo "$response" | jq -r '.error.message // "Access forbidden"' 2>/dev/null)
            error $ERR_API "Forbidden: $err_msg (check balance or domain whitelist)"
            ;;
        404)
            error $ERR_API "Agent not found (404)"
            ;;
        429)
            error $ERR_API "Rate limit exceeded. Wait and retry."
            ;;
        500|502|503)
            error $ERR_API "Server error ($http_code). Try again later."
            ;;
        *)
            local err_msg=$(echo "$response" | jq -r '.error.message // .message // empty' 2>/dev/null)
            [[ -n "$err_msg" ]] && error $ERR_API "HTTP $http_code: $err_msg"
            error $ERR_API "HTTP error: $http_code"
            ;;
    esac
}

# Extract content from API response, handle errors
extract_content() {
    local response="$1"
    local content

    # Check for API error in response
    local api_error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$api_error" ]]; then
        error $ERR_API "$api_error"
    fi

    # Try chat completion format: standard content field
    content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    [[ -n "$content" ]] && { echo "$content"; return 0; }

    # Reasoning models (deepseek-reasoner, qwen thinking): content is in reasoning_content
    content=$(echo "$response" | jq -r '.choices[0].message.reasoning_content // empty')
    [[ -n "$content" ]] && { echo "$content"; return 0; }

    # Timeweb wrapper: reasoning_content nested under provider_specific_fields
    content=$(echo "$response" | jq -r '.choices[0].message.provider_specific_fields.reasoning_content // empty')
    [[ -n "$content" ]] && { echo "$content"; return 0; }

    # Try call format
    content=$(echo "$response" | jq -r '.message // empty')
    [[ -n "$content" ]] && { echo "$content"; return 0; }

    # No content found
    warn "No content in response"
    echo "$response" | jq -r '.'
}

# ============ HELPERS ============

# Get agent by ID
get_agent() {
    local id="$1"
    local agent=$(jq -r ".external_agents.agents[] | select(.id == \"$id\")" "$REGISTRY" 2>/dev/null)
    [[ -z "$agent" || "$agent" == "null" ]] && return 1
    echo "$agent"
}

# List available agents
list_agents() {
    check_registry
    echo "Available Timeweb agents:"
    jq -r '.external_agents.agents[] | "  \(.id): \(.name) (\(.model)) - \(.status // "unknown")"' "$REGISTRY"
}

# Get agent credentials
get_creds() {
    local agent_id="$1"
    local agent

    agent=$(get_agent "$agent_id") || {
        echo "Agent '$agent_id' not found" >&2
        list_agents >&2
        error $ERR_AGENT_NOT_FOUND "Unknown agent: $agent_id"
    }

    UUID=$(echo "$agent" | jq -r '.agent_id')
    API_KEY=$(echo "$agent" | jq -r '.api_key')
    MODEL=$(echo "$agent" | jq -r '.model')

    [[ -z "$UUID" || "$UUID" == "null" ]] && error $ERR_REGISTRY "Missing agent_id in registry"
    [[ -z "$API_KEY" || "$API_KEY" == "null" ]] && error $ERR_REGISTRY "Missing api_key in registry"
}

# ============ API METHODS ============

# 1. Chat Completions (OpenAI-compatible)
chat_completions() {
    local agent_id="${1:-}"
    local prompt="${2:-}"
    local max_tokens="${3:-2000}"
    local temperature="${4:-0.7}"

    [[ -z "$agent_id" ]] && error $ERR_ARGS "Missing agent_id"
    [[ -z "$prompt" ]] && error $ERR_ARGS "Missing prompt"

    get_creds "$agent_id"
    local url="${BASE_URL}/api/v1/cloud-ai/agents/${UUID}/v1/chat/completions"

    # Escape prompt for JSON
    local escaped_prompt=$(echo "$prompt" | jq -Rs '.')

    local response=$(safe_curl POST "$url" "$API_KEY" "{
        \"model\": \"$MODEL\",
        \"messages\": [{\"role\": \"user\", \"content\": $escaped_prompt}],
        \"max_tokens\": $max_tokens,
        \"temperature\": $temperature
    }")

    extract_content "$response"
}

# 2. Call Agent (simplified interface)
call_agent() {
    local agent_id="${1:-}"
    local message="${2:-}"

    [[ -z "$agent_id" ]] && error $ERR_ARGS "Missing agent_id"
    [[ -z "$message" ]] && error $ERR_ARGS "Missing message"

    get_creds "$agent_id"
    local url="${BASE_URL}/api/v1/cloud-ai/agents/${UUID}/call"

    local escaped_msg=$(echo "$message" | jq -Rs '.')

    local response=$(safe_curl POST "$url" "$API_KEY" "{\"message\": $escaped_msg}")
    extract_content "$response"
}

# 3. Get Models
get_models() {
    local agent_id="${1:-}"
    [[ -z "$agent_id" ]] && error $ERR_ARGS "Missing agent_id"

    get_creds "$agent_id"
    local url="${BASE_URL}/api/v1/cloud-ai/agents/${UUID}/v1/models"

    local response=$(safe_curl GET "$url" "$API_KEY")
    echo "$response" | jq -r '.data[] | "\(.id) (owned by: \(.owned_by))"' 2>/dev/null || echo "$response"
}

# 4. Chat with streaming
chat_stream() {
    local agent_id="${1:-}"
    local prompt="${2:-}"
    local max_tokens="${3:-2000}"

    [[ -z "$agent_id" ]] && error $ERR_ARGS "Missing agent_id"
    [[ -z "$prompt" ]] && error $ERR_ARGS "Missing prompt"

    get_creds "$agent_id"
    local url="${BASE_URL}/api/v1/cloud-ai/agents/${UUID}/v1/chat/completions"

    local escaped_prompt=$(echo "$prompt" | jq -Rs '.')

    curl -s -N -X POST "$url" \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time 120 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL\",
            \"messages\": [{\"role\": \"user\", \"content\": $escaped_prompt}],
            \"max_tokens\": $max_tokens,
            \"stream\": true
        }" 2>/dev/null | while read -r line; do
            if [[ "$line" =~ ^data:\ (.+)$ ]]; then
                local chunk="${BASH_REMATCH[1]}"
                [[ "$chunk" == "[DONE]" ]] && break
                local content=$(echo "$chunk" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
                [[ -n "$content" ]] && printf "%s" "$content"
            fi
        done
    echo ""
}

# 5. Raw JSON response
chat_raw() {
    local agent_id="${1:-}"
    local prompt="${2:-}"
    local max_tokens="${3:-2000}"

    [[ -z "$agent_id" ]] && error $ERR_ARGS "Missing agent_id"
    [[ -z "$prompt" ]] && error $ERR_ARGS "Missing prompt"

    get_creds "$agent_id"
    local url="${BASE_URL}/api/v1/cloud-ai/agents/${UUID}/v1/chat/completions"

    local escaped_prompt=$(echo "$prompt" | jq -Rs '.')

    local response=$(safe_curl POST "$url" "$API_KEY" "{
        \"model\": \"$MODEL\",
        \"messages\": [{\"role\": \"user\", \"content\": $escaped_prompt}],
        \"max_tokens\": $max_tokens
    }")

    echo "$response" | jq '.'
}

# 6. Check usage/health
check_usage() {
    local agent_id="${1:-}"
    [[ -z "$agent_id" ]] && error $ERR_ARGS "Missing agent_id"

    get_creds "$agent_id"
    local url="${BASE_URL}/api/v1/cloud-ai/agents/${UUID}/v1/chat/completions"

    echo "Testing agent: $agent_id ($MODEL)"
    echo "---"

    local response
    response=$(safe_curl POST "$url" "$API_KEY" "{
        \"model\": \"$MODEL\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Say OK\"}],
        \"max_tokens\": 10
    }") || {
        echo ""
        echo "Possible issues:"
        echo "  - Balance exhausted"
        echo "  - API key expired"
        echo "  - Agent suspended"
        echo ""
        echo "Check balance: https://my.timeweb.cloud/services/cloud-ai"
        return 1
    }

    local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // "?"')
    local completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // "?"')
    local total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // "?"')

    echo "✅ Agent is working"
    echo ""
    echo "Test request usage:"
    echo "  Prompt tokens:     $prompt_tokens"
    echo "  Completion tokens: $completion_tokens"
    echo "  Total tokens:      $total_tokens"
    echo ""
    echo "⚠️  Balance check: https://my.timeweb.cloud/services/cloud-ai"
    echo "    (API does not expose balance endpoint)"
}

# ============ MAIN ============

show_help() {
    cat <<'EOF'
Timeweb Cloud AI Agent Caller
API docs: https://agent.timeweb.cloud/docs

USAGE:
  timeweb-agent.sh <command> [arguments]

COMMANDS:
  chat <agent_id> "prompt" [max_tokens] [temperature]
      OpenAI-compatible chat completions (default command)

  call <agent_id> "message"
      Simplified call interface

  stream <agent_id> "prompt" [max_tokens]
      Chat with streaming output

  models <agent_id>
      List available models for agent

  raw <agent_id> "prompt" [max_tokens]
      Return full JSON response (for debugging)

  usage <agent_id>
      Test agent and show token usage (balance check proxy)

  --list, -l
      List available agents from registry

  --help, -h
      Show this help

AGENTS:
  grok3-mini  - Grok 3 mini (xAI) - fast, creative
  gpt41-mini  - GPT 4.1 mini (OpenAI) - balanced

EXAMPLES:
  timeweb-agent.sh chat grok3-mini "Generate greeting"
  timeweb-agent.sh stream gpt41-mini "Write a poem" 500
  timeweb-agent.sh call grok3-mini "Hello"
  timeweb-agent.sh models grok3-mini
  timeweb-agent.sh usage grok3-mini  # check if agent works
  timeweb-agent.sh grok3-mini "Quick question"  # shorthand for chat

ERROR CODES:
  1 - Missing dependencies (curl, jq)
  2 - Registry error
  3 - Agent not found
  4 - Network error
  5 - API error
  6 - JSON parsing error
  7 - Timeout
  8 - Invalid arguments

USE CASES (allowed):
  ✓ Document generation
  ✓ Content creation
  ✓ Bot responses
  ✓ Text editing/naming

FORBIDDEN:
  ✗ Code writing
  ✗ Code review
  ✗ Architecture decisions
EOF
}

# Initialize
check_deps
check_registry

# Main dispatcher
case "${1:-}" in
    --list|-l)
        list_agents
        ;;
    --help|-h)
        show_help
        ;;
    chat)
        shift
        chat_completions "$@"
        ;;
    call)
        shift
        call_agent "$@"
        ;;
    stream)
        shift
        chat_stream "$@"
        ;;
    models)
        shift
        get_models "$@"
        ;;
    raw)
        shift
        chat_raw "$@"
        ;;
    usage|check|balance)
        shift
        check_usage "$@"
        ;;
    "")
        error $ERR_ARGS "Missing command. Use --help for usage."
        ;;
    *)
        # Shorthand: timeweb-agent.sh <agent_id> "prompt"
        if [[ -n "${2:-}" ]]; then
            chat_completions "$1" "$2" "${3:-2000}" "${4:-0.7}"
        else
            error $ERR_ARGS "Missing prompt. Usage: timeweb-agent.sh <agent_id> \"prompt\""
        fi
        ;;
esac
