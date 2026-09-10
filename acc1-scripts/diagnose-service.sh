#!/usr/bin/env bash
# =============================================================================
# diagnose-service.sh — 8-layer web service diagnostic + modular service checks
# Usage:
#   bash diagnose-service.sh <domain_or_url> [--ssh user@host] [--json] [--quick]
#   bash diagnose-service.sh <domain_or_url> --service <name>   # L1-L5 + named module
#   bash diagnose-service.sh --local --service <name>           # module only, no domain
#   bash diagnose-service.sh <domain_or_url> --all-services     # L1-L8 + auto-detect
#   bash diagnose-service.sh --system                           # USE signals + auto-discovery (no domain)
#   bash diagnose-service.sh --netflix60                        # 10 Netflix SRE commands in sequence
# Modules: docker redis clickhouse apache kubernetes minio mysql postgres firewall php-fpm
# PE script | scope: /root/workspaces/tools/acc1-scripts/
# =============================================================================

set +e

# ── constants ────────────────────────────────────────────────────────────────
TIMEOUT=5
TELEGRAM_ENV="/root/workspaces/secrets/services/telegram.env"
REDIS_CLI=$(command -v redis-cli 2>/dev/null)
DATE_UTC=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
TIMESTAMP=$(date +%s)

# ── result tracking ───────────────────────────────────────────────────────────
declare -A LAYER_NAME
JSON_RESULTS='[]'
OVERALL_STATUS="PASS"

# ── argument parsing ──────────────────────────────────────────────────────────
INPUT=""
SSH_TARGET=""
FLAG_JSON=false
FLAG_QUICK=false
FLAG_LOCAL=false
FLAG_SERVICE=""
FLAG_ALL_SERVICES=false
FLAG_SYSTEM=false
FLAG_NETFLIX60=false
MODULES_DIR="$(dirname "$0")/diagnostic-modules"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh)          SSH_TARGET="$2"; shift 2 ;;
    --json)         FLAG_JSON=true; shift ;;
    --quick)        FLAG_QUICK=true; shift ;;
    --local)        FLAG_LOCAL=true; shift ;;
    --service)      FLAG_SERVICE="$2"; shift 2 ;;
    --all-services) FLAG_ALL_SERVICES=true; shift ;;
    --system)       FLAG_SYSTEM=true; shift ;;
    --netflix60)    FLAG_NETFLIX60=true; shift ;;
    -*)             echo "Unknown flag: $1"; exit 1 ;;
    *)              INPUT="$1"; shift ;;
  esac
done

# --local mode: run module only, no domain required
if $FLAG_LOCAL; then
  if [[ -z "$FLAG_SERVICE" ]]; then
    echo "Usage: bash diagnose-service.sh --local --service <name>"
    echo "Available modules: docker redis clickhouse apache kubernetes minio mysql postgres firewall php-fpm"
    exit 1
  fi
  MODULE_FILE="${MODULES_DIR}/${FLAG_SERVICE}.sh"
  if [[ ! -f "$MODULE_FILE" ]]; then
    echo "ERROR: Module not found: $MODULE_FILE"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$MODULE_FILE"
  FN="run_module_$(echo "$FLAG_SERVICE" | tr '-' '_')"
  if declare -f "$FN" >/dev/null 2>&1; then
    "$FN"
  else
    echo "ERROR: Function $FN not found in $MODULE_FILE"
    exit 1
  fi
  exit 0
fi

