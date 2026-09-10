#!/usr/bin/env bash
# Agent Metrics Report - Unified view of all agent activity
# Aggregates data from Redis DBs 4 (code), 5 (tokens), 6 (worktime)
# Part of agent compliance and monitoring system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Pricing per 1M tokens (as of Jan 2025)
declare -A PRICE_INPUT=(
    ["opus"]="15.00"
    ["sonnet"]="3.00"
    ["haiku"]="0.80"
)
declare -A PRICE_OUTPUT=(
    ["opus"]="75.00"
    ["sonnet"]="15.00"
    ["haiku"]="4.00"
)
declare -A PRICE_CACHE_WRITE=(
    ["opus"]="18.75"
    ["sonnet"]="3.75"
    ["haiku"]="1.00"
)
declare -A PRICE_CACHE_READ=(
    ["opus"]="1.50"
    ["sonnet"]="0.30"
    ["haiku"]="0.08"
)

# Model name mapping
declare -A MODEL_NAMES=(
    ["claude-opus-4-5-20251101"]="opus"
    ["claude-sonnet-4-5-20250929"]="sonnet"
    ["claude-haiku-4-5-20251001"]="haiku"
)

# Default values
DATE=$(date +%Y-%m-%d)
OUTPUT_FORMAT="table"
DAYS=1

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --date)
            DATE="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --days)
            DAYS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --date YYYY-MM-DD   Specific date (default: today)"
            echo "  --json              Output as JSON instead of table"
            echo "  --days N            Show last N days summary"
            echo "  -h, --help          Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
format_number() {
    local num=$1
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        printf "%'d" "$num"
    else
        echo "$num"
    fi
}

format_duration() {
    local sec=$1
    if [[ ! "$sec" =~ ^[0-9]+$ ]]; then
        echo "0s"
        return
    fi

    if [ "$sec" -lt 60 ]; then
        echo "${sec}s"
    elif [ "$sec" -lt 3600 ]; then
        printf "%dm %ds" $((sec/60)) $((sec%60))
    else
        printf "%dh %02dm" $((sec/3600)) $((sec%3600/60))
    fi
}

calculate_cost() {
    local model=$1
    local input=$2
    local output=$3
    local cache_write=${4:-0}
    local cache_read=${5:-0}

    # Convert to millions
    local input_m=$(echo "scale=6; $input / 1000000" | bc -l)
    local output_m=$(echo "scale=6; $output / 1000000" | bc -l)
    local cache_write_m=$(echo "scale=6; $cache_write / 1000000" | bc -l)
    local cache_read_m=$(echo "scale=6; $cache_read / 1000000" | bc -l)

    # Calculate cost components
    local cost_input=$(echo "scale=4; $input_m * ${PRICE_INPUT[$model]}" | bc -l)
    local cost_output=$(echo "scale=4; $output_m * ${PRICE_OUTPUT[$model]}" | bc -l)
    local cost_cache_w=$(echo "scale=4; $cache_write_m * ${PRICE_CACHE_WRITE[$model]}" | bc -l)
    local cost_cache_r=$(echo "scale=4; $cache_read_m * ${PRICE_CACHE_READ[$model]}" | bc -l)

    # Total
    echo "scale=4; $cost_input + $cost_output + $cost_cache_w + $cost_cache_r" | bc -l
}

# Get date range
if [ "$DAYS" -gt 1 ]; then
    DATE_START=$(date -d "$DATE - $((DAYS - 1)) days" +%Y-%m-%d)
    DATE_END="$DATE"
else
    DATE_START="$DATE"
    DATE_END="$DATE"
fi

# Collect data from Redis
declare -A token_data
declare -A code_data
declare -A worktime_data

