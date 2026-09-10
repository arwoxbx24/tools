#!/bin/bash
# Validate that issue can be closed
# Usage: bash validate-issue-close.sh <issue_number>
# Returns exit code 1 if validation fails

ISSUE_NUMBER=$1
REPO="arwoxbx24/claude-state"

if [ -z "$ISSUE_NUMBER" ]; then
    echo "ERROR: Issue number required"
    exit 1
fi

echo "=== Validating Issue #$ISSUE_NUMBER ==="

# Get issue body and comments
BODY=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json body -q '.body' 2>/dev/null)
COMMENTS=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json comments -q '.comments[].body' 2>/dev/null)
ALL_CONTENT="$BODY $COMMENTS"

# Check for unchecked items
UNCHECKED=$(echo "$BODY" | grep -c '\- \[ \]' 2>/dev/null)
UNCHECKED=${UNCHECKED:-0}

if [ "$UNCHECKED" -gt 0 ]; then
    echo ""
    echo "❌ VALIDATION FAILED: $UNCHECKED unchecked items in checklist"
    echo ""
    echo "Unchecked items:"
    echo "$BODY" | grep '\- \[ \]'
    echo ""
    echo "Complete checklist before closing!"
    exit 1
fi

# Check for Russian language in body or comments
if ! echo "$ALL_CONTENT" | grep -qE "Результат|Итог|Завершено|Выполнено|RU:|Задача"; then
    echo ""
    echo "⚠️  WARNING: No Russian language results found in body or comments"
    echo "Add Russian summary before closing"
fi

echo ""
echo "✅ Validation passed - issue can be closed"
exit 0
