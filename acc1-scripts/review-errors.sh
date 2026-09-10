#!/bin/bash
# Script: review-errors.sh
# Purpose: Analyze agent-errors.log and suggest CLAUDE.md improvements
# Usage: ./review-errors.sh [--last N] [--agent name] [--type error_type]

set -euo pipefail

# Configuration
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/agent-errors.log"

# Parse optional arguments
LAST_N=""
FILTER_AGENT=""
FILTER_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --last)
            LAST_N="$2"
            shift 2
            ;;
        --agent)
            FILTER_AGENT="$2"
            shift 2
            ;;
        --type)
            FILTER_TYPE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--last N] [--agent name] [--type error_type]" >&2
            exit 1
            ;;
    esac
done

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "No error log found at $LOG_FILE"
    echo "No errors have been logged yet."
    exit 0
fi

# Check if log file is empty
if [ ! -s "$LOG_FILE" ]; then
    echo "Error log is empty. No errors to review."
    exit 0
fi

# Process log file with jq
echo "=== Agent Error Review Report ==="
echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "Log file: $LOG_FILE"
echo ""

# Get total error count
TOTAL_ERRORS=$(wc -l < "$LOG_FILE")
echo "Total errors logged: $TOTAL_ERRORS"
echo ""

# Prepare jq filter based on arguments
JQ_FILTER="."
if [ -n "$FILTER_AGENT" ]; then
    JQ_FILTER="$JQ_FILTER | select(.agent == \"$FILTER_AGENT\")"
fi
if [ -n "$FILTER_TYPE" ]; then
    JQ_FILTER="$JQ_FILTER | select(.type == \"$FILTER_TYPE\")"
fi

# Apply last N filter if specified
INPUT_DATA="$LOG_FILE"
if [ -n "$LAST_N" ]; then
    INPUT_DATA="<(tail -n $LAST_N $LOG_FILE)"
    echo "Reviewing last $LAST_N errors"
    echo ""
fi

# Group by error type
echo "--- Errors by Type ---"
if [ -n "$LAST_N" ]; then
    tail -n "$LAST_N" "$LOG_FILE" | jq -r "$JQ_FILTER" | jq -s 'group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count) | .[] | "\(.type): \(.count)"' 2>/dev/null || echo "No matching errors found"
else
    jq -r "$JQ_FILTER" "$LOG_FILE" | jq -s 'group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count) | .[] | "\(.type): \(.count)"' 2>/dev/null || echo "No matching errors found"
fi
echo ""

# Group by agent
echo "--- Errors by Agent ---"
if [ -n "$LAST_N" ]; then
    tail -n "$LAST_N" "$LOG_FILE" | jq -r "$JQ_FILTER" | jq -s 'group_by(.agent) | map({agent: .[0].agent, count: length}) | sort_by(-.count) | .[] | "\(.agent): \(.count)"' 2>/dev/null || echo "No matching errors found"
else
    jq -r "$JQ_FILTER" "$LOG_FILE" | jq -s 'group_by(.agent) | map({agent: .[0].agent, count: length}) | sort_by(-.count) | .[] | "\(.agent): \(.count)"' 2>/dev/null || echo "No matching errors found"
fi
echo ""

# Recent errors (last 10 or filtered)
echo "--- Recent Errors ---"
if [ -n "$LAST_N" ]; then
    tail -n "$LAST_N" "$LOG_FILE" | jq -r "$JQ_FILTER | \"\(.ts) | \(.agent) | \(.type) | \(.msg) | context: \(.context)\"" 2>/dev/null | tail -n 10 || echo "No matching errors found"
else
    cat "$LOG_FILE" | jq -r "$JQ_FILTER | \"\(.ts) | \(.agent) | \(.type) | \(.msg) | context: \(.context)\"" 2>/dev/null | tail -n 10 || echo "No matching errors found"
fi
echo ""

# Analyze error patterns and suggest CLAUDE.md improvements
echo "--- Suggested CLAUDE.md Improvements ---"
echo ""

