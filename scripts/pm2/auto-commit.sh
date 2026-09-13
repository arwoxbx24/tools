#!/bin/bash
# Smart Auto-commit with AI-generated messages
# Fallback chain: Groq → OpenAI → Simple format
# Runs via pm2, commits every 3 minutes if changes exist

set +e

LOG_FILE="/root/workspaces/system/tools/scripts/logs/git-auto-commit.log"
ENV_FILE="/root/workspaces/system/tools/scripts/config/.env"
mkdir -p "$(dirname "$LOG_FILE")"

# Load API keys from file (PRIORITY over system env)
if [[ -f "$ENV_FILE" ]]; then
    # Unset system keys first to ensure file has priority
    unset GROQ_API_KEY OPENAI_API_KEY 2>/dev/null || true
    source "$ENV_FILE"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Generate message via Groq (primary)
query_groq() {
    local PROMPT="$1"

    [[ -z "${GROQ_API_KEY:-}" ]] && return 1

    # Escape prompt for JSON (replace newlines, quotes)
    local ESCAPED_PROMPT=$(echo "$PROMPT" | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c1-1000)

    local RESPONSE=$(curl -s --max-time 10 https://api.groq.com/openai/v1/chat/completions \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"llama-3.1-8b-instant\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"Generate git commit message. Output ONLY message (max 72 chars). Format: type: description\"},
                {\"role\": \"user\", \"content\": \"$ESCAPED_PROMPT\"}
            ],
            \"max_tokens\": 50,
            \"temperature\": 0.3
        }" 2>/dev/null)

    # Extract and clean message
    local MSG=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null | tr -d '"' | head -1 | cut -c1-72)
    [[ -n "$MSG" ]] && echo "$MSG"
}

# Generate message via OpenAI (fallback)
query_openai() {
    local PROMPT="$1"

    [[ -z "${OPENAI_API_KEY:-}" ]] && return 1

    # Escape prompt for JSON
    local ESCAPED_PROMPT=$(echo "$PROMPT" | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c1-1000)

    local RESPONSE=$(curl -s --max-time 10 https://api.openai.com/v1/chat/completions \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"gpt-4o-mini\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"Generate git commit message. Output ONLY message (max 72 chars). Format: type: description\"},
                {\"role\": \"user\", \"content\": \"$ESCAPED_PROMPT\"}
            ],
            \"max_tokens\": 50,
            \"temperature\": 0.3
        }" 2>/dev/null)

    local MSG=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null | tr -d '"' | head -1 | cut -c1-72)
    [[ -n "$MSG" ]] && echo "$MSG"
}

