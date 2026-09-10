#!/bin/bash
# Token usage tracker - logs token consumption to Redis and fires threshold alerts
# Usage: token-tracker.sh <agent_name> <model> <tokens_in> <tokens_out> <action>
# PostToolUse:Agent hook — advisory (exit 0 always, never blocks)
#
# Thresholds (per session):
#   WARN  — 500K tokens total
#   ALERT — 1M tokens total (Telegram to director)
#
# Session key: /tmp/.claude-session-id or CLAUDE_SESSION_ID env

set +euo pipefail

# ── Arguments ──
AGENT_NAME="${1:-unknown}"
MODEL="${2:-unknown}"
TOKENS_IN="${3:-0}"
TOKENS_OUT="${4:-0}"
ACTION="${5:-unknown}"

# ── Validation ──
if [[ ! "$TOKENS_IN" =~ ^[0-9]+$ ]] || [[ ! "$TOKENS_OUT" =~ ^[0-9]+$ ]]; then
    # Silent fail — advisory hook must never block
    exit 0
fi

# ── Session ID ──
SESSION_ID="${CLAUDE_SESSION_ID:-$(cat /tmp/.claude-session-id 2>/dev/null || echo 'default')}"
SESSION_SHORT="${SESSION_ID:0:12}"

# ── Date key ──
DATE_KEY=$(date +%Y-%m-%d)

# ── Redis keys ──
REDIS_KEY="tokens:${DATE_KEY}:${AGENT_NAME}:${MODEL}"
REDIS_ACTIONS_KEY="tokens:${DATE_KEY}:${AGENT_NAME}:${MODEL}:actions"
REDIS_SESSION_KEY="tokens:session:${SESSION_ID}"

# ── Increment per-agent counters in Redis ──
redis-cli HINCRBY "${REDIS_KEY}" "tokens_in" "${TOKENS_IN}" > /dev/null 2>&1
redis-cli HINCRBY "${REDIS_KEY}" "tokens_out" "${TOKENS_OUT}" > /dev/null 2>&1
redis-cli HINCRBY "${REDIS_KEY}" "count" 1 > /dev/null 2>&1
redis-cli EXPIRE "${REDIS_KEY}" 2592000 > /dev/null 2>&1

# ── Increment per-session totals ──
TOTAL_THIS_CALL=$(( TOKENS_IN + TOKENS_OUT ))
redis-cli HINCRBY "${REDIS_SESSION_KEY}" "tokens_in" "${TOKENS_IN}" > /dev/null 2>&1
redis-cli HINCRBY "${REDIS_SESSION_KEY}" "tokens_out" "${TOKENS_OUT}" > /dev/null 2>&1
redis-cli HINCRBY "${REDIS_SESSION_KEY}" "total" "${TOTAL_THIS_CALL}" > /dev/null 2>&1
redis-cli HINCRBY "${REDIS_SESSION_KEY}" "calls" 1 > /dev/null 2>&1
redis-cli EXPIRE "${REDIS_SESSION_KEY}" 86400 > /dev/null 2>&1

# ── Log action detail ──
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)
redis-cli RPUSH "${REDIS_ACTIONS_KEY}" "${TIMESTAMP}|${ACTION}|${TOKENS_IN}|${TOKENS_OUT}" > /dev/null 2>&1
redis-cli EXPIRE "${REDIS_ACTIONS_KEY}" 2592000 > /dev/null 2>&1

# ── Read session total ──
SESSION_TOTAL=$(redis-cli HGET "${REDIS_SESSION_KEY}" "total" 2>/dev/null || echo "0")
SESSION_TOTAL="${SESSION_TOTAL:-0}"
[[ ! "$SESSION_TOTAL" =~ ^[0-9]+$ ]] && SESSION_TOTAL=0

# ── Threshold constants ──
WARN_THRESHOLD=500000    # 500K — log warning
ALERT_THRESHOLD=1000000  # 1M   — log + Telegram

