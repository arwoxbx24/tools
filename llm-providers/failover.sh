#!/usr/bin/env bash
# llm-providers/failover.sh — canonical routed LLM call via OpenRouter.
#
# model-policy.json is the executable authority for the role/model registry;
# models.yaml is its readable mirror. All managed models are selected from its
# allowlist and reached through the configured OpenRouter adapter.
#
# Usage:
#   echo "prompt" | failover.sh
#   failover.sh "prompt" [--role ROLE] [--model MODEL_ID] [--tokens N]
#   failover.sh --start-from openrouter "prompt"   # accepted, chain is registry-driven
#   failover.sh --status                            # offline diagnostics (no API call)
#   failover.sh --preflight-only "prompt"           # guards/policy only, no API call
#
# Contract (tools/llm-providers/AGENTS.md + workspace policy):
#   - allowlist enforced before any request (BLOCKED_MODEL otherwise);
#   - prompts must be in English (BLOCKED_NON_ENGLISH_PROMPT otherwise);
#   - one POST per candidate, no retry of the same candidate, at most
#     attempt_limit (2) POST attempts total;
#   - one monotonic absolute deadline (90 s total) and a USD 0.02 cumulative
#     cost cap including rejected HTTP-200 responses;
#   - strict response/content gate: HTTP 200 alone is never success;
#   - receipts are allowlist-serialized; no secret/body/prompt/header logging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECEIPT_DIR="$PROJECT_ROOT/.agent-work/receipts"
RUNTIME_DIR="$PROJECT_ROOT/.agent-work/runtime"
mkdir -p "$RECEIPT_DIR" "$RUNTIME_DIR"

# Load API keys for non-login shells (subagents don't source ~/.bashrc).
# shellcheck source=/dev/null
_SECRETS_OPENROUTER="/root/workspaces/secrets/services/openrouter.env"
[[ -r "$_SECRETS_OPENROUTER" ]] && . "$_SECRETS_OPENROUTER"
# Export keys sourced above so python3 subprocesses in call_candidate() see them.
export OPENROUTER_API_KEY
MODEL_POLICY="${SCRIPT_DIR}/model-policy.json"
USAGE_JSONL="$RECEIPT_DIR/openrouter-usage.jsonl"
HEALTH_JSON="$RECEIPT_DIR/openrouter-health.json"
FAILOVER_LOG="${FAILOVER_LOG:-$RECEIPT_DIR/openrouter-failover.log}"
RECEIPT_JOURNAL="$RECEIPT_DIR/openrouter-receipts.jsonl"
RECEIPT_LOCK="$RECEIPT_DIR/.receipts.lock"
CIRCUIT_STATE="$RECEIPT_DIR/circuit_state.json"
CIRCUIT_LOCK="$RECEIPT_DIR/.circuit.lock"
CIRCUIT_THRESHOLD=3
CIRCUIT_COOLDOWN=300

MAX_TOKENS="${MAX_TOKENS:-2048}"
_MAX_TOKENS_SET=0  # 1 if --tokens passed explicitly
_MODEL_SET=0       # 1 if --model passed explicitly
OVERRIDE_MODEL=""
ROUTE=""
DEADLINE_SECONDS=90
ATTEMPT_LIMIT=2
COST_CAP_USD="0.02"
CUM_COST=0
ATTEMPTS_USED=0
START_TS=0
PREFLIGHT_ONLY=0
LAST_PT=""
LAST_CT=""
LAST_COST=""
LAST_LATENCY=""
LAST_REASON=""

# --- PII / secret filter (prompt-side guard, kept for test-pii-filter.sh) ---
# Returns 0 = clean, 1 = found (type in stdout)
_pii_check() {
  local text="$1"
  if echo "$text" | grep -qP '(sk-or-|sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN( RSA| EC)? PRIVATE KEY-----)'; then
    echo "api_key_or_secret"; return 1
  fi
  if echo "$text" | grep -qP '(?<!\d)(\+7|8)[\s\(\-]*\d{3}[\s\)\-]*\d{3}[\s\-]*\d{2}[\s\-]*\d{2}(?!\d)'; then
    echo "phone_ru"; return 1
  fi
  if echo "$text" | grep -qP '[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}'; then
    echo "email"; return 1
  fi
  if echo "$text" | grep -qP 'hh\.ru/resume/'; then
    echo "hh_resume_url"; return 1
  fi
  if echo "$text" | grep -qP '(?<=[ \t])@[a-zA-Z][a-zA-Z0-9_]{4,}(?![\w(])'; then
    echo "telegram_handle"; return 1
  fi
  return 0
}

