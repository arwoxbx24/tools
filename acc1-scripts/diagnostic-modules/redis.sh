#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/redis.sh — Redis health module
# Sourced by diagnose-service.sh. Exports: run_module_redis()
# =============================================================================

run_module_redis() {
  local module_label="Redis"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  local RCLI
  RCLI=$(command -v redis-cli 2>/dev/null)

  if [[ -z "$RCLI" ]]; then
    printf "[MODULE] %-14s ... SKIP (redis-cli not found)\n" "$module_label"
    return 0
  fi

  # --- Check 1: PING ---
  local pong
  pong=$(timeout 3 "$RCLI" PING 2>/dev/null | tr -d '[:space:]')
  if [[ "$pong" != "PONG" ]]; then
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (connection refused — redis not running)\n" "$module_label"
    printf "  ROOT CAUSE: redis-cli PING returned '%s'\n" "${pong:-<no response>}"
    printf "  FIX: service redis start OR service redis-server start\n"
    return 0
  fi

  # --- Check 2: Memory ---
  local used_mem max_mem evicted
  local redis_mem_info
  redis_mem_info=$(timeout 3 "$RCLI" INFO memory 2>/dev/null)
  used_mem=$(echo "$redis_mem_info" | grep used_memory_human | cut -d: -f2 | tr -d '[:space:]')
  max_mem=$(echo "$redis_mem_info" | grep maxmemory_human | head -1 | cut -d: -f2 | tr -d '[:space:]')
  local used_bytes max_bytes
  used_bytes=$(echo "$redis_mem_info" | grep '^used_memory:' | cut -d: -f2 | tr -d '[:space:]')
  max_bytes=$(echo "$redis_mem_info" | grep '^maxmemory:' | cut -d: -f2 | tr -d '[:space:]')
  evicted=$(timeout 3 "$RCLI" INFO stats 2>/dev/null | grep evicted_keys | cut -d: -f2 | tr -d '[:space:]')

  if [[ -n "$max_bytes" && "$max_bytes" != "0" && -n "$used_bytes" ]]; then
    local mem_pct
    mem_pct=$(awk "BEGIN{printf \"%d\", ($used_bytes/$max_bytes)*100}" 2>/dev/null)
    if [[ "$mem_pct" =~ ^[0-9]+$ ]] && (( mem_pct >= 80 )); then
      status="WARN"
      cause="Memory ${mem_pct}% used (${used_mem}/${max_mem})"
      fix="Increase maxmemory in redis.conf; set maxmemory-policy allkeys-lru"
    fi
  fi

  if [[ -n "$evicted" && "$evicted" != "0" ]]; then
    status="WARN"
    cause="${cause:+$cause | }Active evictions: ${evicted} keys evicted"
    fix="${fix:+$fix; }Consider increasing maxmemory or cleaning expired keys manually"
  fi

  # --- Check 3: Keyspace ---
  local keyspace
  keyspace=$(timeout 3 "$RCLI" INFO keyspace 2>/dev/null | grep -v '^#' | grep -v '^$' | tr '\n' ' ')

  # --- Check 4: Slowlog ---
  local slow_count slow_worst
  slow_count=$(timeout 3 "$RCLI" SLOWLOG LEN 2>/dev/null | tr -d '[:space:]')
  # Get slowlog entry execution time (field 3, in microseconds)
  slow_worst=$(timeout 3 "$RCLI" SLOWLOG GET 5 2>/dev/null \
    | awk '/^[[:space:]]+[0-9]{5,}$/{gsub(/[[:space:]]/,"",$0); if ($0+0 > max) max=$0+0} END{print max+0}')
  # slowlog time is in microseconds — warn if >100ms (100000 us)
  if [[ -n "$slow_worst" && "$slow_worst" =~ ^[0-9]+$ ]] && (( slow_worst > 100000 )); then
    [[ "$status" == "PASS" ]] && status="WARN"
    local slow_ms=$(( slow_worst / 1000 ))
    cause="${cause:+$cause | }Slowlog: worst command ${slow_ms}ms"
    fix="${fix:+$fix; }Run SLOWLOG RESET after investigation; check client query patterns"
  fi

  # --- Build summary ---
  local db_count
  db_count=$(echo "$keyspace" | grep -c 'db' || echo '?')
  if [[ "$status" == "PASS" ]]; then
    detail="PONG, mem=${used_mem:-?}, ${db_count} DBs"
    [[ -n "$slow_count" && "$slow_count" != "0" ]] && detail="$detail, slowlog=${slow_count}"
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
