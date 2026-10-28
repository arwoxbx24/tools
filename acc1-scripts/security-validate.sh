#!/bin/bash

# ============================================================================
# Security Validation Orchestrator
# ============================================================================
# Main security validation tool that detects languages and runs appropriate
# security checks for hardcoded secrets, SQL injection, XSS, command injection
# ============================================================================
#
# USAGE:
#   security-validate.sh <project_directory> [--quick|--full]
#
# ARGUMENTS:
#   project_directory  Path to the project to scan (default: current directory)
#   --quick           Run basic security checks (default)
#   --full            Run all security checks including deserialization and path traversal
#
# EXIT CODES:
#   0   No CRITICAL issues found
#   1   CRITICAL issues found
#
# ENVIRONMENT VARIABLES:
#   BOT_TOKEN   Telegram bot token for notifications (optional)
#   CHAT_ID     Telegram chat ID for notifications (optional)
#
# EXAMPLES:
#   # Quick scan of current directory
#   security-validate.sh .
#
#   # Full scan with Telegram notification
#   BOT_TOKEN=xxx CHAT_ID=yyy security-validate.sh /path/to/project --full
#
# OUTPUT:
#   - Logs to stderr
#   - JSON report to stdout
#   - Temporary report file in /tmp/security-report-<pid>.json
#
# ============================================================================

set -uo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-.}"
MODE="${2:---quick}"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Severity levels
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

# Temporary files
REPORT_FILE="/tmp/security-report-$$.json"
FINDINGS_FILE="/tmp/security-findings-$$.txt"

# Exclusion patterns for grep
EXCLUDE_DIRS="node_modules|venv|\.git|build|dist|\.tmp|__pycache__|\.venv|vendor|target|bin|obj|\.next|\.nuxt|coverage"

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[OK]${NC} $*" >&2
}

add_finding() {
    local severity="$1"
    local category="$2"
    local file="$3"
    local line="$4"
    local description="$5"
    local pattern="${6:-N/A}"

    case "$severity" in
        CRITICAL) ((CRITICAL++)) ;;
        HIGH) ((HIGH++)) ;;
        MEDIUM) ((MEDIUM++)) ;;
        LOW) ((LOW++)) ;;
    esac

    echo "{\"severity\":\"$severity\",\"category\":\"$category\",\"file\":\"$file\",\"line\":$line,\"description\":\"$description\",\"pattern\":\"$pattern\"}" >> "$FINDINGS_FILE"
}

# ============================================================================
# Language Detection
# ============================================================================

detect_languages() {
    log "Detecting project languages..."

    local langs=()

    # Python
    if find "$PROJECT_DIR" -type f -name "*.py" | head -1 | grep -q .; then
        langs+=("python")
    fi

    # JavaScript/TypeScript
    if find "$PROJECT_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) | head -1 | grep -q .; then
        langs+=("javascript")
    fi

    # PHP
    if find "$PROJECT_DIR" -type f -name "*.php" | head -1 | grep -q .; then
        langs+=("php")
    fi

    # Go
    if find "$PROJECT_DIR" -type f -name "*.go" | head -1 | grep -q .; then
        langs+=("go")
    fi

    # HTML
    if find "$PROJECT_DIR" -type f -name "*.html" | head -1 | grep -q .; then
        langs+=("html")
    fi

    if [ ${#langs[@]} -eq 0 ]; then
        warn "No supported languages detected"
        echo ""
    else
        success "Detected languages: ${langs[*]}"
        echo "${langs[*]}"
    fi
}

# ============================================================================
# Security Checks
# ============================================================================

check_hardcoded_secrets() {
    log "Checking for hardcoded secrets..."

    # Simple high-value patterns
    local patterns=(
        "AKIA[0-9A-Z]{16}"
        "sk_live_[0-9a-zA-Z]{24}"
        "sk_test_[0-9a-zA-Z]{24}"
        "ghp_[0-9a-zA-Z]{36}"
        "gho_[0-9a-zA-Z]{36}"
        "AIzaSy[0-9a-zA-Z_-]{33}"
    )

    for pattern in "${patterns[@]}"; do
        timeout 5 grep -rn -E "$pattern" "$PROJECT_DIR" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor,target,.next,coverage} \
            --exclude="*.min.js" --exclude="*.map" --exclude="package-lock.json" 2>/dev/null | \
        while IFS=: read -r file line content; do
            add_finding "CRITICAL" "Hardcoded Secret" "$file" "$line" "Hardcoded credential detected" "$pattern"
        done || true
    done

    # Generic password/key patterns (faster)
    timeout 5 grep -rn -iE "(password|api_key|secret|token).*=.*(\"[^\"]{12,}\"|'[^']{12,}')" "$PROJECT_DIR" \
        --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor,target,.next,coverage} \
        --exclude="*.min.js" --exclude="*.map" --exclude="package-lock.json" \
        --include="*.py" --include="*.js" --include="*.ts" --include="*.php" --include="*.go" \
        --include="*.env" --include="*.conf" --include="*.config" 2>/dev/null | \
    while IFS=: read -r file line content; do
        # Skip if it looks like a placeholder
        if echo "$content" | grep -qiE "(your|my|test|example|dummy|placeholder|xxx|changeme)"; then
            continue
        fi
        add_finding "CRITICAL" "Hardcoded Secret" "$file" "$line" "Potential hardcoded credential" "credential"
    done || true
}

