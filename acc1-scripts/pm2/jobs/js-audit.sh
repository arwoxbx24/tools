#!/bin/bash
# JS/Node Audit Job - запускается через PM2
# Usage: js-audit.sh <project_path>

PROJECT_PATH="${1:-/root/claude-projects/voice-transcriber}"
REPORT_DIR="/root/workspaces/tools/acc1-scripts/pm2/reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/js-audit-$TIMESTAMP.json"

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 JS/NODE AUDIT STARTED"
echo "═══════════════════════════════════════════════════════════════"
echo "Time: $(date)"
echo "Project: $PROJECT_PATH"
echo ""

# Check if project exists
if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "❌ Project directory not found: $PROJECT_PATH"
  exit 1
fi

# Find JS/TS files (exclude node_modules)
JS_COUNT=$(find "$PROJECT_PATH" -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" 2>/dev/null | grep -v node_modules | wc -l)
echo "📁 JS/TS files found: $JS_COUNT"
echo ""

# Check for eslint config in project
ESLINT_CONFIG=""
if [[ -f "$PROJECT_PATH/eslint.config.js" ]]; then
  ESLINT_CONFIG="$PROJECT_PATH/eslint.config.js"
elif [[ -f "$PROJECT_PATH/.eslintrc.js" ]]; then
  ESLINT_CONFIG="$PROJECT_PATH/.eslintrc.js"
fi

# Run ESLint with V027 resource limits
echo "🔍 Running ESLint (timeout=120s, max-warnings=100)..."
cd "$PROJECT_PATH"
ESLINT_OUTPUT=$(timeout 120 npx eslint . --ext .js,.jsx,.ts,.tsx --format json --max-warnings=100 --ignore-pattern node_modules 2>/dev/null || echo '[]')

# Parse results
ERRORS=$(echo "$ESLINT_OUTPUT" | jq '[.[].errorCount] | add // 0' 2>/dev/null || echo "0")
WARNINGS=$(echo "$ESLINT_OUTPUT" | jq '[.[].warningCount] | add // 0' 2>/dev/null || echo "0")

# Create report
cat > "$REPORT_FILE" << EOF
{
  "type": "js-audit",
  "timestamp": "$(date -Iseconds)",
  "project": "$PROJECT_PATH",
  "files_scanned": $JS_COUNT,
  "tool": "eslint",
  "errors": $ERRORS,
  "warnings": $WARNINGS,
  "status": "$([ "$ERRORS" -eq 0 ] && echo 'ok' || echo 'error')",
  "details": $ESLINT_OUTPUT
}
EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo "Report saved: $REPORT_FILE"
echo "Status: $([ "$ERRORS" -eq 0 ] && echo '✅ OK' || echo '❌ ERROR')"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 JS/NODE AUDIT COMPLETED"
echo "═══════════════════════════════════════════════════════════════"
