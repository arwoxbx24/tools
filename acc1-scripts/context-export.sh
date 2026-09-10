#!/bin/bash
# Context Export & Transfer System
# Exports current context for transfer to another account
# Run: bash /root/workspaces/tools/acc1-scripts/scripts/context-export.sh

set -e

EXPORT_DIR="/root/workspaces/tools/acc1-scripts/exports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_FILE="$EXPORT_DIR/context_$TIMESTAMP.md"

mkdir -p "$EXPORT_DIR"

echo "========================================"
echo "  CONTEXT EXPORT SYSTEM"
echo "  $(date)"
echo "========================================"

# Start export
cat > "$EXPORT_FILE" << 'HEADER'
# Context Transfer Package

This file contains exported context for transfer to a new account/session.

## Transfer Instructions

1. Copy this file to new environment
2. Read it at session start: `Read /path/to/context_*.md`
3. Agent will have full context continuity

---

HEADER

echo ""
echo "[1/5] Exporting active GitHub issues..."
echo "" >> "$EXPORT_FILE"
echo "## Active GitHub Issues" >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"
echo '```' >> "$EXPORT_FILE"
gh issue list --repo arwoxbx24/claude-state --state open --json number,title,labels,body \
    --jq '.[] | "### Issue #\(.number): \(.title)\nLabels: \([.labels[].name] | join(\", \"))\n\(.body)\n---"' \
    >> "$EXPORT_FILE" 2>/dev/null || echo "No issues found" >> "$EXPORT_FILE"
echo '```' >> "$EXPORT_FILE"

echo "[2/5] Exporting recent session history..."
echo "" >> "$EXPORT_FILE"
echo "## Recent Session History (last 20 messages)" >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"
echo '```' >> "$EXPORT_FILE"
if [ -f "/root/workspaces/tools/acc1-scripts/history.jsonl" ]; then
    tail -20 /root/workspaces/tools/acc1-scripts/history.jsonl | \
        python3 -c "import sys,json; [print(json.loads(l).get('display','')[:200]) for l in sys.stdin]" \
        >> "$EXPORT_FILE" 2>/dev/null || echo "Could not parse history" >> "$EXPORT_FILE"
fi
echo '```' >> "$EXPORT_FILE"

echo "[3/5] Exporting index statistics..."
echo "" >> "$EXPORT_FILE"
echo "## Vector Index Statistics" >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"
if [ -f "/root/workspaces/tools/acc1-scripts/data/vectors.db" ]; then
    echo '```' >> "$EXPORT_FILE"
    sqlite3 /root/workspaces/tools/acc1-scripts/data/vectors.db << 'SQL' >> "$EXPORT_FILE" 2>/dev/null
SELECT 'Total chunks: ' || COUNT(*) FROM code_chunks;
SELECT 'Total files: ' || COUNT(DISTINCT file_path) FROM code_chunks;
SELECT 'Languages: ' || GROUP_CONCAT(DISTINCT language) FROM code_chunks;
SQL
    echo '```' >> "$EXPORT_FILE"
else
    echo "No vector database found" >> "$EXPORT_FILE"
fi

echo "[4/5] Exporting API status..."
echo "" >> "$EXPORT_FILE"
echo "## API Status" >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"
echo '```json' >> "$EXPORT_FILE"
if [ -f "/root/workspaces/tools/acc1-scripts/data/api-status.json" ]; then
    cat /root/workspaces/tools/acc1-scripts/data/api-status.json >> "$EXPORT_FILE"
else
    echo '{"status": "no data"}' >> "$EXPORT_FILE"
fi
echo '```' >> "$EXPORT_FILE"

echo "[5/5] Exporting current tasks..."
echo "" >> "$EXPORT_FILE"
echo "## Pending Tasks" >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"
echo "Check GitHub Issues for active tasks:" >> "$EXPORT_FILE"
echo "- https://github.com/arwoxbx24/claude-state/issues" >> "$EXPORT_FILE"
echo "- https://github.com/orgs/arwoxbx24/projects/1" >> "$EXPORT_FILE"

# Summary
echo ""
echo "========================================"
echo "  EXPORT COMPLETE"
echo "========================================"
echo ""
echo "Exported to: $EXPORT_FILE"
echo "Size: $(wc -c < "$EXPORT_FILE") bytes"
echo ""
echo "To transfer:"
echo "  1. Copy file to new environment"
echo "  2. Start new session"
echo "  3. Run: Read $EXPORT_FILE"
echo ""

# Cleanup old exports (keep last 5)
ls -t "$EXPORT_DIR"/context_*.md 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
