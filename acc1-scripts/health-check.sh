#!/bin/bash
# Health Check — Session Start Verification
# Run at the beginning of every agent session

# Load centralized PE detection library
PE_LIB="$(dirname "$0")/../hooks/lib/pe-detect.sh"
[[ -f "$PE_LIB" ]] && source "$PE_LIB"

# Run backup cleanup silently
/root/workspaces/tools/acc1-scripts/scripts/backup-cleanup.sh 2>/dev/null

# V102: Cleanup ghost markers (task ended but PostToolUse didn't run)
# Delete markers older than 5 minutes
find /tmp -name ".v102-subagent-active" -mmin +5 -delete 2>/dev/null

# V213: Clean stale per-session project locks (older than 60 min)
find /tmp -maxdepth 1 -name ".project-dir-lock-*" -mmin +60 -delete 2>/dev/null
# Also clean legacy global lock if exists
rm -f /tmp/.project-dir-lock

CHECKS=0
PASSED=0

[[ "${VERBOSE:-0}" == "1" ]] && echo "🏥 HEALTH CHECK — Session Start"
[[ "${VERBOSE:-0}" == "1" ]] && echo "================================"

# 1. Redis connectivity
if redis-cli PING 2>/dev/null | grep -q PONG; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 1. Redis: Connected"
    ((PASSED++))
else
    echo "❌ 1. Redis: FAILED" >&2
fi
((CHECKS++))

# 2. ACS initialized (DB 2)
if redis-cli -n 2 GET "acs:version" 2>/dev/null | grep -q "1.0"; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 2. ACS: Initialized"
    ((PASSED++))
else
    echo "❌ 2. ACS: Not initialized (run acs-init.sh)" >&2
fi
((CHECKS++))

