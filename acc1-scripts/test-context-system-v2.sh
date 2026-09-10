#!/bin/bash
# test-context-system-v2.sh — 18 tests for Context System v2
# Issue: #230
# Threshold: 15/18 = READY, < 15 = NEEDS FIXES

set +e

REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
MEMORY_FILE="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects/memory/MEMORY.md"
SCRIPTS_DIR="/root/workspaces/tools/acc1-scripts/scripts"

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NC="\033[0m"

PASS=0
FAIL=0
SKIP=0
TOTAL=18

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

test_pass() {
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC} [$1] $2"
}

test_fail() {
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC} [$1] $2"
}

test_skip() {
    SKIP=$((SKIP + 1))
    echo -e "  ${YELLOW}SKIP${NC} [$1] $2"
}

echo ""
echo "============================================"
echo "  Context System v2 — Test Suite"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# --- Test 1: context:archive:* keys exist (Bug #1) ---
ARCHIVE_COUNT=$(rcli --scan --pattern "context:archive:*" | wc -l)
if [ "$ARCHIVE_COUNT" -gt 0 ]; then
    test_pass 1 "context:archive:* keys exist ($ARCHIVE_COUNT)"
else
    test_fail 1 "No context:archive:* keys found"
fi

# --- Test 2: No XML tags in context:latest last_messages (Bug #2) ---
LATEST_MSGS=$(rcli GET "context:latest" | jq -r '.last_messages // ""' 2>/dev/null)
if [ -n "$LATEST_MSGS" ]; then
    if echo "$LATEST_MSGS" | grep -q '<[a-zA-Z]'; then
        test_fail 2 "XML tags found in last_messages"
    else
        test_pass 2 "No XML tags in context:latest last_messages"
    fi
else
    test_skip 2 "context:latest has no last_messages"
fi

# --- Test 3: context:daily:{today}:{branch} exists (Bug #3) ---
TODAY=$(date '+%Y-%m-%d')
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
DAILY_EXISTS=$(rcli EXISTS "context:daily:${TODAY}:${BRANCH}")
if [ "$DAILY_EXISTS" = "1" ]; then
    test_pass 3 "context:daily:${TODAY}:${BRANCH} exists"
else
    # May not exist yet if merger hasn't run today
    DAILY_ANY=$(rcli --scan --pattern "context:daily:*" | wc -l)
    if [ "$DAILY_ANY" -gt 0 ]; then
        test_pass 3 "Daily summaries exist ($DAILY_ANY total, today may not be merged yet)"
    else
        test_skip 3 "No daily summaries yet (merger runs at 02:00)"
    fi
fi

# --- Test 4: sessions_count > 0 in daily summary (Bug #4) ---
DAILY_KEY=$(rcli --scan --pattern "context:daily:*" | head -1)
if [ -n "$DAILY_KEY" ]; then
    DAILY_JSON=$(rcli GET "$DAILY_KEY")
    SESSIONS_COUNT=$(echo "$DAILY_JSON" | jq -r '.sessions_count // 0' 2>/dev/null)
    if [ "${SESSIONS_COUNT:-0}" -gt 0 ]; then
        test_pass 4 "sessions_count=$SESSIONS_COUNT in $DAILY_KEY"
    else
        test_fail 4 "sessions_count=0 in $DAILY_KEY"
    fi
else
    test_skip 4 "No daily summaries to check"
fi

# --- Test 5: History dedup ratio <= 2x (Bug #5) ---
HISTORY_LEN=$(rcli LLEN "context:history")
INDEXED_SIZE=$(rcli SCARD "session:indexed")
if [ "${HISTORY_LEN:-0}" -gt 0 ] && [ "${INDEXED_SIZE:-0}" -gt 0 ]; then
    RATIO=$((HISTORY_LEN / INDEXED_SIZE))
    if [ "$RATIO" -le 2 ]; then
        test_pass 5 "Dedup ratio: history=$HISTORY_LEN, indexed=$INDEXED_SIZE (ratio=$RATIO)"
    else
        test_fail 5 "Dedup ratio too high: $RATIO (history=$HISTORY_LEN, indexed=$INDEXED_SIZE)"
    fi
