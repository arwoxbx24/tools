#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/mysql.sh — MySQL/MariaDB health module (extended)
# Sourced by diagnose-service.sh. Exports: run_module_mysql()
# =============================================================================

run_module_mysql() {
  local module_label="MySQL"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  local MYSQL_BIN MYSQLADMIN_BIN
  MYSQL_BIN=$(command -v mysql 2>/dev/null)
  MYSQLADMIN_BIN=$(command -v mysqladmin 2>/dev/null)

  if [[ -z "$MYSQLADMIN_BIN" && -z "$MYSQL_BIN" ]]; then
    printf "[MODULE] %-14s ... SKIP (mysql/mysqladmin not found)\n" "$module_label"
    return 0
  fi

  # Common MySQL flags (try socket first, then TCP localhost)
  local MYSQL_ARGS="-u root --connect-timeout=5"
  # Accept password from .my.cnf silently
  MYSQL_ARGS="$MYSQL_ARGS --batch --silent"

  # --- Check 1: Server status ---
  local admin_status
  if [[ -n "$MYSQLADMIN_BIN" ]]; then
    admin_status=$(timeout 5 "$MYSQLADMIN_BIN" -u root --connect-timeout=5 status 2>/dev/null)
  fi

  if [[ -z "$admin_status" ]] || echo "$admin_status" | grep -qi "error\|refused\|Access denied"; then
    # Try mysql directly
    admin_status=$(timeout 5 "$MYSQL_BIN" $MYSQL_ARGS -e "SELECT 'alive'" 2>/dev/null)
    if [[ -z "$admin_status" ]] || echo "$admin_status" | grep -qi "error\|refused"; then
      printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (connection refused — MySQL not running or auth failed)\n" "$module_label"
      printf "  ROOT CAUSE: Both mysqladmin and mysql -e failed\n"
      printf "  FIX: service mysql start; check /var/log/mysql/error.log for startup errors\n"
      return 0
    fi
  fi

  # Parse uptime
  local uptime_val
  uptime_val=$(echo "$admin_status" | grep -i "Uptime" | grep -oE 'Uptime:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' || echo '')

  # --- Check 2: Process list ---
  local thread_count max_conn thread_pct
  thread_count=$(timeout 5 "$MYSQL_BIN" $MYSQL_ARGS \
    -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';" 2>/dev/null \
    | awk 'NR==2{print $2}')
  max_conn=$(timeout 5 "$MYSQL_BIN" $MYSQL_ARGS \
    -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null \
    | awk 'NR==2{print $2}')

  if [[ "$thread_count" =~ ^[0-9]+$ && "$max_conn" =~ ^[0-9]+$ && "$max_conn" != "0" ]]; then
    thread_pct=$(awk "BEGIN{printf \"%d\", ($thread_count/$max_conn)*100}")
    if (( thread_pct >= 80 )); then
      status="WARN"
      cause="Connections ${thread_count}/${max_conn} (${thread_pct}%)"
      fix="Kill idle connections: mysqladmin processlist; increase max_connections in my.cnf"
    fi
  fi

  # --- Check 3: Slow query log ---
  local slow_log_file slow_recent
  slow_log_file=$(timeout 5 "$MYSQL_BIN" $MYSQL_ARGS \
    -e "SHOW VARIABLES LIKE 'slow_query_log_file';" 2>/dev/null \
    | awk 'NR==2{print $2}')
  if [[ -f "$slow_log_file" ]]; then
    slow_recent=$(tail -30 "$slow_log_file" 2>/dev/null | grep -c "Query_time" || echo 0)
    if [[ "$slow_recent" =~ ^[0-9]+$ ]] && (( slow_recent > 5 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      cause="${cause:+$cause | }${slow_recent} slow queries in log (last 30 lines)"
      fix="${fix:+$fix; }Review: tail -50 $slow_log_file; SET GLOBAL slow_query_log=ON for monitoring"
    fi
  fi

  # --- Check 4: Disk space ---
  local disk_pct
  disk_pct=$(df -h /var/lib/mysql 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
  if [[ -n "$disk_pct" && "$disk_pct" =~ ^[0-9]+$ ]] && (( disk_pct >= 90 )); then
    status="FAIL"
    cause="${cause:+$cause | }MySQL disk ${disk_pct}% full"
    fix="${fix:+$fix; }Free space: purge binary logs (PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY); expand disk"
  fi

  # --- Build summary ---
  if [[ "$status" == "PASS" ]]; then
    detail="alive, uptime=${uptime_val:-?}s, conn=${thread_count:-?}/${max_conn:-?}"
    [[ -n "$disk_pct" ]] && detail="$detail, disk=${disk_pct}%"
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
