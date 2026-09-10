#!/bin/bash
# classify-intent.sh — shared helper for intent classification
# Sourced by hooks: source "/root/workspaces/tools/acc1-scripts/scripts/classify-intent.sh"
# Provides: classify_intent <text> <intent_name> → sets INTENT_SCORE and INTENT_MATCH

INTENT_CLASSIFIER_URL="http://localhost:11434"
INTENT_CLASSIFIER_TIMEOUT=8  # seconds (hard max for curl; qwen2.5:3b needs 2-8s on CPU)

# Check if classifier is running (cache result for this hook invocation)
_CLASSIFIER_AVAILABLE=""
check_classifier() {
    if [ -z "$_CLASSIFIER_AVAILABLE" ]; then
        if curl -s --max-time 0.3 "${INTENT_CLASSIFIER_URL}/api/tags" >/dev/null 2>&1; then
            _CLASSIFIER_AVAILABLE="yes"
            echo "[OLLAMA] backend: qwen2.5:3b ready" >&2
        else
            _CLASSIFIER_AVAILABLE="no"
        fi
    fi
    [ "$_CLASSIFIER_AVAILABLE" = "yes" ]
}

# Classify text against a specific intent
# Args: $1 = text to classify, $2 = intent name (e.g., "panic", "role_pe")
# Sets: INTENT_SCORE (float like "0.82"), INTENT_MATCH (0 or 1)
# Returns: 0 if classified successfully, 1 if classifier unavailable
classify_intent() {
    local text="$1"
    local intent_name="$2"

    INTENT_SCORE="0"
    INTENT_MATCH=0

    # Load guard: skip if system is under heavy load
    local _LOAD_NOW _LOAD_INT
    _LOAD_NOW=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    _LOAD_INT=$(echo "$_LOAD_NOW" | awk '{printf "%d", $1 * 10}')
    if [ "${_LOAD_INT:-0}" -gt 80 ]; then
        return 1
    fi

    if ! check_classifier; then
        return 1
    fi

    # Trim text to first 200 chars for the prompt
    local short_text
    short_text=$(echo "$text" | head -c 200)

    local prompt_text
    prompt_text="Classify if this text is about '${intent_name}'. Text: ${short_text}. Reply ONLY with JSON: {\"match\":true/false,\"score\":0.0-1.0}"

    # Build JSON payload safely via jq
    local payload
    payload=$(jq -n --arg model "qwen2.5:3b" --arg prompt "$prompt_text" \
        '{"model":$model,"prompt":$prompt,"stream":false}' 2>/dev/null)

    if [ -z "$payload" ]; then
        return 1
    fi

    # Call Ollama
    local raw_response
    raw_response=$(curl -s --max-time "$INTENT_CLASSIFIER_TIMEOUT" \
        -X POST "${INTENT_CLASSIFIER_URL}/api/generate" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)

    if [ -z "$raw_response" ]; then
        return 1
    fi

    # Extract .response field from Ollama reply, then parse match/score JSON
    local inner_json
    inner_json=$(echo "$raw_response" | jq -r '.response // empty' 2>/dev/null)

    if [ -z "$inner_json" ]; then
        return 1
    fi

    # Parse score from inner JSON
    local parsed_score
    parsed_score=$(echo "$inner_json" | jq -r '.score // "0"' 2>/dev/null)
    [ -z "$parsed_score" ] && parsed_score="0"
    INTENT_SCORE="$parsed_score"

    # Parse match from inner JSON
    local parsed_match
    parsed_match=$(echo "$inner_json" | jq -r '.match // false' 2>/dev/null)
    if [ "$parsed_match" = "true" ]; then
        INTENT_MATCH=1
    fi

    echo "[OLLAMA] classify: intent=$intent_name match=$INTENT_MATCH score=$INTENT_SCORE" >&2

    return 0
}

# Classify text and return ALL matching intents as space-separated list
# Args: $1 = text to classify
# Sets: INTENT_ALL (space-separated "name:score" pairs), INTENT_TOP (top intent name)
# NOTE: Ollama single-intent backend does not support multi-intent; returns empty.
classify_all() {
    local text="$1"

    INTENT_ALL=""
    INTENT_TOP=""

    # Load guard: skip if system is under heavy load
    local _LOAD_NOW _LOAD_INT
    _LOAD_NOW=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    _LOAD_INT=$(echo "$_LOAD_NOW" | awk '{printf "%d", $1 * 10}')
    if [ "${_LOAD_INT:-0}" -gt 80 ]; then
        return 1
    fi

    if ! check_classifier; then
        return 1
    fi

    return 0
}
