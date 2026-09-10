#!/bin/bash
# Token usage report generator - reads from Redis and formats tables
# Usage: token-report.sh [daily|weekly|monthly] [date]

set -euo pipefail

# Parse arguments
REPORT_TYPE="${1:-daily}"
REPORT_DATE="${2:-$(date +%Y-%m-%d)}"

# Validate report type
if [[ ! "$REPORT_TYPE" =~ ^(daily|weekly|monthly)$ ]]; then
    echo "Error: report type must be daily, weekly, or monthly" >&2
    exit 1
fi

# Function to generate date range
generate_date_range() {
    local type="$1"
    local base_date="$2"

    case "$type" in
        daily)
            echo "$base_date"
            ;;
        weekly)
            # Last 7 days from base_date
            for i in {0..6}; do
                date -d "$base_date -$i days" +%Y-%m-%d 2>/dev/null || \
                date -v-${i}d -j -f "%Y-%m-%d" "$base_date" +%Y-%m-%d 2>/dev/null
            done
            ;;
        monthly)
            # Last 30 days from base_date
            for i in {0..29}; do
                date -d "$base_date -$i days" +%Y-%m-%d 2>/dev/null || \
                date -v-${i}d -j -f "%Y-%m-%d" "$base_date" +%Y-%m-%d 2>/dev/null
            done
            ;;
    esac
}

# Function to fetch data from Redis
fetch_token_data() {
    local dates=("$@")
    local data=()

    for date_key in "${dates[@]}"; do
        # Get all keys matching pattern for this date
        mapfile -t keys < <(redis-cli KEYS "tokens:${date_key}:*" 2>/dev/null | grep -v "actions" || true)

        for key in "${keys[@]}"; do
            # Parse key: tokens:YYYY-MM-DD:agent:model
            if [[ "$key" =~ tokens:([^:]+):([^:]+):(.+)$ ]]; then
                local date="${BASH_REMATCH[1]}"
                local agent="${BASH_REMATCH[2]}"
                local model="${BASH_REMATCH[3]}"

                # Get values from hash
                local tokens_in=$(redis-cli HGET "$key" "tokens_in" 2>/dev/null || echo "0")
                local tokens_out=$(redis-cli HGET "$key" "tokens_out" 2>/dev/null || echo "0")
                local count=$(redis-cli HGET "$key" "count" 2>/dev/null || echo "0")

                # Skip if no data
                [[ "$tokens_in" == "0" && "$tokens_out" == "0" ]] && continue

                data+=("${date}|${agent}|${model}|${tokens_in}|${tokens_out}|${count}")
            fi
        done
    done

    printf '%s\n' "${data[@]}"
}

# Function to aggregate data by agent and model
aggregate_data() {
    local -A aggregated

    while IFS='|' read -r date agent model tokens_in tokens_out count; do
        local key="${agent}|${model}"

        if [[ -z "${aggregated[$key]:-}" ]]; then
            aggregated[$key]="0|0|0"
        fi

        IFS='|' read -r curr_in curr_out curr_count <<< "${aggregated[$key]}"
        aggregated[$key]="$((curr_in + tokens_in))|$((curr_out + tokens_out))|$((curr_count + count))"
    done

    for key in "${!aggregated[@]}"; do
        echo "${key}|${aggregated[$key]}"
    done
}

# Function to format table
format_table() {
    local period="$1"

    # Check if jq is available
    if command -v jq &> /dev/null; then
        # JSON output with jq formatting
        echo "{"
        echo "  \"period\": \"$period\","
        echo "  \"generated\": \"$(date -Iseconds)\","
        echo "  \"data\": ["

        local first=1
        while IFS='|' read -r agent model tokens_in tokens_out count; do
            [[ $first -eq 0 ]] && echo ","
            first=0

            local total=$((tokens_in + tokens_out))
            printf '    {"agent": "%s", "model": "%s", "tokens_in": %d, "tokens_out": %d, "total": %d, "calls": %d}' \
                "$agent" "$model" "$tokens_in" "$tokens_out" "$total" "$count"
        done | sort -t'"' -k4

        echo ""
        echo "  ]"
        echo "}"
    else
        # Plain text table
        echo "═══════════════════════════════════════════════════════════════════════════"
        printf "Token Usage Report - %s\n" "$period"
        printf "Generated: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        echo "═══════════════════════════════════════════════════════════════════════════"
        printf "%-15s %-20s %12s %12s %12s %8s\n" "AGENT" "MODEL" "TOKENS_IN" "TOKENS_OUT" "TOTAL" "CALLS"
        echo "───────────────────────────────────────────────────────────────────────────"

        local grand_in=0 grand_out=0 grand_calls=0

        while IFS='|' read -r agent model tokens_in tokens_out count; do
            local total=$((tokens_in + tokens_out))
            printf "%-15s %-20s %12s %12s %12s %8s\n" \
                "$agent" "$model" \
                "$(printf "%'d" "$tokens_in")" \
                "$(printf "%'d" "$tokens_out")" \
                "$(printf "%'d" "$total")" \
                "$count"

            grand_in=$((grand_in + tokens_in))
            grand_out=$((grand_out + tokens_out))
            grand_calls=$((grand_calls + count))
        done | sort -k1

        echo "───────────────────────────────────────────────────────────────────────────"
        printf "%-15s %-20s %12s %12s %12s %8s\n" \
            "TOTAL" "" \
            "$(printf "%'d" "$grand_in")" \
            "$(printf "%'d" "$grand_out")" \
            "$(printf "%'d" "$((grand_in + grand_out))")" \
            "$grand_calls"
        echo "═══════════════════════════════════════════════════════════════════════════"
    fi
}

# Main execution
mapfile -t date_range < <(generate_date_range "$REPORT_TYPE" "$REPORT_DATE")

if [[ ${#date_range[@]} -eq 0 ]]; then
    echo "Error: Failed to generate date range" >&2
    exit 1
fi

# Build period string
case "$REPORT_TYPE" in
    daily)
        PERIOD_STR="$REPORT_DATE"
        ;;
    weekly)
        PERIOD_STR="${date_range[-1]} to ${date_range[0]}"
        ;;
    monthly)
        PERIOD_STR="${date_range[-1]} to ${date_range[0]}"
        ;;
esac

# Fetch and process data
raw_data=$(fetch_token_data "${date_range[@]}")

if [[ -z "$raw_data" ]]; then
    echo "No token data found for period: $PERIOD_STR" >&2
    exit 0
fi

# Aggregate and format
echo "$raw_data" | aggregate_data | format_table "$PERIOD_STR"

exit 0
