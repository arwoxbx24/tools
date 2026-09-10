#!/bin/bash
# Git Identity for Account 1 (Expert/Orchestrator)
# Sets environment variables for git commits

export GIT_AUTHOR_NAME="Claude Expert"
export GIT_AUTHOR_EMAIL="expert@arwox.ru"
export GIT_COMMITTER_NAME="Claude Expert"
export GIT_COMMITTER_EMAIL="expert@arwox.ru"

# Can be sourced: source /root/workspaces/tools/acc1-scripts/scripts/git-identity.sh
# Or called to show current identity:
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Git Identity: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
fi