# Blocks secrets outright (exit 3); other PII blocks the call too (fail-closed:
# masked forwarding was removed together with direct providers).
_guard_pii() {
  local prompt="$1" pii_type
  if ! pii_type=$(_pii_check "$prompt"); then
    echo "PII/secret detected: ${pii_type}" >&2
    local ts; ts=$(date -Iseconds)
    printf '{"ts":"%s","blocked":"pii","type":"%s"}\n' "$ts" "$pii_type" >> "$USAGE_JSONL"
    return 3
  fi
  return 0
}

# English instruction rule. Exact source may contain Cyrillic only inside
# balanced SOURCE_PAYLOAD blocks; PII/secret checks still inspect the full text.
_guard_language() {
  local prompt="$1" rc=0
  printf '%s' "$prompt" | python3 -c '
import re, sys

text = sys.stdin.read()
start = "===SOURCE_PAYLOAD==="
end = "===END_SOURCE_PAYLOAD==="
instructions = []
pos = 0
while True:
    opening = text.find(start, pos)
    closing = text.find(end, pos)
    if closing >= 0 and (opening < 0 or closing < opening):
        raise SystemExit(2)
    if opening < 0:
        instructions.append(text[pos:])
        break
    instructions.append(text[pos:opening])
    closing = text.find(end, opening + len(start))
    if closing < 0 or start in text[opening + len(start):closing]:
        raise SystemExit(2)
    pos = closing + len(end)
if re.search(r"[\u0400-\u04ff]", "".join(instructions)):
    raise SystemExit(6)
' || rc=$?
  case "$rc" in
    0) return 0 ;;
    2)
      echo "BLOCKED_MALFORMED_SOURCE_PAYLOAD: source markers must be balanced and non-nested" >&2
      return 6
      ;;
    6)
      echo "BLOCKED_NON_ENGLISH_PROMPT: model instructions must be in English" >&2
      return 6
      ;;
    *)
      echo "BLOCKED_LANGUAGE_GATE_ERROR: preflight parser failed" >&2
      return 6
      ;;
  esac
}

_validate_response_schema() {
  [[ -z "${LLM_RESPONSE_SCHEMA:-}" ]] && return 0
  printf '%s' "$LLM_RESPONSE_SCHEMA" | python3 -c '
import json, sys
schema = json.load(sys.stdin)
raise SystemExit(0 if isinstance(schema, dict) else 1)
' 2>/dev/null || {
    echo "BLOCKED_RESPONSE_SCHEMA: expected one JSON object" >&2
    return 4
  }
}

# --- Redacted receipt: allowlist serialization only ---
log_receipt() {
  local model="$1" status="$2" reason="$3" finish_reason="${4:-null}" \
        pt="${5:-null}" ct="${6:-null}" cost="${7:-null}" latency="${8:-null}"
  python3 - "$USAGE_JSONL" "$model" "$status" "$reason" "$finish_reason" \
            "$pt" "$ct" "$cost" "$latency" "${ROLE:-generate}" "${LLM_REQUEST_ID:-}" <<'PYEOF'
import hashlib, json, sys
from datetime import datetime, timezone
(path, model, status, reason, finish_reason, pt, ct, cost, latency,
 role, req_id) = sys.argv[1:]
def num(v):
    try:
        return float(v) if "." in v else int(v)
    except (TypeError, ValueError):
        return None
rec = {
    "utc_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "request_id_hash": hashlib.sha256(req_id.encode()).hexdigest()[:16] if req_id else None,
    "role": role,
    "model": model,
    "status": status,
    "reason": reason or None,
    "finish_reason": None if finish_reason == "null" else finish_reason,
    "prompt_tokens": num(pt),
    "completion_tokens": num(ct),
    "cost_usd": num(cost),
    "latency_ms": num(latency),
}
with open(path, "a") as f:
    f.write(json.dumps(rec) + "\n")
PYEOF
}

