#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/apache.sh — Apache httpd health module
# Sourced by diagnose-service.sh. Exports: run_module_apache()
# =============================================================================

run_module_apache() {
  local module_label="Apache"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  # Detect apache binary (apache2 or httpd)
  local APACHECTL
  APACHECTL=$(command -v apachectl 2>/dev/null || command -v apache2ctl 2>/dev/null)
  if [[ -z "$APACHECTL" ]]; then
    printf "[MODULE] %-14s ... SKIP (apachectl not found)\n" "$module_label"
    return 0
  fi

  # --- Check 1: Config syntax ---
  local syntax_out
  syntax_out=$(timeout 5 "$APACHECTL" -t 2>&1)
  if ! echo "$syntax_out" | grep -qi "Syntax OK"; then
    status="FAIL"
    local syntax_err
    syntax_err=$(echo "$syntax_out" | grep -i "error\|failed\|invalid" | head -2 | tr '\n' ';')
    cause="Apache config syntax error: ${syntax_err:-see apachectl -t output}"
    fix="Fix config error, then: apachectl configtest && apachectl graceful"
  fi

  # --- Check 2: VHost conflicts ---
  local vhost_out conflict_count
  vhost_out=$(timeout 5 "$APACHECTL" -S 2>&1)
  conflict_count=$(echo "$vhost_out" | grep -ci "conflicting\|overlap\|duplicate" || echo 0)
  if (( conflict_count > 0 )); then
    [[ "$status" == "PASS" ]] && status="WARN"
    local conflict_detail
    conflict_detail=$(echo "$vhost_out" | grep -i "conflicting\|overlap\|duplicate" | head -2 | tr '\n' ';')
    cause="${cause:+$cause | }VHost conflicts detected: ${conflict_detail}"
    fix="${fix:+$fix; }Check duplicate ServerName in vhosts: apachectl -S; disable conflicting vhost"
  fi

  # --- Check 3: Error log ---
  local errlog
  errlog=$(ls /var/log/apache2/error.log /var/log/httpd/error_log 2>/dev/null | head -1)
  if [[ -n "$errlog" ]]; then
    local recent_errors
    recent_errors=$(tail -30 "$errlog" 2>/dev/null | grep -iE "\[error\]|\[crit\]|\[emerg\]" | wc -l | tr -d ' ')
    if [[ "$recent_errors" =~ ^[0-9]+$ ]] && (( recent_errors > 0 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      local sample_err
      sample_err=$(tail -30 "$errlog" 2>/dev/null | grep -iE "\[error\]|\[crit\]|\[emerg\]" | tail -1 | cut -c1-120)
      cause="${cause:+$cause | }${recent_errors} recent errors in error.log: ${sample_err}"
      fix="${fix:+$fix; }Review: tail -50 $errlog"
    fi
  fi

  # --- Check 4: HTTP response on localhost ---
  local http_code
  http_code=$(timeout 5 curl -sI -o /dev/null -w '%{http_code}' http://localhost:80 2>/dev/null)
  if [[ "$http_code" == "000" || -z "$http_code" ]]; then
    status="FAIL"
    cause="${cause:+$cause | }Apache not responding on localhost:80 (curl returned ${http_code:-empty})"
    fix="${fix:+$fix; }Check if Apache is running: ps aux | grep apache; apachectl start"
  fi

  # --- Build summary ---
  local vhost_count
  vhost_count=$(echo "$vhost_out" | grep -c "port " 2>/dev/null || echo '?')
  if [[ "$status" == "PASS" ]]; then
    detail="syntax OK, ${vhost_count} vhosts, HTTP ${http_code:-?}"
  else
    detail="$cause"
  fi

  # --- Output ---
  if [[ "$status" == "PASS" ]]; then
    printf "[MODULE] %-14s ... \xE2\x9C\x85 PASS (%s)\n" "$module_label" "$detail"
  elif [[ "$status" == "WARN" ]]; then
    printf "[MODULE] %-14s ... \xE2\x9A\xA0 WARN (%s)\n" "$module_label" "$detail"
    [[ -n "$fix" ]] && printf "  FIX: %s\n" "$fix"
  else
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (%s)\n" "$module_label" "$detail"
    [[ -n "$cause" ]] && printf "  ROOT CAUSE: %s\n" "$cause"
    [[ -n "$fix"  ]] && printf "  FIX: %s\n" "$fix"
  fi

  return 0
}