# =============================================================================
# --system mode: USE signals (Phase 1) + service auto-discovery (Phase 2)
# =============================================================================
if $FLAG_SYSTEM; then
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  SYSTEM DIAGNOSTIC: USE Method + Auto-Discovery"
  echo "  Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "═══════════════════════════════════════════"
  echo ""

  echo "── Phase 1: System Signals (USE Method) ──"
  echo ""

  echo "[CPU]   uptime:"
  uptime 2>/dev/null || echo "  unavailable"
  echo ""

  echo "[MEM]   free -h:"
  free -h 2>/dev/null || echo "  unavailable"
  echo ""

  echo "[DISK]  df -h:"
  df -h 2>/dev/null || echo "  unavailable"
  echo ""

  echo "[IO]    iostat -x 1 2 (iowait column):"
  command -v iostat >/dev/null 2>&1 \
    && iostat -x 1 2 2>/dev/null | awk '/^Device|^avg/{print}' \
    || echo "  iostat not available (install sysstat)"
  echo ""

  echo "[NET]   ss -s (socket summary):"
  ss -s 2>/dev/null | head -6 || echo "  unavailable"
  echo ""

  echo "[OOM]   dmesg OOM check:"
  OOM_HITS=$(dmesg 2>/dev/null | grep -i "oom\|killed process" | tail -5)
  if [[ -n "$OOM_HITS" ]]; then
    echo "  CRITICAL — OOM entries found:"
    echo "$OOM_HITS" | sed 's/^/  /'
  else
    echo "  OK — no OOM entries"
  fi
  echo ""

  echo "── Phase 2: Service Discovery ──"
  echo ""

  echo "[PORTS] Listening ports:"
  ss -tlnp 2>/dev/null | awk 'NR>1 {print $4, $7}' | sort | sed 's/^/  /' || echo "  unavailable"
  echo ""

  echo "[DOCKER] Containers:"
  docker ps --format '  {{.Names}}\t{{.Status}}' 2>/dev/null || echo "  docker not available or no containers"
  echo ""

  echo "[SYSTEMD] Failed services:"
  FAILED_UNITS=$(systemctl --failed --no-pager 2>/dev/null | grep "●" || true)
  if [[ -n "$FAILED_UNITS" ]]; then
    echo "  WARN — failed units:"
    echo "$FAILED_UNITS" | sed 's/^/  /'
  else
    echo "  OK — no failed units"
  fi
  echo ""

  echo "[PM2] Processes:"
  if command -v pm2 >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      pm2 jlist 2>/dev/null \
        | jq -r '.[] | "  \(.name)\t\(.pm2_env.status)"' 2>/dev/null \
        || echo "  pm2 jlist failed"
    else
      pm2 list 2>/dev/null | grep -v "^\[PM2\]" | sed 's/^/  /' || echo "  pm2 list failed"
    fi
  else
    echo "  pm2 not available"
  fi
  echo ""

  echo "── Phase 3: 5 Universal Questions for unhealthy services ──"
  echo "  Run for each suspicious service found above:"
  echo "  1. Alive?     systemctl status X  /  docker inspect X  /  pm2 show X"
  echo "  2. Listening? ss -tlnp | grep PORT"
  echo "  3. Responding? curl localhost:PORT"
  echo "  4. Resources? pidstat -p PID"
  echo "  5. Logs?      journalctl -u X --since '5 min ago' --no-pager | tail -30"
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  SYSTEM SCAN COMPLETE"
  echo "═══════════════════════════════════════════"
  exit 0
fi

# =============================================================================
# --netflix60 mode: 10 Netflix SRE commands in sequence (~60 seconds)
# =============================================================================
if $FLAG_NETFLIX60; then
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  NETFLIX 60s DIAGNOSTIC"
  echo "  Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "═══════════════════════════════════════════"
  echo ""

  echo "[1/10] uptime — CPU load averages"
  uptime 2>/dev/null || echo "  unavailable"
  echo ""

  echo "[2/10] dmesg | tail -20 — kernel messages"
  dmesg 2>/dev/null | tail -20 | sed 's/^/  /' || echo "  unavailable"
  echo ""

  echo "[3/10] vmstat 1 3 — virtual memory stats"
  command -v vmstat >/dev/null 2>&1 \
    && vmstat 1 3 2>/dev/null | sed 's/^/  /' \
    || echo "  vmstat not available"
  echo ""

  echo "[4/10] mpstat -P ALL 1 1 — per-CPU stats"
  command -v mpstat >/dev/null 2>&1 \
    && mpstat -P ALL 1 1 2>/dev/null | sed 's/^/  /' \
    || echo "  mpstat not available (install sysstat)"
  echo ""

  echo "[5/10] pidstat 1 3 — per-process CPU"
  command -v pidstat >/dev/null 2>&1 \
    && pidstat 1 3 2>/dev/null | sed 's/^/  /' \
    || echo "  pidstat not available (install sysstat)"
  echo ""

  echo "[6/10] iostat -xz 1 2 — disk I/O"
  command -v iostat >/dev/null 2>&1 \
    && iostat -xz 1 2 2>/dev/null | sed 's/^/  /' \
    || echo "  iostat not available (install sysstat)"
  echo ""

  echo "[7/10] free -m — memory overview"
  free -m 2>/dev/null | sed 's/^/  /' || echo "  unavailable"
  echo ""

  echo "[8/10] sar -n DEV 1 1 — network interface stats"
  command -v sar >/dev/null 2>&1 \
    && sar -n DEV 1 1 2>/dev/null | sed 's/^/  /' \
    || echo "  sar not available (install sysstat)"
  echo ""

  echo "[9/10] sar -n TCP,ETCP 1 1 — TCP stats"
  command -v sar >/dev/null 2>&1 \
    && sar -n TCP,ETCP 1 1 2>/dev/null | sed 's/^/  /' \
    || echo "  sar not available"
  echo ""

  echo "[10/10] top -bn1 | head -20 — process snapshot"
  top -bn1 2>/dev/null | head -20 | sed 's/^/  /' || echo "  unavailable"
  echo ""

  echo "═══════════════════════════════════════════"
  echo "  NETFLIX 60s COMPLETE"
  echo "═══════════════════════════════════════════"
  exit 0
