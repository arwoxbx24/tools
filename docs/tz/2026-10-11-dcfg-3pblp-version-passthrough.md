# TZ dcfg-3pblp — agent-browser wrapper: real `--version`

## U1 — remove the hardcoded `--version` branch
Worktree: /root/workspaces/tools/.worktrees/claude/dcfg-3pblp. Recon — repowise; index: repowise/CBM checked, missing → `tools/bin/code-memory-enable`.

Fact: `bin/agent-browser` has a `case` branch `--version) echo "agent-browser 0.39.0"; exit 0;;`. The wrapper then reports 0.39.0 even when the vendored binary is missing, broken or another version.

Change only `bin/agent-browser`: delete the `--version)` branch (3 lines) so `--version` falls through to `exec "$VENDOR_BIN" "$@"`. Keep the `-h|--help` branch (must still print `usage:`), the vendor auto-install, and the env exports unchanged. No other files.

Forbidden: rm -rf, git commit/push, editing outside the worktree, secrets, `~/.ssh`, `/etc`.

Acceptance:
1) `grep -c 'echo "agent-browser 0.39.0"' bin/agent-browser` → 0.
2) `bin/agent-browser --version` → `agent-browser 0.39.0` (now printed by the vendored binary).
3) `python3 tests/test_agent_tools.py` → OK.
