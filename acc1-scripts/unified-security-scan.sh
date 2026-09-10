#!/bin/bash
# Unified Security Scanner — orchestrates all security tools
# PM2 daemon, runs daily at 04:00, sequential mode (OOM protection)
# V192: Security Scanning
set +e

export PATH="$PATH:/root/.local/bin:/usr/local/bin"

SCAN_TARGET="/root/claude-projects"
REPORT_DIR="/root/workspaces/tools/acc1-scripts/pm2/reports/security"
DATE=$(date +%Y%m%d)
TIMESTAMP=$(date -Iseconds)
START_TIME=$(date +%s)
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# Counters
TOOLS_RUN=()
TOOLS_SKIPPED=()
SEMGREP_TOTAL=0; SEMGREP_HIGH=0; SEMGREP_CRITICAL=0
TRIVY_TOTAL=0; TRIVY_HIGH=0; TRIVY_CRITICAL=0
GITLEAKS_TOTAL=0
BANDIT_TOTAL=0; BANDIT_HIGH=0
PIP_AUDIT_TOTAL=0
NPM_AUDIT_TOTAL=0

mkdir -p "$REPORT_DIR"

echo "================================================================"
echo "$LOG_PREFIX UNIFIED SECURITY SCAN STARTED"
echo "================================================================"
echo "Target: $SCAN_TARGET"
echo "Reports: $REPORT_DIR"
echo ""

# Memory guard: skip tool if available memory < 300MB
check_memory() {
    local avail
    avail=$(free -m | awk '/^Mem:/ {print $7}')
    if [ "$avail" -lt 300 ]; then
        echo "$LOG_PREFIX SKIP: Available memory ${avail}MB < 300MB threshold" >&2
        return 1
    fi
    return 0
}

# ================================================================
# TOOL 1: SEMGREP (SAST — multi-language)
# ================================================================
echo "$LOG_PREFIX [1/6] Running Semgrep..."
if check_memory && command -v semgrep &>/dev/null; then
    SEMGREP_REPORT="$REPORT_DIR/semgrep-$DATE.json"
    timeout 300 semgrep scan "$SCAN_TARGET" \
        --config=p/security-audit \
        --json \
        --quiet \
        --timeout=30 \
        --max-target-bytes=500000 \
        -j 1 \
        --exclude='node_modules' \
        --exclude='vendor' \
        --exclude='.git' \
        --exclude='docker-stacks' \
        > "$SEMGREP_REPORT" 2>/dev/null

    if [ -f "$SEMGREP_REPORT" ] && [ -s "$SEMGREP_REPORT" ]; then
        SEMGREP_TOTAL=$(jq '.results | length' "$SEMGREP_REPORT" 2>/dev/null || echo 0)
        SEMGREP_HIGH=$(jq '[.results[] | select(.extra.severity == "WARNING")] | length' "$SEMGREP_REPORT" 2>/dev/null || echo 0)
        SEMGREP_CRITICAL=$(jq '[.results[] | select(.extra.severity == "ERROR")] | length' "$SEMGREP_REPORT" 2>/dev/null || echo 0)
        TOOLS_RUN+=("semgrep")
        echo "$LOG_PREFIX   Semgrep: $SEMGREP_TOTAL findings ($SEMGREP_HIGH high, $SEMGREP_CRITICAL critical)"
    else
        echo "$LOG_PREFIX   Semgrep: no output or failed"
        TOOLS_SKIPPED+=("semgrep")
    fi
else
    echo "$LOG_PREFIX   Semgrep: SKIPPED (memory or not installed)"
    TOOLS_SKIPPED+=("semgrep")
fi

