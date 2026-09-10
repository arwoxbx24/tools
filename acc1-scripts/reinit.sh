#!/bin/bash
# ============================================================================
# reinit.sh — Post-Clear/Compact Re-initialization
# Run after /clear or /compact to restore agent context
# ============================================================================

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  🔄 RE-INITIALIZATION — Post /clear or /compact             │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

# Step 0: Crash Recovery Check
echo "📋 STEP 0: Crash Recovery"
echo "────────────────────────"
REDIS_OK=$(redis-cli PING 2>/dev/null || echo "fail")
if [ "$REDIS_OK" = "PONG" ]; then
    # Check for pre-action checkpoint (indicates crash during tool)
    PRE_ACTION=$(redis-cli GET "context:pre-action" 2>/dev/null)
    if [ -n "$PRE_ACTION" ] && [ "$PRE_ACTION" != "null" ]; then
        echo "⚠️  CRASH DETECTED: Found pre-action checkpoint"
        echo ""
        echo "Last state before crash:"
        echo "$PRE_ACTION" | jq -r '"  Tool: \(.next_tool // "unknown")\n  Time: \(.timestamp // "unknown")\n  Messages: \(.message_count // 0)"' 2>/dev/null
        LAST_MSG=$(echo "$PRE_ACTION" | jq -r '.last_user_message // empty' 2>/dev/null | head -c 200)
        if [ -n "$LAST_MSG" ]; then
            echo "  Last user request:"
            echo "    $LAST_MSG"
        fi
        echo ""
        # Clear the pre-action checkpoint
        redis-cli DEL "context:pre-action" >/dev/null 2>&1
    fi

    # Show latest context (v2: with topics)
    LATEST=$(redis-cli GET "context:latest" 2>/dev/null)
    if [ -n "$LATEST" ] && [ "$LATEST" != "null" ]; then
        echo "📦 Latest saved context:"
        echo "$LATEST" | jq -r '"  Session: \(.session_id[0:8] // "unknown")...\n  Time: \(.timestamp // "unknown")\n  Issue: \(.active_issue // "none")\n  Messages: \(.message_count // 0)\n  Topics: \(.topics // "none")"' 2>/dev/null
        echo ""
    fi

    # V2: Show session registry stats
    REG_COUNT=$(redis-cli --scan --pattern "session:registry:*" 2>/dev/null | wc -l)
    TOPIC_COUNT=$(redis-cli --scan --pattern "topic:index:*" 2>/dev/null | wc -l)
    ARCHIVE_COUNT=$(redis-cli --scan --pattern "context:archive:*" 2>/dev/null | wc -l)
    echo "📊 Context System v2:"
    echo "  Registry: $REG_COUNT sessions indexed"
    echo "  Topics: $TOPIC_COUNT unique keywords"
    echo "  Archives: $ARCHIVE_COUNT individual session backups"
    echo ""

    # Check for current task
    CURRENT_TASK=$(redis-cli GET "task:current" 2>/dev/null)
    if [ -n "$CURRENT_TASK" ] && [ "$CURRENT_TASK" != "null" ]; then
        echo "📌 Unfinished task:"
        echo "$CURRENT_TASK" | jq -r '"  \(.subject // "unknown task")"' 2>/dev/null
        echo ""
    fi
else
    echo "⚠️ Redis not available — limited recovery"
fi
echo ""

# Step 1: Health Check
echo "📋 STEP 1: Health Check"
echo "────────────────────────"
bash /root/workspaces/tools/acc1-scripts/scripts/health-check.sh
HC_RESULT=$?
echo ""

# Step 2: System Checklist
echo "📋 STEP 2: Systems Checklist"
echo "────────────────────────────"
cat << 'EOF'
Agent MUST acknowledge understanding of:

┌─────────────────────────────────────────────────────────────┐
│ SYSTEM          │ KEY RULE                                  │
├─────────────────┼───────────────────────────────────────────┤
│ ACS             │ Log violations: acs-log.sh {agent} {code} │
│ DRFIT           │ 5 sections: Problem→Investigation→        │
│                 │ Solution→Result→Remaining                 │
│ Error Triage    │ CLASSIFY → LOCALIZE → ONE TEST → PROOF    │
│ Brainstorm      │ complexity ≥5 → 7 tentacles               │
│ Health Check    │ Run at session start                      │
│ GitHub Issue    │ NO WORK without issue                     │
└─────────────────┴───────────────────────────────────────────┘
EOF
echo ""

# Step 3: Quick Reference
echo "📋 STEP 3: Quick Commands"
echo "────────────────────────"
cat << 'EOF'
ACS Report:    bash /root/workspaces/tools/acc1-scripts/scripts/acs-report.sh
Health Check:  bash /root/workspaces/tools/acc1-scripts/scripts/health-check.sh
Link Validator: bash /root/workspaces/tools/acc1-scripts/scripts/link-validator.sh
Session Search: bash /root/workspaces/tools/acc1-scripts/scripts/session-search.sh --list
Topic Search:  bash /root/workspaces/tools/acc1-scripts/scripts/session-search.sh --keyword <word>
EOF
echo ""

# Final status
echo "────────────────────────────────────────────────────────────"
if [ $HC_RESULT -eq 0 ]; then
    echo "✅ RE-INITIALIZED: All systems ready"
    echo ""
    echo "Agent должен ответить:"
    echo "\"✅ Re-initialized: ACS, DRFIT, Error-Triage, Brainstorm — acknowledged\""
else
    echo "⚠️ RE-INITIALIZED with warnings — check Health Check output"
fi
# Create session-init marker for enforce-session-init.sh hook
PROJECTS_DIR="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects"
CURRENT_SESSION=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.jsonl$//')
if [ -n "$CURRENT_SESSION" ]; then
    date +%s > "/tmp/.session-init-done-${CURRENT_SESSION:0:16}"
fi
echo "────────────────────────────────────────────────────────────"
echo ""
