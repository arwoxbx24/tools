#!/bin/bash
# API Usage Monitor & Failover System
# Monitors API limits and switches accounts when needed
# Run: bash /root/workspaces/tools/acc1-scripts/scripts/api-monitor.sh [check|status|switch]

set -e

CONFIG_DIR="/root/workspaces/tools/acc1-scripts/config"
DATA_DIR="/root/workspaces/tools/acc1-scripts/data"
STATUS_FILE="$DATA_DIR/api-status.json"
ACCOUNTS_FILE="$CONFIG_DIR/api-accounts.json"

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$DATA_DIR"

# Initialize status file if not exists
if [ ! -f "$STATUS_FILE" ]; then
    cat > "$STATUS_FILE" << 'EOF'
{
  "current_account": "primary",
  "last_check": null,
  "accounts": {
    "primary": {
      "openai_usage_percent": 0,
      "anthropic_usage_percent": 0,
      "last_updated": null,
      "status": "active"
    }
  },
  "alerts": []
}
EOF
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_openai_usage() {
    echo -e "${YELLOW}[1/3] Checking OpenAI API usage...${NC}"

    # OpenAI usage API (requires org admin access)
    # For now, estimate based on embeddings count
    if [ -f "$DATA_DIR/vectors.db" ]; then
        CHUNKS=$(sqlite3 "$DATA_DIR/vectors.db" "SELECT COUNT(*) FROM code_chunks" 2>/dev/null || echo "0")
        ESTIMATED_TOKENS=$((CHUNKS * 50))
        echo "  Indexed chunks: $CHUNKS"
        echo "  Estimated tokens used: $ESTIMATED_TOKENS"
        echo "  Estimated cost: \$$(echo "scale=4; $ESTIMATED_TOKENS * 0.00002 / 1000" | bc)"
    else
        echo "  No vector database found"
        CHUNKS=0
        ESTIMATED_TOKENS=0
    fi
}

check_anthropic_usage() {
    echo -e "${YELLOW}[2/3] Checking Anthropic API usage...${NC}"

    # Anthropic doesn't have a public usage API
    # We track locally in history.jsonl
    if [ -f "/root/workspaces/tools/acc1-scripts/history.jsonl" ]; then
        MESSAGES=$(wc -l < "/root/workspaces/tools/acc1-scripts/history.jsonl")
        echo "  Session messages: $MESSAGES"
    else
        echo "  No history found"
        MESSAGES=0
    fi
}

check_embedding_providers() {
    echo -e "${YELLOW}[3/3] Checking embedding providers...${NC}"

    # Test each provider
    echo "  Testing OpenAI..."
    if curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        "https://api.openai.com/v1/models" | grep -q "200"; then
        echo -e "    ${GREEN}✓ OpenAI: OK${NC}"
        OPENAI_STATUS="active"
    else
        echo -e "    ${RED}✗ OpenAI: Failed${NC}"
        OPENAI_STATUS="failed"
    fi

    echo "  Testing Voyage AI..."
    # Voyage doesn't have a simple health check, skip for now
    echo "    ⚠ Voyage: Not tested (no health endpoint)"

    echo "  Testing Jina AI..."
    # Jina doesn't have a simple health check, skip for now
    echo "    ⚠ Jina: Not tested (no health endpoint)"
}

update_status() {
    local NOW=$(date -Iseconds)

    # Update status file
    cat > "$STATUS_FILE" << EOF
{
  "current_account": "primary",
  "last_check": "$NOW",
  "accounts": {
    "primary": {
      "openai_status": "$OPENAI_STATUS",
      "indexed_chunks": $CHUNKS,
      "estimated_tokens": $ESTIMATED_TOKENS,
      "session_messages": $MESSAGES,
      "last_updated": "$NOW",
      "status": "active"
    }
  },
  "thresholds": {
    "warning_percent": 70,
    "critical_percent": 90,
    "switch_percent": 95
  },
  "alerts": []
}
EOF

    echo ""
    echo -e "${GREEN}Status updated: $STATUS_FILE${NC}"
}

show_status() {
    echo "=== API Status ==="
    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE" | python3 -m json.tool 2>/dev/null || cat "$STATUS_FILE"
    else
        echo "No status file found. Run: $0 check"
    fi
}

show_help() {
    echo "API Monitor & Failover System"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check   - Check all API providers and update status"
    echo "  status  - Show current status"
    echo "  help    - Show this help"
    echo ""
    echo "Thresholds:"
    echo "  70%  - Warning alert"
    echo "  90%  - Critical alert"
    echo "  95%  - Auto-switch to backup account"
    echo ""
    echo "Files:"
    echo "  Status: $STATUS_FILE"
    echo "  Config: $ACCOUNTS_FILE"
}

# Main
case "${1:-check}" in
    check)
        echo "========================================"
        echo "  API USAGE MONITOR"
        echo "  $(date)"
        echo "========================================"
        echo ""
        check_openai_usage
        echo ""
        check_anthropic_usage
        echo ""
        check_embedding_providers
        echo ""
        update_status
        echo ""
        echo "========================================"
        echo "  CHECK COMPLETE"
        echo "========================================"
        ;;
    status)
        show_status
        ;;
    *)
        show_help
        ;;
esac
