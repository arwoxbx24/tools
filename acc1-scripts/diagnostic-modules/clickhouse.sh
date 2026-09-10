#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/clickhouse.sh — ClickHouse health module
# Sourced by diagnose-service.sh. Exports: run_module_clickhouse()
# =============================================================================

run_module_clickhouse() {
  local module_label="ClickHouse"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""
  local CH_URL="http://localhost:8123"

  # --- Check 1: Basic connectivity ---
  local ch_ping
  ch_ping=$(timeout 5 curl -s "${CH_URL}/?query=SELECT+1" 2>/dev/null | tr -d '[:space:]')
  if [[ "$ch_ping" != "1" ]]; then
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (port 8123 not responding)\n" "$module_label"
    printf "  ROOT CAUSE: ClickHouse HTTP interface unreachable (got '%s')\n" "${ch_ping:-<timeout>}"
    printf "  FIX: service clickhouse-server start; check /var/log/clickhouse-server/clickhouse-server.err.log\n"
    return 0
  fi

  # --- Check 2: Error metrics ---
  local error_metrics
  error_metrics=$(timeout 5 curl -s \
    "${CH_URL}/?query=SELECT+metric,value+FROM+system.metrics+WHERE+metric+LIKE+'%25Error%25'+AND+value>0+FORMAT+TSV" \
    2>/dev/null)
  if [[ -n "$error_metrics" ]]; then
    local error_count
    error_count=$(echo "$error_metrics" | grep -c . || echo 0)
    status="WARN"
    cause="Error metrics elevated (${error_count} error types): $(echo "$error_metrics" | head -2 | tr '\n' ';')"
    fix="Check /var/log/clickhouse-server/ for details; review system.query_log for failing queries"
  fi

  # --- Check 3: Active processlist ---
  local active_queries
  active_queries=$(timeout 5 curl -s \
    "${CH_URL}/?query=SELECT+count()+FROM+system.processes" \
    2>/dev/null | tr -d '[:space:]')
  if [[ "$active_queries" =~ ^[0-9]+$ ]] && (( active_queries > 20 )); then
    [[ "$status" == "PASS" ]] && status="WARN"
    cause="${cause:+$cause | }High active query count: ${active_queries}"
    fix="${fix:+$fix; }Review system.processes: SELECT query,elapsed,memory_usage FROM system.processes ORDER BY elapsed DESC"
  fi

  # --- Check 4: Disk space ---
  local data_size disk_pct
  data_size=$(du -sh /var/lib/clickhouse 2>/dev/null | awk '{print $1}')
  disk_pct=$(df -h /var/lib/clickhouse 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
  if [[ -n "$disk_pct" && "$disk_pct" =~ ^[0-9]+$ ]] && (( disk_pct >= 90 )); then
    status="FAIL"
    cause="${cause:+$cause | }ClickHouse disk ${disk_pct}% full (data size: ${data_size:-?})"
    fix="${fix:+$fix; }Drop old partitions: ALTER TABLE db.table DROP PARTITION 'YYYYMM'; or expand disk"
  fi

  # --- Build summary ---
  if [[ "$status" == "PASS" ]]; then
    detail="responding, active_queries=${active_queries:-?}, disk=${disk_pct:-?}%"
    [[ -n "$data_size" ]] && detail="$detail, data=${data_size}"
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
