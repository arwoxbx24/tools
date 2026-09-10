#!/bin/bash
# OpenClaw Agent Helper Script
# Usage: openclaw-agent.sh [architect|developer] "message"

set -e

# Source environment
source ~/.nvm/nvm.sh 2>/dev/null
nvm use 22 >/dev/null 2>&1 || true
source /root/workspaces/tools/acc1-scripts/.env.global
export OPENAI_API_KEY

AGENT="${1:-architect}"
MESSAGE="${2:-Hello}"

if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "Error: OPENAI_API_KEY not set in /root/workspaces/tools/acc1-scripts/.env.global"
    exit 1
fi

openclaw agent --local --agent "$AGENT" --message "$MESSAGE"
