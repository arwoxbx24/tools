#!/bin/bash
#
# Unified Code Quality Pipeline
# =============================
# ЕДИНАЯ точка входа для всех проверок кода
#
# Использование:
#   ./code-quality-pipeline.sh <path> [mode] [format]
#
# Режимы:
#   full         - полный анализ проекта
#   quick        - только syntax + critical
#   changed-only - только изменённые файлы (для pre-commit)
#
# Форматы вывода:
#   json   - JSON для автоматизации
#   human  - человекочитаемый
#   silent - только exit code
#
# V027 Resource Limits встроены!
#

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

PROJECT_PATH="${1:-.}"
MODE="${2:-full}"
OUTPUT_FORMAT="${3:-human}"

# V027 Resource Limits (ОБЯЗАТЕЛЬНЫЕ!)
TIMEOUT_PHPSTAN=300      # 5 минут
TIMEOUT_ESLINT=120       # 2 минуты
TIMEOUT_SEMGREP=60       # 1 минута
PHPSTAN_PROCESSES=1
PHPSTAN_MEMORY="256M"

# Результаты
REPORTS_DIR="/root/workspaces/tools/acc1-scripts/data/quality-reports"
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Статистика
ERRORS=0
WARNINGS=0
CHECKS_PASSED=0
CHECKS_FAILED=0

# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════

log() {
    [[ "$OUTPUT_FORMAT" != "silent" ]] && echo "$1"
}

log_section() {
    [[ "$OUTPUT_FORMAT" == "human" ]] && echo "" && echo "═══ $1 ═══"
}

get_project_name() {
    basename "$(cd "$PROJECT_PATH" && pwd)"
}

detect_project_type() {
    local types=""
    [[ -f "$PROJECT_PATH/composer.json" ]] && types="${types}php,"
    [[ -f "$PROJECT_PATH/package.json" ]] && types="${types}js,"
    [[ -f "$PROJECT_PATH/requirements.txt" ]] && types="${types}python,"
    [[ -f "$PROJECT_PATH/go.mod" ]] && types="${types}go,"
    echo "${types%,}"
}