log_failover() {
  local from="$1" to="$2" reason="$3"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$ts FAILOVER $from -> $to reason: $reason" | tee -a "$FAILOVER_LOG" >&2
}

# --- Atomic append-only receipt journal (flock-protected) ---
_atomic_append_receipt() {
  local route="$1" model="$2" pt="$3" ct="$4" cost="$5" rc="$6" latency="$7" reason="$8"
  local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 9
      python3 -c '
import json, sys
def _num(v):
    if v in ("", "null"): return None
    try: return int(v)
    except ValueError:
        try: return float(v)
        except ValueError: return None
rec = {
    "ts": sys.argv[1],
    "route": sys.argv[2],
    "model": sys.argv[3],
    "tokens_in": _num(sys.argv[4]),
    "tokens_out": _num(sys.argv[5]),
    "cost_usd": _num(sys.argv[6]),
    "rc": int(sys.argv[7]),
    "latency_ms": _num(sys.argv[8]),
    "reason": sys.argv[9] if sys.argv[9] not in ("", "null") else None,
}
with open(sys.argv[10], "a") as f:
    f.write(json.dumps(rec) + "\n")
' "$ts" "$route" "$model" "$pt" "$ct" "$cost" "$rc" "$latency" "$reason" "$RECEIPT_JOURNAL"
    ) 9>"$RECEIPT_LOCK"
  else
    # Fallback: no flock, just append directly (less safe under concurrency)
    python3 -c '
import json, sys
def _num(v):
    if v in ("", "null"): return None
    try: return int(v)
    except ValueError:
        try: return float(v)
        except ValueError: return None
rec = {
    "ts": sys.argv[1],
    "route": sys.argv[2],
    "model": sys.argv[3],
    "tokens_in": _num(sys.argv[4]),
    "tokens_out": _num(sys.argv[5]),
    "cost_usd": _num(sys.argv[6]),
    "rc": int(sys.argv[7]),
    "latency_ms": _num(sys.argv[8]),
    "reason": sys.argv[9] if sys.argv[9] not in ("", "null") else None,
}
with open(sys.argv[10], "a") as f:
    f.write(json.dumps(rec) + "\n")
' "$ts" "$route" "$model" "$pt" "$ct" "$cost" "$rc" "$latency" "$reason" "$RECEIPT_JOURNAL"
  fi
}

# --- Circuit breaker (flock-protected state: {model:{fails,open_until}}) ---
# rc 1/2/3 increments consecutive fails; 3 consecutive opens the circuit for
# CIRCUIT_COOLDOWN seconds; rc 0 resets. rc 4 (policy/cost block) is ignored.
_circuit_is_open() {
  # rc 0 = circuit open (candidate must be skipped), 1 = closed/usable
  local model="$1"
  (
    flock -x 9
    python3 - "$CIRCUIT_STATE" "$model" <<'PYEOF'
import json, sys, time
path, model = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        state = json.load(f)
except Exception:
    state = {}
entry = state.get(model) or {}
try:
    open_until = float(entry.get("open_until") or 0)
except (TypeError, ValueError):
    open_until = 0.0
sys.exit(0 if open_until > time.time() else 1)
PYEOF
  ) 9>"$CIRCUIT_LOCK"
}

_circuit_record() {
  local model="$1" rc="$2"
  (
    flock -x 9
    python3 - "$CIRCUIT_STATE" "$model" "$rc" "$CIRCUIT_THRESHOLD" "$CIRCUIT_COOLDOWN" <<'PYEOF'
import json, os, sys, time
path, model, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
threshold, cooldown = int(sys.argv[4]), int(sys.argv[5])
try:
    with open(path) as f:
        state = json.load(f)
except Exception:
    state = {}
entry = state.get(model) or {}
fails = int(entry.get("fails") or 0)
open_until = float(entry.get("open_until") or 0)
if rc == 0:
    fails, open_until = 0, 0
elif rc in (1, 2, 3):
    fails += 1
    if fails >= threshold:
        open_until = time.time() + cooldown
        fails = 0
state[model] = {"fails": fails, "open_until": open_until}
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f)
os.replace(tmp, path)
PYEOF
  ) 9>"$CIRCUIT_LOCK"
}