# ================================================================
# TOOL 2: TRIVY (Dependencies + Filesystem)
# ================================================================
echo "$LOG_PREFIX [2/6] Running Trivy..."
if check_memory && command -v trivy &>/dev/null; then
    TRIVY_REPORT="$REPORT_DIR/trivy-$DATE.json"
    timeout 300 trivy fs "$SCAN_TARGET" \
        --severity HIGH,CRITICAL \
        --format json \
        --timeout 5m \
        --scanners vuln \
        --skip-dirs 'node_modules,vendor,.git,.archive,docker-stacks,moltbook-agent' \
        > "$TRIVY_REPORT" 2>/dev/null

    if [ -f "$TRIVY_REPORT" ] && [ -s "$TRIVY_REPORT" ]; then
        TRIVY_TOTAL=$(jq '[.Results[]? | .Vulnerabilities[]?] | length' "$TRIVY_REPORT" 2>/dev/null || echo 0)
        TRIVY_HIGH=$(jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$TRIVY_REPORT" 2>/dev/null || echo 0)
        TRIVY_CRITICAL=$(jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$TRIVY_REPORT" 2>/dev/null || echo 0)
        TOOLS_RUN+=("trivy")
        echo "$LOG_PREFIX   Trivy: $TRIVY_TOTAL findings ($TRIVY_HIGH high, $TRIVY_CRITICAL critical)"
    else
        echo "$LOG_PREFIX   Trivy: no output or failed"
        TOOLS_SKIPPED+=("trivy")
    fi
else
    echo "$LOG_PREFIX   Trivy: SKIPPED (memory or not installed)"
    TOOLS_SKIPPED+=("trivy")
fi

# ================================================================
# TOOL 3: GITLEAKS (Secret Scanning)
# ================================================================
echo "$LOG_PREFIX [3/6] Running Gitleaks..."
if check_memory && command -v gitleaks &>/dev/null; then
    GITLEAKS_REPORT="$REPORT_DIR/gitleaks-$DATE.json"
    timeout 300 gitleaks detect \
        --source "$SCAN_TARGET" \
        --no-git \
        --report-format json \
        --report-path "$GITLEAKS_REPORT" \
        2>/dev/null

    if [ -f "$GITLEAKS_REPORT" ] && [ -s "$GITLEAKS_REPORT" ]; then
        GITLEAKS_TOTAL=$(jq 'length' "$GITLEAKS_REPORT" 2>/dev/null || echo 0)
        TOOLS_RUN+=("gitleaks")
        echo "$LOG_PREFIX   Gitleaks: $GITLEAKS_TOTAL secrets found"
    else
        GITLEAKS_TOTAL=0
        TOOLS_RUN+=("gitleaks")
        echo "$LOG_PREFIX   Gitleaks: clean (no secrets found)"
    fi
else
    echo "$LOG_PREFIX   Gitleaks: SKIPPED (memory or not installed)"
    TOOLS_SKIPPED+=("gitleaks")
fi

# ================================================================
# TOOL 4: BANDIT (Python SAST)
# ================================================================
echo "$LOG_PREFIX [4/6] Running Bandit..."
PY_COUNT=$(find "$SCAN_TARGET" -name "*.py" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" 2>/dev/null | wc -l)
if [ "$PY_COUNT" -gt 0 ] && check_memory && command -v bandit &>/dev/null; then
    BANDIT_REPORT="$REPORT_DIR/bandit-$DATE.json"
    timeout 300 bandit -r "$SCAN_TARGET" \
        -f json \
        --exclude "node_modules,vendor,.git,__pycache__,venv,.venv" \
        -ll \
        --quiet \
        > "$BANDIT_REPORT" 2>/dev/null

    if [ -f "$BANDIT_REPORT" ] && [ -s "$BANDIT_REPORT" ]; then
        BANDIT_TOTAL=$(jq '.results | length' "$BANDIT_REPORT" 2>/dev/null || echo 0)
        BANDIT_HIGH=$(jq '[.results[] | select(.issue_severity == "HIGH")] | length' "$BANDIT_REPORT" 2>/dev/null || echo 0)
        TOOLS_RUN+=("bandit")
        echo "$LOG_PREFIX   Bandit: $BANDIT_TOTAL findings ($BANDIT_HIGH high) from $PY_COUNT Python files"
    else
        echo "$LOG_PREFIX   Bandit: no output or failed"
        TOOLS_SKIPPED+=("bandit")
    fi
else
    echo "$LOG_PREFIX   Bandit: SKIPPED (no Python files: $PY_COUNT or memory/not installed)"
    TOOLS_SKIPPED+=("bandit")
fi

# ================================================================
# TOOL 5: PIP-AUDIT (Python Dependencies)
# ================================================================
echo "$LOG_PREFIX [5/6] Running pip-audit..."
REQ_FILES=$(find "$SCAN_TARGET" -name "requirements.txt" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)
if [ -n "$REQ_FILES" ] && check_memory && command -v pip-audit &>/dev/null; then
    PIP_REPORT="$REPORT_DIR/pip-audit-$DATE.json"
    echo "[]" > "$PIP_REPORT"
    while IFS= read -r req_file; do
        timeout 120 pip-audit -r "$req_file" --format json 2>/dev/null | jq '.dependencies[]? | select(.vulns | length > 0)' >> "$PIP_REPORT" 2>/dev/null
    done <<< "$REQ_FILES"
    PIP_AUDIT_TOTAL=$(jq -s 'length' "$PIP_REPORT" 2>/dev/null || echo 0)
    TOOLS_RUN+=("pip-audit")
    echo "$LOG_PREFIX   pip-audit: $PIP_AUDIT_TOTAL vulnerable packages"
else
    echo "$LOG_PREFIX   pip-audit: SKIPPED (no requirements.txt or memory/not installed)"
    TOOLS_SKIPPED+=("pip-audit")
fi

# ================================================================
# TOOL 6: NPM AUDIT (JS Dependencies)
# ================================================================
echo "$LOG_PREFIX [6/6] Running npm audit..."
LOCK_FILES=$(find "$SCAN_TARGET" -name "package-lock.json" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)
if [ -n "$LOCK_FILES" ] && check_memory; then
    NPM_REPORT="$REPORT_DIR/npm-audit-$DATE.json"
    echo "[]" > "$NPM_REPORT"
    while IFS= read -r lock_file; do
        proj_dir=$(dirname "$lock_file")
        cd "$proj_dir" 2>/dev/null || continue
        timeout 120 npm audit --json 2>/dev/null | jq '{advisories: .advisories // {}, vulnerabilities: .vulnerabilities // {}}' >> "$NPM_REPORT" 2>/dev/null
        cd - >/dev/null 2>&1
    done <<< "$LOCK_FILES"
    NPM_AUDIT_TOTAL=$(jq -s '[.[].vulnerabilities // {} | to_entries | length] | add // 0' "$NPM_REPORT" 2>/dev/null || echo 0)
    TOOLS_RUN+=("npm-audit")
    echo "$LOG_PREFIX   npm audit: $NPM_AUDIT_TOTAL vulnerabilities"
else
    echo "$LOG_PREFIX   npm audit: SKIPPED (no package-lock.json or memory)"
    TOOLS_SKIPPED+=("npm-audit")
fi

# ================================================================
# UNIFIED REPORT
# ================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

TOTAL_FINDINGS=$((SEMGREP_TOTAL + TRIVY_TOTAL + GITLEAKS_TOTAL + BANDIT_TOTAL + PIP_AUDIT_TOTAL + NPM_AUDIT_TOTAL))
CRITICAL_COUNT=$((SEMGREP_CRITICAL + TRIVY_CRITICAL))

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    STATUS="critical"
elif [ "$TOTAL_FINDINGS" -gt 50 ]; then
    STATUS="warning"
else
    STATUS="ok"
fi

TOOLS_RUN_JSON=$(printf '%s\n' "${TOOLS_RUN[@]}" | jq -R . | jq -s .)
TOOLS_SKIPPED_JSON=$(printf '%s\n' "${TOOLS_SKIPPED[@]}" | jq -R . | jq -s .)

UNIFIED_REPORT="$REPORT_DIR/unified-$DATE.json"
cat > "$UNIFIED_REPORT" << EOFUNIFIED
{
    "timestamp": "$TIMESTAMP",
    "scan_duration_seconds": $DURATION,
    "tools_run": $TOOLS_RUN_JSON,
    "tools_skipped": $TOOLS_SKIPPED_JSON,
    "findings": {
        "semgrep": {"total": $SEMGREP_TOTAL, "high": $SEMGREP_HIGH, "critical": $SEMGREP_CRITICAL},
        "trivy": {"total": $TRIVY_TOTAL, "high": $TRIVY_HIGH, "critical": $TRIVY_CRITICAL},
        "gitleaks": {"total": $GITLEAKS_TOTAL},
        "bandit": {"total": $BANDIT_TOTAL, "high": $BANDIT_HIGH},
        "pip_audit": {"total": $PIP_AUDIT_TOTAL},
        "npm_audit": {"total": $NPM_AUDIT_TOTAL}
    },
    "total_findings": $TOTAL_FINDINGS,
    "critical_count": $CRITICAL_COUNT,
    "status": "$STATUS"
}
EOFUNIFIED

echo ""
echo "================================================================"
echo "$LOG_PREFIX RESULTS"
echo "================================================================"
echo "Duration: ${DURATION}s"
echo "Tools run: ${TOOLS_RUN[*]}"
echo "Tools skipped: ${TOOLS_SKIPPED[*]}"
echo ""
echo "Findings:"
echo "  Semgrep (SAST):     $SEMGREP_TOTAL ($SEMGREP_HIGH high, $SEMGREP_CRITICAL critical)"
echo "  Trivy (deps):       $TRIVY_TOTAL ($TRIVY_HIGH high, $TRIVY_CRITICAL critical)"
echo "  Gitleaks (secrets): $GITLEAKS_TOTAL"
echo "  Bandit (Python):    $BANDIT_TOTAL ($BANDIT_HIGH high)"
echo "  pip-audit:          $PIP_AUDIT_TOTAL"
echo "  npm audit:          $NPM_AUDIT_TOTAL"
echo "  ─────────────────────"
echo "  TOTAL:              $TOTAL_FINDINGS"
echo "  CRITICAL:           $CRITICAL_COUNT"
echo "  STATUS:             $STATUS"
echo ""

# Redis: save scan summary (30 day TTL)
REDIS_SUMMARY=$(jq -c . "$UNIFIED_REPORT" 2>/dev/null)
redis-cli SET "security:scan:$DATE" "$REDIS_SUMMARY" EX 2592000 >/dev/null 2>&1

# Redis: alert if critical
if [ "$STATUS" = "critical" ]; then
    redis-cli SET "security:alert:$DATE" "{\"critical\":$CRITICAL_COUNT,\"total\":$TOTAL_FINDINGS,\"timestamp\":\"$TIMESTAMP\"}" EX 604800 >/dev/null 2>&1
    echo "$LOG_PREFIX ALERT: $CRITICAL_COUNT critical findings! Check $UNIFIED_REPORT"
fi

# Cleanup: delete reports older than 30 days
find "$REPORT_DIR" -name "*.json" -mtime +30 -delete 2>/dev/null
CLEANED=$(find "$REPORT_DIR" -name "*.json" -mtime +30 2>/dev/null | wc -l)

echo ""
echo "Reports saved to: $REPORT_DIR"
echo "Redis key: security:scan:$DATE"
echo ""
echo "================================================================"
echo "$LOG_PREFIX UNIFIED SECURITY SCAN COMPLETED"
echo "================================================================"
