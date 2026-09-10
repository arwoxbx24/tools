#!/bin/bash
# Claude Code - Junior Mode
# Role: Helper, simple tasks only

claude \
  --model haiku \
  --append-system-prompt "JUNIOR MODE: Simple fixes <50 lines. Tests, docs. Ask Senior before architectural changes." \
  "$@"
