#!/bin/bash
# Archives plan to GitHub issue then deletes
PLAN="$1"
if [ -z "$PLAN" ]; then echo "Usage: archive-plan.sh <plan-file>"; exit 1; fi
TITLE=$(head -1 "$PLAN" | sed 's/# //')
gh issue create --title "[PLAN] $TITLE" --body "$(cat $PLAN)" --repo arwoxbx24/claude-state && rm "$PLAN" && echo "Archived and deleted"
