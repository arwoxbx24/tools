#!/usr/bin/env bash
# claude-version-pe-notify.sh — Create PE notification when Ink bug is fixed
# Called by claude-version-check.sh with latest version as $1

set -euo pipefail

LATEST_VERSION="${1:-unknown}"
PINNED_VERSION="$(claude --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo 'unknown')"
NOTIFY_DIR="/root/workspaces/tools/acc1-scripts/pe-notifications"
NOTIFY_FILE="${NOTIFY_DIR}/ink-bug-fixed.md"
CREATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

mkdir -p "$NOTIFY_DIR"

cat > "$NOTIFY_FILE" <<EOF
---
type: notification
priority: high
created: ${CREATED_AT}
---
# Ink Renderer Bug Fixed

Issues #16310 and #41814 are CLOSED.
Latest version: v${LATEST_VERSION}
Current pinned: v${PINNED_VERSION}

## Action Required
1. Update: npm install -g @anthropic-ai/claude-code@${LATEST_VERSION}
2. Re-enable auto-updates in /root/.claude.json: rename _COMMENTED_autoUpdatesProtectedForNative back to autoUpdatesProtectedForNative
EOF

echo "PE notification written to $NOTIFY_FILE"
