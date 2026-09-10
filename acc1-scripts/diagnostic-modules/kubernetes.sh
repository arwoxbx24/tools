#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/kubernetes.sh — Kubernetes cluster health module
# Sourced by diagnose-service.sh. Exports: run_module_kubernetes()
# =============================================================================

run_module_kubernetes() {
  local module_label="Kubernetes"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  if ! command -v kubectl >/dev/null 2>&1; then
    printf "[MODULE] %-14s ... SKIP (kubectl not found)\n" "$module_label"
    return 0
  fi

  # --- Check 1: API server reachable ---
  local cluster_info
  cluster_info=$(timeout 10 kubectl cluster-info 2>&1)
  if ! echo "$cluster_info" | grep -qi "Kubernetes.*is running\|control plane.*https"; then
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (API server unreachable)\n" "$module_label"
    printf "  ROOT CAUSE: kubectl cluster-info failed: %s\n" "$(echo "$cluster_info" | head -2 | tr '\n' ' ')"
    printf "  FIX: Check kubeconfig (KUBECONFIG env or ~/.kube/config); verify cluster network\n"
    return 0
  fi

  # --- Check 2: Node status ---
  local nodes_out not_ready_nodes
  nodes_out=$(timeout 10 kubectl get nodes --no-headers 2>/dev/null)
  not_ready_nodes=$(echo "$nodes_out" | grep -v " Ready" | grep -v "^$" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
  local total_nodes
  total_nodes=$(echo "$nodes_out" | grep -c . || echo 0)

  if [[ -n "$not_ready_nodes" ]]; then
    status="FAIL"
    cause="Nodes NotReady: $not_ready_nodes"
    fix="kubectl describe node ${not_ready_nodes%%,*}; check kubelet: journalctl -u kubelet --since '5m ago'"
  fi

  # --- Check 3: Non-running pods ---
  local bad_pods
  bad_pods=$(timeout 15 kubectl get pods --all-namespaces --no-headers 2>/dev/null \
    | grep -vE "Running|Completed|Succeeded" | grep -v "^$")
  local bad_pod_count
  bad_pod_count=$(echo "$bad_pods" | grep -c . || echo 0)
  if (( bad_pod_count > 0 )); then
    [[ "$status" == "PASS" ]] && status="WARN"
    local sample_bad
    sample_bad=$(echo "$bad_pods" | head -3 | awk '{print $2"/"$4}' | tr '\n' ' ')
    cause="${cause:+$cause | }${bad_pod_count} non-running pods: ${sample_bad}"
    # CrashLoopBackOff specifically
    if echo "$bad_pods" | grep -qi "CrashLoop\|OOMKilled\|Error"; then
      status="FAIL"
      fix="${fix:+$fix; }kubectl logs <pod> -n <ns>; kubectl describe pod <pod> -n <ns> | tail -20 (check Events)"
    else
      fix="${fix:+$fix; }kubectl get pods --all-namespaces | grep -v Running; kubectl describe pod <name> for Events"
    fi
  fi

  # --- Check 4: Resource usage ---
  local top_out
  top_out=$(timeout 10 kubectl top nodes 2>/dev/null)
  if [[ -n "$top_out" ]]; then
    local high_cpu_nodes
    high_cpu_nodes=$(echo "$top_out" | awk 'NR>1{cpu=$3; gsub(/%/,"",cpu); if(cpu+0>80) print $1":"cpu"%"}' | tr '\n' ',')
    if [[ -n "$high_cpu_nodes" ]]; then
      [[ "$status" == "PASS" ]] && status="WARN"
      cause="${cause:+$cause | }High CPU nodes: $high_cpu_nodes"
      fix="${fix:+$fix; }kubectl top pods --all-namespaces --sort-by=cpu | head -10 to find heavy pods"
    fi
  fi

  # --- Build summary ---
  local running_pods
  running_pods=$(timeout 15 kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -c "Running" || echo '?')
  if [[ "$status" == "PASS" ]]; then
    detail="${total_nodes} nodes Ready, ${running_pods} pods running"
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