# DB 4: Code stats (code:model:date)
for model in opus sonnet haiku; do
    current_date="$DATE_START"
    total_added=0
    total_deleted=0
    total_files=0
    total_commits=0

    while [[ "$current_date" < "$DATE_END" ]] || [[ "$current_date" == "$DATE_END" ]]; do
        key="code:${model}:${current_date}"
        if redis-cli -n 4 EXISTS "$key" | grep -q "1"; then
            added=$(redis-cli -n 4 HGET "$key" lines_added 2>/dev/null || echo "0")
            deleted=$(redis-cli -n 4 HGET "$key" lines_deleted 2>/dev/null || echo "0")
            files=$(redis-cli -n 4 HGET "$key" files_changed 2>/dev/null || echo "0")
            commits=$(redis-cli -n 4 HGET "$key" commits 2>/dev/null || echo "0")

            total_added=$((total_added + ${added:-0}))
            total_deleted=$((total_deleted + ${deleted:-0}))
            total_files=$((total_files + ${files:-0}))
            total_commits=$((total_commits + ${commits:-0}))
        fi
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done

    code_data[$model,added]=$total_added
    code_data[$model,deleted]=$total_deleted
    code_data[$model,files]=$total_files
    code_data[$model,commits]=$total_commits
done

# DB 5: Token stats (tokens:model:date)
# Note: This DB may not be populated yet - placeholder for future implementation
for model in opus sonnet haiku; do
    current_date="$DATE_START"
    total_input=0
    total_output=0
    total_cache_write=0
    total_cache_read=0

    while [[ "$current_date" < "$DATE_END" ]] || [[ "$current_date" == "$DATE_END" ]]; do
        key="tokens:${model}:${current_date}"
        if redis-cli -n 5 EXISTS "$key" | grep -q "1"; then
            input=$(redis-cli -n 5 HGET "$key" input 2>/dev/null || echo "0")
            output=$(redis-cli -n 5 HGET "$key" output 2>/dev/null || echo "0")
            cache_w=$(redis-cli -n 5 HGET "$key" cache_write 2>/dev/null || echo "0")
            cache_r=$(redis-cli -n 5 HGET "$key" cache_read 2>/dev/null || echo "0")

            total_input=$((total_input + ${input:-0}))
            total_output=$((total_output + ${output:-0}))
            total_cache_write=$((total_cache_write + ${cache_w:-0}))
            total_cache_read=$((total_cache_read + ${cache_r:-0}))
        fi
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done

    token_data[$model,input]=$total_input
    token_data[$model,output]=$total_output
    token_data[$model,cache_write]=$total_cache_write
    token_data[$model,cache_read]=$total_cache_read
done

# DB 6: Work time (worktime:model:date)
# Note: This DB may not be populated yet - placeholder for future implementation
for model in opus sonnet haiku; do
    current_date="$DATE_START"
    total_time=0
    session_count=0
    max_duration=0
    min_duration=999999

    while [[ "$current_date" < "$DATE_END" ]] || [[ "$current_date" == "$DATE_END" ]]; do
        key="worktime:${model}:${current_date}"
        if redis-cli -n 6 EXISTS "$key" | grep -q "1"; then
            time=$(redis-cli -n 6 HGET "$key" total_seconds 2>/dev/null || echo "0")
            sessions=$(redis-cli -n 6 HGET "$key" sessions 2>/dev/null || echo "0")
            max_dur=$(redis-cli -n 6 HGET "$key" max_duration 2>/dev/null || echo "0")
            min_dur=$(redis-cli -n 6 HGET "$key" min_duration 2>/dev/null || echo "999999")

            total_time=$((total_time + ${time:-0}))
            session_count=$((session_count + ${sessions:-0}))
            [ "${max_dur:-0}" -gt "$max_duration" ] && max_duration=${max_dur:-0}
            [ "${min_dur:-999999}" -lt "$min_duration" ] && [ "${min_dur:-999999}" -gt 0 ] && min_duration=${min_dur:-999999}
        fi
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done

    worktime_data[$model,total]=$total_time
    worktime_data[$model,sessions]=$session_count
    worktime_data[$model,max]=$max_duration
    worktime_data[$model,min]=$((min_duration == 999999 ? 0 : min_duration))
done

# Fallback: Get data from .claude.json if Redis is empty
CLAUDE_JSON="/root/workspaces/tools/acc1-scripts/.claude.json"
PROJECT_PATH="/root/claude-projects"