check_sql_injection() {
    log "Checking for SQL injection patterns..."

    # JavaScript SQL injection patterns (simplified)
    if [[ "$LANGUAGES" == *"javascript"* ]]; then
        timeout 5 grep -rn -E "(query|execute)\(.*\+|SELECT.*\$\{|INSERT.*\$\{|UPDATE.*\$\{|DELETE.*\$\{" "$PROJECT_DIR" \
            --include="*.js" --include="*.ts" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            add_finding "HIGH" "SQL Injection" "$file" "$line" "Potential SQL injection via string concatenation" "sql_concat"
        done || true
    fi

    # Python SQL injection patterns
    if [[ "$LANGUAGES" == *"python"* ]]; then
        timeout 5 grep -rn -E "execute\(.*(format|%|\+)" "$PROJECT_DIR" --include="*.py" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            add_finding "HIGH" "SQL Injection" "$file" "$line" "Potential SQL injection via string formatting" "sql_format"
        done || true
    fi

    # PHP SQL injection patterns
    if [[ "$LANGUAGES" == *"php"* ]]; then
        timeout 5 grep -rn -E "(mysql_query|mysqli_query|->query|->exec)\(.*\\\$" "$PROJECT_DIR" --include="*.php" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            add_finding "HIGH" "SQL Injection" "$file" "$line" "Potential SQL injection via variable interpolation" "sql_var"
        done || true
    fi
}

check_xss() {
    log "Checking for XSS patterns..."

    # Combined XSS pattern
    timeout 5 grep -rn -E "(innerHTML|outerHTML).*=|document\.(write|writeln)\(|dangerouslySetInnerHTML|v-html=|\[innerHTML\]=" "$PROJECT_DIR" \
        --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" --include="*.html" --include="*.php" \
        --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
    while IFS=: read -r file line content; do
        add_finding "HIGH" "XSS" "$file" "$line" "Potential XSS via DOM manipulation" "dom_xss"
    done || true

    # Check for eval usage
    timeout 5 grep -rn -E "\beval\s*\(" "$PROJECT_DIR" \
        --include="*.js" --include="*.ts" --include="*.py" --include="*.php" \
        --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
    while IFS=: read -r file line content; do
        add_finding "CRITICAL" "Code Injection" "$file" "$line" "Use of eval() can lead to code injection" "eval"
    done || true
}

