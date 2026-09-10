#!/bin/bash
# Sync GitHub Issue status to Projects V2 board
# Usage: bash sync-project-status.sh ISSUE_NUMBER STATUS
# STATUS: todo | in-progress | blocked | done

set -e

GITHUB_USER="arwoxbx24"
REPO="claude-state"
CONFIG_FILE="/root/workspaces/tools/acc1-scripts/.projects-config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE"
    exit 1
fi

# Validate arguments
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 ISSUE_NUMBER STATUS"
    echo "STATUS: todo | in-progress | blocked | done"
    exit 1
fi

ISSUE_NUMBER=$1
STATUS=$2

# Map status to option ID
case "$STATUS" in
    todo)
        OPTION_ID="$STATUS_OPTION_TODO"
        ;;
    in-progress)
        OPTION_ID="$STATUS_OPTION_IN_PROGRESS"
        ;;
    blocked)
        OPTION_ID="$STATUS_OPTION_BLOCKED"
        ;;
    done)
        OPTION_ID="$STATUS_OPTION_DONE"
        ;;
    *)
        echo "[ERROR] Invalid status: $STATUS"
        echo "Valid: todo | in-progress | blocked | done"
        exit 1
        ;;
esac

echo "[1/4] Getting Issue node ID for #$ISSUE_NUMBER..."
ISSUE_NODE_ID=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_USER/$REPO" --json id -q .id)

if [ -z "$ISSUE_NODE_ID" ]; then
    echo "[ERROR] Issue #$ISSUE_NUMBER not found"
    exit 1
fi
echo "      Issue node ID: $ISSUE_NODE_ID"

echo "[2/4] Finding item in Projects..."
# Try direct query via issue node
ITEM_ID=$(gh api graphql -f query="query { node(id: \"$ISSUE_NODE_ID\") { ... on Issue { projectItems(first: 1) { nodes { id } } } } }" --jq '.data.node.projectItems.nodes[0].id' 2>/dev/null)

# If not found in project, add it first
if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" == "null" ]; then
    echo "      Issue not in project, adding..."
    ADD_RESULT=$(gh api graphql -f query="
      mutation {
        addProjectV2ItemById(input: {
          projectId: \"$PROJECT_ID\"
          contentId: \"$ISSUE_NODE_ID\"
        }) {
          item { id }
        }
      }")
    ITEM_ID=$(echo "$ADD_RESULT" | jq -r '.data.addProjectV2ItemById.item.id')
    echo "      Added to project, item ID: $ITEM_ID"
else
    echo "      Found item ID: $ITEM_ID"
fi

echo "[3/4] Updating status to '$STATUS'..."
UPDATE_RESULT=$(gh api graphql -f query='
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: {singleSelectOptionId: $optionId}
    }) {
      projectV2Item {
        id
      }
    }
  }' -f projectId="$PROJECT_ID" -f itemId="$ITEM_ID" -f fieldId="$STATUS_FIELD_ID" -f optionId="$OPTION_ID")

echo "[4/4] Verifying..."
if echo "$UPDATE_RESULT" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null 2>&1; then
    echo "[OK] Issue #$ISSUE_NUMBER status updated to '$STATUS'"
else
    echo "[ERROR] Failed to update status"
    echo "$UPDATE_RESULT"
    exit 1
fi
