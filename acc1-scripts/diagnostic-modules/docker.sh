#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/docker.sh — Docker health module
# Sourced by diagnose-service.sh. Exports: run_module_docker()
# =============================================================================

run_module_docker() {
  local module_label="Docker"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  # Check docker command available
  if ! command -v docker >/dev/null 2>&1; then
    printf "[MODULE] %-14s ... SKIP (docker not installed)\n" "$module_label"
    return 0
  fi

  # --- Check 1: container states ---
  local containers
  containers=$(docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null) || {
    printf "[MODULE] %-14s ... \xE2\x9A\xA0 WARN (docker ps failed — daemon not running?)\n" "$module_label"
    return 0
  }

  local restarting_list exited_list unhealthy_list total_count
  restarting_list=$(echo "$containers" | grep -i "restarting" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
  exited_list=$(echo "$containers" | grep -iE "exited|dead" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
  unhealthy_list=$(echo "$containers" | grep -i "unhealthy" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
  total_count=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')

  if [[ -n "$restarting_list" ]]; then
    status="FAIL"
    cause="Container(s) in restart loop: $restarting_list"
    fix="Check OOM or crash: docker logs ${restarting_list%%,*} --tail 50; docker inspect ${restarting_list%%,*}"
  fi

  if [[ -n "$exited_list" ]]; then
    status="FAIL"
    cause="${cause:+$cause | }Container(s) exited: $exited_list"
    fix="${fix:+$fix; }Restart: docker start ${exited_list%%,*}; check logs for root cause"
  fi

  if [[ -n "$unhealthy_list" ]]; then
    [[ "$status" == "PASS" ]] && status="WARN"
    cause="${cause:+$cause | }Unhealthy containers: $unhealthy_list"
    fix="${fix:+$fix; }Investigate health check: docker inspect --format='{{.State.Health}}' ${unhealthy_list%%,*}"
  fi

  # --- Check 2: Docker disk space ---
  local docker_disk_pct
  docker_disk_pct=$(df -h /var/lib/docker 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
  if [[ -n "$docker_disk_pct" ]] && [[ "$docker_disk_pct" =~ ^[0-9]+$ ]] && (( docker_disk_pct >= 90 )); then
    [[ "$status" == "PASS" ]] && status="WARN"
    cause="${cause:+$cause | }Docker disk ${docker_disk_pct}% full"
    fix="${fix:+$fix; }docker system prune -af --volumes (WARNING: removes stopped containers & unused images)"
  fi

  # --- Check 3: memory usage (top 3 containers) ---
  local mem_info
  mem_info=$(docker stats --no-stream --format '{{.Name}} {{.MemPerc}}' 2>/dev/null \
    | sort -t'%' -k1 -rn 2>/dev/null | head -3 | tr '\n' ' ') || true

  local oom_hit
  oom_hit=$(docker events --filter event=oom --since 1h --until 0s 2>/dev/null | head -3) || true
  if [[ -n "$oom_hit" ]]; then
    status="FAIL"
    cause="${cause:+$cause | }OOM kill detected in last 1h"
    fix="${fix:+$fix; }Increase memory limit in docker-compose.yml or reduce workers"
  fi

  # --- Build detail string ---
  if [[ "$status" == "PASS" ]]; then
    detail="${total_count} containers, all healthy"
    [[ -n "$docker_disk_pct" ]] && detail="$detail, disk ${docker_disk_pct}%"
  else
    detail="${cause}"
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