fi

if [[ -z "$INPUT" ]]; then
  echo "Usage: bash diagnose-service.sh <domain_or_url> [--ssh user@host] [--json] [--quick]"
  echo "       bash diagnose-service.sh <domain_or_url> --service <name>"
  echo "       bash diagnose-service.sh --local --service <name>"
  echo "       bash diagnose-service.sh <domain_or_url> --all-services"
  echo "       bash diagnose-service.sh --system"
  echo "       bash diagnose-service.sh --netflix60"
  exit 1
fi

# Strip scheme and path
DOMAIN=$(echo "$INPUT" | sed -E 's|^https?://||' | sed 's|/.*||')

# ── layer name map ────────────────────────────────────────────────────────────
LAYER_NAME["L1"]="DNS"
LAYER_NAME["L2"]="Network"
LAYER_NAME["L3"]="TCP"
LAYER_NAME["L4"]="TLS/SSL"
LAYER_NAME["L5"]="HTTP"
LAYER_NAME["L6"]="App"
LAYER_NAME["L7"]="DB/Disk"
LAYER_NAME["L8"]="External"

# ── tool availability ─────────────────────────────────────────────────────────
HAS_DIG=$(command -v dig   >/dev/null 2>&1 && echo yes || echo no)
HAS_NC=$(command  -v nc    >/dev/null 2>&1 && echo yes || echo no)
HAS_OPENSSL=$(command -v openssl >/dev/null 2>&1 && echo yes || echo no)
HAS_JQ=$(command  -v jq    >/dev/null 2>&1 && echo yes || echo no)
HAS_PING=$(command -v ping >/dev/null 2>&1 && echo yes || echo no)

# ── helpers ───────────────────────────────────────────────────────────────────
ssh_run() {
  [[ -z "$SSH_TARGET" ]] && return 1
  timeout "$TIMEOUT" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_TARGET" "$1" 2>&1
}

append_json() {
  local layer="$1" status="$2" detail="$3" cause="${4:-}" fix="${5:-}"
  [[ "$HAS_JQ" != "yes" ]] && return
  local entry
  entry=$(jq -cn \
    --arg l "$layer" --arg s "$status" \
    --arg d "$detail" --arg c "$cause" --arg f "$fix" \
    '{layer:$l,status:$s,detail:$d,cause:$c,fix:$f}')
  JSON_RESULTS=$(echo "$JSON_RESULTS" | jq --argjson e "$entry" '. + [$e]')
}

print_layer_line() {
  local id="$1" name="${LAYER_NAME[$1]}" status="$2" detail="$3"
  printf "[%-2s] %-14s ... %s (%s)\n" "$id" "$name" "$status" "$detail"
}

output_json_if_needed() {
  $FLAG_JSON || return
  [[ "$HAS_JQ" != "yes" ]] && { echo '{"error":"jq not available"}'; return; }
  jq -n \
    --arg domain "$DOMAIN" --arg date "$DATE_UTC" --arg status "$OVERALL_STATUS" \
    --argjson res "$JSON_RESULTS" \
    '{domain:$domain,date:$date,overall:$status,layers:$res}'
}

