# TZ — code-channel: OpenCode Go as fallback after sdk (goal item 3, atom dcfg-s4k5j)

Owner /goal 17.10 item (3): "у канала кода есть запасной исполнитель после SDK, как требует закон"; owner 17.10 order: close the goal.
sdk stays first (priority); go is the next ladder entry, used only when sdk fails.

## U1
FILE: config/code-channel.json

1. Ladder entry `go`: `"enabled": false` → `"enabled": true`. Order unchanged (sdk first). Nothing else changes.

Check: `jq -c '[.ladder[] | select(.enabled) | .id]' config/code-channel.json` → `["sdk","go"]`.
Rollback: set `go` back to `"enabled": false`.