check_command_injection() {
    log "Checking for command injection patterns..."

    # JavaScript/Node.js command injection
    if [[ "$LANGUAGES" == *"javascript"* ]]; then
        timeout 5 grep -rn -E "child_process\.(exec|spawn|execSync|execFile)\(" "$PROJECT_DIR" \
            --include="*.js" --include="*.ts" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            if echo "$content" | grep -qE "(req\.|request\.|params\.|query\.|body\.)"; then
                add_finding "CRITICAL" "Command Injection" "$file" "$line" "Command execution with user input" "cmd_inject"
            else
                add_finding "MEDIUM" "Command Execution" "$file" "$line" "Command execution detected" "cmd_exec"
            fi
        done || true
    fi

    # Python command injection
    if [[ "$LANGUAGES" == *"python"* ]]; then
        timeout 5 grep -rn -E "os\.(system|popen)\(|subprocess\.(call|run|Popen)\(.*shell=True" "$PROJECT_DIR" \
            --include="*.py" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            if echo "$content" | grep -qE "(request\.|input\(|argv|form\.|GET|POST)"; then
                add_finding "CRITICAL" "Command Injection" "$file" "$line" "Command execution with user input" "cmd_inject"
            else
                add_finding "MEDIUM" "Command Execution" "$file" "$line" "Command execution detected" "cmd_exec"
            fi
        done || true
    fi

    # PHP command injection
    if [[ "$LANGUAGES" == *"php"* ]]; then
        timeout 5 grep -rn -E "\b(system|exec|shell_exec|passthru|popen|proc_open)\(" "$PROJECT_DIR" \
            --include="*.php" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            if echo "$content" | grep -qE "(\\\$_GET|\\\$_POST|\\\$_REQUEST|\\\$_COOKIE)"; then
                add_finding "CRITICAL" "Command Injection" "$file" "$line" "Command execution with user input" "cmd_inject"
            else
                add_finding "MEDIUM" "Command Execution" "$file" "$line" "Command execution detected" "cmd_exec"
            fi
        done || true
    fi
}

check_insecure_deserialization() {
    log "Checking for insecure deserialization..."

    # Python pickle
    if [[ "$LANGUAGES" == *"python"* ]]; then
        timeout 5 grep -rn -E "pickle\.loads?\(" "$PROJECT_DIR" --include="*.py" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            add_finding "HIGH" "Insecure Deserialization" "$file" "$line" "Use of pickle can lead to code execution" "pickle"
        done || true
    fi

    # PHP unserialize
    if [[ "$LANGUAGES" == *"php"* ]]; then
        timeout 5 grep -rn -E "\bunserialize\(" "$PROJECT_DIR" --include="*.php" \
            --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
        while IFS=: read -r file line content; do
            add_finding "HIGH" "Insecure Deserialization" "$file" "$line" "Use of unserialize can lead to object injection" "unserialize"
        done || true
    fi
}

check_path_traversal() {
    log "Checking for path traversal vulnerabilities..."

    # Combined pattern for file operations
    timeout 5 grep -rn -E "open\(.*\+|readFile\(.*\+|file_get_contents\(.*\\\$|(include|require)(_once)?\(.*\\\$" "$PROJECT_DIR" \
        --include="*.py" --include="*.js" --include="*.ts" --include="*.php" \
        --exclude-dir={node_modules,venv,.git,build,dist,.tmp,__pycache__,.venv,vendor} 2>/dev/null | \
    while IFS=: read -r file line content; do
        if echo "$content" | grep -qE "(request\.|input\(|argv|form\.|GET|POST|req\.|params\.|query\.|body\.|\\\$_GET|\\\$_POST)"; then
            add_finding "HIGH" "Path Traversal" "$file" "$line" "File operation with user input" "path_traversal"
        fi
    done || true
}

# ============================================================================
# Report Generation
# ============================================================================

