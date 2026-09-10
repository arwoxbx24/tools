#!/bin/bash
# Git commit wrapper with auto-identity detection
# Usage: bash git-commit.sh "commit message"
# Or with explicit account: ACCOUNT=acc2 bash git-commit.sh "message"

MESSAGE="$1"
ACCOUNT="${ACCOUNT:-acc1}"

if [ -z "$MESSAGE" ]; then
    echo "Usage: bash git-commit.sh \"commit message\""
    echo "       ACCOUNT=acc2 bash git-commit.sh \"message\""
    exit 1
fi

# Detect account from CLAUDE_CONFIG_DIR or default
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
    if echo "$CLAUDE_CONFIG_DIR" | grep -q "acc2\|alex"; then
        ACCOUNT="acc2"
    else
        ACCOUNT="acc1"
    fi
fi

# Set identity based on account
case "$ACCOUNT" in
    acc1|expert)
        export GIT_AUTHOR_NAME="Claude Expert"
        export GIT_AUTHOR_EMAIL="expert@arwox.ru"
        export GIT_COMMITTER_NAME="Claude Expert"
        export GIT_COMMITTER_EMAIL="expert@arwox.ru"
        ;;
    acc2|alex)
        export GIT_AUTHOR_NAME="Claude ALEX"
        export GIT_AUTHOR_EMAIL="alex@arwox.ru"
        export GIT_COMMITTER_NAME="Claude ALEX"
        export GIT_COMMITTER_EMAIL="alex@arwox.ru"
        ;;
    *)
        echo "Unknown account: $ACCOUNT"
        exit 1
        ;;
esac

echo "Committing as: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
git commit -m "$MESSAGE

Co-Authored-By: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