# Query Ollama (local, free)
query_ollama() {
    local PROMPT="$1"

    # Check if ollama is running
    if ! curl -s --max-time 2 http://localhost:11434/api/tags &>/dev/null; then
        return 1
    fi

    local RESPONSE=$(curl -s --max-time 15 http://localhost:11434/api/generate \
        -d '{
            "model": "llama3.2:1b",
            "prompt": "Generate a concise git commit message (max 72 chars) for: '"${PROMPT//\"/\\\"}"'",
            "stream": false
        }' 2>/dev/null)

    echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null | head -1 | cut -c1-72
}

# Smart heuristic - analyze files to generate message (NO AI needed)
generate_heuristic_message() {
    local FILES="$1"

    # Detect type by file patterns
    local TYPE="chore"
    local SCOPE=""
    local DESC=""

    # Analyze file names
    if echo "$FILES" | grep -qE "\.md$"; then
        TYPE="docs"
    fi
    if echo "$FILES" | grep -qE "test|spec"; then
        TYPE="test"
    fi
    if echo "$FILES" | grep -qE "fix|bug|patch"; then
        TYPE="fix"
    fi
    if echo "$FILES" | grep -qE "feat|feature|add"; then
        TYPE="feat"
    fi

    # Detect scope from path
    if echo "$FILES" | grep -q "reference/"; then
        SCOPE="rules"
    elif echo "$FILES" | grep -q "scripts/"; then
        SCOPE="scripts"
    elif echo "$FILES" | grep -q "hooks/"; then
        SCOPE="hooks"
    elif echo "$FILES" | grep -q "CLAUDE"; then
        SCOPE="config"
    fi

    # Build description from first changed file
    local FIRST_FILE=$(echo "$FILES" | head -1 | sed 's/.*\///' | sed 's/\.[^.]*$//')
    DESC="update $FIRST_FILE"

    # Format message
    if [[ -n "$SCOPE" ]]; then
        echo "$TYPE($SCOPE): $DESC"
    else
        echo "$TYPE: $DESC"
    fi
}

# Generate commit body with anchors for agent context recovery
generate_commit_body() {
    local FILES_STAT="$1"
    local FILES_LIST="$2"
    local REPO_NAME="$3"

    # Section: Files Changed (anchor: [FILES])
    echo "[FILES]"
    echo "$FILES_STAT" | head -15 | sed 's/^/• /'
    echo ""

    # Section: Categories (anchor: [SCOPE])
    echo "[SCOPE]"
    echo "$FILES_LIST" | grep -q "\.md$" && echo "• docs"
    echo "$FILES_LIST" | grep -q "\.sh$" && echo "• scripts"
    echo "$FILES_LIST" | grep -qE "config|\.env|\.json" && echo "• config"
    echo "$FILES_LIST" | grep -qE "reference/|CLAUDE" && echo "• rules"
    echo "$FILES_LIST" | grep -q "\.js$" && echo "• code"
    echo "$FILES_LIST" | grep -q "\.py$" && echo "• python"
    echo ""

    # Section: Stats (anchor: [STATS])
    local INSERTIONS=$(echo "$FILES_STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
    local DELETIONS=$(echo "$FILES_STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
    local FILE_COUNT=$(echo "$FILES_LIST" | wc -l | tr -d ' ')
    echo "[STATS] +${INSERTIONS} -${DELETIONS} lines, ${FILE_COUNT} files"
    echo ""

    # Section: Context (anchor: [CONTEXT])
    echo "[CONTEXT] repo=$REPO_NAME time=$(date '+%H:%M')"
}

# Generate smart commit message with fallback chain
# Chain: Groq → OpenAI → Ollama → Heuristic (100% uptime)
# Returns: title + body for full context
generate_commit_message() {
    local DIFF="$1"
    local FILES_COUNT="$2"
    local FILES_LIST="$3"
    local REPO_NAME="${4:-unknown}"

    # Skip AI if diff is empty
    if [[ -z "$DIFF" ]]; then
        echo "chore: sync changes ($FILES_COUNT files)"
        return
    fi

    # Truncate diff (max 1500 chars for API)
    local TRUNCATED_DIFF="${DIFF:0:1500}"
    local PROMPT="Generate a concise git commit message for these changes:\n\n$TRUNCATED_DIFF"

    local TITLE=""

    # 1. Try Groq first (fastest)
    TITLE=$(query_groq "$PROMPT" 2>/dev/null)
    if [[ -n "$TITLE" ]] && [[ "$TITLE" != "null" ]] && [[ ${#TITLE} -gt 5 ]]; then
        log "AI: Groq OK"
    else
        # 2. Fallback to OpenAI
        TITLE=$(query_openai "$PROMPT" 2>/dev/null)
        if [[ -n "$TITLE" ]] && [[ "$TITLE" != "null" ]] && [[ ${#TITLE} -gt 5 ]]; then
            log "AI: OpenAI OK"
        else
            # 3. Fallback to Ollama
            TITLE=$(query_ollama "$PROMPT" 2>/dev/null)
            if [[ -n "$TITLE" ]] && [[ "$TITLE" != "null" ]] && [[ ${#TITLE} -gt 5 ]]; then
                log "AI: Ollama OK"
            else
                # 4. Final fallback - heuristic
                TITLE=$(generate_heuristic_message "$FILES_LIST")
                log "Heuristic: $TITLE"
            fi
        fi
    fi

    # Generate detailed body
    local BODY=$(generate_commit_body "$DIFF" "$FILES_LIST" "$REPO_NAME")

    # Return full message: title + body
    echo "$TITLE"
    echo ""
    echo "$BODY"
}

commit_dir() {
    local DIR="$1"
    local NAME="$2"

    cd "$DIR" || return 1

    # Init git if not exists
    if [ ! -d ".git" ]; then
        git init --quiet
        git branch -M main
        log "$NAME: Initialized git repo"
    fi

    # Check for changes
    if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
        return 0  # No changes
    fi

    # ---------------------------------------------------------------
    # Tier 1: Important files — stage and commit every run (3 min)
    # ---------------------------------------------------------------
    # ponytail: чужой staged = пропускаем цикл, подберём в следующий
    if ! git diff --cached --quiet 2>/dev/null; then
        log "[skip] index busy (foreign staged), repo=$NAME"
        return 0
    fi
    git add CLAUDE.md reference/ rules-data/ templates/ schedulers/ config/ skills/ plugins/ settings.json 2>/dev/null
    git add *.yaml *.md 2>/dev/null  # root level only
    # Remove accidentally staged data files from Tier 1
    git reset HEAD -- data/ logs/ action-logs/ 2>/dev/null

    if ! git diff --cached --quiet 2>/dev/null; then
        local CHANGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
        local DIFF=$(git diff --cached --stat 2>/dev/null || echo "")
        local FILES_LIST=$(git diff --cached --name-only 2>/dev/null)

        local COMMIT_MSG=$(generate_commit_message "$DIFF" "$CHANGED" "$FILES_LIST" "$NAME")
        git commit -m "$COMMIT_MSG" --quiet 2>/dev/null

        if [ $? -eq 0 ]; then
            local HASH=$(git rev-parse --short HEAD)
            log "$NAME [tier1]: $HASH - $COMMIT_MSG"

            # Push to remote if configured
            if git remote get-url origin &>/dev/null; then
                git push origin "$(git rev-parse --abbrev-ref HEAD)" --quiet 2>/dev/null && log "$NAME: pushed to origin" || true
            fi
        fi
    fi

    # ---------------------------------------------------------------
    # Tier 2: Data files — stage everything, commit every 30 min
    # ---------------------------------------------------------------
    local TIMESTAMP_FILE="/tmp/.auto-commit-full-$(echo "$NAME" | tr '/' '-')"
    local FULL_INTERVAL=1800  # 30 minutes

    local should_full_commit=false
    if [[ ! -f "$TIMESTAMP_FILE" ]]; then
        should_full_commit=true
    elif [[ $(( $(date +%s) - $(stat -c %Y "$TIMESTAMP_FILE") )) -ge $FULL_INTERVAL ]]; then
        should_full_commit=true
    fi

    if $should_full_commit; then
        # ponytail: чужой staged = пропускаем цикл, подберём в следующий
        if ! git diff --cached --quiet 2>/dev/null; then
            log "[skip] index busy (foreign staged), repo=$NAME"
            return 0
        fi
        git add data/ docs/ logs/ action-logs/ .agent-work/receipts/ tools/llm-providers/usage.jsonl 2>/dev/null
        if ! git diff --cached --quiet 2>/dev/null; then
            local D_CHANGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
            local D_DIFF=$(git diff --cached --stat 2>/dev/null || echo "")
            local D_FILES=$(git diff --cached --name-only 2>/dev/null)

            local D_MSG=$(generate_commit_message "$D_DIFF" "$D_CHANGED" "$D_FILES" "$NAME")
            # Prefix data commits for easy identification
            D_MSG="[data] $D_MSG [skip ci]"
            git commit -m "$D_MSG" --quiet 2>/dev/null

            if [ $? -eq 0 ]; then
                local D_HASH=$(git rev-parse --short HEAD)
                log "$NAME [tier2]: $D_HASH - $D_MSG"

                # Push to remote if configured
                if git remote get-url origin &>/dev/null; then
                    git push origin "$(git rev-parse --abbrev-ref HEAD)" --quiet 2>/dev/null && log "$NAME: pushed to origin (data)" || true
                fi
            fi
        fi
        # Update timestamp regardless (even if nothing new to commit)
        touch "$TIMESTAMP_FILE"
    fi
}

# Repos excluded from auto-commit (have their own deploy mechanisms)
EXCLUDE_REPOS="stroyremont"

# Commit nested git repositories
commit_nested_repos() {
    local BASE_DIR="$1"

    find "$BASE_DIR" -maxdepth 4 -type d -name ".git" \
        ! -path "*/node_modules/*" \
        ! -path "*/vendor/*" \
        ! -path "*/.venv/*" \
        ! -path "*/venv/*" \
        2>/dev/null | while read gitdir; do

        local repo_dir=$(dirname "$gitdir")
        local repo_name=$(basename "$repo_dir")

        if [ "$repo_dir" = "$BASE_DIR" ]; then
            continue
        fi

        if echo "$EXCLUDE_REPOS" | grep -qw "$repo_name"; then
            continue
        fi

        commit_dir "$repo_dir" "nested:$repo_name"
    done
}

# Main execution (skip if sourced)
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

log "=== Smart Auto-commit started ==="

commit_dir "/root/workspaces/system/tools/scripts" "system-scripts"
commit_dir "/root/.claude_shared" "shared"
commit_dir "/root/workspaces/projects" "projects"

commit_nested_repos "/root/workspaces/projects"

log "=== Smart Auto-commit finished ==="
