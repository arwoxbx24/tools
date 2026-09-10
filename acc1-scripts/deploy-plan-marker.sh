#!/bin/bash
# deploy-plan-marker.sh — V212: Sets deploy plan marker after agent completes pre-deploy checklist
# Usage: bash /root/workspaces/tools/acc1-scripts/scripts/deploy-plan-marker.sh "description" [plan-file-path]
# V212: Agent MUST run this AFTER completing SNAPSHOT→DIFF→PLAN steps
# Arguments:
#   $1 = description (required, non-empty) — what is being deployed
#   $2 = plan-file-path (optional) — must exist in /root/workspaces/tools/acc1-scripts/plans/
set +e

MARKER="/tmp/.deploy-plan-marker"
MARKER_LEGACY="/tmp/.deploy-plan-ready"
PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"

# ── ARG VALIDATION ──

DESCRIPTION="${1:-}"
PLAN_FILE="${2:-}"

# No args at all
if [[ $# -eq 0 ]]; then
    echo "Usage: deploy-plan-marker.sh \"description\" [plan-file-path]" >&2
    echo "  description   — what is being deployed (required, non-empty)" >&2
    echo "  plan-file-path — path to plan file in $PLANS_DIR/ (optional)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  deploy-plan-marker.sh \"Deploy nginx config update\"" >&2
    echo "  deploy-plan-marker.sh \"Deploy hook fixes\" \"/root/workspaces/tools/acc1-scripts/plans/active-plan.md\"" >&2
    exit 1
fi

# Empty description
if [[ -z "$DESCRIPTION" ]]; then
    echo "ERROR: Description cannot be empty." >&2
    echo "Usage: deploy-plan-marker.sh \"description\" [plan-file-path]" >&2
    exit 1
fi

# Validate plan file if provided
if [[ -n "$PLAN_FILE" ]]; then
    # Must exist
    if [[ ! -f "$PLAN_FILE" ]]; then
        echo "ERROR: Plan file not found: $PLAN_FILE" >&2
        echo "Plan file must exist in: $PLANS_DIR/" >&2
        exit 1
    fi
    # Must be inside PLANS_DIR
    REAL_PLAN=$(realpath "$PLAN_FILE" 2>/dev/null || echo "$PLAN_FILE")
    REAL_PLANS=$(realpath "$PLANS_DIR" 2>/dev/null || echo "$PLANS_DIR")
    if [[ "$REAL_PLAN" != "$REAL_PLANS"/* ]]; then
        echo "ERROR: Plan file must be inside $PLANS_DIR/" >&2
        echo "Got: $PLAN_FILE" >&2
        exit 1
    fi
fi

# ── BUILD MARKER CONTENT ──

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")

if [[ -n "$PLAN_FILE" ]]; then
    CHECKSUM=$(sha256sum "$PLAN_FILE" 2>/dev/null | awk '{print $1}')
    CHECKSUM="${CHECKSUM:-$(echo -n "$DESCRIPTION" | sha256sum | awk '{print $1}')}"
else
    CHECKSUM=$(echo -n "$DESCRIPTION" | sha256sum | awk '{print $1}')
fi

# ── WRITE MARKER FILES ──

{
    echo "TIMESTAMP=$TIMESTAMP"
    echo "DESCRIPTION=$DESCRIPTION"
    if [[ -n "$PLAN_FILE" ]]; then
        echo "PLAN_FILE=$PLAN_FILE"
    fi
    echo "CHECKSUM=$CHECKSUM"
} > "$MARKER"

# Write legacy marker so enforce-pre-deploy-plan.sh hook still passes
touch "$MARKER_LEGACY" 2>/dev/null

# Set Redis key (10-min TTL)
redis-cli SET "session:deploy_plan_ready" "1" EX 600 2>/dev/null || true

echo "V212: Deploy plan marker SET. Agent may now execute deploy commands (valid 10 min)." >&2
echo "DESCRIPTION: $DESCRIPTION" >&2
if [[ -n "$PLAN_FILE" ]]; then
    echo "PLAN_FILE:   $PLAN_FILE" >&2
fi
echo "CHECKSUM:    $CHECKSUM" >&2
echo "REMINDER: Marker is ONE-TIME USE — cleared after first deploy command." >&2
