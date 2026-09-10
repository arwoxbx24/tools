#!/bin/bash
# Claude Code - Expert/Architect Mode
# Role: Delegate only, no direct tool use

claude \
  --permission-mode delegate \
  --append-system-prompt "EXPERT MODE: You are an Architect. Delegate ALL work via Task tool. NO direct Read/Edit/Write/Bash. GitHub (gh) allowed for Issues/PR." \
  "$@"
