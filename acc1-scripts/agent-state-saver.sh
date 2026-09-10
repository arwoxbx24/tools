#!/bin/bash
# agent-state-saver.sh — V396 3-Level Mandatory State Commit
# Called by agents before reporting "done" to ensure full state persistence
# Levels: L1=Redis, L2=Local Git Commit, L3=Remote Git Push
# L0=Partial checkpoint for crash recovery

set +e

# === PARSE ARGS ===
PROJECT=""
SUMMARY=""
TYPE="build"
FILES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT="$2"; shift 2 ;;
        --summary) SUMMARY="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --files) FILES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# === SESSION/AGENT IDs ===
SESSION_ID="${CLAUDE_SESSION_ID:-}"
[[ -z "$SESSION_ID" ]] && SESSION_ID=$(cat /tmp/.claude-session-id 2>/dev/null || echo "")
[[ -z "$SESSION_ID" ]] && SESSION_ID="proc-${PPID:-$$}"
AGENT_ID="${CLAUDE_AGENT_ID:-agent-$$}"
CWD=$(pwd)
[[ -z "$PROJECT" ]] && PROJECT=$(basename "$CWD")
[[ -z "$SUMMARY" ]] && SUMMARY="Agent task completed"
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
TS=$(date -Iseconds)

LEVEL1_OK=0
LEVEL2_OK=0
LEVEL3_OK=0

# === LEVEL 0: Partial checkpoint (crash safety) ===
PARTIAL_KEY="checkpoint:partial:${SESSION_ID}:${AGENT_ID}"
redis-cli HSET "$PARTIAL_KEY" \
    "timestamp" "$TS" \
    "project" "$PROJECT" \
    "cwd" "$CWD" \
    "branch" "$BRANCH" \
    "task_summary" "$SUMMARY" \
    "type" "$TYPE" \
    "level1_ok" "0" "level2_ok" "0" "level3_ok" "0" \
    "status" "in_progress" >/dev/null 2>&1
redis-cli EXPIRE "$PARTIAL_KEY" 3600 >/dev/null 2>&1

# === LEVEL 1: Redis checkpoint ===
CHECKPOINT_KEY="checkpoint:${SESSION_ID}:${AGENT_ID}"
redis-cli HSET "$CHECKPOINT_KEY" \
    "timestamp" "$TS" \
    "project" "$PROJECT" \
    "branch" "$BRANCH" \
    "commit_sha" "$COMMIT_SHA" \
    "files_changed" "$FILES" \
    "task_summary" "$SUMMARY" \
    "agent_type" "$TYPE" \
    "level1_ok" "1" \
    "level2_ok" "0" \
    "level3_ok" "0" \
    "saved_by" "agent-state-saver.sh" >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    redis-cli EXPIRE "$CHECKPOINT_KEY" 86400 >/dev/null 2>&1
    redis-cli ZADD "checkpoint:index:${SESSION_ID}" "$(date +%s)" "$AGENT_ID" >/dev/null 2>&1
    redis-cli EXPIRE "checkpoint:index:${SESSION_ID}" 86400 >/dev/null 2>&1
    LEVEL1_OK=1
fi

# File fallback
FALLBACK_FILE="/tmp/checkpoint-${SESSION_ID:0:12}-${AGENT_ID:0:8}.json"
cat > "$FALLBACK_FILE" <<FEOF
{"session":"$SESSION_ID","agent":"$AGENT_ID","project":"$PROJECT","branch":"$BRANCH","commit":"$COMMIT_SHA","summary":"$SUMMARY","type":"$TYPE","ts":"$TS"}
FEOF
chmod 600 "$FALLBACK_FILE" 2>/dev/null
[[ $LEVEL1_OK -eq 0 && -f "$FALLBACK_FILE" ]] && LEVEL1_OK=1

# === LEVEL 2: Local git commit ===
if git rev-parse --is-inside-work-tree &>/dev/null; then
    GIT_DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' | grep -v '\.log$' | grep -v 'node_modules/' | grep -v '__pycache__/')
    if [[ -n "$GIT_DIRTY" ]]; then
        if [[ -n "$FILES" ]]; then
            for f in $FILES; do
                git add "$f" 2>/dev/null
            done
        else
            git add -u 2>/dev/null
        fi

        git commit -m "$(cat <<CEOF
[agent] ${SUMMARY}

Agent-Type: ${TYPE}
Session: ${SESSION_ID:0:8}
Files: ${FILES:-auto-staged}
V396: 3-level commit

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
CEOF
)" 2>/dev/null

        if [[ $? -eq 0 ]]; then
            COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null)
            LEVEL2_OK=1
        fi
    else
        # Nothing to commit = clean state = OK
        LEVEL2_OK=1
    fi
else
    # Not a git repo = exempt
    LEVEL2_OK=1
fi
redis-cli HSET "$CHECKPOINT_KEY" "level2_ok" "$LEVEL2_OK" "commit_sha" "$COMMIT_SHA" >/dev/null 2>&1

# === LEVEL 3: Remote git push ===
REMOTE=$(git remote 2>/dev/null | head -1)
if [[ -n "$REMOTE" ]]; then
    UNPUSHED=$(git log "${REMOTE}/${BRANCH}..HEAD" --oneline 2>/dev/null)
    if [[ -n "$UNPUSHED" ]]; then
        git push "$REMOTE" HEAD 2>/dev/null
        if [[ $? -eq 0 ]]; then
            LEVEL3_OK=1
        fi
    else
        # Nothing to push = already synced = OK
        LEVEL3_OK=1
    fi
else
    # No remote = exempt
    LEVEL3_OK=1
fi
redis-cli HSET "$CHECKPOINT_KEY" "level3_ok" "$LEVEL3_OK" "status" "complete" >/dev/null 2>&1

# Clean partial checkpoint
redis-cli DEL "$PARTIAL_KEY" >/dev/null 2>&1

# === OUTPUT: Structured 3-level report ===
L1_STATUS=$([[ $LEVEL1_OK -eq 1 ]] && echo "OK" || echo "FAIL")
L2_STATUS=$([[ $LEVEL2_OK -eq 1 ]] && echo "OK" || echo "FAIL")
L3_STATUS=$([[ $LEVEL3_OK -eq 1 ]] && echo "OK" || echo "FAIL")

echo ""
echo "STATE-COMMIT-REPORT:"
echo "| Level | Name             | Status |"
echo "|-------|------------------|--------|"
echo "| L1    | Redis checkpoint | ${L1_STATUS}     |"
echo "| L2    | Local git commit | ${L2_STATUS}     |"
echo "| L3    | Remote git push  | ${L3_STATUS}     |"
echo "Commit: ${COMMIT_SHA} | Branch: ${BRANCH} | Project: ${PROJECT}"
echo "Key: ${CHECKPOINT_KEY}"
echo "STATE-COMMIT-DONE"
