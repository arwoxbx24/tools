# TZ dcfg-8kv99 — code-channel ladder: SDK only

Why: owner 16.10 "всё переводи на SDK". Run dcfg-oqtdg fell sdk→go after sdk rc=0 without changes; the go fallback hides SDK problems.

## U1 — config/code-channel.json
Skills: caveman:surgical-patch (one JSON value)
1. In `ladder`, set `"enabled": false` for the entry with `"id": "go"`. Nothing else changes.

Files: `config/code-channel.json`
