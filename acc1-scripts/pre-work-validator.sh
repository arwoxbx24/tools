#!/bin/bash
# pre-work-validator.sh
# Checks if there's an open GitHub issue assigned to current user
# Returns exit 0 if issues exist, exit 0 with warning if PE/init session, exit 1 if DEV and no issue

set +e

# Detect session mode
IS_PE=0
[ -f "/tmp/.teamlead-agent-session" ] && IS_PE=1

SESSION_MODE=$(redis-cli GET "session:mode" 2>/dev/null || echo "")
[ "$SESSION_MODE" = "(nil)" ] && SESSION_MODE=""

# Quick check for open issues assigned to current user
ISSUE_COUNT=$(gh issue list --assignee @me --state open --limit 1 --json number --jq 'length' 2>/dev/null || echo "0")

if [[ "$ISSUE_COUNT" -gt 0 ]]; then
    # Issues exist — save current issue number to Redis
    ISSUE_NUM=$(gh issue list --assignee @me --state open --limit 1 --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [[ -n "$ISSUE_NUM" && "$ISSUE_NUM" != "null" ]]; then
        redis-cli SET "current_issue" "$ISSUE_NUM" EX 86400 >/dev/null 2>&1 || true
    fi
    exit 0
fi

# No issues found — check if PE session or fresh init
if [[ "$IS_PE" -eq 1 || "$SESSION_MODE" == "PE" || "$SESSION_MODE" == "init" ]]; then
    [[ "${VERBOSE:-0}" == "1" ]] && echo "⚠️ No active issue. Will auto-create when task is assigned."
    redis-cli SET "session:issue-pending" "true" EX 7200 >/dev/null 2>&1 || true
    exit 0
fi

# Regular DEV session with no issue — require one
echo "❌ NO OPEN ISSUES ASSIGNED TO YOU" >&2
echo "Create GitHub issue before starting work:" >&2
echo "  gh issue create --title \"Task description\" --body \"Details\"" >&2
exit 1