# --- Role -> route resolution from model-policy.json (executable authority) ---
_resolve_role() {
  local role="$1"
  [[ -f "$MODEL_POLICY" ]] || {
    echo "BLOCKED_POLICY_IMPLEMENTATION_MISMATCH: model-policy.json missing at $MODEL_POLICY" >&2
    return 1
  }
  local result
  result=$(python3 - "$MODEL_POLICY" "$role" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
role = sys.argv[2]
route = p.get("role_map", {}).get(role)
if not route:
    raise SystemExit(f"unknown role: {role}")
candidates = p["routes"][route]
print(route)
print(p["max_tokens"][route])
print(p.get("attempt_limit", 2))
print(p.get("deadline_seconds", 90))
print(p.get("cost_cap_usd", 0.02))
print("\n".join(candidates))
PYEOF
  ) || return $?
  ROUTE=$(sed -n '1p' <<< "$result")
  ROUTE_MAX_TOKENS=$(sed -n '2p' <<< "$result")
  [[ "$_MAX_TOKENS_SET" == "0" ]] && MAX_TOKENS="$ROUTE_MAX_TOKENS"
  ATTEMPT_LIMIT=$(sed -n '3p' <<< "$result")
  DEADLINE_SECONDS=$(sed -n '4p' <<< "$result")
  COST_CAP_USD=$(sed -n '5p' <<< "$result")
  CANDIDATES=($(tail -n +6 <<< "$result"))
  return 0
}

