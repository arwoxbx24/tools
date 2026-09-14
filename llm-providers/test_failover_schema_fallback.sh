#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILOVER="$SOURCE_DIR/failover.sh"

python3 - "$FAILOVER" <<'PY'
import contextlib, io, json, pathlib, sys

source = pathlib.Path(sys.argv[1]).read_text()
start = source.index("payload = {")
marker = "print(json.dumps(payload))"
end = source.index(marker, start) + len(marker)
builder = source[start:end]

schema = {
    "type": "object",
    "properties": {"result": {"type": "string"}},
    "required": ["result"],
    "additionalProperties": False,
}
old_argv, old_stdin = sys.argv, sys.stdin
try:
    sys.argv = ["payload-builder", "test/model", "256", json.dumps(schema)]
    sys.stdin = io.StringIO("Return the required JSON object.")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        exec(builder, {"json": json, "sys": sys})
finally:
    sys.argv, sys.stdin = old_argv, old_stdin

payload = json.loads(output.getvalue())
assert "response_format" in payload, payload
assert payload.get("provider") == {"require_parameters": True}, payload
assert "reasoning" not in payload, payload

try:
    sys.argv = ["payload-builder", "test/model", "256", ""]
    sys.stdin = io.StringIO("Return a concise answer.")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        exec(builder, {"json": json, "sys": sys})
finally:
    sys.argv, sys.stdin = old_argv, old_stdin

plain_payload = json.loads(output.getvalue())
assert plain_payload.get("reasoning") == {"effort": "none"}, plain_payload
assert "response_format" not in plain_payload, plain_payload
assert "provider" not in plain_payload, plain_payload
PY

function_source="$(sed -n '/^_prioritize_override()/,/^}/p' "$FAILOVER")"
[[ -n "$function_source" ]] || { echo "missing _prioritize_override" >&2; exit 1; }
eval "$function_source"

CANDIDATES=(first second third)
OVERRIDE_MODEL=second
_prioritize_override
[[ "${CANDIDATES[*]}" == "second first third" ]]

CANDIDATES=(first second third)
OVERRIDE_MODEL=first
_prioritize_override
[[ "${CANDIDATES[*]}" == "first second third" ]]

echo "PASS schema payload and override-first fallback"