save_to_redis() {
  [[ -z "$REDIS_CLI" ]] && return
  [[ "$HAS_JQ" != "yes" ]] && return
  local key="diagnostic:${DOMAIN}:${TIMESTAMP}"
  local payload
  payload=$(jq -cn \
    --arg domain "$DOMAIN" --arg date "$DATE_UTC" --arg status "$OVERALL_STATUS" \
    --argjson res "$JSON_RESULTS" \
    '{domain:$domain,date:$date,overall:$status,layers:$res}')
  "$REDIS_CLI" set "$key" "$payload" EX 86400 >/dev/null 2>&1 || true
}

send_telegram_alert() {
  [[ ! -f "$TELEGRAM_ENV" ]] && return
  # shellcheck disable=SC1090
  source "$TELEGRAM_ENV" 2>/dev/null || return
  [[ -z "${NOTIFICATION_BOT_TOKEN:-}" ]] && return
  [[ -z "${DIRECTOR_CHAT_ID:-}" ]] && return
  local layer="$1" detail="$2" cause="$3" fix="$4"
  local msg
  msg=$(printf "ALERT Service Diagnostic FAIL\n\nDomain: %s\nLayer:  %s\nDetail: %s\nCause:  %s\nFix:    %s\nTime:   %s" \
    "$DOMAIN" "$layer" "$detail" "$cause" "$fix" "$DATE_UTC")
  curl -s -X POST \
    "https://api.telegram.org/bot${NOTIFICATION_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${DIRECTOR_CHAT_ID}" \
    -d "parse_mode=Markdown" \
    --data-urlencode "text=${msg}" >/dev/null 2>&1 || true
}

fail_and_exit() {
  local layer="$1" detail="$2" cause="$3" fix="$4"
  OVERALL_STATUS="FAIL"
  print_layer_line "$layer" "FAIL" "$detail"
  echo ""
  echo "  ROOT CAUSE: $cause"
  echo "  FIX:        $fix"
  echo "  LAYER:      $layer"
  echo ""
  echo "═══════════════════════════════════════════"
  append_json "$layer" "FAIL" "$detail" "$cause" "$fix"
  output_json_if_needed
  save_to_redis
  send_telegram_alert "$layer" "$detail" "$cause" "$fix"
  exit 1
}

# =============================================================================
# HEADER
# =============================================================================
echo ""
echo "═══════════════════════════════════════════"
echo "  SERVICE DIAGNOSTIC: $DOMAIN"
echo "  Date: $DATE_UTC"
[[ -n "$SSH_TARGET" ]] && echo "  SSH:  $SSH_TARGET"
echo "═══════════════════════════════════════════"
echo ""

# =============================================================================
# L1: DNS
# =============================================================================
IP=""

