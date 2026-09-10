#!/bin/bash
# Test Context Boundary - определение минимального контекста для recovery
# Генерирует тестовые данные разных уровней для оценки

REDIS_HOST="127.0.0.1"
SESSION_KEY=$(redis-cli GET session:latest)

echo "============================================"
echo "  CONTEXT BOUNDARY TEST"
echo "  Session: $SESSION_KEY"
echo "============================================"
echo ""

# Получаем данные из Redis
ISSUES=$(redis-cli HGET "$SESSION_KEY" issues)
BRANCH=$(redis-cli HGET "$SESSION_KEY" branch)
UNCOMMITTED=$(redis-cli HGET "$SESSION_KEY" uncommitted)
LAST_ASK=$(redis-cli HGET "$SESSION_KEY" last_ask)
CONV_FILE=$(redis-cli HGET "$SESSION_KEY" file)
MSG_COUNT=$(redis-cli HGET "$SESSION_KEY" msgs)

echo "=== LEVEL 0: Minimal (~10 tokens) ==="
echo "issues: $ISSUES"
echo ""
echo "Tokens estimate: ~10"
echo "---"
echo ""

echo "=== LEVEL 1: Basic (~50 tokens) ==="
echo "issues: $ISSUES"
echo "branch: $BRANCH"
echo "uncommitted: $UNCOMMITTED"
echo "total_msgs: $MSG_COUNT"
echo ""
echo "Tokens estimate: ~50"
echo "---"
echo ""

echo "=== LEVEL 2: With Last Ask (~100 tokens) ==="
echo "issues: $ISSUES"
echo "branch: $BRANCH"
echo "uncommitted: $UNCOMMITTED"
echo "last_ask: ${LAST_ASK:0:200}"
echo ""
echo "Tokens estimate: ~100"
echo "---"
echo ""

echo "=== LEVEL 3: Last 5 Messages (~300 tokens) ==="
echo "issues: $ISSUES"
echo "branch: $BRANCH"
echo "last_messages:"
if [[ -f "$CONV_FILE" ]]; then
    tail -5 "$CONV_FILE" | jq -r '
        if .message.role then
            "[\(.message.role)] \(.message.content // .display | tostring | .[0:150])"
        else
            "[user] \(.display // "" | .[0:150])"
        end
    ' 2>/dev/null
fi
echo ""
echo "Tokens estimate: ~300"
echo "---"
echo ""

echo "=== LEVEL 4: Last 15 Messages (~500 tokens) ==="
echo "issues: $ISSUES"
echo "branch: $BRANCH"
echo "last_messages:"
if [[ -f "$CONV_FILE" ]]; then
    tail -15 "$CONV_FILE" | jq -r '
        if .message.role then
            "[\(.message.role | .[0:4])] \(.message.content // .display | tostring | .[0:80])..."
        else
            "[user] \(.display // "" | .[0:80])..."
        end
    ' 2>/dev/null
fi
echo ""
echo "Tokens estimate: ~500"
echo "---"
echo ""

echo "=== LEVEL 5: Last 30 Messages (~1000 tokens) ==="
echo "issues: $ISSUES"
echo "branch: $BRANCH"
echo "msg_count: $(tail -30 "$CONV_FILE" | wc -l)"
echo "(Full output: tail -30 $CONV_FILE)"
echo ""
echo "Tokens estimate: ~1000"
echo "---"
echo ""

echo "============================================"
echo "  TEST QUESTIONS FOR EACH LEVEL:"
echo "============================================"
echo ""
echo "После получения контекста уровня LX, агент должен ответить:"
echo ""
echo "1. Какой проект/задача была в работе?"
echo "2. Что было последним действием?"
echo "3. Какие issues открыты и приоритетны?"
echo "4. Можешь продолжить работу без дополнительных вопросов?"
echo ""
echo "SCORING:"
echo "  4/4 правильно = уровень ДОСТАТОЧЕН"
echo "  3/4 = уровень МИНИМАЛЕН"
echo "  <3/4 = уровень НЕДОСТАТОЧЕН"
echo ""
echo "============================================"