# --- Single proxied call to one candidate (one POST, no retry) ---
# rc: 0 ok | 1 error | 2 quota/rate-limit | 3 unavailable | 4 blocked
call_candidate() {
  local prompt="$1" model="$2"
  local adapter routed_model base_url api_key model_info
  local CONTENT_FILE
  LAST_PT="" LAST_CT="" LAST_COST="" LAST_LATENCY="" LAST_REASON=""
  model_info=$(python3 - "$MODEL_POLICY" "$model" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
m = p["models"].get(sys.argv[2])
if not m:
    sys.exit(4)
print(m["adapter"], m["model"])
PYEOF
  ) || { echo "BLOCKED_MODEL: $model is not in model-policy.json" >&2; return 4; }
  read -r adapter routed_model <<< "$model_info"

  base_url=$(python3 - "$MODEL_POLICY" "$adapter" <<'PYEOF'
import json, os, sys
p = json.load(open(sys.argv[1]))
a = p["adapters"][sys.argv[2]]
print(os.environ.get(a["base_url_env"], "") or a["default_base_url"])
PYEOF
  )
  api_key=$(python3 - "$MODEL_POLICY" "$adapter" <<'PYEOF'
import json, os, sys
p = json.load(open(sys.argv[1]))
a = p["adapters"][sys.argv[2]]
print(os.environ.get(a["api_key_env"], ""))
PYEOF
  )
  if [[ -z "$api_key" ]]; then
    if ! python3 - "$base_url" <<'PYEOF'
from urllib.parse import urlsplit
import sys
u = urlsplit(sys.argv[1])
sys.exit(0 if u.scheme == "http" and u.hostname in {"127.0.0.1", "localhost", "::1"} else 1)
PYEOF
    then
      echo "BLOCKED_PROVIDER_AUTH" >&2
      return 4
    fi
  fi

  local tmpbody t0 t1 http_code="000"
  tmpbody=$(mktemp "$RUNTIME_DIR/response-XXXXXX")
  CONTENT_FILE=$(mktemp "$RUNTIME_DIR/content-XXXXXX")
  t0=$(python3 -c 'import time; print(int(time.time()*1000))')
  local auth_args=()
  [[ -n "$api_key" ]] && auth_args=(-H "Authorization: Bearer $api_key")
  printf '%s' "$prompt" | python3 -c "
import json, sys
text = sys.stdin.read()
route = sys.argv[1]
try:
    with open(sys.argv[2]) as f:
        _policy = json.load(f)
    _limit = _policy.get('max_input_tokens', {}).get(route, 24000)
except Exception:
    _limit = 24000
_input_tokens = (len(text) * 2) // 5
if _input_tokens > _limit:
    print(f'ERR: input_tokens={_input_tokens} exceeds max_input_tokens={_limit} for route={route}', file=sys.stderr)
    sys.exit(2)
" "$ROUTE" "$MODEL_POLICY" || return 2
  http_code=$(printf '%s' "$prompt" | python3 -c "
import json, sys
payload = {
  'model': sys.argv[1],
  'messages': [{'role': 'user', 'content': sys.stdin.read()}],
  'max_tokens': int(sys.argv[2]),
}
if sys.argv[3]:
    payload['response_format'] = {
        'type': 'json_schema',
        'json_schema': {
            'name': 'codex_response',
            'strict': True,
            'schema': json.loads(sys.argv[3]),
        },
    }
    payload['provider'] = {'require_parameters': True}
else:
    payload['reasoning'] = {'effort': 'none'}
print(json.dumps(payload))" "$routed_model" "$MAX_TOKENS" "${LLM_RESPONSE_SCHEMA:-}" | curl -s -o "$tmpbody" -w "%{http_code}" \
      --max-time "$DEADLINE_SECONDS" \
      -X POST "${base_url}/chat/completions" \
      "${auth_args[@]}" \
      -H "Content-Type: application/json" \
      -d @- 2>/dev/null) || http_code="000"
  t1=$(python3 -c 'import time; print(int(time.time()*1000))')
  local latency=$((t1 - t0))

  # Strict response/content gate + usage extraction; body never leaves this pipe.
  local gate_out gate_rc=0
  gate_out=$(python3 - "$http_code" "$latency" "$COST_CAP_USD" "$CUM_COST" "$CONTENT_FILE" "$tmpbody" <<'PYEOF'
import json, sys
http_code, latency, cap, cum, content_path, body_path = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5], sys.argv[6]
def j(v):
    return "null" if v is None else v
try:
    d = json.load(open(body_path))
except Exception:
    print("GATE_FAIL\tinvalid_json\tnull\tnull\tnull\tnull"); sys.exit(0)
usage = d.get("usage", {}) if isinstance(d, dict) else {}
cost = float(usage.get("cost") or 0)
pt, ct = j(usage.get("prompt_tokens")), j(usage.get("completion_tokens"))
# Cost cap applies to every HTTP-200 response, including rejected ones.
if http_code.startswith("2") and cum + cost > cap:
    print(f"GATE_COST\tcost_cap_exceeded\tnull\t{pt}\t{ct}\t{cost}"); sys.exit(0)
if not http_code.startswith("2"):
    err = d.get("error", {}) if isinstance(d, dict) else {}
    msg = str(err.get("type") or err.get("code") or http_code)
    print(f"GATE_HTTP\t{msg}\tnull\tnull\tnull\tnull"); sys.exit(0)
try:
    choice = d["choices"][0]
    content = (choice.get("message") or {}).get("content") or ""
    content = content.strip()
    finish = choice.get("finish_reason")
except Exception:
    print(f"GATE_FAIL\tmissing_message\tnull\t{pt}\t{ct}\t{cost}"); sys.exit(0)
finish = j(finish)
if finish != "stop":
    print(f"GATE_FAIL\tfinish_reason:{finish}\t{finish}\t{pt}\t{ct}\t{cost}"); sys.exit(0)
if not content or content.lower() in ("none", "null"):
    print(f"GATE_FAIL\tempty_content\t{finish}\t{pt}\t{ct}\t{cost}"); sys.exit(0)
print(f"GATE_OK\tnull\t{finish}\t{pt}\t{ct}\t{cost}")
sys.stdout.flush()
with open(content_path, "w") as f:
    f.write(content)
PYEOF
  ) || gate_rc=$?
  CONTENT=""
  if [[ $gate_rc -eq 0 && "$gate_out" == GATE_OK$'\t'* ]]; then
    CONTENT=$(cat "$CONTENT_FILE") || gate_rc=$?
  fi
  rm -f "$tmpbody" "$CONTENT_FILE"
  [[ $gate_rc -ne 0 ]] && { log_receipt "$model" "error" "gate_crash" null null null null "$latency"; return 1; }

  local gate reason finish pt ct cost
  IFS=$'\t' read -r gate reason finish pt ct cost <<< "$gate_out"

  LAST_PT="$pt"
  LAST_CT="$ct"
  LAST_COST="$cost"
  LAST_LATENCY="$latency"
  LAST_REASON="$reason"

  # Accumulate cost for every HTTP-200 response, including rejected ones.
  if [[ "$cost" != "null" && -n "$cost" ]]; then
    CUM_COST=$(python3 -c "print($CUM_COST + $cost)")
  fi

  case "$gate" in
    GATE_OK)
      log_receipt "$model" "ok" null "$finish" "$pt" "$ct" "$cost" "$latency"
      echo "[provider: openrouter-direct model=$model]" >&2
      echo "[usage] prompt=$pt completion=$ct cost=$cost" >&2
      return 0
      ;;
    GATE_COST)
      log_receipt "$model" "blocked" "cost_cap_exceeded" "$finish" "$pt" "$ct" "$cost" "$latency"
      echo "BLOCKED_COST_CAP: cumulative cost exceeds $COST_CAP_USD USD" >&2
      return 4
      ;;
    GATE_HTTP)
      log_receipt "$model" "error" "$reason" null null null null "$latency"
      if [[ "$http_code" == "429" ]]; then return 2; fi
      [[ "$http_code" == "000" ]] && return 3
      return 1
      ;;
    *)
      log_receipt "$model" "rejected" "$reason" "$finish" "$pt" "$ct" "$cost" "$latency"
      return 1
      ;;
  esac
}