if [ -f "$CLAUDE_JSON" ]; then
    project_stats=$(jq -r --arg proj "$PROJECT_PATH" '.projects[$proj] // empty' "$CLAUDE_JSON" 2>/dev/null || echo "")

    if [ -n "$project_stats" ]; then
        # Parse model usage
        for full_model in "${!MODEL_NAMES[@]}"; do
            model="${MODEL_NAMES[$full_model]}"
            model_data=$(echo "$project_stats" | jq -r --arg model "$full_model" '.lastModelUsage[$model] // empty' 2>/dev/null || echo "")

            if [ -n "$model_data" ]; then
                input=$(echo "$model_data" | jq -r '.inputTokens // 0')
                output=$(echo "$model_data" | jq -r '.outputTokens // 0')

                # Only use if Redis data is zero
                if [ "${token_data[$model,input]:-0}" -eq 0 ]; then
                    token_data[$model,input]=$input
                    token_data[$model,output]=$output
                fi
            fi
        done
    fi
fi

# Output as JSON
if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo "{"
    echo "  \"report_date\": \"$DATE\","
    echo "  \"date_range\": {"
    echo "    \"start\": \"$DATE_START\","
    echo "    \"end\": \"$DATE_END\","
    echo "    \"days\": $DAYS"
    echo "  },"
    echo "  \"tokens\": {"

    first_model=true
    for model in opus sonnet haiku; do
        [ "$first_model" = false ] && echo ","
        first_model=false

        input=${token_data[$model,input]:-0}
        output=${token_data[$model,output]:-0}
        cache_w=${token_data[$model,cache_write]:-0}
        cache_r=${token_data[$model,cache_read]:-0}
        cost=$(calculate_cost "$model" "$input" "$output" "$cache_w" "$cache_r")

        echo "    \"$model\": {"
        echo "      \"input\": $input,"
        echo "      \"output\": $output,"
        echo "      \"cache_write\": $cache_w,"
        echo "      \"cache_read\": $cache_r,"
        echo "      \"cost_usd\": $cost"
        echo -n "    }"
    done

    echo ""
    echo "  },"
    echo "  \"code\": {"

    first_model=true
    for model in opus sonnet haiku; do
        [ "$first_model" = false ] && echo ","
        first_model=false

        echo "    \"$model\": {"
        echo "      \"lines_added\": ${code_data[$model,added]:-0},"
        echo "      \"lines_deleted\": ${code_data[$model,deleted]:-0},"
        echo "      \"files_changed\": ${code_data[$model,files]:-0},"
        echo "      \"commits\": ${code_data[$model,commits]:-0}"
        echo -n "    }"
    done

    echo ""
    echo "  },"
    echo "  \"worktime\": {"

    first_model=true
    for model in opus sonnet haiku; do
        [ "$first_model" = false ] && echo ","
        first_model=false

        total=${worktime_data[$model,total]:-0}
        sessions=${worktime_data[$model,sessions]:-0}
        avg=$((sessions > 0 ? total / sessions : 0))

        echo "    \"$model\": {"
        echo "      \"total_seconds\": $total,"
        echo "      \"sessions\": $sessions,"
        echo "      \"avg_seconds\": $avg,"
        echo "      \"max_seconds\": ${worktime_data[$model,max]:-0},"
        echo "      \"min_seconds\": ${worktime_data[$model,min]:-0}"
        echo -n "    }"
    done

    echo ""
    echo "  },"
    echo "  \"generated\": \"$(date -Iseconds)\""
    echo "}"
    exit 0
fi

# Output as table
echo "═══════════════════════════════════════════════════════════════════"
echo -e "                ${BOLD}${CYAN}AGENT METRICS REPORT${NC} — $DATE"
if [ "$DAYS" -gt 1 ]; then
    echo -e "                ${BOLD}${YELLOW}Range: $DATE_START to $DATE_END ($DAYS days)${NC}"
fi
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Token Usage Section
echo -e "${BOLD}${CYAN}📊 TOKEN USAGE BY MODEL${NC}"
echo "───────────────────────────────────────────────────────────────────"
printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" "Model" "Input" "Output" "Cache" "Cost \$"
echo "───────────────────────────────────────────────────────────────────"

