#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/php-fpm.sh — PHP-FPM health module
# Sourced by diagnose-service.sh. Exports: run_module_php_fpm()
# =============================================================================

run_module_php_fpm() {
  local module_label="PHP-FPM"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  if ! command -v php >/dev/null 2>&1; then
    printf "[MODULE] %-14s ... SKIP (php not found)\n" "$module_label"
    return 0
  fi

  # --- Check 1: PHP-FPM service status ---
  # Find all php-fpm service names (php7.4-fpm, php8.1-fpm, php-fpm, etc.)
  local fpm_procs fpm_running
  fpm_procs=$(ps aux 2>/dev/null | grep -E 'php[0-9.]?-fpm|php-fpm' | grep -v grep | wc -l | tr -d ' ')
  if [[ "$fpm_procs" == "0" ]]; then
    status="FAIL"
    cause="PHP-FPM not running (no php*fpm processes found)"
    fix="service php-fpm start  OR  service php8.x-fpm start; check php version: php -v"
  else
    fpm_running="$fpm_procs processes"
  fi

  # --- Check 2: PHP version ---
  local php_version
  php_version=$(php -v 2>/dev/null | head -1 | grep -oE 'PHP [0-9]+\.[0-9]+\.[0-9]+' | head -1)

  # --- Check 3: Error log ---
  local errlog_file
  # Find PHP-FPM error log
  errlog_file=$(find /var/log/php* -name "*.log" 2>/dev/null | grep -iE 'fpm|error' | head -1)
  if [[ -z "$errlog_file" ]]; then
    errlog_file=$(php -i 2>/dev/null | grep 'error_log' | grep -v 'directive' | grep -v '^$' | head -1 | awk -F'=>' '{print $2}' | tr -d ' ')
  fi

  if [[ -f "$errlog_file" ]]; then
    local recent_fatals
    recent_fatals=$(tail -30 "$errlog_file" 2>/dev/null | grep -cE "Fatal error|Segfault|out of memory|SIGSEGV" || echo 0)
    if [[ "$recent_fatals" =~ ^[0-9]+$ ]] && (( recent_fatals > 0 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      local sample_fatal
      sample_fatal=$(tail -30 "$errlog_file" 2>/dev/null | grep -E "Fatal error|Segfault|out of memory|SIGSEGV" | tail -1 | cut -c1-120)
      cause="${cause:+$cause | }${recent_fatals} fatal errors in log: ${sample_fatal}"
      fix="${fix:+$fix; }Review: tail -50 $errlog_file"
    fi
  fi

  # --- Check 4: PHP ini settings ---
  local mem_limit upload_max max_exec
  mem_limit=$(php -i 2>/dev/null | grep 'memory_limit' | grep -v 'directive' | head -1 | awk -F'=>' '{print $NF}' | tr -d ' ')
  upload_max=$(php -i 2>/dev/null | grep 'upload_max_filesize' | grep -v 'directive' | head -1 | awk -F'=>' '{print $NF}' | tr -d ' ')
  max_exec=$(php -i 2>/dev/null | grep 'max_execution_time' | grep -v 'directive' | head -1 | awk -F'=>' '{print $NF}' | tr -d ' ')

  # Warn if memory_limit is very low (< 64M) — parse M suffix
  if [[ -n "$mem_limit" ]]; then
    local mem_mb
    mem_mb=$(echo "$mem_limit" | grep -oE '^[0-9]+' || echo '')
    local mem_unit
    mem_unit=$(echo "$mem_limit" | grep -oE '[KMG]$' | tr '[:lower:]' '[:upper:]' || echo 'M')
    if [[ "$mem_unit" == "M" && "$mem_mb" =~ ^[0-9]+$ ]] && (( mem_mb < 64 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      cause="${cause:+$cause | }memory_limit too low: ${mem_limit}"
      fix="${fix:+$fix; }Set memory_limit=256M in php.ini or pool config; reload php-fpm after change"
    fi
  fi

  # --- Check 5: Loaded modules count ---
  local module_count
  module_count=$(php -m 2>/dev/null | grep -v '\[' | grep -v '^$' | wc -l | tr -d ' ')

  # --- Build summary ---
  if [[ "$status" == "PASS" ]]; then
    detail="${php_version:-php}, ${fpm_running:-?} FPM procs, mem=${mem_limit:-?}, modules=${module_count:-?}"
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