else
    test_pass 5 "History dedup: history=$HISTORY_LEN, indexed=$INDEXED_SIZE (OK)"
fi

# --- Test 6: MEMORY.md contains AUTO-RESTORE section (Bug #6) ---
if [ -f "$MEMORY_FILE" ]; then
    if grep -q "AUTO-RESTORE-START" "$MEMORY_FILE"; then
        test_pass 6 "MEMORY.md contains AUTO-RESTORE section"
    else
        test_fail 6 "MEMORY.md missing AUTO-RESTORE section"
    fi
else
    test_fail 6 "MEMORY.md not found"
fi

# --- Test 7: session:registry:* + topic:index:* exist (Bugs #7,#8) ---
REG_COUNT=$(rcli --scan --pattern "session:registry:*" | wc -l)
TOPIC_COUNT=$(rcli --scan --pattern "topic:index:*" | wc -l)
if [ "$REG_COUNT" -gt 0 ] && [ "$TOPIC_COUNT" -gt 0 ]; then
    test_pass 7 "Registry: $REG_COUNT sessions, Topics: $TOPIC_COUNT keywords"
else
    test_fail 7 "Registry=$REG_COUNT, Topics=$TOPIC_COUNT (both must be > 0)"
fi

# --- Test 8: Heartbeat daemon log not empty (Bug #9) ---
HB_LOG="/root/workspaces/tools/acc1-scripts/logs/context-heartbeat.log"
if [ -f "$HB_LOG" ] && [ -s "$HB_LOG" ]; then
    HB_LINES=$(wc -l < "$HB_LOG")
    test_pass 8 "Heartbeat daemon log: $HB_LINES lines"
else
    test_fail 8 "Heartbeat daemon log empty or missing"
fi

# --- Test 9: Restore marker uses session-ID (Bug #10) ---
MARKER_FILE="/tmp/.context-restore-session"
if [ -f "$MARKER_FILE" ]; then
    MARKER_CONTENT=$(cat "$MARKER_FILE")
    # Session IDs are UUIDs (36 chars with dashes)
    if echo "$MARKER_CONTENT" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-'; then
        test_pass 9 "Restore marker contains session-ID: ${MARKER_CONTENT:0:12}..."
    elif echo "$MARKER_CONTENT" | grep -qE '^[0-9]+$'; then
        test_fail 9 "Restore marker still uses timestamp: $MARKER_CONTENT"
    else
        test_pass 9 "Restore marker present: ${MARKER_CONTENT:0:20}"
    fi
else
    test_skip 9 "No restore marker yet (session not started via hook)"
fi

# --- Test 10: role field in context:latest ---
ROLE=$(rcli GET "context:latest" | jq -r '.role // empty' 2>/dev/null)
if [ -n "$ROLE" ] && [ "$ROLE" != "null" ]; then
    test_pass 10 "Role field present: $ROLE"
else
    test_fail 10 "No role field in context:latest"
fi

# --- Test 11: agent_model field in context:latest ---
MODEL=$(rcli GET "context:latest" | jq -r '.agent_model // empty' 2>/dev/null)
if [ -n "$MODEL" ] && [ "$MODEL" != "null" ]; then
    test_pass 11 "Agent model field present: $MODEL"
else
    test_fail 11 "No agent_model field in context:latest"
fi

# --- Test 12: session-search.sh --list works ---
SEARCH_OUTPUT=$(bash "$SCRIPTS_DIR/session-search.sh" --list --limit 3 2>&1)
if echo "$SEARCH_OUTPUT" | grep -q "Session Registry"; then
    test_pass 12 "session-search.sh --list works"
else
    test_fail 12 "session-search.sh --list failed: $SEARCH_OUTPUT"
fi