if [[ "$HAS_DIG" == "yes" ]]; then
  IP=$(timeout "$TIMEOUT" dig +short "$DOMAIN" 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
fi

if [[ -z "$IP" ]]; then
  IP=$(timeout "$TIMEOUT" nslookup "$DOMAIN" 8.8.8.8 2>/dev/null \
    | awk '/^Address: [0-9]/{print $2}' | head -1)
fi

if [[ -z "$IP" ]]; then
  fail_and_exit "L1" "no resolution" \
    "Domain $DOMAIN does not resolve to any IP" \
    "Check DNS records at registrar; verify nameservers; run: dig $DOMAIN"
fi

append_json "L1" "PASS" "$IP"
print_layer_line "L1" "PASS" "$IP"

# =============================================================================
# L2: Network (ping)
# =============================================================================
PING_RESULT=""
RTT=""
if [[ "$HAS_PING" == "yes" ]]; then
  PING_RESULT=$(timeout 8 ping -c 2 -W 3 "$IP" 2>&1)
  RTT=$(echo "$PING_RESULT" | grep -oE 'rtt.*= [0-9.]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)
fi

if echo "$PING_RESULT" | grep -qE '2 received|2 packets received'; then
  PING_DETAIL="rtt=${RTT:-?}ms"
  append_json "L2" "PASS" "$PING_DETAIL"
  print_layer_line "L2" "PASS" "$PING_DETAIL"
else
  # ICMP often blocked — warn only, do not fail
  append_json "L2" "WARN" "ICMP blocked (non-fatal)"
  print_layer_line "L2" "WARN" "ICMP blocked (continuing)"
fi

# =============================================================================
# L3: TCP ports
# =============================================================================
TCP_443="closed"
TCP_80="closed"

if [[ "$HAS_NC" == "yes" ]]; then
  echo "$( timeout "$TIMEOUT" nc -zv -w 3 "$DOMAIN" 443 2>&1 )" \
    | grep -qiE 'succeeded|open|Connected' && TCP_443="open"
  echo "$( timeout "$TIMEOUT" nc -zv -w 3 "$DOMAIN" 80  2>&1 )" \
    | grep -qiE 'succeeded|open|Connected' && TCP_80="open"
else
  timeout "$TIMEOUT" curl -s --connect-timeout 4 "telnet://$DOMAIN:443" >/dev/null 2>&1 \
    && TCP_443="open"
  timeout "$TIMEOUT" curl -s --connect-timeout 4 "telnet://$DOMAIN:80"  >/dev/null 2>&1 \
    && TCP_80="open"
fi

if [[ "$TCP_443" == "closed" && "$TCP_80" == "closed" ]]; then
  fail_and_exit "L3" "443:closed 80:closed" \
    "Both HTTP/HTTPS ports unreachable on $IP" \
    "Check firewall rules (ufw/iptables); verify web server is listening; check cloud security groups"
fi

TCP_DETAIL="80:$TCP_80 443:$TCP_443"
append_json "L3" "PASS" "$TCP_DETAIL"
print_layer_line "L3" "PASS" "$TCP_DETAIL"

# =============================================================================
# L4: TLS/SSL
# =============================================================================
if [[ "$TCP_443" == "open" && "$HAS_OPENSSL" == "yes" ]]; then
  TLS_INFO=$(echo | timeout "$TIMEOUT" openssl s_client \
    -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null)
  CERT_DATES=$(echo "$TLS_INFO" | openssl x509 -noout -dates -subject 2>/dev/null)
  NOT_AFTER=$(echo "$CERT_DATES" | grep notAfter | cut -d= -f2)
  CERT_CN=$(echo "$CERT_DATES" | grep subject \
    | grep -oE 'CN\s*=\s*[^,/]+' | head -1 | sed 's/CN *= *//')

  if [[ -z "$NOT_AFTER" ]]; then
    fail_and_exit "L4" "TLS handshake failed" \
      "Cannot retrieve TLS certificate from $DOMAIN:443" \
      "Check SSL cert installation: openssl s_client -connect $DOMAIN:443"
  fi

  EXPIRY_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null \
    || date -j -f "%b %d %T %Y %Z" "$NOT_AFTER" +%s 2>/dev/null)
  NOW_EPOCH=$(date +%s)

  if [[ -n "$EXPIRY_EPOCH" ]] && (( EXPIRY_EPOCH < NOW_EPOCH )); then
    fail_and_exit "L4" "EXPIRED: $NOT_AFTER" \
      "TLS certificate for $DOMAIN expired on $NOT_AFTER" \
      "Renew: certbot renew --cert-name $DOMAIN OR acme.sh --renew -d $DOMAIN"
  fi

  EXPIRY_SHORT=$(echo "$NOT_AFTER" | awk '{print $1,$2,$4}')
  TLS_DETAIL="valid until $EXPIRY_SHORT CN=$CERT_CN"
  append_json "L4" "PASS" "$TLS_DETAIL"
  print_layer_line "L4" "PASS" "$TLS_DETAIL"

elif [[ "$TCP_443" == "closed" ]]; then
  append_json "L4" "SKIP" "443 not open"
  print_layer_line "L4" "SKIP" "443 not open"
else
  append_json "L4" "SKIP" "openssl not available"
  print_layer_line "L4" "SKIP" "openssl not available"
fi

# =============================================================================
# L5: HTTP response code
# =============================================================================
SCHEME="https"
[[ "$TCP_443" == "closed" ]] && SCHEME="http"

HTTP_CODE=$(timeout "$TIMEOUT" curl -sI -o /dev/null \
  -w '%{http_code}' \
  --connect-timeout 4 --max-time "$TIMEOUT" \
  -L "$SCHEME://$DOMAIN" 2>/dev/null)

HTTP_OK=false
case "$HTTP_CODE" in 2*|301|302|303|307|308) HTTP_OK=true ;; esac