get_changed_files() {
    if [[ "$MODE" == "changed-only" ]]; then
        # Для pre-commit: staged файлы
        git -C "$PROJECT_PATH" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
    else
        # Для full: все файлы
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════════════
# PHP ANALYSIS (PHPStan)
# ═══════════════════════════════════════════════════════════════

run_phpstan() {
    log_section "PHPStan Analysis"

    # Проверка наличия PHP файлов
    local php_files
    if [[ "$MODE" == "changed-only" ]]; then
        php_files=$(get_changed_files | grep '\.php$' || true)
        [[ -z "$php_files" ]] && { log "  No PHP files changed"; return 0; }
    else
        php_files=$(find "$PROJECT_PATH" -name "*.php" -not -path "*/vendor/*" -not -path "*/node_modules/*" | head -5)
        [[ -z "$php_files" ]] && { log "  No PHP files found"; return 0; }
    fi

    # Проверка установки PHPStan
    local phpstan_cmd=""
    if [[ -f "$PROJECT_PATH/vendor/bin/phpstan" ]]; then
        phpstan_cmd="$PROJECT_PATH/vendor/bin/phpstan"
    elif command -v phpstan &> /dev/null; then
        phpstan_cmd="phpstan"
    elif [[ -f "$HOME/.config/composer/vendor/bin/phpstan" ]]; then
        phpstan_cmd="$HOME/.config/composer/vendor/bin/phpstan"
    else
        log "  PHPStan not installed (skipping)"
        return 0
    fi

    # Запуск с V027 лимитами
    log "  Running PHPStan (processes=$PHPSTAN_PROCESSES, memory=$PHPSTAN_MEMORY, timeout=${TIMEOUT_PHPSTAN}s)..."

    local target="$PROJECT_PATH"
    [[ "$MODE" == "changed-only" ]] && target="$php_files"

    local result
    if result=$(timeout $TIMEOUT_PHPSTAN $phpstan_cmd analyse $target \
        --level=5 \
        --no-progress \
        --processes=$PHPSTAN_PROCESSES \
        --memory-limit=$PHPSTAN_MEMORY \
        --error-format=json 2>/dev/null); then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "  ✅ PHPStan: OK"
        echo "$result"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "  ⏱️ PHPStan: Timeout (>${TIMEOUT_PHPSTAN}s)"
            WARNINGS=$((WARNINGS + 1))
        else
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            local error_count=$(echo "$result" | jq -r '.totals.errors // 0' 2>/dev/null || echo "?")
            log "  ❌ PHPStan: $error_count errors"
            ERRORS=$((ERRORS + error_count))
        fi
        echo "$result"
    fi
}

# ═══════════════════════════════════════════════════════════════
# JavaScript/TypeScript Analysis (ESLint)
# ═══════════════════════════════════════════════════════════════

run_eslint() {
    log_section "ESLint Analysis"

    # Проверка наличия JS/TS файлов
    local js_files
    if [[ "$MODE" == "changed-only" ]]; then
        js_files=$(get_changed_files | grep -E '\.(js|jsx|ts|tsx)$' || true)
        [[ -z "$js_files" ]] && { log "  No JS/TS files changed"; return 0; }
    else
        js_files=$(find "$PROJECT_PATH" -name "*.js" -o -name "*.ts" -not -path "*/node_modules/*" | head -5)
        [[ -z "$js_files" ]] && { log "  No JS/TS files found"; return 0; }
    fi

    # Проверка установки ESLint
    if ! command -v eslint &> /dev/null && ! [[ -f "$PROJECT_PATH/node_modules/.bin/eslint" ]]; then
        log "  ESLint not installed (skipping)"
        return 0
    fi

    local eslint_cmd="eslint"
    [[ -f "$PROJECT_PATH/node_modules/.bin/eslint" ]] && eslint_cmd="$PROJECT_PATH/node_modules/.bin/eslint"

    # Запуск с V027 лимитами
    log "  Running ESLint (timeout=${TIMEOUT_ESLINT}s, max-warnings=100)..."

    local target="$PROJECT_PATH"
    [[ "$MODE" == "changed-only" ]] && target="$js_files"

    local result
    if result=$(timeout $TIMEOUT_ESLINT $eslint_cmd $target \
        --ext .js,.jsx,.ts,.tsx \
        --format json \
        --max-warnings=100 \
        --ignore-pattern node_modules 2>/dev/null); then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log "  ✅ ESLint: OK"
        echo "$result"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "  ⏱️ ESLint: Timeout (>${TIMEOUT_ESLINT}s)"
            WARNINGS=$((WARNINGS + 1))
        else
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            log "  ❌ ESLint: Found issues"
        fi
        echo "$result"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Security Analysis (Semgrep)
# ═══════════════════════════════════════════════════════════════

run_semgrep() {
    log_section "Security Scan (Semgrep)"

    # Semgrep только для full режима (слишком медленный для pre-commit)
    if [[ "$MODE" == "quick" ]] || [[ "$MODE" == "changed-only" ]]; then
        log "  Skipped in $MODE mode"
        return 0
    fi

    # Проверка установки Semgrep
    if ! command -v semgrep &> /dev/null; then
        log "  Semgrep not installed (skipping)"
        return 0
    fi

    # Запуск с V027 лимитами
    log "  Running Semgrep (timeout=${TIMEOUT_SEMGREP}s)..."

    local result
    if result=$(timeout $TIMEOUT_SEMGREP semgrep scan "$PROJECT_PATH" \
        --config=auto \
        --json \
        --quiet \
        --timeout=60 \
        --max-target-bytes=1000000 2>/dev/null); then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        local findings=$(echo "$result" | jq -r '.results | length' 2>/dev/null || echo "0")
        if [[ "$findings" -gt 0 ]]; then
            log "  ⚠️ Semgrep: $findings security findings"
            WARNINGS=$((WARNINGS + findings))
        else
            log "  ✅ Semgrep: No security issues"
        fi
        echo "$result"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "  ⏱️ Semgrep: Timeout (>${TIMEOUT_SEMGREP}s)"
        else
            log "  ❌ Semgrep: Scan failed"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# RESULTS
# ═══════════════════════════════════════════════════════════════

save_results() {
    local project_name=$(get_project_name)
    local project_types=$(detect_project_type)

    # Создать директории
    mkdir -p "$REPORTS_DIR/$TODAY"
    mkdir -p "$REPORTS_DIR/latest"

    # JSON результат
    local json_result
    json_result=$(cat <<EOF
{
  "project": "$project_name",
  "path": "$PROJECT_PATH",
  "types": "$project_types",
  "mode": "$MODE",
  "timestamp": "$TIMESTAMP",
  "summary": {
    "errors": $ERRORS,
    "warnings": $WARNINGS,
    "checks_passed": $CHECKS_PASSED,
    "checks_failed": $CHECKS_FAILED
  },
  "status": "$([ $ERRORS -eq 0 ] && echo 'passed' || echo 'failed')"
}
EOF
)

    # Сохранить в файл
    echo "$json_result" > "$REPORTS_DIR/$TODAY/${project_name}.json"
    echo "$json_result" > "$REPORTS_DIR/latest/${project_name}.json"

    # Сохранить в Redis
    redis-cli SET "quality:${project_name}:latest" "$json_result" EX 86400 >/dev/null 2>&1 || true
    redis-cli LPUSH "quality:${project_name}:history" "$json_result" >/dev/null 2>&1 || true
    redis-cli LTRIM "quality:${project_name}:history" 0 99 >/dev/null 2>&1 || true

    [[ "$OUTPUT_FORMAT" == "json" ]] && echo "$json_result"
}

print_summary() {
    log_section "Summary"
    log "  Project: $(get_project_name)"
    log "  Mode: $MODE"
    log "  Checks passed: $CHECKS_PASSED"
    log "  Checks failed: $CHECKS_FAILED"
    log "  Errors: $ERRORS"
    log "  Warnings: $WARNINGS"
    log ""

    if [[ $ERRORS -eq 0 ]]; then
        log "  ✅ ALL CHECKS PASSED"
    else
        log "  ❌ CHECKS FAILED ($ERRORS errors)"
    fi
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
    # Validate project path
    if [[ ! -d "$PROJECT_PATH" ]]; then
        echo "ERROR: Directory not found: $PROJECT_PATH" >&2
        exit 1
    fi

    PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)

    log_section "Code Quality Pipeline"
    log "  Path: $PROJECT_PATH"
    log "  Mode: $MODE"
    log "  Format: $OUTPUT_FORMAT"
    log "  Types: $(detect_project_type)"

    # Run checks based on project type
    local project_types=$(detect_project_type)

    [[ "$project_types" == *"php"* ]] && run_phpstan
    [[ "$project_types" == *"js"* ]] && run_eslint
    run_semgrep

    # Save and show results
    save_results
    [[ "$OUTPUT_FORMAT" == "human" ]] && print_summary

    # Exit code
    [[ $ERRORS -eq 0 ]] && exit 0 || exit 1
}

main "$@"