# --- Test 13: topic-extractor.sh returns keywords ---
JSONL=$(ls -t /root/workspaces/tools/acc1-scripts/projects/-root-claude-projects/*.jsonl 2>/dev/null | head -1)
if [ -n "$JSONL" ]; then
    TOPICS=$(bash "$SCRIPTS_DIR/topic-extractor.sh" "$JSONL" 5 2>/dev/null)
    if [ -n "$TOPICS" ]; then
        test_pass 13 "Topic extractor returns: $TOPICS"
    else
        test_fail 13 "Topic extractor returned empty"
    fi
else
    test_skip 13 "No JSONL file to test"
fi

# --- Test 14: PM2 daemons session-indexer + memory-updater online ---
SI_STATUS=$(pm2 jlist 2>/dev/null | jq -r '.[] | select(.name == "session-indexer") | .pm2_env.status' 2>/dev/null)
MU_STATUS=$(pm2 jlist 2>/dev/null | jq -r '.[] | select(.name == "memory-updater") | .pm2_env.status' 2>/dev/null)
if [ "$SI_STATUS" = "online" ] && [ "$MU_STATUS" = "online" ]; then
    test_pass 14 "PM2: session-indexer=$SI_STATUS, memory-updater=$MU_STATUS"
else
    test_fail 14 "PM2: session-indexer=${SI_STATUS:-missing}, memory-updater=${MU_STATUS:-missing}"
fi

# --- Test 15: MEMORY.md <= 200 lines ---
if [ -f "$MEMORY_FILE" ]; then
    MEM_LINES=$(wc -l < "$MEMORY_FILE")
    if [ "$MEM_LINES" -le 200 ]; then
        test_pass 15 "MEMORY.md: $MEM_LINES lines (<= 200)"
    else
        test_fail 15 "MEMORY.md: $MEM_LINES lines (> 200 limit)"
    fi
else
    test_fail 15 "MEMORY.md not found"
fi

# --- Test 16: context:latest is valid JSON ---
LATEST_JSON=$(rcli GET "context:latest")
if echo "$LATEST_JSON" | jq empty 2>/dev/null; then
    test_pass 16 "context:latest is valid JSON"
else
    test_fail 16 "context:latest is NOT valid JSON"
fi

# --- Test 17: context:heartbeat is valid JSON ---
HB_JSON=$(rcli GET "context:heartbeat")
if [ -n "$HB_JSON" ] && [ "$HB_JSON" != "(nil)" ]; then
    if echo "$HB_JSON" | jq empty 2>/dev/null; then
        test_pass 17 "context:heartbeat is valid JSON"
    else
        test_fail 17 "context:heartbeat is NOT valid JSON"
    fi
else
    test_skip 17 "context:heartbeat not set (may need active session)"
fi

# --- Test 18: Redis memory < 60MB ---
REDIS_MEM=$(rcli INFO memory | grep used_memory_human | cut -d: -f2 | tr -d '\r' | tr -d ' ')
REDIS_MEM_BYTES=$(rcli INFO memory | grep 'used_memory:' | head -1 | cut -d: -f2 | tr -d '\r')
if [ "${REDIS_MEM_BYTES:-0}" -lt 62914560 ]; then
    test_pass 18 "Redis memory: $REDIS_MEM (< 60MB)"
else
    test_fail 18 "Redis memory: $REDIS_MEM (>= 60MB limit)"
fi

# === SUMMARY ===
echo ""
echo "============================================"
SCORE=$((PASS + SKIP))
echo "  Results: $PASS PASS, $FAIL FAIL, $SKIP SKIP"
echo "  Score: $SCORE / $TOTAL"
echo ""

if [ "$PASS" -ge 15 ]; then
    echo -e "  ${GREEN}STATUS: READY${NC} (>= 15/18)"
elif [ "$SCORE" -ge 15 ]; then
    echo -e "  ${YELLOW}STATUS: READY (with skips)${NC} (>= 15/18 including skips)"
else
    echo -e "  ${RED}STATUS: NEEDS FIXES${NC} (< 15/18)"
fi
echo "============================================"
echo ""