if $HTTP_OK; then
  append_json "L5" "PASS" "HTTP $HTTP_CODE"
  print_layer_line "L5" "PASS" "HTTP $HTTP_CODE"
else
  CAUSE_MSG="Server returned HTTP $HTTP_CODE"
  FIX_MSG="Check nginx error log and app process status"

  case "$HTTP_CODE" in
    502) CAUSE_MSG="Upstream not responding (502 Bad Gateway)"
         FIX_MSG="Verify app process is online: pm2 list | grep online; check php-fpm/gunicorn status" ;;
    503) CAUSE_MSG="Service temporarily unavailable (503)"
         FIX_MSG="App may be overloaded or down; check process manager and resource usage" ;;
    504) CAUSE_MSG="Gateway timeout — app too slow or unresponsive (504)"
         FIX_MSG="Inspect app logs for slow queries or memory exhaustion" ;;
    000) CAUSE_MSG="Connection refused (curl error 000)"
         FIX_MSG="nginx not listening: nginx -t; systemctl status nginx" ;;
    4*)  CAUSE_MSG="Client-side error HTTP $HTTP_CODE"
         FIX_MSG="Verify URL/routing; inspect nginx vhost config" ;;
  esac

  # Optional nginx diagnostics via SSH
  if [[ -n "$SSH_TARGET" ]]; then
    NGINX_TEST=$(ssh_run "nginx -t 2>&1" || true)
    if echo "$NGINX_TEST" | grep -qi "failed\|error"; then
      CAUSE_MSG="$CAUSE_MSG | nginx config error: $(echo "$NGINX_TEST" | tail -1)"
    fi
  fi

  fail_and_exit "L5" "HTTP $HTTP_CODE" "$CAUSE_MSG" "$FIX_MSG"
fi

# =============================================================================
# L6: App layer (SSH required)
# =============================================================================
if [[ -n "$SSH_TARGET" ]]; then
  APP_STATUS="PASS"
  APP_DETAIL="processes OK"

  if [[ "$HAS_JQ" == "yes" ]]; then
    PM2_DOWN=$(ssh_run \
      "pm2 jlist 2>/dev/null | jq -r '.[] | select(.pm2_env.status != \"online\") | .name + \":\" + .pm2_env.status'" \
      2>/dev/null || true)
  else
    PM2_DOWN=$(ssh_run "pm2 list 2>/dev/null | grep -v online | grep -v '\\[PM2\\]'" || true)
  fi

  if [[ -n "$PM2_DOWN" ]] && ! echo "$PM2_DOWN" | grep -qE '^\s*$'; then
    APP_STATUS="WARN"
    APP_DETAIL="PM2 not-online: $(echo "$PM2_DOWN" | head -3 | tr '\n' ';')"
  fi

  MEM_FREE=$(ssh_run "free -m 2>/dev/null | awk '/Mem:/{print \$4}'" || true)
  if [[ -n "$MEM_FREE" ]] && echo "$MEM_FREE" | grep -qE '^[0-9]+$' && (( MEM_FREE < 100 )); then
    APP_STATUS="WARN"
    APP_DETAIL="$APP_DETAIL | LOW MEM: ${MEM_FREE}MB free"
  fi

  if [[ "$APP_STATUS" == "PASS" ]]; then
    LOAD=$(ssh_run "uptime 2>/dev/null | awk -F'load average:' '{print \$2}'" || true)
    APP_DETAIL="load:$(echo "$LOAD" | tr -d ' ' | cut -c1-20) mem:${MEM_FREE:-?}MB free"
  fi

  append_json "L6" "$APP_STATUS" "$APP_DETAIL"
  ICON="PASS"; [[ "$APP_STATUS" == "WARN" ]] && ICON="WARN"
  print_layer_line "L6" "$ICON" "$APP_DETAIL"
else
  append_json "L6" "SKIP" "no SSH target"
  print_layer_line "L6" "SKIP" "no SSH target (use --ssh user@host)"
