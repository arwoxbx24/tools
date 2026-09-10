#!/bin/bash
# show-mode-status.sh
# Shows current active thinking mode for statusLine

MODE=""

# Check for brainstorm mode
if [ -f /tmp/claude_brainstorm_active ]; then
  MODE="🧠 BRAINSTORM"
fi

# Check for ultrathink mode (higher priority)
if [ -f /tmp/claude_ultrathink_active ]; then
  MODE="⚡ ULTRATHINK"
fi

# Output if mode is active
if [ -n "$MODE" ]; then
  echo -e "\033[1;33m[$MODE]\033[0m "
fi
