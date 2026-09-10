#!/bin/bash
# Sync issue type: labels to GitHub Projects V2 Type field using GraphQL
# Usage: bash sync-project-type-field.sh ISSUE_NUMBER

set -e

ISSUE_NUMBER="$1"
GITHUB_USER="arwoxbx24"
REPO="claude-state"

# Load configuration
CONFIG_FILE="/root/workspaces/tools/acc1-scripts/.projects-config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[NO] Configuration not found: $CONFIG_FILE"
    echo "Run get-project-info.sh first"
    exit 1
fi

source "$CONFIG_FILE"

if [ -z "$ISSUE_NUMBER" ]; then
    echo "Usage: $0 ISSUE_NUMBER"
    exit 1
fi

echo "=========================================="
echo "  SYNC TYPE FIELD TO PROJECTS V2"
echo "=========================================="
echo ""
echo "Issue: #$ISSUE_NUMBER"
echo "Project: #$PROJECT_NUMBER"
echo ""

# Step 1: Get issue labels
echo "[1/4] Getting issue labels..."
LABELS=$(gh issue view $ISSUE_NUMBER --repo "$GITHUB_USER/$REPO" \
  --json labels --jq '.labels[].name' 2>/dev/null)

if [ -z "$LABELS" ]; then
    echo "[NO] Issue #$ISSUE_NUMBER not found"
    exit 1
fi

# Step 2: Extract type from label
TYPE_LABEL=$(echo "$LABELS" | grep "^type:" | head -1)
case "$TYPE_LABEL" in
    "type:epic")
        TYPE_VALUE="Epic"
        TYPE_OPTION_ID="$TYPE_OPTION_EPIC"
        ;;
    "type:plan")
        TYPE_VALUE="Plan"
        TYPE_OPTION_ID="$TYPE_OPTION_PLAN"
        ;;
    "type:task")
        TYPE_VALUE="Task"
        TYPE_OPTION_ID="$TYPE_OPTION_TASK"
        ;;
    *)
        echo "[WARN] No type: label found"
        echo "Available labels:"
        echo "$LABELS" | sed 's/^/  - /'
        exit 0
        ;;
esac

echo "[OK] Detected type: $TYPE_VALUE"
echo ""

# Step 3: Get project item ID for this issue
echo "[2/4] Finding issue in project..."
PROJECT_ITEM=$(gh api graphql -f query='
  query($org: String!, $number: Int!) {
    organization(login: $org) {
      projectV2(number: $number) {
        items(first: 100) {
          nodes {
            id
            content {
              ... on Issue {
                number
              }
            }
          }
        }
      }
    }
  }' -f org="$GITHUB_USER" -F number="$PROJECT_NUMBER")

PROJECT_ITEM_ID=$(echo "$PROJECT_ITEM" | jq -r ".data.organization.projectV2.items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .id")

if [ -z "$PROJECT_ITEM_ID" ]; then
    echo "[WARN] Issue #$ISSUE_NUMBER not found in project"
    echo "Adding to project first..."

    # Get issue node ID
    ISSUE_NODE_ID=$(gh api repos/$GITHUB_USER/$REPO/issues/$ISSUE_NUMBER --jq '.node_id')

    # Add issue to project
    gh api graphql -f query='
      mutation($projectId: ID!, $contentId: ID!) {
        addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
          item {
            id
          }
        }
      }' -f projectId="$PROJECT_ID" -f contentId="$ISSUE_NODE_ID" > /dev/null

    # Get item ID again
    sleep 1
    PROJECT_ITEM=$(gh api graphql -f query='
      query($org: String!, $number: Int!) {
        organization(login: $org) {
          projectV2(number: $number) {
            items(first: 100) {
              nodes {
                id
                content {
                  ... on Issue {
                    number
                  }
                }
              }
            }
          }
        }
      }' -f org="$GITHUB_USER" -F number="$PROJECT_NUMBER")

    PROJECT_ITEM_ID=$(echo "$PROJECT_ITEM" | jq -r ".data.organization.projectV2.items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .id")
fi

echo "[OK] Project item ID: $PROJECT_ITEM_ID"
echo ""

# Step 4: Update Type field
echo "[3/4] Updating Type field to '$TYPE_VALUE'..."
RESULT=$(gh api graphql -f query='
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
  }' -f projectId="$PROJECT_ID" -f itemId="$PROJECT_ITEM_ID" -f fieldId="$TYPE_FIELD_ID" -f optionId="$TYPE_OPTION_ID")

if echo "$RESULT" | jq -e '.data.updateProjectV2ItemFieldValue' > /dev/null 2>&1; then
    echo "[OK] Type field updated successfully"
else
    echo "[NO] Failed to update Type field"
    echo "$RESULT"
    exit 1
fi

echo ""
echo "[4/4] Verification..."
echo "Visit: https://github.com/orgs/$GITHUB_USER/projects/$PROJECT_NUMBER"
echo "Issue #$ISSUE_NUMBER should show Type: $TYPE_VALUE"
echo ""
echo "=========================================="
echo "[OK] Sync complete!"
echo "=========================================="
