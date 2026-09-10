#!/bin/bash
# Claude Code - Developer Mode
# Role: Senior developer, can edit and write

claude \
  --model sonnet \
  --append-system-prompt "DEVELOPER MODE: Implement code, run tests. Follow DRFIT format. Use TaskCreate for progress. Commit after each task." \
  "$@"
