#!/bin/bash
# Auto Scanner - сканирует ВСЕ проекты в /root/claude-projects
# Определяет тип (PHP/JS/mixed) и запускает нужные анализаторы
# Формирует единый отчёт с ошибками

PROJECTS_DIR="/root/claude-projects"
REPORT_DIR="/root/workspaces/tools/acc1-scripts/pm2/reports"
ERRORS_FILE="$REPORT_DIR/ALL-ERRORS-$(date +%Y%m%d).txt"
SUMMARY_FILE="$REPORT_DIR/SUMMARY-$(date +%Y%m%d).json"

export PATH="$PATH:/root/.config/composer/vendor/bin:/root/.local/bin"

# Исключаемые директории
EXCLUDE_DIRS="node_modules|vendor|.git|_archive|automation-demo"

echo "═══════════════════════════════════════════════════════════════════"
echo "🔄 AUTO SCAN ALL PROJECTS"
echo "═══════════════════════════════════════════════════════════════════"
echo "Start: $(date)"
echo "Directory: $PROJECTS_DIR"
echo ""

# Инициализация файлов
echo "# ERRORS REPORT - $(date)" > "$ERRORS_FILE"
echo "# Generated automatically by auto-scan-all.sh" >> "$ERRORS_FILE"
echo "" >> "$ERRORS_FILE"

TOTAL_PROJECTS=0
TOTAL_PHP_ERRORS=0
TOTAL_JS_ERRORS=0
TOTAL_SECURITY=0
PROJECTS_WITH_ERRORS=""

