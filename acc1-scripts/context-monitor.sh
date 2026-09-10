#!/bin/bash
# Context Window Monitoring System
# Estimates current context usage and provides alerts

set -euo pipefail

# Configuration
readonly TOKEN_BUDGET=200000
readonly CHARS_PER_TOKEN=4
readonly WARN_THRESHOLD=60
readonly CRITICAL_THRESHOLD=80
readonly LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/context-alerts.log"

# Colors for output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to estimate tokens from character count
estimate_tokens() {
    local chars="$1"
    echo $(( chars / CHARS_PER_TOKEN ))
}

# Function to calculate percentage
calculate_percentage() {
    local used="$1"
    local total="$2"
    echo $(( (used * 100) / total ))
}

# Function to get conversation size estimate
get_conversation_size() {
    # Try to get conversation history from Claude CLI temp files
    local conv_size=0

    # Check for active conversation files in common locations
    if [ -d "/tmp/claude" ]; then
        conv_size=$(find /tmp/claude -type f -name "*.json" -o -name "*.txt" 2>/dev/null | xargs du -cb 2>/dev/null | tail -1 | cut -f1 || echo 0)
    fi

    # If no temp files, estimate from recent shell history and file operations
    if [ "$conv_size" -eq 0 ]; then
        # Rough estimate: assume 50k characters for a typical conversation
        conv_size=50000
    fi

    echo "$conv_size"
}

# Function to format number with commas
format_number() {
    printf "%'d" "$1"
}

# Function to get status level
get_status() {
    local percentage="$1"

    if [ "$percentage" -ge "$CRITICAL_THRESHOLD" ]; then
        echo "CRITICAL"
    elif [ "$percentage" -ge "$WARN_THRESHOLD" ]; then
        echo "WARNING"
    else
        echo "OK"
    fi
}

# Function to get status color
get_status_color() {
    local status="$1"

    case "$status" in
        CRITICAL)
            echo "$RED"
            ;;
        WARNING)
            echo "$YELLOW"
            ;;
        OK)
            echo "$GREEN"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# Function to get recommendation
get_recommendation() {
    local status="$1"

    case "$status" in
        CRITICAL)
            echo "URGENT: Create checkpoint NOW with /checkpoint"
            ;;
        WARNING)
            echo "Consider creating checkpoint with /checkpoint"
            ;;
        OK)
            echo "Continue working normally"
            ;;
        *)
            echo "No action needed"
            ;;
    esac
}

# Function to log alert
log_alert() {
    local timestamp="$1"
    local percentage="$2"
    local tokens_used="$3"
    local status="$4"

    echo "[$timestamp] Context: ${percentage}% (~${tokens_used}/${TOKEN_BUDGET} tokens) - Status: $status" >> "$LOG_FILE"
}

# Main monitoring function
monitor_context() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Get conversation size
    local conv_chars
    conv_chars=$(get_conversation_size)

    # Estimate tokens
    local tokens_used
    tokens_used=$(estimate_tokens "$conv_chars")

    # Calculate percentage
    local percentage
    percentage=$(calculate_percentage "$tokens_used" "$TOKEN_BUDGET")

    # Get status
    local status
    status=$(get_status "$percentage")

    # Get color
    local color
    color=$(get_status_color "$status")

    # Get recommendation
    local recommendation
    recommendation=$(get_recommendation "$status")

    # Format output
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  CONTEXT WINDOW MONITOR"
    echo "═══════════════════════════════════════════"
    echo ""
    printf "Context: ${color}%d%%${NC} (~%s/%s tokens)\n" \
        "$percentage" \
        "$(format_number "$tokens_used")" \
        "$(format_number "$TOKEN_BUDGET")"
    echo ""
    printf "Status: ${color}%s${NC}\n" "$status"
    echo ""
    echo "Action: $recommendation"
    echo ""
    echo "═══════════════════════════════════════════"
    echo ""

    # Log if warning or critical
    if [ "$percentage" -ge "$WARN_THRESHOLD" ]; then
        log_alert "$timestamp" "$percentage" "$(format_number "$tokens_used")" "$status"
    fi

    # Return exit code based on status
    case "$status" in
        CRITICAL)
            return 2
            ;;
        WARNING)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Parse command line arguments
show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Context Window Monitoring System

OPTIONS:
    -h, --help          Show this help message
    -q, --quiet         Quiet mode (no output, only exit code)
    -p, --percentage    Show only percentage
    -l, --log           Show recent log entries

EXIT CODES:
    0 = OK (<60%)
    1 = WARNING (60-79%)
    2 = CRITICAL (80%+)

EXAMPLES:
    $(basename "$0")              # Full monitoring output
    $(basename "$0") -q           # Silent check
    $(basename "$0") -p           # Just the percentage
    $(basename "$0") -l           # Show recent alerts

EOF
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -q|--quiet)
        conv_chars=$(get_conversation_size)
        tokens_used=$(estimate_tokens "$conv_chars")
        percentage=$(calculate_percentage "$tokens_used" "$TOKEN_BUDGET")
        status=$(get_status "$percentage")

        if [ "$percentage" -ge "$WARN_THRESHOLD" ]; then
            log_alert "$(date '+%Y-%m-%d %H:%M:%S')" "$percentage" "$(format_number "$tokens_used")" "$status"
        fi

        case "$status" in
            CRITICAL) exit 2 ;;
            WARNING) exit 1 ;;
            *) exit 0 ;;
        esac
        ;;
    -p|--percentage)
        conv_chars=$(get_conversation_size)
        tokens_used=$(estimate_tokens "$conv_chars")
        percentage=$(calculate_percentage "$tokens_used" "$TOKEN_BUDGET")
        echo "${percentage}%"
        exit 0
        ;;
    -l|--log)
        if [ -f "$LOG_FILE" ]; then
            echo "Recent Context Alerts (last 20):"
            echo "═══════════════════════════════════════════"
            tail -20 "$LOG_FILE"
        else
            echo "No alerts logged yet"
        fi
        exit 0
        ;;
    "")
        monitor_context
        ;;
    *)
        echo "Error: Unknown option '$1'"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
