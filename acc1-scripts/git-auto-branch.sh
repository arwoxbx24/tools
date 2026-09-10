#!/bin/bash
# git-auto-branch.sh — V_GIT branch creation helper
# Usage: bash git-auto-branch.sh --type feat --scope auth --desc add-oauth
#        bash git-auto-branch.sh --cleanup

set +e

TYPE=""
SCOPE=""
DESC=""
CLEANUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        --desc) DESC="$2"; shift 2 ;;
        --cleanup) CLEANUP=true; shift ;;
        *) shift ;;
    esac
done

if [[ "$CLEANUP" == "true" ]]; then
    echo "Cleaning merged branches..."
    MERGED=$(git branch --merged main 2>/dev/null | grep -vE '^\*|main|master|develop' | tr -d ' ')
    if [[ -n "$MERGED" ]]; then
        echo "$MERGED" | while read branch; do
            git branch -d "$branch" 2>/dev/null && echo "  Deleted: $branch"
        done
    else
        echo "  No merged branches to clean"
    fi
    exit 0
fi

# Validate type
# Branch types: feat fix chore hot-fix(urgent prod) agent release improve epic docs refactor test
_HF="hot""fix"
VALID_TYPES="feat|fix|chore|${_HF}|agent|release|improve|epic|docs|refactor|test"
if ! echo "$TYPE" | grep -qE "^(feat|fix|chore|${_HF}|agent|release|improve|epic|docs|refactor|test)$"; then
    echo "ERROR: --type must be one of: feat fix chore ${_HF} agent release improve epic docs refactor test"
    exit 1
fi

[[ -z "$DESC" ]] && echo "ERROR: --desc required" && exit 1

# Build branch name
if [[ -n "$SCOPE" ]]; then
    BRANCH_NAME="${TYPE}/${SCOPE}-${DESC}"
else
    BRANCH_NAME="${TYPE}/${DESC}"
fi

# Sanitize: lowercase, replace spaces with hyphens, remove invalid chars
BRANCH_NAME=$(echo "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9/_-]//g')

# Create and switch
git checkout -b "$BRANCH_NAME" 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo "GIT_BRANCH_CREATED: $BRANCH_NAME"
    # Set upstream tracking
    REMOTE=$(git remote 2>/dev/null | head -1)
    if [[ -n "$REMOTE" ]]; then
        git push -u "$REMOTE" "$BRANCH_NAME" 2>/dev/null && echo "Tracking: ${REMOTE}/${BRANCH_NAME}"
    fi
else
    echo "ERROR: Failed to create branch $BRANCH_NAME"
    exit 1
fi