fi

# =============================================================================
# L7: DB / Disk (SSH required)
# =============================================================================
if [[ -n "$SSH_TARGET" ]]; then
  DB_OUT=$(ssh_run \
    "pg_isready 2>/dev/null || mysqladmin -u root status 2>/dev/null || echo DB_SKIP" \
    || true)
  DISK_OUT=$(ssh_run "df -h / 2>/dev/null | tail -1" || true)
  DISK_PCT=$(echo "$DISK_OUT" | awk '{print $5}' | tr -d '%')

  if echo "$DB_OUT" | grep -qi "accepting\|mysqld is alive"; then
    DB_LABEL="DB:online"
  elif echo "$DB_OUT" | grep -qi "DB_SKIP"; then
    DB_LABEL="DB:no-pg/mysql"
  else
    DB_LABEL="DB:unknown"
  fi

  L7_DETAIL="${DB_LABEL} disk:${DISK_PCT:-?}%"

  if [[ -n "$DISK_PCT" ]] && echo "$DISK_PCT" | grep -qE '^[0-9]+$' && (( DISK_PCT >= 90 )); then
    append_json "L7" "WARN" "$L7_DETAIL"
    print_layer_line "L7" "WARN" "DISK CRITICAL ${DISK_PCT}% — run: du -sh /*"
  else
    append_json "L7" "PASS" "$L7_DETAIL"
    print_layer_line "L7" "PASS" "$L7_DETAIL"
  fi
else
  append_json "L7" "SKIP" "no SSH target"
  print_layer_line "L7" "SKIP" "no SSH target"
fi

# =============================================================================
# L8: External reachability via check-host.net
# =============================================================================
if $FLAG_QUICK; then
  append_json "L8" "SKIP" "--quick flag"
  print_layer_line "L8" "SKIP" "--quick flag (skipping external check)"
else
  REQUEST_ID=""
  REQUEST_ID=$(timeout 8 curl -s -H "Accept: application/json" \
    "https://check-host.net/check-http?host=https://${DOMAIN}&max_nodes=4" 2>/dev/null \
    | ([[ "$HAS_JQ" == "yes" ]] && jq -r '.request_id' \
       || grep -oE '"request_id":"[^"]+"' | cut -d'"' -f4))

  if [[ -z "$REQUEST_ID" || "$REQUEST_ID" == "null" ]]; then
    append_json "L8" "WARN" "check-host.net API unavailable"
    print_layer_line "L8" "WARN" "check-host.net unreachable (non-fatal)"
  else
    sleep 6
    EXT_RESULT=$(timeout 8 curl -s -H "Accept: application/json" \
      "https://check-host.net/check-result/$REQUEST_ID" 2>/dev/null)

    if [[ "$HAS_JQ" == "yes" ]]; then
      NODES_OK=$(echo "$EXT_RESULT" \
        | jq '[.. | arrays | select(length>0 and (.[0]|type)=="number") | .[0] | select(.==1)] | length' \
        2>/dev/null || echo 0)
      NODES_TOTAL=$(echo "$EXT_RESULT" \
        | jq '[.. | arrays | select(length>0)] | length' 2>/dev/null || echo 4)
    else
      NODES_OK=$(echo "$EXT_RESULT" | grep -c '"1"' || echo 0)
      NODES_TOTAL=4
    fi

    EXT_DETAIL="${NODES_OK}/${NODES_TOTAL} nodes reachable globally"

    if (( NODES_OK == 0 && NODES_TOTAL > 0 )); then
      fail_and_exit "L8" "$EXT_DETAIL" \
        "Service unreachable from all external nodes (0/$NODES_TOTAL)" \
        "Possible global outage or DNS propagation issue; check CDN and DDoS protection status"
    else
      append_json "L8" "PASS" "$EXT_DETAIL"
      print_layer_line "L8" "PASS" "$EXT_DETAIL"
    fi
  fi
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "═══════════════════════════════════════════"
echo "  RESULT: ALL LAYERS PASSED"
echo "  Domain: $DOMAIN"
echo "  Time:   $DATE_UTC"
echo "═══════════════════════════════════════════"
echo ""

save_to_redis
output_json_if_needed

exit 0
