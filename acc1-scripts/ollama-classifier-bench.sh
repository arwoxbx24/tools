#!/bin/bash
# ollama-classifier-bench.sh — benchmark Ollama models for CWD dispatcher
# Usage: bash ollama-classifier-bench.sh [model1 model2 ...]
# Writes winner to /root/workspaces/tools/acc1-scripts/state/ollama-classifier-model.txt
# Logs full results to /root/workspaces/tools/acc1-scripts/logs/cwd-dispatcher.log

set +e

STATE_DIR="/root/workspaces/tools/acc1-scripts/state"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/cwd-dispatcher.log"
STATE_FILE="${STATE_DIR}/ollama-classifier-model.txt"
OLLAMA_URL="http://localhost:11434/api/generate"
TIMEOUT=30

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date -Iseconds)] [bench] $*" >> "$LOG_FILE"
    echo "$*" >&2
}

# Models to test: accept CLI args or use defaults
if [ $# -gt 0 ]; then
    MODELS=("$@")
else
    MODELS=("nchapman/dolphin3.0-qwen2.5:latest" "qwen2.5-coder:7b")
fi

# Fixed test cases: prompt → expected_answer
declare -A TESTS
TESTS_PROMPTS=(
    "работай со стройремонтом"
    "TeamLead, давай работать"
    "нужно поправить сайт kircom"
    "привет как дела"
    "давай поработаем с тест-2026"
)
TESTS_EXPECTED=(
    "stroyremont"
    "teamlead"
    "kircom"
    "NONE"
    "NONE"
)

# Get projects from Redis for the prompt template
PROJECTS_LIST=$(redis-cli HKEYS projects:registry 2>/dev/null | tr '\n' ',' | sed 's/,$//')
if [ -z "$PROJECTS_LIST" ]; then
    PROJECTS_LIST="stroyremont,kircom,teamlead,security-scanner"
    log "WARNING: Redis unavailable, using fallback project list"
fi

BEST_MODEL=""
BEST_SCORE=-1
BEST_LATENCY=999999

for MODEL in "${MODELS[@]}"; do
    log "Testing model: $MODEL"
    CORRECT=0
    TOTAL=${#TESTS_PROMPTS[@]}
    TOTAL_LATENCY=0

    for i in "${!TESTS_PROMPTS[@]}"; do
        PROMPT="${TESTS_PROMPTS[$i]}"
        EXPECTED="${TESTS_EXPECTED[$i]}"

        CLASSIFY_PROMPT="User message: '${PROMPT}'. Available projects: [${PROJECTS_LIST}]. Task: if user explicitly asks to work with a specific project from the list — reply with EXACTLY that project name. If user says 'teamlead' or 'тимлид' reply 'teamlead'. If no project mentioned or ambiguous — reply NONE. No other text."

        T_START=$(date +%s%3N)
        RESPONSE=$(curl -s --max-time "$TIMEOUT" \
            -X POST "$OLLAMA_URL" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"${MODEL}\",\"prompt\":$(echo -n "$CLASSIFY_PROMPT" | jq -Rs .),\"stream\":false}" \
            2>/dev/null)
        T_END=$(date +%s%3N)
        LATENCY=$(( T_END - T_START ))
        TOTAL_LATENCY=$(( TOTAL_LATENCY + LATENCY ))

        if [ -z "$RESPONSE" ]; then
            log "  [$i] TIMEOUT/ERROR | prompt='${PROMPT}' expected='${EXPECTED}' latency=${LATENCY}ms"
            continue
        fi

        ANSWER=$(echo "$RESPONSE" | jq -r '.response // ""' 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        EXPECTED_LOWER=$(echo "$EXPECTED" | tr '[:upper:]' '[:lower:]')

        if [ "$ANSWER" = "$EXPECTED_LOWER" ]; then
            CORRECT=$(( CORRECT + 1 ))
            log "  [$i] OK    | prompt='${PROMPT}' expected='${EXPECTED}' got='${ANSWER}' latency=${LATENCY}ms"
        else
            log "  [$i] FAIL  | prompt='${PROMPT}' expected='${EXPECTED}' got='${ANSWER}' latency=${LATENCY}ms"
        fi
    done

    AVG_LATENCY=$(( TOTAL_LATENCY / TOTAL ))
    log "Model ${MODEL}: score=${CORRECT}/${TOTAL} avg_latency=${AVG_LATENCY}ms"

    # Pick best: higher score wins; on tie, lower latency wins
    if [ "$CORRECT" -gt "$BEST_SCORE" ] || { [ "$CORRECT" -eq "$BEST_SCORE" ] && [ "$AVG_LATENCY" -lt "$BEST_LATENCY" ]; }; then
        BEST_SCORE="$CORRECT"
        BEST_LATENCY="$AVG_LATENCY"
        BEST_MODEL="$MODEL"
    fi
done

if [ -z "$BEST_MODEL" ]; then
    log "ERROR: no model produced valid responses — falling back to first model"
    BEST_MODEL="${MODELS[0]}"
fi

# Write state file: model + metadata for 24h validity
TIMESTAMP=$(date -Iseconds)
EXPIRES=$(date -d "+24 hours" -Iseconds 2>/dev/null || date -d "24 hours" -Iseconds 2>/dev/null || echo "")
{
    echo "model=${BEST_MODEL}"
    echo "score=${BEST_SCORE}"
    echo "latency_ms=${BEST_LATENCY}"
    echo "timestamp=${TIMESTAMP}"
    echo "expires=${EXPIRES}"
} > "${STATE_FILE}.tmp"
mv "${STATE_FILE}.tmp" "$STATE_FILE"

log "WINNER: ${BEST_MODEL} (score=${BEST_SCORE}, avg_latency=${BEST_LATENCY}ms) → ${STATE_FILE}"
echo "$BEST_MODEL"