# ── Alert guard keys (fire once per session per threshold) ──
WARN_FIRED_KEY="tokens:alert:warn:${SESSION_ID}"
ALERT_FIRED_KEY="tokens:alert:alert:${SESSION_ID}"

if [[ "$SESSION_TOTAL" -ge "$ALERT_THRESHOLD" ]]; then
    ALREADY_FIRED=$(redis-cli GET "${ALERT_FIRED_KEY}" 2>/dev/null || echo "")
    if [[ -z "$ALREADY_FIRED" ]]; then
        redis-cli SET "${ALERT_FIRED_KEY}" "1" EX 86400 > /dev/null 2>&1

        LOG_FILE="/root/workspaces/tools/acc1-scripts/data/token-alerts.log"
        mkdir -p "/root/workspaces/tools/acc1-scripts/data"
        echo "[${TIMESTAMP}] ALERT: Session ${SESSION_SHORT} crossed 1M tokens. Total=${SESSION_TOTAL}. Agent=${AGENT_NAME} Model=${MODEL}" >> "$LOG_FILE"

        # Telegram alert — respects 3/day counter from consequence-guard
        TG_ENV="/root/workspaces/secrets/services/telegram.env"
        if [[ -f "$TG_ENV" ]]; then
            source "$TG_ENV" 2>/dev/null
            BOT_TOKEN="${NOTIFICATION_BOT_TOKEN:-}"
            CHAT_ID="${DIRECTOR_CHAT_ID:-}"
            if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
                TG_COUNTER="/tmp/.tg-curl-count-$(date +%Y%m%d)"
                TG_COUNT=$(cat "$TG_COUNTER" 2>/dev/null || echo "0")
                if [[ "$TG_COUNT" -lt 3 ]]; then
                    MSG="TOKEN ALERT%0ASessiya: ${SESSION_SHORT}%0AVsego tokenov: $(( SESSION_TOTAL / 1000 ))K / 1000K%0APosledniy agent: ${AGENT_NAME} (${MODEL})%0AVremya: ${TIMESTAMP}"
                    curl -s -m 5 \
                        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                        -d "chat_id=${CHAT_ID}&text=${MSG}" \
                        > /dev/null 2>&1
                    echo $(( TG_COUNT + 1 )) > "$TG_COUNTER"
                fi
            fi
        fi
    fi

elif [[ "$SESSION_TOTAL" -ge "$WARN_THRESHOLD" ]]; then
    ALREADY_WARN=$(redis-cli GET "${WARN_FIRED_KEY}" 2>/dev/null || echo "")
    if [[ -z "$ALREADY_WARN" ]]; then
        redis-cli SET "${WARN_FIRED_KEY}" "1" EX 86400 > /dev/null 2>&1

        LOG_FILE="/root/workspaces/tools/acc1-scripts/data/token-alerts.log"
        mkdir -p "/root/workspaces/tools/acc1-scripts/data"
        echo "[${TIMESTAMP}] WARN: Session ${SESSION_SHORT} crossed 500K tokens. Total=${SESSION_TOTAL}. Agent=${AGENT_NAME} Model=${MODEL}" >> "$LOG_FILE"
    fi
fi

# ── Debug mode ──
if [[ "${DEBUG:-0}" == "1" ]]; then
    TOTAL_IN=$(redis-cli HGET "${REDIS_KEY}" "tokens_in" 2>/dev/null)
    TOTAL_OUT=$(redis-cli HGET "${REDIS_KEY}" "tokens_out" 2>/dev/null)
    TOTAL_COUNT=$(redis-cli HGET "${REDIS_KEY}" "count" 2>/dev/null)
    echo "Logged: ${AGENT_NAME}/${MODEL} - ${ACTION}"
    echo "  In: ${TOKENS_IN} (total: ${TOTAL_IN})"
    echo "  Out: ${TOKENS_OUT} (total: ${TOTAL_OUT})"
    echo "  Calls: ${TOTAL_COUNT}"
    echo "  Session total: ${SESSION_TOTAL}"
fi

# Advisory hook — never block
exit 0