# Check for common error patterns
if grep -q '"type":"api_error"' "$LOG_FILE" 2>/dev/null; then
    API_ERRORS=$(grep -c '"type":"api_error"' "$LOG_FILE" || echo 0)
    if [ "$API_ERRORS" -gt 5 ]; then
        echo "1. API Error Pattern (${API_ERRORS} occurrences)"
        echo "   Suggestion: Add to CLAUDE.md > API section:"
        echo "   - Implement exponential backoff for rate limits"
        echo "   - Monitor API usage via operations/05-api-monitoring.md"
        echo "   - Use haiku for non-critical tasks to preserve API quota"
        echo ""
    fi
fi

if grep -q '"type":"context_overflow"' "$LOG_FILE" 2>/dev/null; then
    CTX_ERRORS=$(grep -c '"type":"context_overflow"' "$LOG_FILE" || echo 0)
    if [ "$CTX_ERRORS" -gt 3 ]; then
        echo "2. Context Overflow Pattern (${CTX_ERRORS} occurrences)"
        echo "   Suggestion: Add to CLAUDE.md > Context & API section:"
        echo "   - Create checkpoint at 75% context usage (currently 80%)"
        echo "   - Use targeted file reading (limit/offset) for files >100 lines"
        echo "   - Delegate large refactoring tasks to separate sessions"
        echo ""
    fi
fi

if grep -q '"type":"github_sync_error"' "$LOG_FILE" 2>/dev/null; then
    GH_ERRORS=$(grep -c '"type":"github_sync_error"' "$LOG_FILE" || echo 0)
    if [ "$GH_ERRORS" -gt 2 ]; then
        echo "3. GitHub Sync Error Pattern (${GH_ERRORS} occurrences)"
        echo "   Suggestion: Add to CLAUDE.md > Status Sync section:"
        echo "   - Verify GitHub CLI authentication before sync operations"
        echo "   - Add retry logic with 3-second delay for network errors"
        echo "   - Log sync failures to separate github-sync.log"
        echo ""
    fi
fi

if grep -q '"type":"permission_denied"' "$LOG_FILE" 2>/dev/null; then
    PERM_ERRORS=$(grep -c '"type":"permission_denied"' "$LOG_FILE" || echo 0)
    if [ "$PERM_ERRORS" -gt 1 ]; then
        echo "4. Permission Denied Pattern (${PERM_ERRORS} occurrences)"
        echo "   Suggestion: Add to CLAUDE.md > Security section:"
        echo "   - Verify file permissions before write operations"
        echo "   - Use \$USER variable instead of hardcoding 'root'"
        echo "   - Check directory ownership in /root/workspaces/tools/acc1-scripts/"
        echo ""
    fi
fi

if grep -q '"type":"validation_error"' "$LOG_FILE" 2>/dev/null; then
    VAL_ERRORS=$(grep -c '"type":"validation_error"' "$LOG_FILE" || echo 0)
    if [ "$VAL_ERRORS" -gt 3 ]; then
        echo "5. Validation Error Pattern (${VAL_ERRORS} occurrences)"
        echo "   Suggestion: Add to CLAUDE.md > Verify Before Closing section:"
        echo "   - Add pre-commit validation hook for common errors"
        echo "   - Create validation checklist in issue templates"
        echo "   - Require test run confirmation before closing issues"
        echo ""
    fi
fi

# Check for agent-specific patterns
for agent in haiku sonnet opus codex alex; do
    if grep -q "\"agent\":\"$agent\"" "$LOG_FILE" 2>/dev/null; then
        AGENT_ERROR_COUNT=$(grep -c "\"agent\":\"$agent\"" "$LOG_FILE" || echo 0)
        if [ "$AGENT_ERROR_COUNT" -gt 5 ]; then
            echo "6. Agent-Specific Pattern: $agent (${AGENT_ERROR_COUNT} errors)"
            echo "   Suggestion: Review delegation strategy in operations/01-delegation-strategy.md"
            echo "   - Verify $agent is used for appropriate task complexity"
            echo "   - Consider additional training or constraints for $agent"
            echo ""
        fi
    fi
done

# If no patterns detected
if ! grep -qE '"type":"(api_error|context_overflow|github_sync_error|permission_denied|validation_error)"' "$LOG_FILE" 2>/dev/null; then
    echo "No common error patterns detected requiring CLAUDE.md updates."
    echo "Continue monitoring. Patterns emerge after 5+ similar errors."
fi

echo ""
echo "=== End of Report ==="