generate_report() {
    log "Generating security report..."

    # Recalculate counts from findings file (update global variables)
    CRITICAL=0
    HIGH=0
    MEDIUM=0
    LOW=0

    if [ -f "$FINDINGS_FILE" ] && [ -s "$FINDINGS_FILE" ]; then
        CRITICAL=$(grep '"severity":"CRITICAL"' "$FINDINGS_FILE" 2>/dev/null | wc -l | tr -d ' \n')
        HIGH=$(grep '"severity":"HIGH"' "$FINDINGS_FILE" 2>/dev/null | wc -l | tr -d ' \n')
        MEDIUM=$(grep '"severity":"MEDIUM"' "$FINDINGS_FILE" 2>/dev/null | wc -l | tr -d ' \n')
        LOW=$(grep '"severity":"LOW"' "$FINDINGS_FILE" 2>/dev/null | wc -l | tr -d ' \n')

        # Ensure values are numbers
        CRITICAL=${CRITICAL:-0}
        HIGH=${HIGH:-0}
        MEDIUM=${MEDIUM:-0}
        LOW=${LOW:-0}
    fi

    local total=$((CRITICAL + HIGH + MEDIUM + LOW))

    cat > "$REPORT_FILE" <<EOF || { error "Failed to create report file"; return 1; }
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project": "$PROJECT_DIR",
  "mode": "$MODE",
  "languages": "$LANGUAGES",
  "summary": {
    "total": $total,
    "critical": $CRITICAL,
    "high": $HIGH,
    "medium": $MEDIUM,
    "low": $LOW
  },
  "findings": [
EOF

    if [ -f "$FINDINGS_FILE" ]; then
        # Add findings with proper JSON formatting
        local first=true
        while IFS= read -r finding; do
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$REPORT_FILE"
            fi
            echo "    $finding" >> "$REPORT_FILE"
        done < "$FINDINGS_FILE"
        echo "" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" <<EOF
  ]
}
EOF

    # Display summary
    echo ""
    echo "=================================="
    echo "Security Scan Summary"
    echo "=================================="
    echo "Total findings: $total"
    echo "CRITICAL: $CRITICAL"
    echo "HIGH: $HIGH"
    echo "MEDIUM: $MEDIUM"
    echo "LOW: $LOW"
    echo "=================================="
    echo ""

    # Display critical findings
    if [ $CRITICAL -gt 0 ]; then
        error "CRITICAL issues found!"
        if [ -f "$FINDINGS_FILE" ]; then
            grep '"severity":"CRITICAL"' "$FINDINGS_FILE" | while read -r line; do
                local file=$(echo "$line" | jq -r '.file')
                local lineno=$(echo "$line" | jq -r '.line')
                local desc=$(echo "$line" | jq -r '.description')
                echo "  - $file:$lineno - $desc"
            done
        fi
        echo ""
    fi

    # Display the report (don't fail if it doesn't exist)
    if [ -f "$REPORT_FILE" ]; then
        cat "$REPORT_FILE"
    else
        error "Report file not generated"
    fi
}

# ============================================================================
# Telegram Notification
# ============================================================================

send_telegram_notification() {
    if [ ${CRITICAL:-0} -eq 0 ]; then
        return 0
    fi

    if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ]; then
        warn "Telegram credentials not set (BOT_TOKEN, CHAT_ID)"
        return 0
    fi

    log "Sending Telegram notification..."

    local message="🚨 *CRITICAL Security Issues Found*%0A%0A"
    message+="Project: \`$PROJECT_DIR\`%0A"
    message+="Critical: $CRITICAL%0A"
    message+="High: $HIGH%0A"
    message+="Medium: $MEDIUM%0A"
    message+="Low: $LOW%0A%0A"

    if [ -f "$FINDINGS_FILE" ]; then
        local count=0
        grep '"severity":"CRITICAL"' "$FINDINGS_FILE" | while read -r line && [ $count -lt 5 ]; do
            local file=$(echo "$line" | jq -r '.file' | xargs basename)
            local lineno=$(echo "$line" | jq -r '.line')
            local desc=$(echo "$line" | jq -r '.description')
            message+="• \`$file:$lineno\` - $desc%0A"
            ((count++))
        done
    fi

    curl -s --max-time 10 --connect-timeout 5 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown" \
        > /dev/null || warn "Failed to send Telegram notification"
}

# ============================================================================
# Cleanup
# ============================================================================

cleanup() {
    rm -f "$FINDINGS_FILE" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log "Starting security validation..."
    log "Project: $PROJECT_DIR"
    log "Mode: $MODE"

    # Validate project directory
    if [ ! -d "$PROJECT_DIR" ]; then
        error "Project directory not found: $PROJECT_DIR"
        exit 1
    fi

    # Initialize findings file
    : > "$FINDINGS_FILE"

    # Detect languages
    LANGUAGES=$(detect_languages)

    if [ -z "$LANGUAGES" ]; then
        warn "No supported languages detected. Skipping language-specific checks."
    fi

    # Run security checks
    check_hardcoded_secrets
    check_sql_injection
    check_xss
    check_command_injection

    if [ "$MODE" = "--full" ]; then
        check_insecure_deserialization
        check_path_traversal
    fi

    # Generate report
    generate_report

    # Send notification if critical issues found
    send_telegram_notification

    # Cleanup temporary files (except report)
    # Report file is intentionally kept for further analysis

    # Exit with appropriate code
    if [ $CRITICAL -gt 0 ]; then
        error "Security scan failed: CRITICAL issues found"
        exit 1
    else
        success "Security scan completed successfully"
        exit 0
    fi
}

# Run main function
main "$@"
