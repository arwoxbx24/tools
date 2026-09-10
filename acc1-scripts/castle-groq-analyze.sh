#!/bin/bash
# CASTLE: Use Groq AI to generate smart summary
# Requires: /root/workspaces/tools/acc1-scripts/scripts/groq-client.sh

TODAY=$(date +%Y-%m-%d)
GROQ_SCRIPT="/root/workspaces/tools/acc1-scripts/scripts/groq-client.sh"

# Get raw data
LINES=$(redis-cli -n 4 HGET "castle:lines:$TODAY" "total" 2>/dev/null || echo 0)
FILES=$(redis-cli -n 4 HGET "castle:files:$TODAY" "count" 2>/dev/null || echo 0)
TOKENS_IN=$(redis-cli -n 5 HGET "castle:tokens:$TODAY" "input" 2>/dev/null || echo 0)
TOKENS_OUT=$(redis-cli -n 5 HGET "castle:tokens:$TODAY" "output" 2>/dev/null || echo 0)

# Handle null values
[ -z "$LINES" ] || [ "$LINES" = "(nil)" ] && LINES=0
[ -z "$FILES" ] || [ "$FILES" = "(nil)" ] && FILES=0
[ -z "$TOKENS_IN" ] || [ "$TOKENS_IN" = "(nil)" ] && TOKENS_IN=0
[ -z "$TOKENS_OUT" ] || [ "$TOKENS_OUT" = "(nil)" ] && TOKENS_OUT=0

# Calculate cost (Opus pricing: $15/M input, $75/M output)
COST=$(echo "scale=4; ($TOKENS_IN * 0.015 + $TOKENS_OUT * 0.075) / 1000" | bc 2>/dev/null || echo "0")

# Get per-language breakdown
PY=$(redis-cli -n 4 HGET "castle:lines:$TODAY" "py" 2>/dev/null || echo 0)
JS=$(redis-cli -n 4 HGET "castle:lines:$TODAY" "js" 2>/dev/null || echo 0)
PHP=$(redis-cli -n 4 HGET "castle:lines:$TODAY" "php" 2>/dev/null || echo 0)
SH=$(redis-cli -n 4 HGET "castle:lines:$TODAY" "sh" 2>/dev/null || echo 0)

# Prepare prompt for Groq
PROMPT="Generate a brief productivity summary in Russian (2-3 sentences) for today's coding session:
- Total lines written: $LINES
- Files modified: $FILES
- Python: $PY lines, JavaScript: $JS lines, PHP: $PHP lines, Shell: $SH lines
- Tokens used: input=$TOKENS_IN, output=$TOKENS_OUT
- API cost: \$$COST

Focus on productivity highlights and efficiency."

# Check if Groq client exists
if [ -x "$GROQ_SCRIPT" ]; then
    "$GROQ_SCRIPT" "$PROMPT"
else
    echo "Groq client not available. Raw data:"
    echo "Lines: $LINES | Files: $FILES | Tokens: $((TOKENS_IN + TOKENS_OUT)) | Cost: \$$COST"
fi
