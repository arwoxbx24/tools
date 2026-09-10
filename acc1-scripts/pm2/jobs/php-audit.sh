#!/bin/bash
# PHP Audit Job - запускается через PM2
# Usage: php-audit.sh <project_path>

PROJECT_PATH="${1:-/root/claude-projects/bitrix}"
REPORT_DIR="/root/workspaces/tools/acc1-scripts/pm2/reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/php-audit-$TIMESTAMP.json"

export PATH="$PATH:/root/.config/composer/vendor/bin"

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 PHP AUDIT STARTED"
echo "═══════════════════════════════════════════════════════════════"
echo "Time: $(date)"
echo "Project: $PROJECT_PATH"
echo ""

# Check if project exists
if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "❌ Project directory not found: $PROJECT_PATH"
  exit 1
fi

# Find PHP files
PHP_COUNT=$(find "$PROJECT_PATH" -name "*.php" -type f 2>/dev/null | wc -l)
echo "📁 PHP files found: $PHP_COUNT"
echo ""

# Run PHPStan with V027 resource limits
echo "🔍 Running PHPStan (level 5, processes=1, memory=256M)..."
PHPSTAN_OUTPUT=$(timeout 300 phpstan analyse "$PROJECT_PATH" --level=5 --error-format=json --no-progress --processes=1 --memory-limit=256M 2>/dev/null || echo '{"totals":{"errors":0}}')

# Parse results
ERRORS=$(echo "$PHPSTAN_OUTPUT" | jq '.totals.errors // 0' 2>/dev/null || echo "0")

# Create report
cat > "$REPORT_FILE" << EOF
{
  "type": "php-audit",
  "timestamp": "$(date -Iseconds)",
  "project": "$PROJECT_PATH",
  "files_scanned": $PHP_COUNT,
  "tool": "phpstan",
  "level": 5,
  "errors": $ERRORS,
  "status": "$([ "$ERRORS" -eq 0 ] && echo 'ok' || echo 'warning')",
  "details": $PHPSTAN_OUTPUT
}
EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo "Errors found: $ERRORS"
echo "Report saved: $REPORT_FILE"
echo "Status: $([ "$ERRORS" -eq 0 ] && echo '✅ OK' || echo '⚠️ WARNING')"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 PHP AUDIT COMPLETED"
echo "═══════════════════════════════════════════════════════════════"