# Сканируем каждый проект
for PROJECT in "$PROJECTS_DIR"/*/; do
  PROJECT_NAME=$(basename "$PROJECT")

  # Пропускаем исключённые
  if [[ "$PROJECT_NAME" =~ ^($EXCLUDE_DIRS)$ ]]; then
    continue
  fi

  TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))

  echo "───────────────────────────────────────────────────────────────────"
  echo "📁 Scanning: $PROJECT_NAME"
  echo "───────────────────────────────────────────────────────────────────"

  PROJECT_ERRORS=0

  # Определяем тип проекта
  PHP_COUNT=$(find "$PROJECT" -name "*.php" -type f 2>/dev/null | grep -v "$EXCLUDE_DIRS" | wc -l)
  JS_COUNT=$(find "$PROJECT" \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) -type f 2>/dev/null | grep -v "$EXCLUDE_DIRS" | wc -l)

  echo "   PHP files: $PHP_COUNT"
  echo "   JS/TS files: $JS_COUNT"

  # ═══════════════════════════════════════════════════════════════════
  # PHP Analysis
  # ═══════════════════════════════════════════════════════════════════
  if [[ $PHP_COUNT -gt 0 ]]; then
    echo "   🔍 Running PHPStan..."

    # V027: Resource limits mandatory
    PHPSTAN_OUTPUT=$(timeout 300 phpstan analyse "$PROJECT" --level=5 --error-format=raw --no-progress --processes=1 --memory-limit=256M 2>/dev/null || echo "")
    PHP_ERRORS=$(echo "$PHPSTAN_OUTPUT" | grep -c ":" 2>/dev/null || echo "0")

    if [[ $PHP_ERRORS -gt 0 ]]; then
      echo "" >> "$ERRORS_FILE"
      echo "## [$PROJECT_NAME] PHP ERRORS ($PHP_ERRORS)" >> "$ERRORS_FILE"
      echo '```' >> "$ERRORS_FILE"
      echo "$PHPSTAN_OUTPUT" >> "$ERRORS_FILE"
      echo '```' >> "$ERRORS_FILE"

      TOTAL_PHP_ERRORS=$((TOTAL_PHP_ERRORS + PHP_ERRORS))
      PROJECT_ERRORS=$((PROJECT_ERRORS + PHP_ERRORS))
    fi

    echo "   PHP errors: $PHP_ERRORS"
  fi

  # ═══════════════════════════════════════════════════════════════════
  # JS/TS Analysis
  # ═══════════════════════════════════════════════════════════════════
  if [[ $JS_COUNT -gt 0 ]]; then
    echo "   🔍 Running ESLint..."

    # Check for eslint config
    if [[ -f "$PROJECT/eslint.config.js" ]] || [[ -f "$PROJECT/.eslintrc.js" ]] || [[ -f "$PROJECT/.eslintrc.json" ]]; then
      cd "$PROJECT"
      # V027: Resource limits mandatory
      ESLINT_OUTPUT=$(timeout 120 npx eslint . --ext .js,.jsx,.ts,.tsx --format compact --max-warnings=100 --ignore-pattern node_modules 2>/dev/null || echo "")
      JS_ERRORS=$(echo "$ESLINT_OUTPUT" | grep -c "Error\|error" 2>/dev/null || echo "0")
      cd - > /dev/null

      if [[ $JS_ERRORS -gt 0 ]]; then
        echo "" >> "$ERRORS_FILE"
        echo "## [$PROJECT_NAME] JS/TS ERRORS ($JS_ERRORS)" >> "$ERRORS_FILE"
        echo '```' >> "$ERRORS_FILE"
        echo "$ESLINT_OUTPUT" | head -50 >> "$ERRORS_FILE"
        echo '```' >> "$ERRORS_FILE"

        TOTAL_JS_ERRORS=$((TOTAL_JS_ERRORS + JS_ERRORS))
        PROJECT_ERRORS=$((PROJECT_ERRORS + JS_ERRORS))
      fi
    fi

    echo "   JS errors: ${JS_ERRORS:-0}"
  fi

  # ═══════════════════════════════════════════════════════════════════
  # Security Quick Check
  # ═══════════════════════════════════════════════════════════════════
  echo "   🔒 Security check..."

  SEC_ISSUES=0

  # SQL Injection
  SQL_INJ=$(grep -rn "SELECT.*\\\$\|INSERT.*\\\$\|UPDATE.*\\\$" "$PROJECT" --include="*.php" 2>/dev/null | grep -v "$EXCLUDE_DIRS" | wc -l)
  SEC_ISSUES=$((SEC_ISSUES + SQL_INJ))

  # eval/exec
  EVAL_USE=$(grep -rn "eval(\|exec(\|system(" "$PROJECT" --include="*.php" --include="*.js" 2>/dev/null | grep -v "$EXCLUDE_DIRS" | wc -l)
  SEC_ISSUES=$((SEC_ISSUES + EVAL_USE))

  if [[ $SEC_ISSUES -gt 0 ]]; then
    echo "" >> "$ERRORS_FILE"
    echo "## [$PROJECT_NAME] SECURITY WARNINGS ($SEC_ISSUES)" >> "$ERRORS_FILE"
    echo "- SQL injection risk: $SQL_INJ" >> "$ERRORS_FILE"
    echo "- Dangerous functions: $EVAL_USE" >> "$ERRORS_FILE"

    TOTAL_SECURITY=$((TOTAL_SECURITY + SEC_ISSUES))
    PROJECT_ERRORS=$((PROJECT_ERRORS + SEC_ISSUES))
  fi

  echo "   Security issues: $SEC_ISSUES"

  # Запоминаем проекты с ошибками
  if [[ $PROJECT_ERRORS -gt 0 ]]; then
    PROJECTS_WITH_ERRORS="$PROJECTS_WITH_ERRORS$PROJECT_NAME ($PROJECT_ERRORS), "
  fi

  echo ""
done

# ═══════════════════════════════════════════════════════════════════
# Формируем JSON Summary
# ═══════════════════════════════════════════════════════════════════
TOTAL_ALL=$((TOTAL_PHP_ERRORS + TOTAL_JS_ERRORS + TOTAL_SECURITY))

cat > "$SUMMARY_FILE" << EOF
{
  "type": "auto-scan-summary",
  "timestamp": "$(date -Iseconds)",
  "projects_scanned": $TOTAL_PROJECTS,
  "totals": {
    "php_errors": $TOTAL_PHP_ERRORS,
    "js_errors": $TOTAL_JS_ERRORS,
    "security_warnings": $TOTAL_SECURITY,
    "total": $TOTAL_ALL
  },
  "status": "$([ "$TOTAL_ALL" -eq 0 ] && echo 'ok' || echo 'needs_review')",
  "projects_with_issues": "${PROJECTS_WITH_ERRORS%, }",
  "errors_file": "$ERRORS_FILE"
}
EOF

# ═══════════════════════════════════════════════════════════════════
# Финальный отчёт
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "📊 SCAN COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo "Projects scanned: $TOTAL_PROJECTS"
echo ""
echo "ERRORS FOUND:"
echo "  PHP:      $TOTAL_PHP_ERRORS"
echo "  JS/TS:    $TOTAL_JS_ERRORS"
echo "  Security: $TOTAL_SECURITY"
echo "  ─────────────────"
echo "  TOTAL:    $TOTAL_ALL"
echo ""
echo "Reports saved:"
echo "  📄 $ERRORS_FILE"
echo "  📄 $SUMMARY_FILE"
echo ""
echo "End: $(date)"
echo "═══════════════════════════════════════════════════════════════════"
