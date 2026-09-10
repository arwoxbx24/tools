#!/usr/bin/env bash

# Token statistics monitoring script
# Part of EPIC #38 - System optimization and token efficiency
# Issue: #48

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

CLAUDE_JSON="/root/workspaces/tools/acc1-scripts/.claude.json"
PROJECT_PATH="${1:-/root/claude-projects}"

# Check if .claude.json exists
if [[ ! -f "$CLAUDE_JSON" ]]; then
    echo -e "${RED}Error: $CLAUDE_JSON not found${NC}"
    exit 1
fi

# Function to format numbers with commas
format_number() {
    printf "%'d" "$1" 2>/dev/null || echo "$1"
}

# Function to get color based on cost
get_cost_color() {
    local cost=$1
    if (( $(echo "$cost < 1" | bc -l) )); then
        echo "$GREEN"
    elif (( $(echo "$cost < 10" | bc -l) )); then
        echo "$YELLOW"
    else
        echo "$RED"
    fi
}

# Function to calculate context percentage (rough estimate)
get_context_percentage() {
    local input_tokens=$1
    local max_context=200000  # Claude's context window
    local percentage=$(echo "scale=0; ($input_tokens * 100) / $max_context" | bc -l)
    echo "$percentage"
}

# Function to get context color
get_context_color() {
    local pct=$1
    if (( pct < 65 )); then
        echo "$GREEN"
    elif (( pct < 85 )); then
        echo "$YELLOW"
    else
        echo "$RED"
    fi
}

# Extract project data using jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    exit 1
fi

# Parse project stats
project_stats=$(jq -r --arg proj "$PROJECT_PATH" '
    .projects[$proj] // empty
' "$CLAUDE_JSON")

if [[ -z "$project_stats" ]]; then
    echo -e "${RED}Error: No stats found for project: $PROJECT_PATH${NC}"
    echo -e "${YELLOW}Available projects:${NC}"
    jq -r '.projects | keys[]' "$CLAUDE_JSON"
    exit 1
fi

# Get total tokens and cost
total_input=$(echo "$project_stats" | jq -r '.lastTotalInputTokens // 0')
total_output=$(echo "$project_stats" | jq -r '.lastTotalOutputTokens // 0')
total_cost=$(echo "$project_stats" | jq -r '.lastCost // 0')

# Get model usage breakdown
model_usage=$(echo "$project_stats" | jq -r '.lastModelUsage // {}')

# Model name mapping for display
declare -A model_names=(
    ["claude-opus-4-5-20251101"]="opus"
    ["claude-sonnet-4-5-20250929"]="sonnet"
    ["claude-haiku-4-5-20251001"]="haiku"
)

# Print header
echo ""
echo -e "${BOLD}${CYAN}=== TOKEN STATS ===${NC}"
echo -e "${BOLD}Project:${NC} $PROJECT_PATH"
echo ""

# Print table header
printf "%-12s | %-10s | %-10s | %-10s\n" "Model" "Input" "Output" "Cost USD"
echo "-------------|------------|------------|------------"

# Arrays to store totals
declare -A model_totals

# Parse and display each model
for full_model in claude-opus-4-5-20251101 claude-sonnet-4-5-20250929 claude-haiku-4-5-20251001; do
    model_display="${model_names[$full_model]}"

    # Get model stats
    model_data=$(echo "$model_usage" | jq -r --arg model "$full_model" '.[$model] // empty')

    if [[ -n "$model_data" ]]; then
        input=$(echo "$model_data" | jq -r '.inputTokens // 0')
        output=$(echo "$model_data" | jq -r '.outputTokens // 0')
        cost=$(echo "$model_data" | jq -r '.costUSD // 0')

        # Store in totals
        model_totals[$model_display,input]=$input
        model_totals[$model_display,output]=$output
        model_totals[$model_display,cost]=$cost

        # Format numbers
        input_fmt=$(format_number "$input")
        output_fmt=$(format_number "$output")
        cost_color=$(get_cost_color "$cost")
        cost_fmt=$(printf "%.2f" "$cost")

        # Print row with color
        printf "%-12s | %-10s | %-10s | ${cost_color}%-10s${NC}\n" \
            "$model_display" \
            "$input_fmt" \
            "$output_fmt" \
            "\$$cost_fmt"
    else
        # Model not used
        printf "%-12s | %-10s | %-10s | %-10s\n" "$model_display" "-" "-" "-"
    fi
done

# Print separator
echo "-------------|------------|------------|------------"

# Print totals
total_input_fmt=$(format_number "$total_input")
total_output_fmt=$(format_number "$total_output")
total_cost_color=$(get_cost_color "$total_cost")
total_cost_fmt=$(printf "%.2f" "$total_cost")

printf "${BOLD}%-12s | %-10s | %-10s | ${total_cost_color}%-10s${NC}\n" \
    "TOTAL" \
    "$total_input_fmt" \
    "$total_output_fmt" \
    "\$$total_cost_fmt"

echo ""

# Calculate and display context usage
context_pct=$(get_context_percentage "$total_input")
context_color=$(get_context_color "$context_pct")

echo -e "${BOLD}Context:${NC} ${context_color}~${context_pct}% used${NC}"

# Additional stats if available
cache_read=$(echo "$project_stats" | jq -r '.lastTotalCacheReadInputTokens // 0')
cache_creation=$(echo "$project_stats" | jq -r '.lastTotalCacheCreationInputTokens // 0')

if [[ "$cache_read" -gt 0 ]] || [[ "$cache_creation" -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}=== CACHE STATS ===${NC}"
    echo -e "Cache Read:     $(format_number "$cache_read") tokens"
    echo -e "Cache Creation: $(format_number "$cache_creation") tokens"
fi

# Show duration stats
api_duration=$(echo "$project_stats" | jq -r '.lastAPIDuration // 0')
tool_duration=$(echo "$project_stats" | jq -r '.lastToolDuration // 0')

if [[ "$api_duration" -gt 0 ]]; then
    api_duration_sec=$(echo "scale=2; $api_duration / 1000" | bc -l)
    echo ""
    echo -e "${BOLD}${CYAN}=== DURATION STATS ===${NC}"
    echo -e "API Duration:  ${api_duration_sec}s"

    if [[ "$tool_duration" -gt 0 ]]; then
        tool_duration_sec=$(echo "scale=2; $tool_duration / 1000" | bc -l)
        echo -e "Tool Duration: ${tool_duration_sec}s"
    fi
fi

echo ""
