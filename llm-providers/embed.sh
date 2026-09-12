#!/usr/bin/env bash
# llm-providers/embed.sh — thin wrapper for OpenRouter POST /api/v1/embeddings.
#
# Model: qwen/qwen3-embedding-8b (fixed).
# Input:  embed.sh "text" | echo "text" | embed.sh | embed.sh --file PATH
# Output: JSON vector (data[0].embedding) on stdout.
#
# Contract (mirrors failover.sh):
#   - API key sourced from secrets/services/openrouter.env (no hardcoded secrets);
#   - USD 0.02 cost cap per call; blocked calls exit 4;
#   - redacted receipt appended to .agent-work/receipts/openrouter-usage.jsonl
#     {utc_time, role:"embed", model, status, prompt_tokens, cost_usd, latency_ms};
#   - stderr provider+usage lines; never log text/key.
# Exit codes: 0 ok | 1 error | 4 cost-block/policy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECEIPT_DIR="$PROJECT_ROOT/.agent-work/receipts"
RUNTIME_DIR="$PROJECT_ROOT/.agent-work/runtime"
mkdir -p "$RECEIPT_DIR" "$RUNTIME_DIR"

# Load API keys for non-login shells (same pattern as failover.sh).
# shellcheck source=/dev/null
_SECRETS_OPENROUTER="/root/workspaces/secrets/services/openrouter.env"
[[ -r "$_SECRETS_OPENROUTER" ]] && . "$_SECRETS_OPENROUTER"
export OPENROUTER_API_KEY

MODEL="qwen/qwen3-embedding-8b"
BASE_URL="${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
USAGE_JSONL="$RECEIPT_DIR/openrouter-usage.jsonl"
COST_CAP_USD="0.02"
DEADLINE_SECONDS=60

log_receipt() {
  local status="$1" pt="${2:-null}" cost="${3:-null}" latency="${4:-null}"
  python3 - "$USAGE_JSONL" "$MODEL" "$status" "$pt" "$cost" "$latency" <<'PYEOF'
import json, sys
from datetime import datetime, timezone
path, model, status, pt, cost, latency = sys.argv[1:]
def num(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
rec = {
    "utc_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "role": "embed",
    "model": model,
    "status": status,
    "prompt_tokens": num(pt),
    "cost_usd": num(cost),
    "latency_ms": num(latency),
}
with open(path, "a") as f:
    f.write(json.dumps(rec) + "\n")
PYEOF
}

# --- CLI ---
TEXT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|-f)
      [[ -r "$2" ]] || { echo "ERROR: cannot read file: $2" >&2; exit 1; }
      TEXT=$(cat "$2"); shift 2 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  TEXT="$1"; shift ;;
  esac
done

if [[ -z "$TEXT" ]]; then
  [[ ! -t 0 ]] && TEXT=$(cat) || { echo "ERROR: input text required (arg | stdin | --file PATH)" >&2; exit 1; }
fi
[[ -n "$TEXT" ]] || { echo "ERROR: empty input" >&2; exit 1; }

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "BLOCKED_PROVIDER_AUTH" >&2
  log_receipt "blocked" null null null
  exit 1
fi

tmpbody=$(mktemp "$RUNTIME_DIR/embed-response-XXXXXX")
trap 'rm -f "$tmpbody"' EXIT
t0=$(python3 -c 'import time; print(int(time.time()*1000))')
http_code=$(printf '%s' "$TEXT" | python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'input': sys.stdin.read()}))" "$MODEL" | \
  curl -s -o "$tmpbody" -w "%{http_code}" \
    --max-time "$DEADLINE_SECONDS" \
    -X POST "${BASE_URL}/embeddings" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -d @- 2>/dev/null) || http_code="000"
t1=$(python3 -c 'import time; print(int(time.time()*1000))')
latency=$((t1 - t0))

# Gate: parse response, enforce cost cap, emit vector. Body never leaves this pipe.
vecfile=$(mktemp "$RUNTIME_DIR/embed-vector-XXXXXX")
gate_rc=0
gate_out=$(python3 - "$http_code" "$COST_CAP_USD" "$tmpbody" "$vecfile" <<'PYEOF'
import json, sys
http_code, cap, body_path, vec_path = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
try:
    d = json.load(open(body_path))
except Exception:
    print("GATE_FAIL\tinvalid_json\tnull\tnull"); sys.exit(0)
usage = d.get("usage", {}) if isinstance(d, dict) else {}
cost = float(usage.get("cost") or 0)
pt = usage.get("prompt_tokens")
pt = "null" if pt is None else str(pt)
if http_code.startswith("2") and cost > cap:
    print(f"GATE_COST\tcost_cap_exceeded\t{pt}\t{cost}"); sys.exit(0)
if not http_code.startswith("2"):
    err = d.get("error", {}) if isinstance(d, dict) else {}
    msg = str(err.get("type") or err.get("code") or http_code)
    print(f"GATE_HTTP\t{msg}\tnull\tnull"); sys.exit(0)
try:
    emb = d["data"][0]["embedding"]
    assert isinstance(emb, list) and emb
except Exception:
    print(f"GATE_FAIL\tmissing_embedding\t{pt}\t{cost}"); sys.exit(0)
print(f"GATE_OK\tnull\t{pt}\t{cost}")
with open(vec_path, "w") as f:
    json.dump(emb, f)
PYEOF
) || gate_rc=$?
if [[ $gate_rc -ne 0 ]]; then
  rm -f "$vecfile"
  log_receipt "error" null null "$latency"
  echo "ERROR: gate crash" >&2
  exit 1
fi

gate="${gate_out%%$'\t'*}"
rest="${gate_out#*$'\t'}"
reason="${rest%%$'\t'*}"
rest="${rest#*$'\t'}"
pt="${rest%%$'\t'*}"
cost="${rest#*$'\t'}"

case "$gate" in
  GATE_OK)
    cat "$vecfile"; echo
    rm -f "$vecfile"
    log_receipt "ok" "$pt" "$cost" "$latency"
    echo "[provider: openrouter-direct model=$MODEL]" >&2
    echo "[usage] prompt=$pt cost=$cost" >&2
    exit 0
    ;;
  GATE_COST)
    rm -f "$vecfile"
    log_receipt "blocked" "$pt" "$cost" "$latency"
    echo "BLOCKED_COST_CAP: cost exceeds $COST_CAP_USD USD" >&2
    exit 4
    ;;
  GATE_HTTP)
    log_receipt "error" null null "$latency"
    echo "ERROR: provider HTTP $http_code ($reason)" >&2
    exit 1
    ;;
  *)
    log_receipt "error" "$pt" "$cost" "$latency"
    echo "ERROR: $reason" >&2
    exit 1
    ;;
esac