# --- Failover loop over registry candidates ---
_prioritize_override() {
  local candidate
  local -a ordered=("$OVERRIDE_MODEL")
  for candidate in "${CANDIDATES[@]}"; do
    [[ "$candidate" == "$OVERRIDE_MODEL" ]] || ordered+=("$candidate")
  done
  CANDIDATES=("${ordered[@]}")
}

run_with_failover() {
  local prompt="$1" role="${2:-generate}"

  _guard_pii "$prompt" || return 3
  _guard_language "$prompt" || return 6
  _validate_response_schema || return $?
  _resolve_role "$role" || return $?

  # Fail-closed strict-schema law (registry v2): structured routes require a schema.
  if [[ "$ROUTE" == "validation" || "$ROUTE" == "extract" ]] && [[ -z "${LLM_RESPONSE_SCHEMA:-}" ]]; then
    echo "ERROR: role requires LLM_RESPONSE_SCHEMA (fail-closed strict-schema law, registry v2)" >&2
    return 4
  fi

  if [[ "$_MODEL_SET" == "1" ]]; then
    _prioritize_override
  fi

  # Budget degradation gate (owner law 24.08, docs/parity-revision/07): soft $1/day target,
  # no hard cutoff — YELLOW/RED/BLACK narrow to cheap tier; BLACK additionally stops generate.
  local budget_level level_file="$SCRIPT_DIR/.or-budget-level"
  budget_level=$(cat "$level_file" 2>/dev/null)
  case "$budget_level" in GREEN|YELLOW|RED|BLACK) ;; *) budget_level="YELLOW" ;; esac
  # stale-state expiry: level older than 3h (monitor dead / API outage) can't stay GREEN
  if [[ "$budget_level" == "GREEN" ]] && [[ -n "$(find "$level_file" -mmin +180 2>/dev/null)" ]]; then
    budget_level="YELLOW"
    echo "[budget:stale] level file older than 3h -> YELLOW" >&2
  fi
  if [[ "$budget_level" == "BLACK" && "$role" == "generate" ]]; then
    echo "BLOCKED_BUDGET_BLACK: generate role blocked at BLACK (>=200% daily target)" >&2
    return 4
  fi
  if [[ "$budget_level" =~ ^(YELLOW|RED|BLACK)$ ]]; then
    echo "[budget:$budget_level] restricting to cheap models" >&2
    local _bf=() _m
    for _m in "${CANDIDATES[@]}"; do
      case "$_m" in qwen/*|*flash*|kimi*) _bf+=("$_m") ;; esac
    done
    if [[ ${#_bf[@]} -gt 0 ]]; then
      CANDIDATES=("${_bf[@]}")
    else
      echo "BLOCKED_BUDGET: no cheap models available in route $ROUTE" >&2
      return 4
    fi
  fi

  [[ "$MAX_TOKENS" =~ ^[0-9]+$ ]] && (( MAX_TOKENS > 0 && MAX_TOKENS <= ROUTE_MAX_TOKENS )) || {
    echo "BLOCKED_TOKEN_LIMIT: max_tokens=$MAX_TOKENS; allowed 1..$ROUTE_MAX_TOKENS for route $ROUTE" >&2
    return 4
  }

  if [[ "$PREFLIGHT_ONLY" == "1" ]]; then
    if [[ "$_MODEL_SET" == "1" ]] && ! python3 - "$MODEL_POLICY" "$OVERRIDE_MODEL" <<'PYEOF'
import json, sys
policy = json.load(open(sys.argv[1]))
raise SystemExit(0 if sys.argv[2] in policy.get("models", {}) else 1)
PYEOF
    then
      echo "BLOCKED_MODEL: $OVERRIDE_MODEL is not in model-policy.json" >&2
      return 4
    fi
    echo "PREFLIGHT_OK role=$role route=$ROUTE"
    return 0
  fi

  START_TS=$(date +%s)
  CONTENT_FILE=$(mktemp)
  trap 'rm -f "$CONTENT_FILE"' EXIT

  local prev=""
  for model in "${CANDIDATES[@]}"; do
    # Global gates: attempt limit and monotonic absolute deadline.
    if (( ATTEMPTS_USED >= ATTEMPT_LIMIT )); then
      echo "BLOCKED_ATTEMPT_LIMIT: $ATTEMPT_LIMIT attempts used" >&2
      return 2
    fi
    local elapsed=$(( $(date +%s) - START_TS ))
    if (( elapsed >= DEADLINE_SECONDS )); then
      echo "BLOCKED_DEADLINE: ${DEADLINE_SECONDS}s total deadline reached" >&2
      return 2
    fi

    # Circuit breaker: skip candidates whose circuit is open.
    if _circuit_is_open "$model"; then
      echo "[circuit] skip $model" >&2
      continue
    fi

    local rc=0
    call_candidate "$prompt" "$model" || rc=$?
    ATTEMPTS_USED=$((ATTEMPTS_USED + 1))
    _circuit_record "$model" "$rc"
    _atomic_append_receipt "$ROUTE" "$model" "$LAST_PT" "$LAST_CT" "$LAST_COST" "$rc" "$LAST_LATENCY" "$LAST_REASON"

    if [[ $rc -eq 0 ]]; then
      [[ -n "$prev" ]] && log_failover "$prev" "$model" "previous failed"
      printf '%s\n' "$CONTENT"
      return 0
    elif [[ $rc -eq 4 ]]; then
      return 4  # policy/cost block — stop immediately
    elif [[ $rc -eq 3 ]]; then
      :  # proxy unavailable — skip silently to next candidate
    elif [[ $rc -eq 2 ]]; then
      log_failover "$model" "next" "quota/rate-limit (rc=2)"
    else
      log_failover "$model" "next" "error/rejected rc=$rc"
    fi
    prev="$model"
  done

  echo "ERROR: all registry candidates exhausted" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
# --- CLI ---
PROMPT=""
START_FROM=""
ROLE="generate"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role|-r)       ROLE="$2"; shift 2 ;;
    --start-from|-s) START_FROM="$2"; shift 2 ;;  # accepted; chain is registry-driven
    --model|-m)      OVERRIDE_MODEL="$2"; _MODEL_SET=1; shift 2 ;;
    --tokens|-t)     MAX_TOKENS="$2"; _MAX_TOKENS_SET=1; shift 2 ;;
    --preflight-only) PREFLIGHT_ONLY=1; shift ;;
    --status)
      if [[ -f "$HEALTH_JSON" ]]; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(f'Checked: {d[\"checked_at\"]}')
print(f'Active:  {d[\"active_adapter\"]}')
print(f'Chain:   {\" -> \".join(d[\"failover_chain\"])}')
" "$HEALTH_JSON"
      else
        echo "No data. Run: bash $(dirname "$0")/status.sh"
      fi
      exit 0
      ;;
    --)      shift; break ;;
    -*)      echo "Unknown option: $1" >&2; exit 1 ;;
    *)       PROMPT="$1"; shift ;;
  esac
done

if [[ -z "$PROMPT" ]]; then
  [[ ! -t 0 ]] && PROMPT=$(cat) || { echo "ERROR: prompt required" >&2; exit 1; }
fi

run_with_failover "$PROMPT" "$ROLE"
fi
