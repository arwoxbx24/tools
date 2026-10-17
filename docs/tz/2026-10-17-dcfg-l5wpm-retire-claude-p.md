# TZ — retire the 3 `claude -p` bypass routes in acc1-scripts (atom dcfg-l5wpm)

Owner 16.10/17.10: Claude models run only through `bin/sdk-agent` ("sdk Агент единственный", "никто не может его обойти").
Fact: `acc1-scripts/delegate-task.sh:77`, `:122` and `acc1-scripts/delegate-to-codex.sh:41` start `claude -p ... --dangerously-skip-permissions` with their own `CLAUDE_CONFIG_DIR` — a headless Claude run outside sdk-agent (no model pin, no budget, no daily cap).
Callers: `git grep` finds only comments/usage strings; `pm2 ls` has no delegate process. So the routes are refused, not rerouted.
Reconnaissance — repowise (lead: `grep -n` on the named lines); index: repowise checked.

## U1
FILE: acc1-scripts/delegate-task.sh

1. Line 77 (the line that starts with `    RESULT=$(CLAUDE_CONFIG_DIR="$ALEX_CONFIG"`): replace the whole line with exactly:
   `    RESULT=$(echo "refused: Claude runs only via /root/workspaces/tools/bin/sdk-agent (owner 17.10, dcfg-l5wpm)" >&2; exit 3)`
2. Line 122 (the line that starts with `    RESULT=$(CLAUDE_CONFIG_DIR="$EXPERT_CONFIG"`): replace the whole line with exactly the same new line as in item 1.
3. Nothing else changes in this file.

## U2
FILE: acc1-scripts/delegate-to-codex.sh

1. Line 41 (the line that starts with `    RESULT=$(CLAUDE_CONFIG_DIR="/root/workspaces/tools/acc1-scripts" claude -p`): replace the whole line with exactly:
   `    RESULT=$(echo "refused: Claude runs only via /root/workspaces/tools/bin/sdk-agent (owner 17.10, dcfg-l5wpm)" >&2; exit 3) || {`
   (the existing failure block on lines 42-47 stays and now always runs).
2. Nothing else changes in this file.

## Edit paths
Every edit `path` is exactly the repo-relative path listed: `acc1-scripts/delegate-task.sh`, `acc1-scripts/delegate-to-codex.sh`. Never an absolute path.

Lead check after the run (no Check line — the TZ edits these files):
- `grep -c 'claude -p'` on each of the 2 files → 0;
- `grep -c 'refused: Claude runs only via'` → 2 in delegate-task.sh, 1 in delegate-to-codex.sh;
- `bash -n` on each file → rc 0.

## Bans
No commit, no push, no new files, no other files. Do not run the scripts. Do not read or print `.env`, secrets, `/root/workspaces/secrets/**`, `~/.ssh`, `/etc`, `auth.json`. Code principles: KISS, YAGNI, minimal diff, no unrelated changes.
