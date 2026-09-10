#!/bin/bash
# vcode-coverage-audit.sh — Maps V-codes to enforcing hooks
# Usage: bash vcode-coverage-audit.sh [--verbose]

HOOKS_DIR="/root/workspaces/tools/acc1-scripts/hooks"
RULES_FILE="/root/.claude_shared/reference/rules-index.md"

echo "=== V-Code Coverage Audit ==="
echo "Date: $(date)"
echo ""

# Extract all V-codes from rules-index
VCODES=$(grep -oP 'V\d{3}' "$RULES_FILE" | sort -u)
TOTAL=$(echo "$VCODES" | wc -l)
COVERED=0
UNCOVERED=0

echo "| V-Code | Hook(s) | Status |"
echo "|--------|---------|--------|"

for VCODE in $VCODES; do
    HOOKS=$(grep -rl "$VCODE" "$HOOKS_DIR"/*.sh 2>/dev/null | xargs -I{} basename {} | tr '\n' ', ' | sed 's/,$//')
    if [ -n "$HOOKS" ]; then
        echo "| $VCODE | $HOOKS | COVERED |"
        ((COVERED++))
    else
        echo "| $VCODE | - | UNCOVERED |"
        ((UNCOVERED++))
    fi
done

echo ""
echo "Total: $TOTAL | Covered: $COVERED | Uncovered: $UNCOVERED | Coverage: $(( COVERED * 100 / TOTAL ))%"
