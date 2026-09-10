#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/postgres.sh — PostgreSQL health module (extended)
# Sourced by diagnose-service.sh. Exports: run_module_postgres()
# =============================================================================

run_module_postgres() {
  local module_label="PostgreSQL"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  if ! command -v pg_isready >/dev/null 2>&1 && ! command -v psql >/dev/null 2>&1; then
    printf "[MODULE] %-14s ... SKIP (pg_isready/psql not found)\n" "$module_label"
    return 0
  fi

  # --- Check 1: pg_isready ---
  local pgready_out
  pgready_out=$(timeout 5 pg_isready -h localhost 2>/dev/null)
  if ! echo "$pgready_out" | grep -qi "accepting connections"; then
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (not accepting connections)\n" "$module_label"
    printf "  ROOT CAUSE: pg_isready: %s\n" "${pgready_out:-no response}"
    printf "  FIX: pg_ctlcluster <ver> main start  OR  service postgresql start\n"
    return 0
  fi

  # PSQL command with safe defaults — uses peer auth as current user or postgres
  local PSQL_CMD
  if command -v psql >/dev/null 2>&1; then
    PSQL_CMD="psql -h localhost -U postgres --no-password -t -c"
  fi

  # --- Check 2: Active connections ---
  local active_conn max_conn conn_pct
  if [[ -n "$PSQL_CMD" ]]; then
    active_conn=$(timeout 5 $PSQL_CMD \
      "SELECT count(*) FROM pg_stat_activity WHERE state IS NOT NULL;" 2>/dev/null \
      | tr -d ' ')
    max_conn=$(timeout 5 $PSQL_CMD \
      "SHOW max_connections;" 2>/dev/null \
      | tr -d ' ')

    if [[ "$active_conn" =~ ^[0-9]+$ && "$max_conn" =~ ^[0-9]+$ && "$max_conn" != "0" ]]; then
      conn_pct=$(awk "BEGIN{printf \"%d\", ($active_conn/$max_conn)*100}")
      if (( conn_pct >= 80 )); then
        status="WARN"
        cause="Connections ${active_conn}/${max_conn} (${conn_pct}%)"
        fix="Terminate idle: SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE state='idle' AND query_start < now()-interval '10 min'"
      fi
    fi

    # --- Check 3: Long-running queries ---
    local long_queries
    long_queries=$(timeout 5 $PSQL_CMD \
      "SELECT count(*) FROM pg_stat_activity WHERE state='active' AND query_start < now() - interval '30 seconds';" \
      2>/dev/null | tr -d ' ')
    if [[ "$long_queries" =~ ^[0-9]+$ ]] && (( long_queries > 0 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      cause="${cause:+$cause | }${long_queries} queries running >30s"
      local long_sample
      long_sample=$(timeout 5 $PSQL_CMD \
        "SELECT pid,state,left(query,80) FROM pg_stat_activity WHERE state='active' AND query_start < now() - interval '30 seconds' LIMIT 2;" \
        2>/dev/null | head -3 | tr '\n' ';')
      cause="${cause} | sample: ${long_sample}"
      fix="${fix:+$fix; }SELECT pg_cancel_backend(<pid>) for stuck queries; check for lock waits"
    fi

    # --- Check 4: Bloated tables / dead tuples ---
    local dead_tuples
    dead_tuples=$(timeout 5 $PSQL_CMD \
      "SELECT sum(n_dead_tup) FROM pg_stat_user_tables;" \
      2>/dev/null | tr -d ' ')
    if [[ "$dead_tuples" =~ ^[0-9]+$ ]] && (( dead_tuples > 1000000 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      cause="${cause:+$cause | }High dead tuples: ${dead_tuples} (vacuum needed)"
      fix="${fix:+$fix; }VACUUM ANALYZE; check autovacuum_enabled=on in postgresql.conf"
    fi
  fi

  # --- Check 5: Disk space ---
  local disk_pct
  disk_pct=$(df -h /var/lib/postgresql 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
  if [[ -z "$disk_pct" ]]; then
    disk_pct=$(df -h /var/lib/pgsql 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
  fi
  if [[ -n "$disk_pct" && "$disk_pct" =~ ^[0-9]+$ ]] && (( disk_pct >= 90 )); then
    status="FAIL"
    cause="${cause:+$cause | }PostgreSQL disk ${disk_pct}% full"
    fix="${fix:+$fix; }VACUUM FULL on large tables; archive or drop old partitions; expand disk"
  fi

  # --- Build summary ---
  if [[ "$status" == "PASS" ]]; then
    detail="accepting connections, conn=${active_conn:-?}/${max_conn:-?}"
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
