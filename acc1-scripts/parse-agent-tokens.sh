#!/bin/bash
# parse-agent-tokens.sh
# Parse agent JSONL files and extract token usage statistics
# Save to Redis DB 5 and display summary

set -euo pipefail

REDIS_DB=5
RETENTION_SECONDS=2592000  # 30 days

# Color codes for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $(basename "$0") <path-to-agent-jsonl>

Parse agent JSONL file and extract token usage statistics.
Stores data in Redis DB 5 and displays summary.

Example:
    $(basename "$0") /tmp/claude-0/agent-a87a701.jsonl
    $(basename "$0") agent-a87a701.jsonl

EOF
    exit 1
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}" >&2
    echo "Install with: apt-get install jq" >&2
    exit 1
fi

# Check if redis-cli is available
if ! command -v redis-cli &> /dev/null; then
    echo -e "${RED}Error: redis-cli is required but not installed${NC}" >&2
    exit 1
fi

# Check arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No input file specified${NC}" >&2
    usage
fi

JSONL_FILE="$1"

# Check if file exists
if [ ! -f "$JSONL_FILE" ]; then
    echo -e "${RED}Error: File not found: $JSONL_FILE${NC}" >&2
    exit 1
fi

# Extract agent ID from filename (agent-XXXXX.jsonl)
AGENT_ID=$(basename "$JSONL_FILE" | sed -n 's/^agent-\([^.]*\)\.jsonl$/\1/p')
if [ -z "$AGENT_ID" ]; then
    echo -e "${YELLOW}Warning: Could not extract agent ID from filename${NC}" >&2
    AGENT_ID="unknown-$(date +%s)"
fi

# Get current date
DATE=$(date +%Y-%m-%d)

# Initialize counters
total_input=0
total_output=0
total_cache_read=0
total_cache_write=0
detected_model=""
message_count=0

# Parse JSONL file
while IFS= read -r line; do
    # Skip empty lines
    if [ -z "$line" ]; then
        continue
    fi

    # Extract usage data from message.usage or usage field
    usage_data=$(echo "$line" | jq -r '.message.usage // .usage // empty' 2>/dev/null || echo "")

    if [ -n "$usage_data" ] && [ "$usage_data" != "null" ]; then
        # Extract token counts
        input=$(echo "$usage_data" | jq -r '.input_tokens // 0' 2>/dev/null || echo 0)
        output=$(echo "$usage_data" | jq -r '.output_tokens // 0' 2>/dev/null || echo 0)
        cache_read=$(echo "$usage_data" | jq -r '.cache_read_input_tokens // 0' 2>/dev/null || echo 0)
        cache_write=$(echo "$usage_data" | jq -r '.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)

        # Accumulate totals
        total_input=$((total_input + input))
        total_output=$((total_output + output))
        total_cache_read=$((total_cache_read + cache_read))
        total_cache_write=$((total_cache_write + cache_write))
        message_count=$((message_count + 1))
    fi

    # Try to detect model from various possible fields
    if [ -z "$detected_model" ]; then
        model_raw=$(echo "$line" | jq -r '.message.model // .model // .metadata.model // empty' 2>/dev/null || echo "")

        if [[ "$model_raw" =~ opus ]]; then
            detected_model="opus"
        elif [[ "$model_raw" =~ sonnet ]]; then
            detected_model="sonnet"
        elif [[ "$model_raw" =~ haiku ]]; then
            detected_model="haiku"
        fi
    fi
done < "$JSONL_FILE"

# Check if we found any usage data
if [ $message_count -eq 0 ]; then
    echo -e "${YELLOW}Warning: No usage data found in file${NC}" >&2
    echo "This might not be a valid agent JSONL file with token usage data" >&2
    exit 1
fi

# Default to sonnet if model not detected
if [ -z "$detected_model" ]; then
    echo -e "${YELLOW}Warning: Could not detect model, defaulting to 'sonnet'${NC}" >&2
    detected_model="sonnet"
fi

# Calculate cost based on model pricing (per million tokens)
# Opus: $15/M input, $75/M output
# Sonnet: $3/M input, $15/M output
# Haiku: $0.25/M input, $1.25/M output
case "$detected_model" in
    opus)
        input_price=15
        output_price=75
        ;;
    sonnet)
        input_price=3
        output_price=15
        ;;
    haiku)
        input_price=0.25
        output_price=1.25
        ;;
    *)
        echo -e "${YELLOW}Warning: Unknown model '$detected_model', using sonnet pricing${NC}" >&2
        input_price=3
        output_price=15
        ;;