# 3. Active issue check
if [ -f /root/workspaces/tools/acc1-scripts/data/active-issue.txt ]; then
    ISSUE=$(cat /root/workspaces/tools/acc1-scripts/data/active-issue.txt 2>/dev/null)
    if [ -n "$ISSUE" ]; then
        [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 3. Active Issue: #$ISSUE"
        ((PASSED++))
    else
        [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️ 3. Active Issue: Empty (create issue first)"
        ((PASSED++))  # Warning, not failure
    fi
else
    [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️ 3. Active Issue: No file (will create on first task)"
    ((PASSED++))  # Warning, not failure
fi
((CHECKS++))

# 4. CLAUDE.md readable
if [ -f /root/workspaces/tools/acc1-scripts/CLAUDE.md ]; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 4. CLAUDE.md: Found"
    ((PASSED++))
else
    echo "❌ 4. CLAUDE.md: MISSING" >&2
fi
((CHECKS++))

# 5. Critical hooks exist
HOOKS_OK=true
MISSING_HOOKS=""
for hook in token-guard-read.sh block-haiku.sh commit-blocker.sh; do
    if [ ! -f /root/workspaces/tools/acc1-scripts/hooks/$hook ]; then
        HOOKS_OK=false
        MISSING_HOOKS="$MISSING_HOOKS $hook"
    fi
done
if $HOOKS_OK; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 5. Hooks: All present"
    ((PASSED++))
else
    echo "⚠️ 5. Hooks: Missing:$MISSING_HOOKS" >&2
    ((PASSED++))  # Warning, not failure
fi
((CHECKS++))

# 6. Claude Auth Status
if command -v claude &>/dev/null; then
    AUTH_JSON=$(unset CLAUDECODE && claude auth status 2>/dev/null)
    if echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
        AUTH_PLAN=$(echo "$AUTH_JSON" | grep -o '"subscriptionType": "[^"]*"' | cut -d'"' -f4)
        [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 6. Claude Auth: OK ($AUTH_PLAN)"
        ((PASSED++))
    else
        echo "❌ 6. Claude Auth: NOT LOGGED IN" >&2
    fi
else
    [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️ 6. Claude Auth: binary not found"
    ((PASSED++))
fi
((CHECKS++))

# 7. Docker Backup Status
BACKUP_STATUS=$(bash /root/workspaces/tools/acc1-scripts/scripts/docker-backup-check.sh 2>/dev/null)
if [ $? -eq 0 ]; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 7. Docker Backup: $BACKUP_STATUS"
    ((PASSED++))
else
    [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️ 7. Docker Backup: $BACKUP_STATUS"
    ((PASSED++))  # Warning, not failure
fi
((CHECKS++))

# 8. AIRS Health (Agent Incident Report System)
((CHECKS++))
AIRS_ALERT="/root/workspaces/tools/acc1-scripts/data/airs-alert.txt"
AIRS_TODAY=$(redis-cli -n 2 LLEN "acs:incidents:$(date +%Y-%m-%d)" 2>/dev/null || echo "0")
if [ -f "$AIRS_ALERT" ]; then
    AIRS_LINE=$(cat "$AIRS_ALERT" 2>/dev/null)
    AIRS_FILE_DATE=$(echo "$AIRS_LINE" | cut -d'|' -f1)
    AIRS_MSG=$(echo "$AIRS_LINE" | cut -d'|' -f2-)
    if [ "$AIRS_FILE_DATE" = "$(date +%Y-%m-%d)" ]; then
        echo "⚠️  8. AIRS: CRITICAL — ${AIRS_TODAY} incidents today, trend: growing (run: review-incidents.sh)" >&2
    else
        [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 8. AIRS: Alert stale ($AIRS_FILE_DATE), ${AIRS_TODAY} incidents today"
        rm -f "$AIRS_ALERT"
        ((PASSED++))
    fi
else
    if [ "$AIRS_TODAY" -gt 0 ] 2>/dev/null; then
        [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 8. AIRS: ${AIRS_TODAY} incidents today (below threshold)"
    else
        [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 8. AIRS: Clean"
    fi
    ((PASSED++))
fi

# 9. Backup Watcher Status
WATCHER_STATUS=$(pm2 show backup-watcher 2>/dev/null | grep "status" | head -1 | awk '{print $4}')
STRAY_BACKUPS=$(find /root/workspaces/tools/acc1-scripts/ \( -name "*.backup" -o -name "*.bak" -o -name "*.backup.*" -o -name "*.backup-*" -o -name "*.bak-*" -o -name "*.bak.*" \) -not -path "*/backups/*" 2>/dev/null | wc -l)
if [[ "$WATCHER_STATUS" == "online" ]] && [[ "$STRAY_BACKUPS" -eq 0 ]]; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 9. Backup Watcher: online, 0 stray files"
    ((PASSED++))
elif [[ "$WATCHER_STATUS" == "online" ]]; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️ 9. Backup Watcher: online, $STRAY_BACKUPS stray files found"
    ((PASSED++))
else
    echo "❌ 9. Backup Watcher: $WATCHER_STATUS (should be online)" >&2
fi
((CHECKS++))

# 10. PE Marker Staleness
((CHECKS++))
PE_MARKER="/tmp/.teamlead-agent-session"
if [ -f "$PE_MARKER" ]; then
    PE_AGE=$(( ($(date +%s) - $(stat -c %Y "$PE_MARKER")) / 3600 ))
    if [ "$PE_AGE" -gt 24 ]; then
        [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️  10. PE Marker: STALE (${PE_AGE}h old) — auto-removed"
        rm -f "$PE_MARKER"
        ((PASSED++))
    else
        [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 10. PE Marker: Active (${PE_AGE}h old)"
        ((PASSED++))
    fi
else
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 10. PE Marker: Not set"
    ((PASSED++))
fi

# 11. GitHub Issue Alerts (closed issues from Anthropic)
((CHECKS++))
ALERTS_DIR="/root/workspaces/tools/acc1-scripts/data/issue-closed-alerts"
ALERT_COUNT=0
if [ -d "$ALERTS_DIR" ]; then
    ALERT_COUNT=$(find "$ALERTS_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
fi
if [ "$ALERT_COUNT" -gt 0 ]; then
    echo "" >&2
    echo "🚨 11. GitHub Issues: $ALERT_COUNT CLOSED ISSUE(S) DETECTED!" >&2
    for ALERT_FILE in "$ALERTS_DIR"/*.json; do
        [ -f "$ALERT_FILE" ] || continue
        A_NUM=$(jq -r '.number' "$ALERT_FILE" 2>/dev/null)
        A_TITLE=$(jq -r '.title' "$ALERT_FILE" 2>/dev/null)
        A_PRIORITY=$(jq -r '.priority' "$ALERT_FILE" 2>/dev/null)
        A_ACTION=$(jq -r '.action_on_close' "$ALERT_FILE" 2>/dev/null)
        A_REASON=$(jq -r '.state_reason' "$ALERT_FILE" 2>/dev/null)
        echo "    ISSUE #$A_NUM [$A_PRIORITY]: $A_TITLE" >&2
        echo "      Reason: $A_REASON" >&2
        echo "      Action: $A_ACTION" >&2
        echo "      PE: process alert then move to processed/" >&2
    done
    echo "" >&2
else
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 11. GitHub Issues: No closed issue alerts"
    ((PASSED++))
fi


# 12. Anthropic Status
((CHECKS++))
INCIDENT_FILE="/root/workspaces/tools/acc1-scripts/data/anthropic-incidents.txt"
if [ -f "$INCIDENT_FILE" ] && [ -s "$INCIDENT_FILE" ]; then
    echo "⚠️  12. Anthropic Status: INCIDENTS DETECTED" >&2
    cat "$INCIDENT_FILE" >&2
    ((PASSED++))
else
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 12. Anthropic Status: All services operational"
    ((PASSED++))
fi

# 13. Timeweb AI MCP reminder
((CHECKS++))
[[ "${VERBOSE:-0}" == "1" ]] && echo "✅ 13. Timeweb AI MCP: ОПЛАЧЕН (5 моделей, при 3+ агентах = 1 через mcp__timeweb-ai)"
((PASSED++))

# Clean stale hook state files (>8h old)
find /tmp -maxdepth 1 -name '.block-streak-*' -mmin +480 -delete 2>/dev/null
find /tmp -maxdepth 1 -name '.bash-sequence-*' -mmin +480 -delete 2>/dev/null
find /tmp -maxdepth 1 -name '.opus-call-count-*' -mmin +480 -delete 2>/dev/null
find /tmp -maxdepth 1 -name '.project-dir-lock-*' -mmin +480 -delete 2>/dev/null
find /tmp -maxdepth 1 -name 'claude-loop-tracker*' -mmin +480 -delete 2>/dev/null

[[ "${VERBOSE:-0}" == "1" ]] && echo "Cleaned stale /tmp hook files"
[[ "${VERBOSE:-0}" == "1" ]] && echo "================================"
[[ "${VERBOSE:-0}" == "1" ]] && echo "Result: $PASSED/$CHECKS passed"
[[ "${VERBOSE:-0}" == "1" ]] && echo ""

if [ $PASSED -eq $CHECKS ]; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "✅ HEALTH CHECK PASSED — Ready to work"
    # Log to Redis
    redis-cli -n 2 SET "acs:health_check:$(date +%Y-%m-%d)" "PASSED" EX 86400 >/dev/null 2>&1
    # Create session-init marker for enforce-session-init.sh hook
    # Session init marker — use all recent sessions (health-check is global)
    PROJECTS_DIR="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects"
    for JSONL_FILE in $(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -5); do
        CURRENT_SESSION=$(basename "$JSONL_FILE" .jsonl)
        [ -n "$CURRENT_SESSION" ] && date +%s > "/tmp/.session-init-done-${CURRENT_SESSION:0:16}"
    done
    exit 0
else
    echo "⚠️ HEALTH CHECK INCOMPLETE — Fix issues above" >&2
    redis-cli -n 2 SET "acs:health_check:$(date +%Y-%m-%d)" "FAILED" EX 86400 >/dev/null 2>&1
    exit 1
fi
