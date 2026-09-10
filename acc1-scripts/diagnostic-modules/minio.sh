#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/minio.sh — MinIO health module
# Sourced by diagnose-service.sh. Exports: run_module_minio()
# =============================================================================

run_module_minio() {
  local module_label="MinIO"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  local MC_BIN
  MC_BIN=$(command -v mc 2>/dev/null)
  if [[ -z "$MC_BIN" ]]; then
    printf "[MODULE] %-14s ... SKIP (mc client not found)\n" "$module_label"
    return 0
  fi

  # Use b244public alias (project standard per MEMORY.md)
  local MC_ALIAS="b244public"

  # --- Check 1: Server status ---
  local admin_out
  admin_out=$(timeout 10 "$MC_BIN" admin info "$MC_ALIAS" 2>&1)
  if echo "$admin_out" | grep -qi "Unable to connect\|ERROR\|timed out\|connection refused"; then
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (cannot connect to MinIO)\n" "$module_label"
    printf "  ROOT CAUSE: mc admin info %s failed: %s\n" "$MC_ALIAS" "$(echo "$admin_out" | head -1)"
    printf "  FIX: Check MinIO process (ps aux | grep minio); verify endpoint in mc alias list\n"
    return 0
  fi

  # Parse online status
  local server_status
  server_status=$(echo "$admin_out" | grep -i "Status\|online\|offline" | head -3 | tr '\n' ' ')
  if echo "$admin_out" | grep -qi "offline"; then
    status="WARN"
    cause="One or more MinIO nodes offline: ${server_status}"
    fix="Check MinIO cluster nodes; review MinIO logs at /var/log/minio/ or journalctl -u minio"
  fi

  # --- Check 2: Bucket list accessible ---
  local bucket_list bucket_count
  bucket_list=$(timeout 10 "$MC_BIN" ls "$MC_ALIAS" 2>&1)
  if echo "$bucket_list" | grep -qi "ERROR\|Unable\|refused"; then
    status="FAIL"
    cause="${cause:+$cause | }Bucket list failed: $(echo "$bucket_list" | head -1)"
    fix="${fix:+$fix; }Check MinIO access key/secret in alias; verify IAM permissions"
  else
    bucket_count=$(echo "$bucket_list" | grep -c "/" || echo 0)
  fi

  # --- Check 3: Disk space ---
  # Try to find MinIO data path from process or common locations
  local minio_data_path disk_pct
  minio_data_path=$(ps aux 2>/dev/null | grep 'minio server' | grep -oE '/[^ ]+/data[^ ]*|/data[^ ]*|/mnt/[^ ]+' | head -1)
  if [[ -z "$minio_data_path" ]]; then
    minio_data_path="/var/lib/minio"
  fi
  if [[ -d "$minio_data_path" ]]; then
    disk_pct=$(df -h "$minio_data_path" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    if [[ -n "$disk_pct" && "$disk_pct" =~ ^[0-9]+$ ]] && (( disk_pct >= 85 )); then
      [[ "$status" == "PASS" ]] && status="WARN"
      cause="${cause:+$cause | }MinIO disk ${disk_pct}% full at ${minio_data_path}"
      fix="${fix:+$fix; }Clean old/unused objects; expand disk or add distributed node"
    fi
  fi

  # --- Build summary ---
  if [[ "$status" == "PASS" ]]; then
    detail="online, ${bucket_count:-?} buckets accessible"
    [[ -n "$disk_pct" ]] && detail="$detail, disk ${disk_pct}%"
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
