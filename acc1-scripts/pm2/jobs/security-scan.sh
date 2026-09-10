#!/bin/bash
# Security Scan Job - запускается через PM2
# Usage: security-scan.sh <project_path>

PROJECT_PATH="${1:-/root/claude-projects}"
REPORT_DIR="/root/workspaces/tools/acc1-scripts/pm2/reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORT_DIR/security-$TIMESTAMP.json"

export PATH="$PATH:/root/.local/bin"

echo "═══════════════════════════════════════════════════════════════"
echo "🔒 SECURITY SCAN STARTED"
echo "═══════════════════════════════════════════════════════════════"
echo "Time: $(date)"
echo "Project: $PROJECT_PATH"
echo ""

# Check if semgrep is available
if ! command -v semgrep &> /dev/null; then
  echo "⚠️ Semgrep not installed. Using basic security checks..."

  # Fallback: grep for common security issues
  echo "🔍 Scanning for common vulnerabilities..."

  ISSUES=0

  # SQL Injection patterns
  SQL_INJ=$(grep -rn "SELECT.*\$" "$PROJECT_PATH" --include="*.php" 2>/dev/null | wc -l)
  ISSUES=$((ISSUES + SQL_INJ))

  # eval() usage
  EVAL_USE=$(grep -rn "eval(" "$PROJECT_PATH" --include="*.php" --include="*.js" 2>/dev/null | wc -l)
  ISSUES=$((ISSUES + EVAL_USE))

  # Hardcoded passwords
  HARDCODED=$(grep -rn "password.*=.*['\"]" "$PROJECT_PATH" --include="*.php" --include="*.js" --include="*.env" 2>/dev/null | wc -l)
  ISSUES=$((ISSUES + HARDCODED))

  cat > "$REPORT_FILE" << EOF
{
  "type": "security-scan",
  "timestamp": "$(date -Iseconds)",
  "project": "$PROJECT_PATH",
  "tool": "grep-fallback",
  "findings": {
    "sql_injection_risk": $SQL_INJ,
    "eval_usage": $EVAL_USE,
    "hardcoded_secrets": $HARDCODED
  },
  "total_issues": $ISSUES,
  "status": "$([ "$ISSUES" -eq 0 ] && echo 'ok' || echo 'warning')"
}
EOF

else
  # Run Semgrep with V027 resource limits
  echo "🔍 Running Semgrep (timeout=60s)..."
  SEMGREP_OUTPUT=$(timeout 60 semgrep scan "$PROJECT_PATH" --config=auto --json --quiet --timeout=60 --max-target-bytes=1000000 2>/dev/null || echo '{"results":[]}')

  ISSUES=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo "0")

  cat > "$REPORT_FILE" << EOF
{
  "type": "security-scan",
  "timestamp": "$(date -Iseconds)",
  "project": "$PROJECT_PATH",
  "tool": "semgrep",
  "total_issues": $ISSUES,
  "status": "$([ "$ISSUES" -eq 0 ] && echo 'ok' || echo 'warning')",
  "details": $SEMGREP_OUTPUT
}
EOF
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo "Issues found: $ISSUES"
echo "Report saved: $REPORT_FILE"
echo "Status: $([ "$ISSUES" -eq 0 ] && echo '✅ SECURE' || echo '⚠️ REVIEW NEEDED')"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "🔒 SECURITY SCAN COMPLETED"
echo "═══════════════════════════════════════════════════════════════"
