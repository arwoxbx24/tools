#!/bin/bash
# mcp-control.sh — Dynamic MCP Server Management
# V110: MCP_TOKEN_CONTROL
#
# Heavy MCPs consume ~9k tokens just for descriptions.
# Enable ONLY when explicitly needed, disable immediately after.

ACTION="$1"  # enable | disable | status
MCP_NAME="$2"  # chrome-devtools | playwright | code-search

HEAVY_MCPS=("chrome-devtools" "playwright")

usage() {
    echo "Usage: $0 <action> [mcp-name]"
    echo ""
    echo "Actions:"
    echo "  enable <name>   - Enable specific MCP server"
    echo "  disable <name>  - Disable specific MCP server"
    echo "  disable-heavy   - Disable all heavy MCPs (chrome-devtools, playwright)"
    echo "  status          - Show current MCP servers"
    echo ""
    echo "Heavy MCPs (>1000 tokens each):"
    echo "  chrome-devtools - Browser debugging (~50 tools, ~5k tokens)"
    echo "  playwright      - Browser automation (~25 tools, ~3.7k tokens)"
    echo ""
    echo "Examples:"
    echo "  $0 enable playwright      # Enable for browser testing"
    echo "  $0 disable playwright     # Disable after task complete"
    echo "  $0 disable-heavy          # Disable all heavy MCPs"
    echo "  $0 status                 # List all MCP servers"
}

case "$ACTION" in
    enable)
        if [ -z "$MCP_NAME" ]; then
            echo "Error: MCP name required"
            usage
            exit 1
        fi
        echo "⚠️  Enabling MCP: $MCP_NAME"
        echo "   Remember to disable after task completion!"
        claude mcp add "$MCP_NAME" --scope user 2>&1
        echo "✅ MCP $MCP_NAME enabled"
        ;;

    disable)
        if [ -z "$MCP_NAME" ]; then
            echo "Error: MCP name required"
            usage
            exit 1
        fi
        claude mcp remove "$MCP_NAME" --scope user 2>&1
        echo "✅ MCP $MCP_NAME disabled"
        ;;

    disable-heavy)
        echo "Disabling all heavy MCPs..."
        for mcp in "${HEAVY_MCPS[@]}"; do
            claude mcp remove "$mcp" --scope user 2>&1 || true
            echo "  ✅ $mcp disabled"
        done
        echo "✅ All heavy MCPs disabled (~9k tokens saved)"
        ;;

    status)
        echo "Current MCP servers:"
        claude mcp list 2>&1
        ;;

    *)
        usage
        exit 1
        ;;
esac