total_input_all=0
total_output_all=0
total_cache_all=0
total_cost_all=0

for model in opus sonnet haiku; do
    input=${token_data[$model,input]:-0}
    output=${token_data[$model,output]:-0}
    cache_w=${token_data[$model,cache_write]:-0}
    cache_r=${token_data[$model,cache_read]:-0}
    cache_total=$((cache_w + cache_r))

    cost=$(calculate_cost "$model" "$input" "$output" "$cache_w" "$cache_r")

    # Format for display
    input_fmt=$(format_number "$input")
    output_fmt=$(format_number "$output")
    cache_fmt=$(format_number "$cache_total")
    cost_fmt=$(printf "%.4f" "${cost:-0}")

    # Show row if any data exists
    if [ "$input" -gt 0 ] || [ "$output" -gt 0 ] || [ "$cache_total" -gt 0 ]; then
        printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" \
            "$model" "$input_fmt" "$output_fmt" "$cache_fmt" "\$$cost_fmt"
    else
        printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" \
            "$model" "—" "—" "—" "—"
    fi

    total_input_all=$((total_input_all + input))
    total_output_all=$((total_output_all + output))
    total_cache_all=$((total_cache_all + cache_total))
    total_cost_all=$(echo "$total_cost_all + $cost" | bc -l)
done

echo "───────────────────────────────────────────────────────────────────"
printf "${BOLD}%-10s │ %10s │ %10s │ %10s │ %10s${NC}\n" \
    "TOTAL" \
    "$(format_number $total_input_all)" \
    "$(format_number $total_output_all)" \
    "$(format_number $total_cache_all)" \
    "\$$(printf "%.4f" "${total_cost_all:-0}")"

echo ""

# Work Time Section
echo -e "${BOLD}${CYAN}⏱️  WORK TIME BY MODEL${NC}"
echo "───────────────────────────────────────────────────────────────────"
printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" "Model" "Total" "Avg" "Longest" "Shortest"
echo "───────────────────────────────────────────────────────────────────"

has_worktime=false
for model in opus sonnet haiku; do
    total=${worktime_data[$model,total]:-0}
    sessions=${worktime_data[$model,sessions]:-0}
    max_dur=${worktime_data[$model,max]:-0}
    min_dur=${worktime_data[$model,min]:-0}

    if [ "$total" -gt 0 ]; then
        has_worktime=true
        avg=$((sessions > 0 ? total / sessions : 0))

        printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" \
            "$model" \
            "$(format_duration $total)" \
            "$(format_duration $avg)" \
            "$(format_duration $max_dur)" \
            "$(format_duration $min_dur)"
    else
        printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" \
            "$model" "—" "—" "—" "—"
    fi
done

if [ "$has_worktime" = false ]; then
    echo -e "${YELLOW}No work time data available (tracking not yet implemented)${NC}"
fi

echo ""

# Code Output Section
echo -e "${BOLD}${CYAN}📝 CODE OUTPUT (from Git commits)${NC}"
echo "───────────────────────────────────────────────────────────────────"
printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" "Agent" "Added" "Deleted" "Files" "Commits"
echo "───────────────────────────────────────────────────────────────────"

has_code=false
for model in opus sonnet haiku; do
    added=${code_data[$model,added]:-0}
    deleted=${code_data[$model,deleted]:-0}
    files=${code_data[$model,files]:-0}
    commits=${code_data[$model,commits]:-0}

    if [ "$commits" -gt 0 ]; then
        has_code=true
        printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" \
            "$model" \
            "+$(format_number $added)" \
            "-$(format_number $deleted)" \
            "$(format_number $files)" \
            "$(format_number $commits)"
    else
        printf "%-10s │ %10s │ %10s │ %10s │ %10s\n" \
            "$model" "—" "—" "—" "—"
    fi
done

if [ "$has_code" = false ]; then
    echo -e "${YELLOW}No code statistics available in Redis${NC}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════════════"