esac

# Calculate cost (tokens / 1,000,000 * price)
input_cost=$(echo "scale=6; $total_input / 1000000 * $input_price" | bc)
output_cost=$(echo "scale=6; $total_output / 1000000 * $output_price" | bc)
total_cost=$(echo "scale=4; $input_cost + $output_cost" | bc)

# Format numbers with commas
format_number() {
    printf "%'d" "$1"
}

# Store in Redis DB 5
redis-cli -n $REDIS_DB HSET "tokens:agent:$AGENT_ID:$DATE" \
    input_tokens "$total_input" \
    output_tokens "$total_output" \
    cache_read "$total_cache_read" \
    cache_write "$total_cache_write" \
    model "$detected_model" \
    cost_usd "$total_cost" \
    message_count "$message_count" \
    timestamp "$(date +%s)" \
    > /dev/null

# Set expiration (30 days)
redis-cli -n $REDIS_DB EXPIRE "tokens:agent:$AGENT_ID:$DATE" $RETENTION_SECONDS > /dev/null

# Update daily model totals
redis-cli -n $REDIS_DB HINCRBY "tokens:model:$detected_model:$DATE" total_input "$total_input" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "tokens:model:$detected_model:$DATE" total_output "$total_output" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "tokens:model:$detected_model:$DATE" total_cache_read "$total_cache_read" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "tokens:model:$detected_model:$DATE" total_cache_write "$total_cache_write" > /dev/null
redis-cli -n $REDIS_DB HINCRBYFLOAT "tokens:model:$detected_model:$DATE" total_cost "$total_cost" > /dev/null
redis-cli -n $REDIS_DB EXPIRE "tokens:model:$detected_model:$DATE" $RETENTION_SECONDS > /dev/null

# Update global daily totals
redis-cli -n $REDIS_DB HINCRBY "tokens:global:$DATE" total_input "$total_input" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "tokens:global:$DATE" total_output "$total_output" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "tokens:global:$DATE" total_cache_read "$total_cache_read" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "tokens:global:$DATE" total_cache_write "$total_cache_write" > /dev/null
redis-cli -n $REDIS_DB HINCRBYFLOAT "tokens:global:$DATE" total_cost "$total_cost" > /dev/null
redis-cli -n $REDIS_DB EXPIRE "tokens:global:$DATE" $RETENTION_SECONDS > /dev/null

# Display formatted output
echo ""
echo -e "${CYAN}📊 Agent Token Stats: ${GREEN}$AGENT_ID${NC}"
echo "─────────────────────────────────"
echo -e "${CYAN}Model:${NC}        $detected_model"
echo -e "${CYAN}Input:${NC}        $(format_number $total_input) tokens"
echo -e "${CYAN}Output:${NC}       $(format_number $total_output) tokens"
echo -e "${CYAN}Cache Read:${NC}   $(format_number $total_cache_read) tokens"
echo -e "${CYAN}Cache Write:${NC}  $(format_number $total_cache_write) tokens"
echo -e "${CYAN}Messages:${NC}     $message_count"
echo -e "${CYAN}Est. Cost:${NC}    \$$total_cost"
echo "─────────────────────────────────"
echo -e "${GREEN}✓ Saved to Redis DB $REDIS_DB${NC}"
echo ""

# Show Redis keys created
echo -e "${CYAN}Redis keys:${NC}"
echo "  tokens:agent:$AGENT_ID:$DATE"
echo "  tokens:model:$detected_model:$DATE"
echo "  tokens:global:$DATE"
echo ""

exit 0
