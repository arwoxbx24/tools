# TZ dcfg-cvyea.7 — deliver the live statusline panel files into tools

Atom: dcfg-cvyea.7 (with dcfg-43aqf: SDK cap from sdk-agent DAILY_CAP/MAX_BUDGET + .inflight). Copies of the live files from the main checkout, copied by place-files (fix dcfg-bf6pk).

## U1

FILE: hooks/statusline-segment.sh
FILE: hooks/statusline-segment-test.sh
FILE: ccstatusline/package.json
FILE: ccstatusline/package-lock.json

Check: `bash hooks/statusline-segment-test.sh` → PASS 25/25. Panel config ~/.config/ccstatusline/settings.json (contour-config) calls hooks/statusline-segment.sh <field>.
